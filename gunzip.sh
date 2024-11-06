#!/bin/bash

usage="$(basename "$0") [-w working_dir] "



WORKING_DIR="."

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

BARCODE_FOLDERS=$(find "$WORKING_DIR" -maxdepth 2 -name "*.fastq.gz")


for BARCODE_FOLDER in $BARCODE_FOLDERS; do
   
    gunzip "$BARCODE_FOLDER"
    
    OUTPUT_FASTQ="${BARCODE_FOLDER%.fastq}"
    
done
