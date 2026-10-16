# Aman Check — publier une version

Deux chemins : la version **ad hoc** (celle d'aujourd'hui, sans compte Apple Developer) et la version **notarisée**
(quand un Developer ID sera payé, 99 $/an — objectif Ko-fi). La signature ad hoc reste le comportement par défaut :
rien ne change tant que les variables de notarisation ne sont pas fournies.

## 1. Préparer

1. Partir de `main` à jour, arbre propre (`git status`).
2. Version : `VERSION` par défaut dans `build_app.sh` (et le repli de `AppInfo.version` dans `CheckController.swift`).
3. `CHANGELOG.md` : renommer « Unreleased » en « X.Y.Z — AAAA-MM-JJ ».
4. Vérifications :
   ```bash
   ./scripts/test.sh
   python3 scripts/extract_strings.py --missing      # aucune ligne « manquante »
   python3 scripts/gen_translations.py --check
   (cd server && npm test)                           # si MetricCatalog / Level2Text ont changé :
   swift run AmanCatalogExport server/src/catalog.json
   ```
5. Captures : `open -n "Aman Check.app" --args --snapshot ~/Desktop/shots` (puis `--language ar` pour le sens de lecture).
6. README et site (`docs/index.html`, `docs/fr/index.html`) : version minimale de macOS, nouveautés.

## 2a. Version ad hoc (par défaut)

```bash
UNIVERSAL=1 ./build_app.sh       # binaire universel, signature ad hoc, Hardened Runtime
./scripts/make-dmg.sh            # dist/Aman-Check-X.Y.Z.dmg
shasum -a 256 dist/Aman-Check-X.Y.Z.dmg
```

macOS bloque l'app au premier lancement : la notice du DMG (`scripts/dmg/How to Install.txt`), le README et la
section « Is it safe? » du site expliquent comment l'autoriser.

## 2b. Version notarisée

Prérequis, une fois :

1. Compte Apple Developer (programme payant) et certificat **Developer ID Application** installé dans le trousseau
   (`security find-identity -v -p codesigning` doit le lister).
2. Identifiants de notarisation enregistrés dans le trousseau (recommandé, le mot de passe n'apparaît jamais dans
   une ligne de commande) :
   ```bash
   xcrun notarytool store-credentials aman-notary --apple-id "vous@exemple.com" --team-id ABCDE12345
   ```
   Le mot de passe demandé est un **mot de passe pour app** créé sur appleid.apple.com, pas celui du compte.

Variables lues par `scripts/notarize.sh` et `scripts/make-dmg.sh --notarize` (détail dans `scripts/notary-env.sh`) :

| Variable | Exemple |
|---|---|
| `DEVELOPER_ID` | `Developer ID Application: Nom Prénom (ABCDE12345)` |
| `TEAM_ID` | `ABCDE12345` |
| `NOTARY_PROFILE` | `aman-notary` (profil du trousseau) |
| ou `APPLE_ID` + `APP_PASSWORD` | à défaut de profil |

```bash
export DEVELOPER_ID="Developer ID Application: …" TEAM_ID=… NOTARY_PROFILE=aman-notary
UNIVERSAL=1 ./build_app.sh       # compile et signe ad hoc
./scripts/notarize.sh            # re-signe Developer ID + Hardened Runtime + horodatage, notarise, agrafe
./scripts/make-dmg.sh --notarize # DMG signé, notarisé et agrafé
shasum -a 256 dist/Aman-Check-X.Y.Z.dmg
```

Chaque script s'arrête avec un message clair si une variable manque, si le certificat est absent du trousseau, ou
(pour le DMG) si l'app n'a pas encore de ticket. En cas de refus d'Apple, `xcrun notarytool log <id> --keychain-profile aman-notary`
donne la raison.

Une fois la première version notarisée publiée : retirer l'étape Gatekeeper de la notice du DMG, du README, du site
(« Is it safe? », ligne sous le bouton) et des notes de version ; mettre à jour `docs/SPECIFICATION.md` §10.

## 3. Publier

1. Commit « chore: release X.Y.Z », tag `vX.Y.Z`, push (avec l'accord explicite du mainteneur).
2. Release GitHub avec le DMG, au format des précédentes : résumé, **Installation** (étapes Gatekeeper pour une version
   ad hoc), « macOS 13 or later · Apple Silicon and Intel (universal binary) », SHA-256, liens CHANGELOG et Aman Disk.
   ```bash
   gh release create vX.Y.Z dist/Aman-Check-X.Y.Z.dmg --title "Aman Check X.Y.Z" --notes-file notes.md
   ```
3. Le site n'a pas besoin d'être modifié pour le lien de téléchargement : les boutons pointent vers le dernier DMG publié.
