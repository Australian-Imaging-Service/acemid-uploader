#!/bin/bash

#create more robust scripts by ensuring that they terminate on errors, do not reference unset variables, and correctly report failures in command pipelines.
set -euo pipefail

#print each command before executing it for debug purpose
set -x

# Check for required tools for uploader
for cmd in curl zip find basename mkdir mv cp; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: $cmd is not installed."; exit 1; }
done

# XNAT server URL
XNAT_URL="your_xnat_url"

# XNAT credentials
USERNAME="your_xnat_username"
PASSWORD="your_xnat_password"

JS_ID=$(curl -u $USERNAME:$PASSWORD -X POST $XNAT_URL/data/JSESSION)
echo "JSESSION_ID is $JS_ID"

# Project ID
PROJECT_ID="your_xnat_project_id"

# Create the "error" directory if it doesn't exist
mkdir -p error

# Loop through all .db files in the current directory
for file in *.db; do
    # Check if the file exists
    if [[ -f "$file" ]]; then
        # Extract the filename without the extension
        filename=$(basename "$file" .db)
        
        # Extract the part before and after the underscore
        before_underscore=${filename%%_*}
        after_underscore=${filename#*_}
        
        # Check if the part before the underscore is empty
        if [[ -z "$before_underscore" ]]; then
            # Move the file to the "error" directory
            mv "$file" error/
            echo "Moved $file to error/ directory due to empty part before underscore."
            # Move the folder $after_underscore to "error" directory
            mv "$after_underscore" error
        else
            # Print the results
            echo "File: $file"
            echo "Before underscore: $before_underscore"
            echo "After underscore: $after_underscore"
            echo "zip files in progress and it will take some time, please wait ..."

            # Add the zip process, before zip, make sure the temp folder holds the original data
            TEMP_DIR="temp_$filename"
            mkdir -p "$TEMP_DIR"
            cp -r "$after_underscore" "$TEMP_DIR/"

            # Loop through all items in the after_underscore directory
            for dir in "$after_underscore"/*/ ; do
                # Check if the item is a directory
                if [ -d "$dir" ]; then
                    # Remove the trailing slash from the directory name
                    dir_name=$(basename "$dir")
                    # Include the .db file in the upload
                    cp "$file" "$dir" 
                    # split into chunks of a maximum size of 2GB. 
                    zip -s 2g -r "${dir_name}.zip" "$dir"
                    # Move the zip file into the original directory
                    mv "${dir_name}.zip" "$dir"
                    # Remove all files and folders in the original directory except the zip file
                    find "$dir" -mindepth 1 ! -name "${dir_name}.zip" -exec rm -rf {} +
                fi
            done

            # Loop through all zip files in the current directory and its subdirectories
            find "$after_underscore" -type f -name "*.zip" | while read -r ZIP_FILE; do
                 echo "Processing zip file: $ZIP_FILE"

                 # Check if the file is the start of a multi-part zip file
                 if ! unzip -l "$ZIP_FILE" > /dev/null 2>&1; then
                     echo "Skipping multi-part zip file component: $ZIP_FILE"
                     continue
                 fi

                 # Extract the base name and extension from the file path
                 BASE_FILENAME=$(basename "$ZIP_FILE" .zip)
                 DIR_NAME=$(basename "$(dirname "$ZIP_FILE")")

                 # Use before_underscore as SUBJECT_ID
                SUBJECT_ID=$before_underscore
                SESSION_ID=$DIR_NAME
                SCAN_ID=$BASE_FILENAME

                echo "Subject ID: $SUBJECT_ID"
                echo "Session ID: $SESSION_ID"
                echo "Scan ID: $SCAN_ID"

                # Subject label and session label can be the same as their IDs or customized
                SUBJECT_LABEL=$SUBJECT_ID
                SESSION_LABEL=$SESSION_ID
             
                # Check if the session already exists
                RESPONSE=$(curl --cookie JSESSIONID=$JS_ID -X GET "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/$SESSION_ID" -w "%{http_code}" -o /dev/null)
                if [ "$RESPONSE" -eq 200 ]; then
                    echo "Session $SESSION_ID already exists. Skipping creation."
                else
                    # Create a subject
                    curl --cookie JSESSIONID=$JS_ID -X PUT "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID?label=$SUBJECT_LABEL" -H "Content-Type: application/json" -H "Content-Length: 0" &

                    # Create a session (experiment) with session type
                    SESSION_TYPE="xnat:xcSessionData"  # Replace with the correct session type
                    # Check if the SESSION_LABEL is numeric



                    if [[ "$SESSION_LABEL" =~ ^[0-9]{14}$ || "$SESSION_LABEL" =~ ^[0-9]{17}$ ]]; then
                       DATE_INPUT="${SESSION_LABEL:0:8}"

                       # Try GNU-style first
                       if FORMATTED_DATE=$(date -d "$DATE_INPUT" "+%Y-%m-%d" 2>/dev/null); then
                           :
                       # Fallback to BSD-style
                       elif FORMATTED_DATE=$(date -j -f "%Y%m%d" "$DATE_INPUT" "+%Y-%m-%d" 2>/dev/null); then
                           :
                       else
                          echo "Invalid date format: $DATE_INPUT"
                          FORMATTED_DATE=""
                       fi

                       if [[ -n "$FORMATTED_DATE" ]]; then
                          echo "Folder name is numeric and date stamp inserted: $FORMATTED_DATE"
                          RESPONSE=$(curl --cookie JSESSIONID=$JS_ID -X PUT "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/$SESSION_ID?xsiType=$SESSION_TYPE&label=${SESSION_LABEL}_single_zip&date=$FORMATTED_DATE" -H "Content-Type: application/json" -H "Content-Length: 0" -w "%{http_code}" -o /dev/null)
                          RESPONSE=$(curl --cookie JSESSIONID=$JS_ID -X PUT "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/$SESSION_ID?xsiType=$SESSION_TYPE&label=${SESSION_LABEL}_loose_files&date=$FORMATTED_DATE" -H "Content-Type: application/json" -H "Content-Length: 0" -w "%{http_code}" -o /dev/null)
                       fi
                    else
                        echo "folder name is not numeric format and skiping insert the date stamp ..."
                        RESPONSE=$(curl --cookie JSESSIONID=$JS_ID -X PUT "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/$SESSION_ID?xsiType=$SESSION_TYPE&label=${SESSION_LABEL}_single_zip" -H "Content-Type: application/json" -H "Content-Length: 0" -w "%{http_code}" -o /dev/null)
                        RESPONSE=$(curl --cookie JSESSIONID=$JS_ID -X PUT "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/$SESSION_ID?xsiType=$SESSION_TYPE&label=${SESSION_LABEL}_loose_files" -H "Content-Type: application/json" -H "Content-Length: 0" -w "%{http_code}" -o /dev/null)
                        continue
                    fi
                    

                    # Check if the session creation was successful
                    if [ "$RESPONSE" -eq 200 ] || [ "$RESPONSE" -eq 201 ]; then
                        echo "Session created successfully."
                    else
                        echo "Failed to create session. HTTP response code: $RESPONSE"
                        exit 1
                    fi
                fi

                # Create a scan
                SCAN_TYPE="xnat:xcScanData"  # Replace with the correct scan type
                RESPONSE=$(curl --cookie JSESSIONID=$JS_ID -X PUT "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/${SESSION_ID}_single_zip/scans/$SCAN_ID?xsiType=$SCAN_TYPE" -H "Content-Type: application/json" -H "Content-Length: 0" -w "%{http_code}" -o /dev/null)
                RESPONSE=$(curl --cookie JSESSIONID=$JS_ID -X PUT "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/${SESSION_ID}_loose_files/scans/$SCAN_ID?xsiType=$SCAN_TYPE" -H "Content-Type: application/json" -H "Content-Length: 0" -w "%{http_code}" -o /dev/null)

                # Check if the scan creation was successful
                if [ "$RESPONSE" -eq 200 ] || [ "$RESPONSE" -eq 201 ]; then
                    echo "Scan created successfully."
                else
                    echo "Failed to create scan. HTTP response code: $RESPONSE"
                    exit 1
                fi

                # Upload the single zip file
                curl --cookie JSESSIONID=$JS_ID -X PUT "$XNAT_URL/data/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/${SESSION_ID}_single_zip/scans/$SCAN_ID/resources/RAW/files?extract=false" -F "file=@$FILENAME" &
                # Upload the extract content file
                curl --cookie JSESSIONID=$JS_ID -X PUT "$XNAT_URL/data/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/${SESSION_ID}_loose_files/scans/$SCAN_ID/resources/RAW/files?extract=true" -F "file=@$FILENAME" &
                               
            done
        fi
    fi
done

