#!/bin/bash
set -Eeuo pipefail

USB_DIR="/mnt/usb"

#CIPHER_DIR="/mnt/usb/locked"
#TEMP_DIR="/mnt/usb/temp_folder"

CIPHER_DIR="/mnt/usb/Linux/myworkspace/locked"
TEMP_DIR="/mnt/usb/Linux/myworkspace/temp_folder"

cleanup() {
    local status=$?
    trap - EXIT INT TERM HUP

    echo
    echo "=== Stopping media Server ==="

    sudo systemctl stop nginx || {
        echo "ERROR : Could not stop Nginx"
        echo "Leaving encrypted folder mounted for safety"
        exit 1
    }

    if mountpoint -q "$TEMP_DIR"; then
        if fusermount3 -u "$TEMP_DIR"; then
            echo "Encrytped folder locked"
        else

            echo "ERROR: Unmount failed"
            echo "The decrypted folder may be still accessible"
            exit 1
        fi
    fi

    if [[ -d "$TEMP_DIR" ]] &&
        [[ -z "$(ls -A "$TEMP_DIR")" ]]; then
        rmdir "$TEMP_DIR"
    fi

    echo "Media server Stopped"
    exit "$status"
}

echo "=== Starting Media Server ==="

if ! mountpoint -q "$USB_DIR"; then
    echo "ERROR: USB Drive is not mounted at $USB_DIR"
    exit 1
fi

if [[ ! -f "$CIPHER_DIR/gocryptfs.conf" ]]; then
    echo "ERROR: gocrypts configuration not found in :"
    echo "$CIPHER_DIR"
    echo "Check directory path"
    exit 1
fi

mkdir -p "$TEMP_DIR"

if mountpoint -q "$TEMP_DIR"; then
    echo "Encrypted folder is already unlocked."
else
    if [[ -n "$(ls -A "$TEMP_DIR")" ]]; then
        echo "ERROR: $TEMP_DIR is not empty and is not a mountpoint"
        exit 1
    fi

    echo "Unlocking folder.."
    gocryptfs -allow_other "$CIPHER_DIR" "$TEMP_DIR"
fi

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

if ! sudo -u www-data ls "$TEMP_DIR" >/dev/null; then
    echo "ERROR: Nginx cannot access the decrypted folder"
    echo "Nginx has not been started"
    exit 1
fi

sudo nginx -t

sudo systemctl start nginx

echo
echo "Media Servier Running..."

while true; do
	sleep 3600 &
	wait $! || true
done
