#!/bin/bash

# Create the destination directory
destination_dir="your_specified_dermoscopy_data_folder"
mkdir -p "$destination_dir"

# Find all files matching the pattern 'lesion_data_*.json'
find . -type f -name 'lesion_data_*.json' | while read -r file; do
    # Get the immediate parent directory name
    parent_dir=$(basename "$(dirname "$file")")
    # Check if the parent directory is 'analysis'
    if [ "$parent_dir" == "analysis" ]; then
        # Copy the file to the destination directory, preserving the directory structure
        mkdir -p "$destination_dir/$(dirname "$file")"
        cp "$file" "$destination_dir/$(dirname "$file")"
        echo "Copied $file to $destination_dir/$(dirname "$file")"
    fi
done

# Find all files in folders matching the pattern DexiData_*
find . -type f -path '*/DexiData_*/*' | while read -r file; do
    # Get the immediate parent directory name
    parent_dir=$(basename "$(dirname "$file")")
    # Check if the parent directory starts with 'DexiData_' and is not exactly 'DexiData'
    if [[ "$parent_dir" == DexiData_* ]] && [[ "$parent_dir" != "DexiData" ]]; then
        # Copy the file to the destination directory, preserving the directory structure
        mkdir -p "$destination_dir/$(dirname "$file")"
        cp "$file" "$destination_dir/$(dirname "$file")"
        echo "Copied $file to $destination_dir/$(dirname "$file")"
    fi
done
