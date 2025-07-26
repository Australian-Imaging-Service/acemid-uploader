#!/bin/bash

# XNAT server URL
XNAT_URL="your_xnat_url"

# XNAT credentials
USERNAME="your_xnat_username"
PASSWORD="your_xnat_password"

# XNAT Project ID
PROJECT_ID="your_xnat_project_id"

# Check if the user has provided a csv input file or not
if [ -z "$1" ]; then
  echo "Usage: $0 <input_csv_file>"
  exit 1
fi

input_file="$1"

# Ensure csvkit is installed, we use it to process the csv files
if ! command -v csvcut &> /dev/null || ! command -v csvgrep &> /dev/null; then
  echo "csvkit is required but not installed. Install it using 'pip install csvkit'."
  exit 1
fi

# Extract unique PatientMRN values
patient_mrns=$(csvcut -c PatientMRN "$input_file" | tail -n +2 | sort | uniq)
echo "Patient mrn is: $patient_mrns"

# Extract unique ImagePath values
patient_image_path=$(csvcut -c ImagePath "$input_file" | tail -n +2 | sort | uniq)


# Extract the part before the forward slash and remove the unwanted characters
patient_image_path=$(echo "$patient_image_path" | awk -F'/' '{print $1}' | sed 's/=HYPERLINK(""//; s/"")//' | tr -d '"' | head -n 1)
echo "Patient image path is: $patient_image_path"

# Create a directory to store the output csv files ordered by per patient
output_dir="per_patient_csv_files"
mkdir -p "$output_dir"

# Split the CSV file based on unique PatientMRN values and remove specified columns
while IFS= read -r mrn; do
  temp_file="temp_${mrn}.csv"
  output_file="$output_dir/patient_${mrn}.csv"

  # Extract rows for the current PatientMRN
  csvgrep -c PatientMRN -m "$mrn" "$input_file" > "$temp_file"

  # Remove specified columns
  csvcut -C LastName,FirstName,DOB,PatientNotes "$temp_file" > "$output_file"

  # Remove the temporary file
  rm "$temp_file"

  echo "Created file: $output_file"
done <<< "$patient_mrns"

echo "Split csv files ordered by per patient created in directory: $output_dir"

# -------------------------------
# Prepare the Zip file for upload
# -------------------------------

# Extract the folder name from the first ImagePath entry
image_folder=$(csvcut -c ImagePath "$input_file" | tail -n +2 | head -n 1 | sed 's/=HYPERLINK(""//; s/"")//; s/^"//; s/"$//' | cut -d'/' -f1)

if [ -z "$image_folder" ]; then
  echo "No valid ImagePath found in CSV."
  exit 1
fi

echo "Image folder identified: $image_folder"

# Create the folder if it doesn't exist
mkdir -p "$image_folder"

# Copy all .jpg and .png files listed in ImagePath into the folder
csvcut -c ImagePath "$input_file" | tail -n +2 | while IFS= read -r raw_path; do
  # Clean up Excel-style HYPERLINK formatting
  clean_path=$(echo "$raw_path" | sed 's/=HYPERLINK(""//; s/"")//; s/^"//; s/"$//')

  src_file="$clean_path"
  if [ -f "$src_file" ]; then
    cp "$src_file" "$image_folder/"
  else
    echo "Warning: File not found - "$src_file""
  fi
done

# Create a zip archive of the folder
zip_file="${image_folder}.zip"
zip -r "$zip_file" "$image_folder"

# Set the zip file path for upload
FILE_PATH="$zip_file"


# Check if the ZIP file exists
if [ ! -f "$FILE_PATH" ]; then
  echo "Error: ZIP file '$FILE_PATH' not found. Skipping upload."
  exit 1
fi


for SUBJECT_ID in $patient_mrns
do
  SUBJECT_LABEL=$SUBJECT_ID
  SESSION_ID=$SUBJECT_ID
  SCAN_ID="1"

  # Create the subject ID
  curl -u $USERNAME:$PASSWORD -X PUT "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID?label=$SUBJECT_LABEL" -H "Content-Type: application/json" -H "Content-Length: 0" &

  # Create the session
  SESSION_TYPE="xnat:xcSessionData"
  SESSION_LABEL=$SESSION_ID
  curl -u $USERNAME:$PASSWORD -X PUT "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/$SESSION_ID?xsiType=$SESSION_TYPE&label=${SESSION_LABEL}" -H "Content-Type: application/json" -H "Content-Length: 0" &

  # Create the scan
  SCAN_TYPE="xnat:xcScanData"
  curl -u $USERNAME:$PASSWORD -X PUT "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/${SESSION_ID}/scans/$SCAN_ID?xsiType=$SCAN_TYPE" -H "Content-Type: application/json" -H "Content-Length: 0" &

  # Upload the file
  curl -u $USERNAME:$PASSWORD -X PUT "$XNAT_URL/data/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/${SESSION_ID}/scans/$SCAN_ID/resources/RAW/files?extract=true" -F "file=@$FILE_PATH"
done

echo "dermoscopy image data upload complete!"
