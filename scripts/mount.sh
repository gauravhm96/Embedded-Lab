#!/bin/bash

MOUNT_POINT="/mnt/usb"

#Find first USB Partition
USB_DEV=$(lsblk -rpno NAME,TYPE | awk '$2=="part" {print $1}' | grep -E '/dev/sd[a-z][0-9]' | head -1)

if [ -z "$USB_DEV" ]; then
	echo "No USB Partition Found!"
	exit 1
fi

mkdir -p "$MOUNT_POINT"

if mount | grep -q "$USB_DEV"; then
	echo "$USB_DEV is already mounted."
	mount | grep "$USB_DEV"
	exit 0
fi

sudo mount "$USB_DEV" "$MOUNT_POINT"

if [ $? -eq 0 ]; then
	echo "Mounted $USB_DEV at $MOUNT_POINT"
	df -h "$MOUNT_POINT"
else
	echo "Mount failed!"
fi




