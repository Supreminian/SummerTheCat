#!/bin/zsh
set -eu
SCRIPT_DIR="${0:A:h}"
OUTPUT_DIR="${SCRIPT_DIR:h}"
APP_DIR="${TUXI_APP_DIR:-$OUTPUT_DIR/Summer The Cat AI.app}"
BUILD_DIR="${TUXI_BUILD_DIR:-$OUTPUT_DIR/.build}"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$BUILD_DIR"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/clang-cache"
export SWIFT_MODULECACHE_PATH="$BUILD_DIR/swift-cache"
TUXI_FLAGS=()
# Some upgraded Command Line Tools retain an obsolete second SwiftBridging map.
# Mask only that duplicate in this compilation's virtual filesystem.
TUXI_INCLUDE="$(xcrun --find swiftc | sed 's@/bin/swiftc$@/include/swift@')"
if [[ -f "$TUXI_INCLUDE/bridging.modulemap" && -f "$TUXI_INCLUDE/module.modulemap" ]]; then
 printf '// Empty virtual map\n' > "$BUILD_DIR/empty.modulemap"
 printf '{"version":0,"roots":[{"type":"file","name":"%s/module.modulemap","external-contents":"%s/empty.modulemap"}]}' "$TUXI_INCLUDE" "$BUILD_DIR" > "$BUILD_DIR/overlay.json"
 TUXI_FLAGS=(-vfsoverlay "$BUILD_DIR/overlay.json")
fi
for TUXI_ARCH in arm64 x86_64; do
 swiftc "$SCRIPT_DIR/SummerTheCat.swift" "$SCRIPT_DIR/FocusMode.swift" "$SCRIPT_DIR/BasicFeatures.swift" "$SCRIPT_DIR/ConversationUI.swift" "$SCRIPT_DIR/ConversationSmoke.swift" "$SCRIPT_DIR/OpenAIClient.swift" "$SCRIPT_DIR/OpenAISettingsUI.swift" "$SCRIPT_DIR/StandardEditing.swift" "$SCRIPT_DIR/OpenAIDiagnostic.swift" "$SCRIPT_DIR/AIProvider.swift" "$SCRIPT_DIR/GeminiClient.swift" "$SCRIPT_DIR/FloatingPetMenu.swift" "$SCRIPT_DIR/TeaserMotion.swift" "$SCRIPT_DIR/TeaserCursor.swift" "$SCRIPT_DIR/PetCursorStyles.swift" -O -target "$TUXI_ARCH-apple-macosx13.0" "${TUXI_FLAGS[@]}" -framework AppKit -framework WebKit -framework Carbon -framework ServiceManagement -framework Security -module-cache-path "$BUILD_DIR/swift-cache" -o "$BUILD_DIR/SummerTheCat-$TUXI_ARCH"
done
lipo -create "$BUILD_DIR/SummerTheCat-arm64" "$BUILD_DIR/SummerTheCat-x86_64" -output "$APP_DIR/Contents/MacOS/SummerTheCat"
awk 'FILENAME==ARGV[1]{motion=motion $0 ORS;next}FILENAME==ARGV[2]{playback=playback $0 ORS;next}FILENAME==ARGV[3]{mouse=mouse $0 ORS;next}{if($0=="__MOTION_RENDERER__")printf "%s",motion;else if($0=="__PLAYBACK__")printf "%s",playback;else if($0=="__MOUSE_INTERACTION__")printf "%s",mouse;else print}' "$SCRIPT_DIR/motion-renderer.js" "$SCRIPT_DIR/playback.js" "$SCRIPT_DIR/mouse-interaction.js" "$SCRIPT_DIR/pet.html" > "$APP_DIR/Contents/Resources/pet.html"
python3 - "$SCRIPT_DIR" "$APP_DIR" <<'PYBUNDLE'
import sys
from pathlib import Path
source=Path(sys.argv[1]);target=Path(sys.argv[2])/'Contents/Resources/pet.html'
target.write_text(target.read_text().replace('__CHAT_MOTION__',(source/'chat-motion.js').read_text()))
PYBUNDLE
cp "$SCRIPT_DIR/teaser-assets/"*.png "$APP_DIR/Contents/Resources/"
cp "$SCRIPT_DIR/menu-assets/"*.png "$APP_DIR/Contents/Resources/"
cp "$SCRIPT_DIR/chat.html" "$APP_DIR/Contents/Resources/chat.html"
rm -rf "$APP_DIR/Contents/Resources/pet-pack"
mkdir -p "$APP_DIR/Contents/Resources/pet-pack"
rm -f "$APP_DIR/Contents/Resources/petting-hand.png"
cp "$SCRIPT_DIR/cursor-assets/"*.png "$APP_DIR/Contents/Resources/"
cp "$SCRIPT_DIR/pet-details.html" "$SCRIPT_DIR/summer-profile.json" "$APP_DIR/Contents/Resources/"
cp "$OUTPUT_DIR/pet-pack/pet.json" "$OUTPUT_DIR/pet-pack/spritsheet.webp" "$OUTPUT_DIR/pet-pack/main.png" "$APP_DIR/Contents/Resources/pet-pack/"
if [[ -d "$OUTPUT_DIR/pet-pack/motion" ]]; then
 mkdir -p "$APP_DIR/Contents/Resources/pet-pack/motion"
 cp "$OUTPUT_DIR/pet-pack/motion/"*.flow "$APP_DIR/Contents/Resources/pet-pack/motion/"
fi
if [[ -d "$OUTPUT_DIR/pet-pack/clips" ]]; then
 cp -R "$OUTPUT_DIR/pet-pack/clips" "$APP_DIR/Contents/Resources/pet-pack/"
fi
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SummerTheCat</string>
<key>CFBundleIdentifier</key><string>local.summerthecat.v30.openai</string>
<key>CFBundleName</key><string>Summer The Cat AI</string>
<key>CFBundleDisplayName</key><string>Summer The Cat AI</string>
<key>CFBundleVersion</key><string>312</string>
<key>CFBundleShortVersionString</key><string>2.0.30.12</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>PetIcon</string>
</dict></plist>
PLIST
ICON_DIR="$BUILD_DIR/PetIcon.iconset"
mkdir -p "$ICON_DIR"
for TUXI_SIZE in 16 32 128 256 512; do
 sips -z "$TUXI_SIZE" "$TUXI_SIZE" "$OUTPUT_DIR/pet-pack/main.png" --out "$ICON_DIR/icon_${TUXI_SIZE}x${TUXI_SIZE}.png" >/dev/null
 TUXI_DOUBLE=$((TUXI_SIZE * 2))
 sips -z "$TUXI_DOUBLE" "$TUXI_DOUBLE" "$OUTPUT_DIR/pet-pack/main.png" --out "$ICON_DIR/icon_${TUXI_SIZE}x${TUXI_SIZE}@2x.png" >/dev/null
done
if ! iconutil -c icns "$ICON_DIR" -o "$APP_DIR/Contents/Resources/PetIcon.icns"; then
 swiftc "$SCRIPT_DIR/IconWriter.swift" "${TUXI_FLAGS[@]}" -module-cache-path "$BUILD_DIR/swift-cache" -o "$BUILD_DIR/IconWriter"
 "$BUILD_DIR/IconWriter" "$ICON_DIR" "$APP_DIR/Contents/Resources/PetIcon.icns"
fi
codesign --force --deep --sign - "$APP_DIR"
echo "Built: $APP_DIR"
