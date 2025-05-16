#!/bin/bash

# Stage server directory to monitor
WATCH_DIR="/vol/efs"

# Log file
LOG_FILE="/var/log/stage_server.log"

# In this script, we use inotify-tools to monitor changes to files and directories in real time
# Check if inotifywait is installed or not
if ! command -v inotifywait &> /dev/null; then
    echo "Error: inotifywait is not installed. Please install inotify-tools."
    exit 1
fi

echo "Monitoring $WATCH_DIR for new files and directories..."
echo "Logging to $LOG_FILE"

# Start monitoring the stage server
inotifywait -m -e create --format '%w%f' "$WATCH_DIR" | while read NEW_ENTRY
do
    if [ -d "$NEW_ENTRY" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - New directory detected: $NEW_ENTRY" | tee -a "$LOG_FILE"
    elif [ -f "$NEW_ENTRY" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - New file detected: $NEW_ENTRY" | tee -a "$LOG_FILE"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - New item detected (unknown type): $NEW_ENTRY" | tee -a "$LOG_FILE"
    fi
done
