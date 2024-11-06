#!/bin/bash

usage="$(basename "$0") [-w working_dir] [-d destination_dir_for_merged_fastq] [-m metadata.csv]"

WORKING_DIR="."
DESTINATION_DIR="."
MAP_FILE=""

while :; do
    case "$1" in
        -h | --help)
            echo "$usage"
            exit 0
            ;;
        -w)
            WORKING_DIR=$(realpath "$2")
            shift 2
            ;;
        -d)
            DESTINATION_DIR=$(realpath "$2")
            shift 2
            ;;
        -m)
            METADATA_FILE="$2"
            shift 2
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


if [[ -z "$METADATA_FILE" || ! -f "$METADATA_FILE" ]]; then
    echo "Error: Barcode-sample mapping file not provided or does not exist."
    exit 1
fi

declare -A barcode_map
while read -r barcode sample; do
    barcode_map["$barcode"]="$sample"
done < "$METADATA_FILE"


for folder in "$WORKING_DIR"/*/; do
    barcode=$(basename "$folder")
    
    
    sample_name=${barcode_map["$barcode"]}
    
   
    if [[ -z "$sample_name" ]]; then
        echo "Warning: No sample name found for barcode '$barcode'. Skipping."
        continue
    fi

    all_fastq="${folder}${sample_name}_all.fastq"
    
    folder_fastq_files=$(find "$folder" -name "*.fastq")
    
    if [[ -n "$folder_fastq_files" ]]; then
        cat "$folder"/*.fastq > "$all_fastq"
    fi
    
   
    mv "$all_fastq" "$DESTINATION_DIR"
done

