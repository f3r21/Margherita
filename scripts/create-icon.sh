#!/bin/bash
set -e

SOURCE_PNG="$1"
OUTPUT_DIR="resources"
ICONSET_DIR="${OUTPUT_DIR}/AppIcon.iconset"
OUTPUT_ICNS="${OUTPUT_DIR}/AppIcon.icns"

if [ -z "$SOURCE_PNG" ]; then
    echo "Error: Please specify the source PNG path."
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
mkdir -p "$ICONSET_DIR"

echo "Resizing icons..."
sips -s format png -z 16 16 "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_16x16.png"
sips -s format png -z 32 32 "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_16x16@2x.png"
sips -s format png -z 32 32 "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_32x32.png"
sips -s format png -z 64 64 "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_32x32@2x.png"
sips -s format png -z 128 128 "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_128x128.png"
sips -s format png -z 256 256 "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_128x128@2x.png"
sips -s format png -z 256 256 "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_256x256.png"
sips -s format png -z 512 512 "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_256x256@2x.png"
sips -s format png -z 512 512 "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_512x512.png"
sips -s format png -z 1024 1024 "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_512x512@2x.png"

echo "Compiling .icns file..."
iconutil -c icns "$ICONSET_DIR"

echo "Cleaning up staging files..."
rm -rf "$ICONSET_DIR"

echo "Icon generated successfully at ${OUTPUT_ICNS}!"
