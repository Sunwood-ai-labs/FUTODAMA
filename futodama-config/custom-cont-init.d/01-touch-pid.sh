#!/usr/bin/with-contenv bash

# This script ensures that /defaults/pid exists so that the selkies
# process can finish initializing and start the backend on port 8082.

echo "Applying custom fix: Touching /defaults/pid to allow selkies backend to start..."
touch /defaults/pid

# Fixing permission to ensure abc can freely access it if needed
chown abc:abc /defaults/pid
