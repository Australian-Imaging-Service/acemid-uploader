#!/bin/bash

# XNAT server URL
XNAT_URL="your_xnat_url"

# XNAT credentials
USERNAME="your_xnat_username"
PASSWORD="your_xnat_password"

# Get JSESSION ID
JS_ID=$(curl -u $USERNAME:$PASSWORD -X POST $XNAT_URL/data/JSESSION)
echo "JSESSION_ID is $JS_ID"

# Project ID
PROJECT_ID="your_xnat_project_id"

# Create the "error" directory if it doesn't exist
mkdir -p error

# Function to measure transfer speed
measure_transfer_speed() {
    timestamp=$(date -Iseconds)
    local operation=$1
    local url=$2
    local output_file=$3
    local format_string='{
        "operation": "'"$operation"'",
        "timestamp": "'"$timestamp"'",
        "url": "%{url_effective}",
        "http_code": %{http_code},
        "time_total": %{time_total},
        "size_upload": %{size_upload},
        "size_download": %{size_download},
        "speed_upload": %{speed_upload},
        "speed_download": %{speed_download}
    }'

    curl --cookie JSESSIONID=$JS_ID -X PUT "$url" -F "file=@$output_file" -w "$format_string" -o /dev/null >> transfer_log.json
}

# Loop through all .db files in the current directory
for file in *.db; do
    if [[ -f "$file" ]]; then
        filename=$(basename "$file" .db)
        before_underscore=${filename%%_*}
        after_underscore=${filename#*_}

        if [[ -z "$before_underscore" ]]; then
            mv "$file" error/
            echo "Moved $file to error/ directory due to empty part before underscore."
            mv "$after_underscore" error
        else
            echo "File: $file"
            echo "Before underscore: $before_underscore"
            echo "After underscore: $after_underscore"

            TEMP_DIR="temp_$filename"
            mkdir -p "$TEMP_DIR"
            cp -r "$after_underscore" "$TEMP_DIR/"

            for dir in "$after_underscore"/*/ ; do
                if [ -d "$dir" ]; then
                    dir_name=$(basename "$dir")
                    zip -r "${dir_name}.zip" "$dir"
                    mv "${dir_name}.zip" "$dir"
                    find "$dir" -mindepth 1 ! -name "${dir_name}.zip" -exec rm -rf {} +
                fi
            done

            find "$after_underscore" -type f -name "*.zip" | while read -r FILENAME; do
                echo "Filename: $FILENAME"

                SUBJECT_ID=$before_underscore
                SESSION_ID=$(echo $FILENAME | cut -d'/' -f2)
                SCAN_ID=$(echo $FILENAME | cut -d'/' -f3 | cut -d'.' -f1)

                SUBJECT_LABEL=$SUBJECT_ID
                SESSION_LABEL=$SESSION_ID
                echo "Subject ID: $SUBJECT_ID"
                echo "Session ID: $SESSION_ID"
                echo "Scan ID: $SCAN_ID"

                RESPONSE=$(curl --cookie JSESSIONID=$JS_ID -X GET "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/$SESSION_ID" -w "%{http_code}" -o /dev/null)
                if [ "$RESPONSE" -eq 200 ]; then
                    echo "Session $SESSION_ID already exists. Skipping creation."
                else
                    curl --cookie JSESSIONID=$JS_ID -X PUT "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID?label=$SUBJECT_LABEL" -H "Content-Type: application/json" -H "Content-Length: 0"

                    SESSION_TYPE="xnat:xcSessionData"
                    RESPONSE=$(curl --cookie JSESSIONID=$JS_ID -X PUT "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/$SESSION_ID?xsiType=$SESSION_TYPE&label=${SESSION_LABEL}_single_zip" -H "Content-Type: application/json" -H "Content-Length: 0" -w "%{http_code}" -o /dev/null)
                    RESPONSE=$(curl --cookie JSESSIONID=$JS_ID -X PUT "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/$SESSION_ID?xsiType=$SESSION_TYPE&label=${SESSION_LABEL}_loose_files" -H "Content-Type: application/json" -H "Content-Length: 0" -w "%{http_code}" -o /dev/null)

                    if [ "$RESPONSE" -eq 200 ] || [ "$RESPONSE" -eq 201 ]; then
                        echo "Session created successfully."
                    else
                        echo "Failed to create session. HTTP response code: $RESPONSE"
                        exit 1
                    fi
                fi

                SCAN_TYPE="xnat:xcScanData"
                RESPONSE=$(curl --cookie JSESSIONID=$JS_ID -X PUT "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/${SESSION_ID}_single_zip/scans/$SCAN_ID?xsiType=$SCAN_TYPE" -H "Content-Type: application/json" -H "Content-Length: 0" -w "%{http_code}" -o /dev/null)
                RESPONSE=$(curl --cookie JSESSIONID=$JS_ID -X PUT "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/${SESSION_ID}_loose_files/scans/$SCAN_ID?xsiType=$SCAN_TYPE" -H "Content-Type: application/json" -H "Content-Length: 0" -w "%{http_code}" -o /dev/null)

                if [ "$RESPONSE" -eq 200 ] || [ "$RESPONSE" -eq 201 ]; then
                    echo "Scan created successfully."
                else
                    echo "Failed to create scan. HTTP response code: $RESPONSE"
                    exit 1
                fi

                # Upload with transfer speed measurement
                measure_transfer_speed "single_zip_upload" "$XNAT_URL/data/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/${SESSION_ID}_single_zip/scans/$SCAN_ID/resources/RAW/files?extract=false" "$FILENAME"
                measure_transfer_speed "loose_files_upload" "$XNAT_URL/data/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/${SESSION_ID}_loose_files/scans/$SCAN_ID/resources/RAW/files?extract=true" "$FILENAME"

            done
        fi
    fi
done
