#!/bin/bash

# XNAT server URL
XNAT_URL="your-xnat-url"

# XNAT credentials
USERNAME="your-xnat-username"
PASSWORD="your-xnat-password"

# XNAT Project ID
PROJECT_ID="your-xnat-project-id"

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
patient_image=$(csvcut -c ImagePath "$input_file" | tail -n +2 | sort | uniq)
echo "Patient image path is: $patient_image"

# Extract the part before the forward slash and remove the unwanted characters
patient_image_path=$(echo "$patient_image" | awk -F'/' '{print $1}' | sed 's/=HYPERLINK(""//; s/"")//' | tr -d '"' | head -n 1)
echo "Patient image path is: $patient_image_path"

patient_image_name=$(echo "$patient_image" | sed -E 's/^=HYPERLINK\("//; s/"\)\)"$//' | awk -F'/' '{print $2}' | sed 's/"//g' | sed 's/)$//')
echo "Image name is: $patient_image_name"

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

# Filter image files that match the patient_image_name
matching_images=$(find . -type f \( -iname "*.jpg" -o -iname "*.png" \) | grep -F "$patient_image_name")

if [ -z "$matching_images" ]; then
  echo "No matching image files found for name: $patient_image_name. Skipping zip creation."
  exit 1
else
  echo "Found matching image files. Creating zip archive..."
  zip -r dermoscopy_images.zip $matching_images
  patient_image_path="dermoscopy_images"
  FILE_PATH="${patient_image_path}.zip"
fi

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

  echo "Creating subject: $SUBJECT_ID with label: $SUBJECT_LABEL"
  echo "curl -u $USERNAME:$PASSWORD -X PUT \"$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID?label=$SUBJECT_LABEL\" -H \"Content-Type: application/json\" -H \"Content-Length: 0\""
  curl -u $USERNAME:$PASSWORD -X PUT "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID?label=$SUBJECT_LABEL" -H "Content-Type: application/json" -H "Content-Length: 0"

  SESSION_TYPE="xnat:xcSessionData"
  SESSION_LABEL=$SESSION_ID
  echo "Creating session: $SESSION_ID with label: $SESSION_LABEL"
  echo "curl -u $USERNAME:$PASSWORD -X PUT \"$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/$SESSION_ID?xsiType=$SESSION_TYPE&label=${SESSION_LABEL}\" -H \"Content-Type: application/json\" -H \"Content-Length: 0\""
  curl -u $USERNAME:$PASSWORD -X PUT "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/$SESSION_ID?xsiType=$SESSION_TYPE&label=${SESSION_LABEL}" -H "Content-Type: application/json" -H "Content-Length: 0"

  SCAN_TYPE="xnat:xcScanData"
  echo "Creating scan: $SCAN_ID for session: $SESSION_ID"
  echo "curl -u $USERNAME:$PASSWORD -X PUT \"$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/${SESSION_ID}/scans/$SCAN_ID?xsiType=$SCAN_TYPE\" -H \"Content-Type: application/json\" -H \"Content-Length: 0\""
  curl -u $USERNAME:$PASSWORD -X PUT "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/${SESSION_ID}/scans/$SCAN_ID?xsiType=$SCAN_TYPE" -H "Content-Type: application/json" -H "Content-Length: 0"

  echo "Uploading file: $FILE_PATH to scan: $SCAN_ID"
  echo "curl -u $USERNAME:$PASSWORD -X PUT \"$XNAT_URL/data/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/${SESSION_ID}/scans/$SCAN_ID/resources/RAW/files?extract=true\" -F \"file=@$FILE_PATH\""
  curl -u $USERNAME:$PASSWORD -X PUT "$XNAT_URL/data/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/${SESSION_ID}/scans/$SCAN_ID/resources/RAW/files?extract=true" -F "file=@$FILE_PATH"
done

echo "dermoscopy image data upload complete!"
