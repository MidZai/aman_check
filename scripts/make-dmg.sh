#!/bin/bash
# Crée dist/Aman-Check-<version>.dmg (l'app, un raccourci vers /Applications et la notice d'installation),
# avec hdiutil seulement. À lancer après « UNIVERSAL=1 ./build_app.sh ».
#
#   scripts/make-dmg.sh              DMG non signé (app signée ad hoc) : la version publiée par défaut
#   scripts/make-dmg.sh --notarize   DMG signé Developer ID, notarisé et agrafé ; l'app doit déjà l'être
#                                    (scripts/notarize.sh). Variables : scripts/notary-env.sh, docs/RELEASE.md.
set -e

NOTARIZE=0
for arg in "$@"; do
    case "$arg" in
        --notarize) NOTARIZE=1 ;;
        *) echo "Option inconnue : $arg (seule --notarize existe)" >&2; exit 1 ;;
    esac
done

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR/.."

APP="Aman Check.app"
if [ ! -d "$APP" ]; then
    echo "« $APP » introuvable : lancer d'abord UNIVERSAL=1 ./build_app.sh" >&2
    exit 1
fi

if [ "$NOTARIZE" == "1" ]; then
    source scripts/notary-env.sh
    notary_require
    # Un DMG notarisé qui contient une app non notarisée serait quand même bloqué au premier lancement.
    xcrun stapler validate "$APP" >/dev/null 2>&1 || {
        echo "L'app n'a pas de ticket de notarisation : lancer d'abord scripts/notarize.sh." >&2
        exit 1
    }
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
if [ "$NOTARIZE" == "1" ]; then
    echo "Signature et notarisation du DMG…"
    codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
    notary_submit "$DMG"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi
echo "DMG créé : $DMG ($(du -h "$DMG" | cut -f1))"
