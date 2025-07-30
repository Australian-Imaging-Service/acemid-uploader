# The bash script used to upload DICOM data (including huge size DICOM data) to your XNAT instance using Chunked method.
#!/bin/bash

# The following bash script use chunked method to support uploading large DICOM file to XNAT.
# Set your XNAT credentials
XNAT_URL="your_xnat_url"
USERNAME="your_xnat_username"
PASSWORD="your_xnat_password"

# Only need to specify the project id
PROJECT_ID="your_xnat_project_id"

# List of zip file names (modify as needed)
ZIP_FILES=("first.zip" "second.zip" "third.zip" "fourth.zip" "fifth.zip" "sixth.zip")

# Loop through the zip files and upload them
for ZIP_FILE in "${ZIP_FILES[@]}"; do
    zip_file_without_extension="${ZIP_FILE%.zip}"
    # check if the file exists on the server or not
    FILE_EXISTS=$(curl -s -o /dev/null -w "%{http_code}" -u $USERNAME:$PASSWORD -k -X HEAD "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$zip_file_without_extension")
    # if the file is on the XNAT server
    if [ "$FILE_EXISTS" == "200" ]; then
        # If file exists, check if file is complete
        SERVER_SIZE=$(curl -s -u $USERNAME:$PASSWORD -k -X GET "$XNAT_URL/data/archive/projects/$PROJECT_ID/subjects/$zip_file_without_extension" | grep -oP 'size="\K[^"]+')
        LOCAL_SIZE=$(stat -c %s $ZIP_FILE)
        # Compare the file on local with the file on server, and if the size is same, then upload is completed.
        if [ "$SERVER_SIZE" == "$LOCAL_SIZE" ]; then
            echo "File $ZIP_FILE already uploaded."
        # Otherwise resume the upload from the previous break point
        else
            # Resume upload
            curl -o /tmp/u.tmp -u $USERNAME:$PASSWORD -k -H 'Content-Type: application/zip' -H 'Transfer-Encoding: chunked' -C - -X POST "$XNAT_URL/data/services/import?inbody=true&PROJECT_ID=$PROJECT_ID&overwrite=true" -T $ZIP_FILE
        fi
    else
        # if file does not exist, do a new fresh upload for it.
        curl -o /tmp/u.tmp -u $USERNAME:$PASSWORD -k -H 'Content-Type: application/zip' -H 'Transfer-Encoding: chunked' -X POST "$XNAT_URL/data/services/import?inbody=true&PROJECT_ID=$PROJECT_ID&overwrite=true" -T $ZIP_FILE
    fi
done
