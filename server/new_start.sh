#!/bin/bash
set -Eeuo pipefail

USB_DIR="/mnt/usb"
CIPHER_DIR="/mnt/usb/Linux/myworkspace/locked"
TEMP_DIR="/mnt/usb/Linux/myworkspace/temp_folder"

NGINX_STARTED=0

cleanup() {
    local status=$?
    trap - EXIT INT TERM HUP

    echo
    echo "=== Stopping Media Server ==="

    # Stop Nginx only if this script started it
    if [[ "$NGINX_STARTED" -eq 1 ]]; then
        if sudo systemctl stop nginx; then
            echo "Nginx stopped."
        else
            echo "ERROR: Could not stop Nginx."
            echo "Leaving encrypted folder mounted for safety."
            exit 1
        fi
    fi

    # Lock the encrypted folder
    if mountpoint -q "$TEMP_DIR"; then
        if command -v fusermount3 >/dev/null 2>&1; then
            FUSERMOUNT="fusermount3"
        else
            FUSERMOUNT="fusermount"
        fi

        if "$FUSERMOUNT" -u "$TEMP_DIR"; then
            echo "Encrypted folder locked."
        else
            echo "ERROR: Unmount failed."
            echo "The decrypted folder may still be accessible."
            exit 1
        fi
    fi

    # Remove only an empty mountpoint
    if [[ -d "$TEMP_DIR" ]] &&
       [[ -z "$(ls -A "$TEMP_DIR")" ]]; then
        rmdir "$TEMP_DIR"
        echo "Temporary mountpoint removed."
    fi

    echo "Media server stopped."
    exit "$status"
}

echo "=== Starting Media Server ==="

# Check USB drive
if ! mountpoint -q "$USB_DIR"; then
    echo "ERROR: USB drive is not mounted at $USB_DIR"
    exit 1
fi

# Check encrypted directory
if [[ ! -f "$CIPHER_DIR/gocryptfs.conf" ]]; then
    echo "ERROR: gocryptfs configuration not found:"
    echo "$CIPHER_DIR"
    exit 1
fi

# Prepare mountpoint
mkdir -p "$TEMP_DIR"

# Register cleanup BEFORE attempting to mount
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# Unlock encrypted folder if necessary
if mountpoint -q "$TEMP_DIR"; then
    echo "Encrypted folder is already unlocked."
else
    if [[ -n "$(ls -A "$TEMP_DIR")" ]]; then
        echo "ERROR: Mountpoint is not empty."
        exit 1
    fi

    echo "Unlocking encrypted folder..."
    gocryptfs -allow_other "$CIPHER_DIR" "$TEMP_DIR"
fi

# Verify Nginx can read the decrypted directory
if ! sudo -u www-data ls "$TEMP_DIR" >/dev/null; then
    echo "ERROR: Nginx cannot access the decrypted folder."
    exit 1
fi

# Validate Nginx configuration
sudo nginx -t

# Start the HTTP server
sudo systemctl start nginx
NGINX_STARTED=1

echo
echo "Media Server Running!"
echo "URL: http://$(hostname -I | awk '{print $1}'):8080/"
echo "Press Ctrl+C to stop Nginx and lock the folder."

# Keep script running until interrupted
while true; do
    sleep 3600 &
    wait $! || true
done
