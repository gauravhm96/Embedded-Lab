#!/bin/bash
set -e

#CIPHER_DIR="/mnt/usb/locked"
#TEMP_DIR="/mnt/usb/temp_folder"

CIPHER_DIR="/mnt/usb/Linux/myworkspace/locked"
TEMP_DIR="/mnt/usb/Linux/myworkspace/temp_folder"

mkdir -p "$TEMP_DIR"

# Check whether already unlocked
if mountpoint -q "$TEMP_DIR"; then
    echo "Already decrypted."
    exit 0
fi

# Unlock the encrypted directory
gocryptfs -allow_other "$CIPHER_DIR" "$TEMP_DIR"


