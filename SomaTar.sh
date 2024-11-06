#!/bin/bash

usage="$(basename "$0") [-w working_dir] [-r reference] [-b bed file] [-t threads] [-p platform] [-q quality] [-pore_chop yes/no] [-disable_indel_calling]"
 
SECONDS=0

while :;
do
    case "$1" in
      -h | --help)
          echo "$usage"
          exit 0
          ;;
      -w)
          WORKING_DIR=$(realpath "$2")
          shift 2
          ;;
      -r)
           REFERENCE=$2
           shift 2
           ;;
      -b) 
           BED_FILE=$2
           shift 2
           ;;
      -t)
           THREADS=$2
           shift 2
           ;;
      -q) 
           QUALITY=$2
           shift 2
           ;;     
      -p) 
           PLATFORM=$2
           shift 2
           ;;
       -pore_chop) 
          RUN_PORECHOP=$2
          shift 2
          ;;    
       -disable_indel_calling)
          DISABLE_INDEL_CALLING="--disable_indel_calling"
          shift 1 
          ;;    
              
    --) 
           shift
           break
           ;;
       -*)
           echo "Error: Unknown option: $1" >&2
           
           exit 1
           ;;
        *) 
           break
           ;;
    esac
done

ask_for_sudo_password() {
    echo -n "Enter your sudo password: "
    read -s sudo_password
    echo
}

if ! docker ps > /dev/null 2>&1; then
    echo "Docker permission denied. Attempting to fix..."
    ask_for_sudo_password
    echo $sudo_password | sudo -S chmod 666 /var/run/docker.sock
    if ! docker ps > /dev/null 2>&1; then
        echo "Failed to connect to Docker after attempting to fix permissions."
        exit 1
    fi
    echo "Docker permissions fixed."
fi

echo "Loading FASTQ files"

FASTQ_FILES=$(find "$WORKING_DIR" -maxdepth 1 -name "*.fastq")

echo "FASTQ files are loaded."

NANOPLOT=$(which NanoPlot)

if [ -z "$NANOPLOT" ]; then

  echo "Error: Nanoplot not found in PATH."
  exit 1
  
fi

mkdir -p "$WORKING_DIR/nanoplot_qc"

for raw_fastq_file in $FASTQ_FILES; do
    sample_name=$(basename "$raw_fastq_file" .fastq)
    "$NANOPLOT" --fastq "$raw_fastq_file" --outdir "$WORKING_DIR/nanoplot_qc/$sample_name" --threads "$THREADS" --loglength
done

echo "Completed running Nanoplot."

duration=$SECONDS
echo "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."

SECONDS=0

echo "Running porechop to remove barcodes."

if [[ "$RUN_PORECHOP" == "yes" ]]; then
    echo "Running Porechop to remove barcodes."

   PORECHOP=$(which porechop)

   if [ -z "$PORECHOP" ]; then

       echo "Error: porechop not found in PATH."
       exit 1
  
   fi
   
   mkdir -p "$WORKING_DIR/porechop_op"
   FASTQ_DIR="$WORKING_DIR/porechop_op"
   
   for fastq_file in $FASTQ_FILES; do 
    "$PORECHOP" -i "$file" -o "$FASTQ_DIR/$(basename "$fastq_file")" --verbosity 2
   done 
   
       echo "Porechop completed."
else
    echo "Skipping Porechop."
    FASTQ_DIR="$WORKING_DIR" 
fi

duration=$SECONDS
echo "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."

SECONDS=0

echo "Starting alignment with Minimap2."

MINIMAP2=$(which minimap2)

if [ -z "$MINIMAP2" ]; then

  echo "Error: minimap2 not found in PATH."
  exit 1
  
fi

mkdir -p "$WORKING_DIR/minimap2_op"

for file in "$FASTQ_DIR"/*.fastq; do
   
    fastq=$(basename "$file" .fastq)
     
    "$MINIMAP2" -ax map-ont "$REFERENCE" "$file" > "$WORKING_DIR/minimap2_op/$(basename "$fastq").sam"
    
done 

echo "Alignment completed"
echo "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."

echo "Converting sam files to sorted bam using samtools."

SAMTOOLS=$(which samtools)

if [ -z "$SAMTOOLS" ]; then

  echo "Error: samtools not found in PATH."
  exit 1
  
fi

mkdir -p "$WORKING_DIR/sorted_bam"

for sam_file in "$WORKING_DIR/minimap2_op"/*.sam; do

    base_name=$(basename "$sam_file" .sam) 
    
    "$SAMTOOLS" sort "$sam_file" -o "$WORKING_DIR/sorted_bam/${base_name}.bam"
    
done

duration=$SECONDS
echo "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."

SECONDS=0

echo "Started indexing bam files."

for bam_file in "$WORKING_DIR/sorted_bam"/*.bam; do

     "$SAMTOOLS" index "$bam_file"
done

mkdir -p "$WORKING_DIR/bam_stat"

for bam_file in "$WORKING_DIR/sorted_bam"/*.bam; do
    bam_stat=$(basename "$bam_file" .bam)
    "$SAMTOOLS" bedcov "$BED_FILE" "${bam_file}" > "$WORKING_DIR/bam_stat/${bam_stat}.coverage"
    "$SAMTOOLS" depth -b "$BED_FILE" "${bam_file}" > "$WORKING_DIR/bam_stat/${bam_stat}.depth"
    "$SAMTOOLS" flagstat "${bam_file}" > "$WORKING_DIR/bam_stat/${bam_stat}.stat"  
done

mkdir  -p "$WORKING_DIR/bam_stat/coverage"
mv $WORKING_DIR/bam_stat/*.coverage $WORKING_DIR/bam_stat/coverage

mkdir  -p "$WORKING_DIR/bam_stat/depth"
mv $WORKING_DIR/bam_stat/*.depth $WORKING_DIR/bam_stat/depth

mkdir  -p "$WORKING_DIR/bam_stat/flagstat"
mv $WORKING_DIR/bam_stat/*.stat $WORKING_DIR/bam_stat/flagstat

echo "Completed coverage, depth and flagstat"
duration=$SECONDS
echo "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."

SECONDS=0

echo "Started SNPs calling with ClairS-TO."

INPUT_DIR="$HOME/ClairS-TO"


for TUMOR_BAM in "$WORKING_DIR/sorted_bam"/*.bam; do
    BAM="${TUMOR_BAM}"
    docker run -it \
      -v "${INPUT_DIR}:${INPUT_DIR}" \
      -v "${WORKING_DIR}:${WORKING_DIR}" \
      hkubal/clairs-to:latest \
      /opt/bin/run_clairs_to \
     --tumor_bam_fn "${BAM}" \
     --ref_fn "${REFERENCE}" \
     --threads "${THREADS}" \
     --bed_fn "${BED_FILE}" \
     --qual "${QUALITY}" \
     --platform "${PLATFORM}" \
     --apply_haplotype_filtering False \
     $DISABLE_INDEL_CALLING \
     --output_dir "${WORKING_DIR}/ClairS_TO/$(basename "${BAM%.*}")_clairs_to"
done
 

echo "Completed ClairS-TO SNPs calling"
duration=$SECONDS
echo "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."

SECONDS=0

echo "Converting VCF files to CSV output."

for sample_dir in "$WORKING_DIR"/ClairS_TO/*_clairs_to/; do
    sample_name=$(basename "$sample_dir")
    
    input_vcf="${sample_dir}/snv.vcf.gz"
    filtered_vcf="$WORKING_DIR/${sample_name}_filtered.vcf"
    temp_vcf="$WORKING_DIR/${sample_name}_temp.vcf"
    snv_vcf1="$WORKING_DIR/${sample_name}_snv.vcf"
    
    mkdir -p "$WORKING_DIR/snv_vcf"
    cp "$input_vcf" "$WORKING_DIR/snv_vcf/${sample_name}_snv.vcf.gz"
    
    gunzip "$WORKING_DIR/snv_vcf/${sample_name}_snv.vcf.gz"
    
    BCFTOOLS=$(which bcftools)


    if [ -z "$BCFTOOLS" ]; then

    echo "Error: bcftools not found in PATH."
    exit 1
  
    fi
    
    "$BCFTOOLS" query -f '%CHROM\t%POS\t%REF\t%ALT\t%QUAL\t%FILTER[\t%FAU\t%FCU\t%FGU\t%FTU\t%RAU\t%RCU\t%RGU\t%RTU][\t%GT\t%GQ\t%DP\t%AF\t%AD\t%AU\t%CU\t%GU\t%TU]\n' "$input_vcf" > "$filtered_vcf"
    
    awk -F ',' '{split($19, a, " "); $19 = a[1]; $20 = a[2]; print $0;}' "$filtered_vcf" > "$temp_vcf"
    
    awk 'BEGIN {
        header = "Chromosome\tPosition\tReference_Allele\tAlternate_Allele\tQuality\tFilter\tCount_of_A_in_forward_strand_in_the_tumor_BAM\tCount_of_C_in_forward_strand_in_the_tumor_BAM\tCount_of_G_in_forward_strand_in_the_tumor_BAM\tCount_of_T_in_forward_strand_in_the_tumor_BAM\tCount_of_A_in_reverse_strand_in_the_tumor_BAM\tCount_of_C_in_reverse_strand_in_the_tumor_BAM\tCount_of_G_in_reverse_strand_in_the_tumor_BAM\tCount_of_T_in_reverse_strand_in_the_tumor_BAM\tGenotype\tGenotype_Quality\tReadDepth\tVAF\tAllelic_depth_ref\tAllelic_depth_for_alt\tCount_of_A_in_the_tumor_BAM\tCount_of_C_in_the_tumor_BAM\tCount_of_G_in_the_tumor_BAM\tCount_of_T_in_the_tumor_BAM"
        print header
    } 
    {
        print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7"\t"$8"\t"$9"\t"$10"\t"$11"\t"$12"\t"$13"\t"$14"\t"$15"\t"$16"\t"$17"\t"$18"\t"$19"\t"$20"\t"$21"\t"$22"\t"$23"\t"$24
    }' "$temp_vcf" > "$snv_vcf1"

    cut -f18 -d$'\t' "$snv_vcf1" > "$WORKING_DIR/${sample_name}_vaf.txt"


    awk 'BEGIN {print "RAF"} {if ($1 ~ /^[0-9.]+$/) print 1 - $1}' "$WORKING_DIR/${sample_name}_vaf.txt" > "$WORKING_DIR/${sample_name}_ref_allele_frequency.txt"


    paste "$snv_vcf1" "$WORKING_DIR/${sample_name}_ref_allele_frequency.txt" > "$WORKING_DIR/${sample_name}_final_snv.vcf"

    awk 'BEGIN {FS="\t"; OFS=","} {print}' "$WORKING_DIR/${sample_name}_final_snv.vcf" > "$WORKING_DIR/${sample_name}_final_snv.csv"

    rm "$filtered_vcf" "$temp_vcf"
    
    mkdir -p "$WORKING_DIR/final_vcf"
    mv "$WORKING_DIR/${sample_name}_final_snv.vcf" "$WORKING_DIR/final_vcf/"
    
    mkdir -p "$WORKING_DIR/snv_csv_output"
    mv "$WORKING_DIR/${sample_name}_final_snv.csv" "$WORKING_DIR/snv_csv_output/"
    
    rm -rvf "$WORKING_DIR/final_vcf/"
    rm -rvf "$WORKING_DIR"/*.vcf
    rm -rvf "$WORKING_DIR"/*.txt
    
done

echo "Completed converting VCF files to CSV output."

mkdir -p "$WORKING_DIR/snp_plot"

for csv_file in "$WORKING_DIR/snv_csv_output"/*.csv; do
        base_name=$(basename "$csv_file".csv)
        Rscript ~/TOSMuVar/src/snp_plot.R "$csv_file"
done

mv $WORKING_DIR/snv_csv_output/*_to_final_snv "$WORKING_DIR/snp_plot"

duration=$SECONDS
echo "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."

for sample_dir in "$WORKING_DIR"/ClairS_TO/*_clairs_to/; do
    sample_name=$(basename "$sample_dir")
      
    
    if [[ "$DISABLE_INDEL_CALLING" != "--disable_indel_calling" ]]; then
    
    	input_vcf="${sample_dir}/indel.vcf.gz"
    	filtered_vcf="$WORKING_DIR/${sample_name}_filtered.vcf"
    	temp_vcf="$WORKING_DIR/${sample_name}_temp.vcf"
    	indel_vcf1="$WORKING_DIR/${sample_name}_indel.vcf"
    	mkdir -p "$WORKING_DIR/indel_vcf"
        cp "$input_vcf" "$WORKING_DIR/indel_vcf/${sample_name}_indel.vcf.gz"
        gunzip "$WORKING_DIR/indel_vcf/${sample_name}_indel.vcf.gz"
    	
  	BCFTOOLS=$(which bcftools)


    	if [ -z "$BCFTOOLS" ]; then

    	echo "Error: bcftools not found in PATH."
   	exit 1
  
    	fi
    
    	"$BCFTOOLS" query -f '%CHROM\t%POS\t%REF\t%ALT\t%QUAL\t%FILTER[\t%FAU\t%FCU\t%FGU\t%FTU\t%RAU\t%RCU\t%RGU\t%RTU][\t%GT\t%GQ\t%DP\t%AF\t%AD\t%AU\t%CU\t%GU\t%TU]\n' "$input_vcf" > "$filtered_vcf"
    
    	awk -F ',' '{split($19, a, " "); $19 = a[1]; $20 = a[2]; print $0;}' "$filtered_vcf" > "$temp_vcf"
    
    	awk 'BEGIN {
        header = "Chromosome\tPosition\tReference_Allele\tAlternate_Allele\tQuality\tFilter\tCount_of_A_in_forward_strand_in_the_tumor_BAM\tCount_of_C_in_forward_strand_in_the_tumor_BAM\tCount_of_G_in_forward_strand_in_the_tumor_BAM\tCount_of_T_in_forward_strand_in_the_tumor_BAM\tCount_of_A_in_reverse_strand_in_the_tumor_BAM\tCount_of_C_in_reverse_strand_in_the_tumor_BAM\tCount_of_G_in_reverse_strand_in_the_tumor_BAM\tCount_of_T_in_reverse_strand_in_the_tumor_BAM\tGenotype\tGenotype_Quality\tReadDepth\tVAF\tAllelic_depth_ref\tAllelic_depth_for_alt\tCount_of_A_in_the_tumor_BAM\tCount_of_C_in_the_tumor_BAM\tCount_of_G_in_the_tumor_BAM\tCount_of_T_in_the_tumor_BAM"
        print header
    } 
    {
        print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7"\t"$8"\t"$9"\t"$10"\t"$11"\t"$12"\t"$13"\t"$14"\t"$15"\t"$16"\t"$17"\t"$18"\t"$19"\t"$20"\t"$21"\t"$22"\t"$23"\t"$24
    }' "$temp_vcf" > "$indel_vcf1"

    	cut -f18 -d$'\t' "$indel_vcf1" > "$WORKING_DIR/${sample_name}_indel_vaf.txt"


    	awk 'BEGIN {print "RAF"} {if ($1 ~ /^[0-9.]+$/) print 1 - $1}' "$WORKING_DIR/${sample_name}_indel_vaf.txt" > "$WORKING_DIR/${sample_name}_indel_ref_allele_frequency.txt"


    	paste "$indel_vcf1" "$WORKING_DIR/${sample_name}_indel_ref_allele_frequency.txt" > "$WORKING_DIR/${sample_name}_final_indel.vcf"

    	awk 'BEGIN {FS="\t"; OFS=","} {print}' "$WORKING_DIR/${sample_name}_final_indel.vcf" > "$WORKING_DIR/${sample_name}_final_indel.csv"

    	rm "$filtered_vcf" "$temp_vcf"
    
    	mkdir -p "$WORKING_DIR/final_vcf"
    	mv "$WORKING_DIR/${sample_name}_final_indel.vcf" "$WORKING_DIR/final_vcf/"
    
    	mkdir -p "$WORKING_DIR/indel_csv_output"
    	mv "$WORKING_DIR/${sample_name}_final_indel.csv" "$WORKING_DIR/indel_csv_output/"
    
    	rm -rvf "$WORKING_DIR/final_vcf/"
    	rm -rvf "WORKING_DIR"/*.vcf
    	rm -rvf "$WORKING_DIR"/*.txt
    	echo "Completed converting VCF files to CSV output."
    else
        echo "Indel calling is disabled. Skipping indel processing for sample: $sample_name."
    fi
done

duration=$SECONDS
echo "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."
