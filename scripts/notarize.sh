#!/bin/bash
# Signe « Aman Check.app » avec un Developer ID (Hardened Runtime, horodatage), le fait notariser par Apple,
# puis agrafe le ticket. À lancer après « UNIVERSAL=1 ./build_app.sh », avant scripts/make-dmg.sh.
# Variables : voir scripts/notary-env.sh et docs/RELEASE.md. Sans elles, le script s'arrête sans rien toucher :
# la signature ad hoc par défaut de build_app.sh n'est pas modifiée.
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR/.."
source scripts/notary-env.sh

APP="Aman Check.app"
[ -d "$APP" ] || { echo "« $APP » introuvable : lancer d'abord UNIVERSAL=1 ./build_app.sh" >&2; exit 1; }
[ -f AmanCheck.entitlements ] || { echo "AmanCheck.entitlements introuvable (écrit par build_app.sh)." >&2; exit 1; }
notary_require

echo "Signature Developer ID ($DEVELOPER_ID, Hardened Runtime)…"
codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID" --entitlements AmanCheck.entitlements "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

ZIP="$(mktemp -d)/Aman-Check.zip"
trap 'rm -rf "$(dirname "$ZIP")"' EXIT
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Soumission à Apple (notarytool, quelques minutes)…"
notary_submit "$ZIP"

echo "Agrafage du ticket…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
echo "Notarisée : $(pwd)/$APP"
