#!/bin/bash

# Stage server directory to monitor
WATCH_DIR="/vol/efs"

# Log file
LOG_FILE="/var/log/stage_server.log"

# ACEMID upload script to be called
ACEMID_UPLOAD_SCRIPT="./ACEMID_data_uploader.sh"

# In this script, we use inotify-tools to monitor changes to files and directories in real time
# Check if inotifywait is installed or not
if ! command -v inotifywait &> /dev/null; then
    echo "Error: inotifywait is not installed. Please install inotify-tools."
    exit 1
fi

# Check if the ACEMID upload script is exists
if [ ! -x "ACEMID_UPLOAD_SCRIPT" ]; then
    echo "Error: ACEMID Upload script is not found at $ACEMID_UPLOAD_SCRIPT"
    exit 1
fi

echo "Monitoring $WATCH_DIR for new files and directories..."
echo "Logging to $LOG_FILE"

# Start monitoring the stage server
inotifywait -m -e create --format '%w%f' "$WATCH_DIR" | while read NEW_ENTRY
do
    if [ -d "$NEW_ENTRY" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - New directory detected: $NEW_ENTRY" | tee -a "$LOG_FILE"
        "$ACEMID_UPLOAD_SCRIPT" "$NEW_ENTRY"  >> $LOG_FILE 2>&1
    elif [ -f "$NEW_ENTRY" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - New file detected: $NEW_ENTRY" | tee -a "$LOG_FILE"
        "$ACEMID_UPLOAD_SCRIPT" "$NEW_ENTRY"  >> $LOG_FILE 2>&1
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - New item detected (unknown type): $NEW_ENTRY" | tee -a "$LOG_FILE"
        "$ACEMID_UPLOAD_SCRIPT" "$NEW_ENTRY"  >> $LOG_FILE 2>&1
    fi
done
