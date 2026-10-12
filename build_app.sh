#!/bin/bash
# Construit « Aman Check.app » (même méthode qu'Aman Disk : SwiftPM + bundle fait main).
#
# Signature : ad hoc par défaut (pas de compte développeur). Pour une distribution,
# SIGN_IDENTITY="Developer ID Application: …" puis notarisation (spec §10).
# Hardened Runtime activé (--options runtime) : sans lui, les entitlements caméra / micro
# n'ont aucun effet, ce qui empêchait la caméra de s'afficher dans la version précédente.
set -e
cd "$(dirname "$0")"

VERSION="${VERSION:-1.0.0}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP_NAME="Aman Check.app"
CONTENTS="$APP_NAME/Contents"

echo "Compilation (release, $(uname -m))…"
swift build -c release --product AmanCheck
BIN_PATH="$(swift build -c release --show-bin-path)"

echo "Création du bundle…"
rm -rf "$APP_NAME"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_PATH/AmanCheck" "$CONTENTS/MacOS/AmanCheck"
cp "Branding/Aman-Disk-brand/app-icon/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
# Ressources SwiftPM (base des ponts USB de DiskHealthCore) : à côté de l'exécutable et dans Resources.
for bundle in "$BIN_PATH"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$CONTENTS/Resources/"
done
cp "Sources/DiskHealthCore/Resources/usb-bridges.json" "$CONTENTS/Resources/"

cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>AmanCheck</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.aman-disk.AmanCheck</string>
    <key>CFBundleName</key>
    <string>Aman Check</string>
    <key>CFBundleDisplayName</key>
    <string>Aman Check</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleDevelopmentRegion</key>
    <string>fr</string>
    <key>CFBundleAllowMixedLocalizations</key>
    <true/>
    <key>NSCameraUsageDescription</key>
    <string>Aman Check affiche l'image de la caméra pour vérifier qu'elle fonctionne. Rien n'est enregistré.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Aman Check mesure le niveau du micro et enregistre 3 secondes pour vous les faire réécouter. Rien n'est conservé.</string>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Aman Check vérifie que le Bluetooth de ce Mac est présent et allumé.</string>
</dict>
</plist>
PLIST

cat > "AmanCheck.entitlements" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.device.camera</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
PLIST

echo "Signature ($SIGN_IDENTITY, Hardened Runtime)…"
codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" --entitlements AmanCheck.entitlements "$APP_NAME"
codesign --verify --deep --strict "$APP_NAME"
codesign -d --entitlements - "$APP_NAME" 2>/dev/null | grep -q "device.camera" && echo "Entitlement caméra : présent"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_NAME" 2>/dev/null || true
echo "Terminé : $(pwd)/$APP_NAME"
