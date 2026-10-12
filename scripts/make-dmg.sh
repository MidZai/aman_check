#!/bin/bash
# Crée dist/Aman-Check-<version>.dmg (l'app, un raccourci vers /Applications et la notice d'installation),
# avec hdiutil seulement. À lancer après « UNIVERSAL=1 ./build_app.sh ».
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR/.."

APP="Aman Check.app"
if [ ! -d "$APP" ]; then
    echo "« $APP » introuvable : lancer d'abord UNIVERSAL=1 ./build_app.sh" >&2
    exit 1
fi

VERSION=$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString)
DMG="dist/Aman-Check-$VERSION.dmg"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

mkdir -p dist
rm -f "$DMG"
# ditto conserve la signature et les attributs étendus du bundle.
ditto "$APP" "$STAGING/$APP"
ln -s /Applications "$STAGING/Applications"
cp "scripts/dmg/How to Install.txt" "$STAGING/"

hdiutil create -volname "Aman Check $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG"
hdiutil verify "$DMG"
echo "DMG créé : $DMG ($(du -h "$DMG" | cut -f1))"
