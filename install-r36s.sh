#!/bin/bash
# Gen2Recomped Direct Installer for R36S SD Card
set -e

# 1. Define the SD card target
TARGET_DIR="${1:-/media/$USER/EASYROMS/ports}"

# 2. Check if the SD card is plugged in
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Target directory '$TARGET_DIR' not found."
    echo "Usage: ./install-r36s.sh /path/to/sdcard/roms/ports"
    exit 1
fi

echo "==> Building package..."
./build-r36s.sh

echo "==> Deploying to $TARGET_DIR..."
# 3. Copy the launcher directly to the root of the ports folder
cp ports/r36s/Gen2recomp.sh "$TARGET_DIR/"

# 4. Create the game directory and copy the contents
mkdir -p "$TARGET_DIR/gen2recomp"
cp -r dist/r36s/gen2recomp/* "$TARGET_DIR/gen2recomp/"

echo "==> Deployment successful!"
