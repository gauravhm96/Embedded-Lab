#!/bin/bash
set -euo pipefail

echo "=== Create a New Encrypted Folder ==="

read -r -p "Enter path for the new encrypted folder: " CIPHER_DIR

# Remove trailing slash
CIPHER_DIR="${CIPHER_DIR%/}"

# Validate input
if [[ -z "$CIPHER_DIR" ]]; then
    echo "ERROR: Folder path cannot be empty."
    exit 1
fi

# Prevent overwriting an existing directory
if [[ -e "$CIPHER_DIR" ]]; then
    echo "ERROR: Path already exists: $CIPHER_DIR"
    exit 1
fi

# Create the directory
mkdir -p "$CIPHER_DIR"

# Initialize gocryptfs encryption
if gocryptfs -init "$CIPHER_DIR"; then
    echo
    echo "Encrypted folder created successfully!"
    echo "Location: $CIPHER_DIR"
else
    echo "ERROR: Failed to initialize encryption."
    rmdir "$CIPHER_DIR" 2>/dev/null || true
    exit 1
fi
