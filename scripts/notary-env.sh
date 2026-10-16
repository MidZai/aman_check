#!/bin/bash
# Identité de notarisation, partagée par scripts/notarize.sh et scripts/make-dmg.sh --notarize.
# À sourcer, pas à lancer. Rien n'est lu dans le dépôt : tout vient de l'environnement.
#
#   DEVELOPER_ID     « Developer ID Application: Nom (TEAMID) » (certificat installé dans le trousseau)
#   TEAM_ID          identifiant d'équipe Apple Developer (10 caractères)
#   et, au choix :
#   NOTARY_PROFILE   profil enregistré par `xcrun notarytool store-credentials` (recommandé : le mot de
#                    passe reste dans le trousseau)
#   APPLE_ID + APP_PASSWORD   identifiant Apple et mot de passe pour app (appleid.apple.com)

notary_require() {
    local missing=()
    [ -n "$DEVELOPER_ID" ] || missing+=("DEVELOPER_ID")
    [ -n "$TEAM_ID" ] || missing+=("TEAM_ID")
    if [ -z "$NOTARY_PROFILE" ]; then
        [ -n "$APPLE_ID" ] || missing+=("APPLE_ID (ou NOTARY_PROFILE)")
        [ -n "$APP_PASSWORD" ] || missing+=("APP_PASSWORD (ou NOTARY_PROFILE)")
    fi
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Notarisation impossible : variable(s) manquante(s) : ${missing[*]}." >&2
        echo "Voir docs/RELEASE.md. Sans compte Apple Developer, la version publiée reste signée ad hoc." >&2
        return 1
    fi
    if ! security find-identity -v -p codesigning | grep -qF "$DEVELOPER_ID"; then
        echo "Certificat « $DEVELOPER_ID » introuvable dans le trousseau (security find-identity -v -p codesigning)." >&2
        return 1
    fi
    command -v xcrun >/dev/null && xcrun --find notarytool >/dev/null 2>&1 || {
        echo "xcrun notarytool introuvable : installer Xcode ou les Command Line Tools récents." >&2
        return 1
    }
}

# Soumet un fichier (.zip ou .dmg) et attend le verdict d'Apple.
notary_submit() {
    local file="$1"
    if [ -n "$NOTARY_PROFILE" ]; then
        xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait
    else
        xcrun notarytool submit "$file" --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASSWORD" --wait
    fi
}
