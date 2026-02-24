#!/usr/bin/with-contenv bash

# This script ensures that the desktop shortcut for Antigravity
# is present in the user's Desktop folder.

DESKTOP_DIR="/config/Desktop"

echo "Ensuring desktop shortcuts are present in $DESKTOP_DIR..."

mkdir -p "$DESKTOP_DIR"

if [ ! -f "$DESKTOP_DIR/antigravity.desktop" ]; then
    cp /defaults/Desktop/antigravity.desktop "$DESKTOP_DIR/"
    chown abc:abc "$DESKTOP_DIR/antigravity.desktop"
fi
