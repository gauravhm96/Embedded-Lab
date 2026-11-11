#!/bin/bash
set -e

#TEMP_DIR="/mnt/usb/temp_folder"

TEMP_DIR="/mnt/usb/Linux/myworkspace/temp_folder"

if mountpoint -q "$TEMP_DIR"; then
    fusermount3 -u "$TEMP_DIR"
    echo "Encrypted successfully."
else
    echo "Already Encrypted."
fi

if [ -d "$TEMP_DIR" ] && [ -z "$(ls -A "$TEMP_DIR")" ];then
	rmdir "$TEMP_DIR"
else
	echo "Folder Not Empty"
fi
