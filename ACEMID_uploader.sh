#!/bin/bash
# XNAT server URL
XNAT_URL="your_xnat_url"
# XNAT credentials
USERNAME="your_xnat_username"
PASSWORD="your_xnat_password"

# Create a directory for speed test logs
mkdir -p speed_logs

# Function to measure and log transfer speeds
measure_transfer_speed() {
    local operation=$1
    local url=$2
    local output_file=$3
    local format_string='{
        "timestamp": "%{time_iso8601}",
        "url": "%{url_effective}",
        "http_code": %{http_code},
        "time_total": %{time_total},
        "size_upload": %{size_upload},
        "size_download": %{size_download},
        "speed_upload": %{speed_upload},
        "speed_download": %{speed_download}
    }'

    # Execute the curl command with the provided arguments and measure speed
    eval "$operation" -w "$format_string" -o "$output_file" 2>> speed_logs/transfer_errors.log

    # Calculate and display human-readable speeds
    if [ -f "$output_file" ]; then
        local json_data=$(cat "$output_file")
        local upload_speed=$(echo "$json_data" | grep -o '"speed_upload": [0-9.]*' | cut -d' ' -f2)
        local download_speed=$(echo "$json_data" | grep -o '"speed_download": [0-9.]*' | cut -d' ' -f2)
        local upload_size=$(echo "$json_data" | grep -o '"size_upload": [0-9.]*' | cut -d' ' -f2)
        local download_size=$(echo "$json_data" | grep -o '"size_download": [0-9.]*' | cut -d' ' -f2)

        # Convert to human-readable format (KB/s, MB/s)
        local upload_speed_hr=$(awk "BEGIN {printf \"%.2f KB/s\", $upload_speed/1024}")
        local download_speed_hr=$(awk "BEGIN {printf \"%.2f KB/s\", $download_speed/1024}")

        if (( $(echo "$upload_speed > 1024*1024" | bc -l) )); then
            upload_speed_hr=$(awk "BEGIN {printf \"%.2f MB/s\", $upload_speed/(1024*1024)}")
        fi

        if (( $(echo "$download_speed > 1024*1024" | bc -l) )); then
            download_speed_hr=$(awk "BEGIN {printf \"%.2f MB/s\", $download_speed/(1024*1024)}")
        fi

        echo "Transfer to $url:"
        echo "  - Upload: $upload_size bytes at $upload_speed_hr"
        echo "  - Download: $download_size bytes at $download_speed_hr"

        # Log the results
        echo "$json_data" >> speed_logs/transfer_speeds.json
    else
        echo "Error: Failed to measure transfer speed for $url"
    fi
}

# Function to test download speed
test_download_speed() {
    local subject_id=$1
    local session_id=$2
    local scan_id=$3
    local js_id=$4

    echo "Testing download speed for scan $scan_id..."

    # Create a temporary file for the download
    local temp_file=$(mktemp)

    # Measure download speed by retrieving scan data
    measure_transfer_speed "curl --cookie JSESSIONID=$js_id -X GET" \
        "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$subject_id/experiments/${session_id}_single_zip/scans/$scan_id" \
        "$temp_file"

    # Clean up
    rm -f "$temp_file"
}

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
                    # Create a zip file for the directory
                    zip -r "${dir_name}.zip" "$dir"
                    # Move the zip file into the original directory
                    mv "${dir_name}.zip" "$dir"
                    # Remove all files and folders in the original directory except the zip file
                    find "$dir" -mindepth 1 ! -name "${dir_name}.zip" -exec rm -rf {} +
                fi
            done
            # Loop through all zip files in the current directory and its subdirectories
            find "$after_underscore" -type f -name "*.zip" | while read -r FILENAME; do
                echo "Filename: $FILENAME"
                # Use before_underscore as SUBJECT_ID
                SUBJECT_ID=$before_underscore
                SESSION_ID=$(echo $FILENAME | cut -d'/' -f2)
                SCAN_ID=$(echo $FILENAME | cut -d'/' -f3 | cut -d'.' -f1)
                # Subject label and session label can be the same as their IDs or customized
                SUBJECT_LABEL=$SUBJECT_ID
                SESSION_LABEL=$SESSION_ID
                echo "Subject ID: $SUBJECT_ID"
                echo "Session ID: $SESSION_ID"
                echo "Scan ID: $SCAN_ID"
                # Check if the session already exists
                RESPONSE=$(curl --cookie JSESSIONID=$JS_ID -X GET "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/$SESSION_ID" -w "%{http_code}" -o /dev/null)
                if [ "$RESPONSE" -eq 200 ]; then
                    echo "Session $SESSION_ID already exists. Skipping creation."
                else
                    # Create a subject
                    curl --cookie JSESSIONID=$JS_ID -X PUT "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID?label=$SUBJECT_LABEL" -H "Content-Type: application/json" -H "Content-Length: 0" &
                    # Create a session (experiment) with session type
                    SESSION_TYPE="xnat:xcSessionData"  # Replace with the correct session type
                    RESPONSE=$(curl --cookie JSESSIONID=$JS_ID -X PUT "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/$SESSION_ID?xsiType=$SESSION_TYPE&label=${SESSION_LABEL}_single_zip" -H "Content-Type: application/json" -H "Content-Length: 0" -w "%{http_code}" -o /dev/null)
                    RESPONSE=$(curl --cookie JSESSIONID=$JS_ID -X PUT "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/$SESSION_ID?xsiType=$SESSION_TYPE&label=${SESSION_LABEL}_loose_files" -H "Content-Type: application/json" -H "Content-Length: 0" -w "%{http_code}" -o /dev/null)
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
                # Upload the single zip file and measure speed
                echo "Uploading and measuring speed for single zip file: $FILENAME"
                UPLOAD_URL="$XNAT_URL/data/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/${SESSION_ID}_single_zip/scans/$SCAN_ID/resources/RAW/files?extract=false"
                TEMP_OUTPUT=$(mktemp)
                measure_transfer_speed "curl --cookie JSESSIONID=$JS_ID -X PUT \"$UPLOAD_URL\" -F \"file=@$FILENAME\"" "$UPLOAD_URL" "$TEMP_OUTPUT"
                rm -f "$TEMP_OUTPUT"

                # Upload the extract content file and measure speed
                echo "Uploading and measuring speed for extracted content: $FILENAME"
                UPLOAD_URL="$XNAT_URL/data/projects/$PROJECT_ID/subjects/$SUBJECT_ID/experiments/${SESSION_ID}_loose_files/scans/$SCAN_ID/resources/RAW/files?extract=true"
                TEMP_OUTPUT=$(mktemp)
                measure_transfer_speed "curl --cookie JSESSIONID=$JS_ID -X PUT \"$UPLOAD_URL\" -F \"file=@$FILENAME\"" "$UPLOAD_URL" "$TEMP_OUTPUT"
                rm -f "$TEMP_OUTPUT"

                # Test download speed after upload is complete
                test_download_speed "$SUBJECT_ID" "$SESSION_ID" "$SCAN_ID" "$JS_ID"

            done
        fi
    fi
done


# Function to display summary statistics of all transfers
display_transfer_summary() {
    echo
    echo "===== XNAT Transfer Speed Summary ====="
    echo

    if [ -f "speed_logs/transfer_speeds.json" ]; then
        # Calculate average upload and download speeds
        local total_upload_size=0
        local total_download_size=0
        local total_upload_time=0
        local total_download_time=0
        local count=0

        while IFS= read -r line; do
            # Extract values from JSON
            local upload_size=$(echo "$line" | grep -o '"size_upload": [0-9.]*' | cut -d' ' -f2)
            local download_size=$(echo "$line" | grep -o '"size_download": [0-9.]*' | cut -d' ' -f2)
            local time_total=$(echo "$line" | grep -o '"time_total": [0-9.]*' | cut -d' ' -f2)

            # Add to totals
            total_upload_size=$(echo "$total_upload_size + $upload_size" | bc)
            total_download_size=$(echo "$total_download_size + $download_size" | bc)

            # Only count time if there was actual data transfer
            if (( $(echo "$upload_size > 0" | bc -l) )); then
                total_upload_time=$(echo "$total_upload_time + $time_total" | bc)
            fi

            if (( $(echo "$download_size > 0" | bc -l) )); then
                total_download_time=$(echo "$total_download_time + $time_total" | bc)
            fi

            count=$((count + 1))
        done < speed_logs/transfer_speeds.json

        # Calculate average speeds
        if (( $(echo "$total_upload_time > 0" | bc -l) )); then
            local avg_upload_speed=$(echo "scale=2; $total_upload_size / $total_upload_time" | bc)
            local avg_upload_speed_kb=$(echo "scale=2; $avg_upload_speed / 1024" | bc)
            local avg_upload_speed_mb=$(echo "scale=2; $avg_upload_speed_kb / 1024" | bc)

            echo "Upload Statistics:"
            echo "  - Total data: $(echo "scale=2; $total_upload_size / (1024*1024)" | bc) MB"
            echo "  - Average speed: $avg_upload_speed_kb KB/s ($avg_upload_speed_mb MB/s)"
        else
            echo "No upload data available."
        fi

        if (( $(echo "$total_download_time > 0" | bc -l) )); then
            local avg_download_speed=$(echo "scale=2; $total_download_size / $total_download_time" | bc)
            local avg_download_speed_kb=$(echo "scale=2; $avg_download_speed / 1024" | bc)
            local avg_download_speed_mb=$(echo "scale=2; $avg_download_speed_kb / 1024" | bc)

            echo "Download Statistics:"
            echo "  - Total data: $(echo "scale=2; $total_download_size / (1024*1024)" | bc) MB"
            echo "  - Average speed: $avg_download_speed_kb KB/s ($avg_download_speed_mb MB/s)"
        else
            echo "No download data available."
        fi

        echo
        echo "Total transfers: $count"
        echo "Detailed logs available in: speed_logs/transfer_speeds.json"
    else
        echo "No transfer data available. Check if any transfers were completed."
    fi

    echo
    echo "======================================"
}

# Display summary at the end of all transfers
display_transfer_summary
