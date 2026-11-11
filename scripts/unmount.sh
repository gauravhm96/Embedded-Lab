#!/bin/bash

sudo umount /mnt/usb

if [ $? -eq 0 ]; then
	echo "USB unmounted"
else
	echo "Unmount Failed"
fi
