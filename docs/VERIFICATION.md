# Aman Check — à vérifier à la main sur le MacBookPro16,1

Construire : `./build_app.sh` puis ouvrir `Aman Check.app`. Tests unitaires : `./scripts/test.sh` (128 tests).
Journal de diagnostic : menu Contrôle › Exporter les données de diagnostic (chaque touche, geste, port et son y est consigné).

| Test | Ce qu'il faut constater | Critère |
|---|---|---|
| Écran | Couleur sur 100 % de l'écran, Dock et barre de menus compris ; Espace / → / ← / Échap ; sortie qui rétablit Dock, barre de menus et curseur | §6.1 |
| Clavier | Chaque touche passe au vert, y compris espace, fn, ⌃, ⌥ et ⌘ gauche/droite, flèches ; total 65 (ANSI) ou 66 (ISO) | §6.2 |
| Clavier ISO | Si le clavier est ISO (AZERTY), appuyer sur la touche « @ » à gauche du 1 doit faire passer le dessin en ISO automatiquement | §6.2 |
| Touch Bar | 12 zones bleues apparaissent sur la Touch Bar ; chacune passe au vert au toucher (si rien : réglage « Commandes de l'app ») | — |
| Trackpad | Clic, clic secondaire, défilement, pincement, rotation, clic forcé détectés ; la grille 8×5 se remplit | §6.3 |
| Caméra | Image de la caméra FaceTime HD affichée (demande d'autorisation au premier lancement) ; refus → « Non testé » | §6.4 |
| Haut-parleurs | Son audible ; gauche et droite distincts ; message si AirPods/HDMI actifs | §6.5 |
| Micro | Jauge qui bouge, enregistrement de 3 s relu | §6.5 |
| Touch ID | Empreinte reconnue | §7.6 |
| Ports | Une clé USB valide un port sans clic ; déplacée, elle valide le suivant (case allumée = n° UsbCPortNumber) ; chargeur débranché/rebranché ; écran externe ; casque | §6.6 |

Profils simulés (sans ces Mac) : `Aman Check.app/Contents/MacOS/AmanCheck --simulate-model Macmini9,1`
(aussi iMac21,1, Mac13,1, MacBookAir10,1, MacBookPro15,1, MacBookPro18,3).

## Capteurs (§6.6)

| Test | Ce qu'il faut constater | Critère |
|---|---|---|
| Ventilateurs | Section « Capteurs » : 2 ventilateurs, vitesses plausibles, température du processeur ; Avancé : clés lues (`FNum, F0Ac, F1Ac, TCXC`) | §6.6 |
| Capot | Commencer, fermer le capot 5 s, rouvrir : « Fermeture et ouverture du capot détectées par le capteur » sans question | §6.6 |
| Capot + écran externe | Écran externe branché : consigne « le Mac ne se mettra pas en veille… », capot fermé/rouvert détecté quand même | §6.6 |
| Luminosité | Torche du téléphone sur le haut de l'écran : « Le capteur de luminosité est passé de X lux à Y lux » sans question, quel que soit le réglage de luminosité automatique ; torche éloignée 20 s : « Le capteur n'a vu aucun changement » | §6.6 |
| Rétroéclairage | Consigne adaptée à la Touch Bar ; Oui / Non | §6.6 |

Vérifié automatiquement sur le MacBookPro16,1 : capteur de luminosité lu par l'app elle-même, sans demande d'autorisation (périphérique USB interne « Ambient Light Sensor », 5,8 lux), lecture du SMC sans droits (2 ventilateurs en `flt`, sondes en `sp78`), `AppleClamshellState` lisible (« No » capot ouvert), luminosité de l'écran lisible par IODisplay. Pas vérifié à la main : la fermeture réelle du capot pendant le test, la luminosité capteur couvert.

## Performance (§7.8)

Mesuré sur le MacBookPro16,1 (2026-10-16, sur secteur) avec `--snapshot <dossier> --performance` : processeur 171 GFLOPS (tranches 150–191), GPU 4 002 GFLOPS (Radeon Pro 5500M), copie mémoire 6,7 Go/s, ventilateurs 4 871 → 5 649 tr/min, 95 °C au plus fort, stabilité −7 % (*Bon*). Un deuxième passage enchaîné, Mac encore chaud : −66 % (*Problème*), d'où le conseil de refaire le test après refroidissement. Quatrième passage, ~10 min plus tard mais Mac occupé par d'autres travaux (charge système 9,5) : processeur 156 GFLOPS (91 % de la référence, *Bon*), GPU stable 12 s autour de 4 000 GFLOPS puis chute nette à 1 340 → −66 % (*Problème*). **À trancher :** ce décrochage du GPU (Radeon Pro 5500M connue pour baisser sa fréquence à chaud) peut faire classer « problème » un MacBook Pro 16 pouces 2019 sain.

| Vérification | Ce qu'il faut constater |
|---|---|
| Lancement | Rien ne démarre sans clic ; progression, mesure en direct, température et ventilateurs mis à jour toutes les 2 s |
| Annulation | « Annuler » arrête en moins de 2 s ; la ligne Stabilité devient « Non testé » (« Test annulé avant la fin. ») |
| Batterie | Débrancher le chargeur avant le test : « Conditions du test » dit « sur batterie » et recommande de refaire le test sur secteur |

## Partage (§8.4)

Vérifié automatiquement : le QR code du PDF exporté en mode `--snapshot` (français, allemand) est relu par CoreImage (`CIDetector`), 335–337 caractères, contenu conforme.

| Vérification | Ce qu'il faut constater |
|---|---|
| Partager | Rapport › « Partager… » : la feuille de partage s'ouvre sous le bouton ; AirDrop vers un iPhone reçoit le PDF ; Mail le joint |
| QR code | Scanner la page 1 imprimée avec l'appareil photo d'un iPhone et d'un Android : le texte s'affiche sans app dédiée |
| Réglage | Réglages › décocher « QR code de résumé dans le PDF » : plus de QR ni de légende ; un rapport publié (niveau 2) garde son QR code |

## Tests guidés, second passage (2026-10-16)

| Test | Ce qu'il faut constater |
|---|---|
| Caméra | L'image s'affiche (la caméra FaceTime des Mac T2 est en transport « usb », elle était rejetée par erreur) |
| Haut-parleurs | « Écouter » : un son qui monte, audible du début à la fin (3 s, barre de progression), puis 3 manches de bips qui partent seules ; image neutre pendant le quiz ; jamais d'écran bloqué (fin de son vérifiée sans bruit : 3,08 s et 0,67 s) |
| Touch ID sans empreinte | « Ouvrir les réglages Touch ID » ; après ajout d'une empreinte, l'app revient au premier plan et demande le doigt d'elle-même |
| Touch Bar | 10 zones visibles en entier ; bouton volume de la Control Strip + glissé → « extrémité droite OK » |
| Accueil | Bandeau « Processeur … °C · Ventilateurs … · en direct » mis à jour toutes les 2 s, absent de la page des résultats (vérifié dans la fenêtre réelle : 71 °C, 3 362 et 3 129 tr/min ; le mode `--snapshot` ne l'affiche pas, ses rendus bloquent la file principale) |

## Non validé (pas de machine disponible)
- Performance sur Apple Silicon : débit de `cblas_dgemm` (coprocesseur matriciel), noyau Metal, ventilateurs à 0 tr/min sous charge courte, aucune référence ; MacBook Air sans ventilateur (pas de ligne « Ventilateurs sous charge »).
- Capteurs sur Apple Silicon : clés de température `Tp*` (M1, M2 ; M3 et M4 peuvent utiliser d'autres préfixes → « Non disponible »), type des clés de ventilateur, `AppleClamshellState`, luminosité par IODisplay (probablement illisible : la question est alors posée), et surtout le capteur de luminosité par HID (sur Apple Silicon il passe par le SPU et peut ne pas apparaître : l'analyse dit alors « Non disponible »). Mac Intel sans T2 et iMac : capteur HID non vérifié. MacBook Air M1+ : « Pas de ventilateur sur ce modèle ». Mac de bureau : section Capteurs sans test du capot.
- Apple Silicon : clés batterie (`MaxCapacity` en %, `NominalChargeCapacity`), « Capacité maximale » de SPPowerDataType, `sppci_cores`, classes des ports USB, `UsbCPortNumber`.
- Mac de bureau réels, Mac Intel sans T2 (Activation Lock non lisible).
- Touches F1–F12 physiques (keyCodes média, Mission Control 160, Launchpad 131), lecteur SD, HDMI.

## Niveau 2 — rapport vérifiable en ligne

Tests automatiques : `./scripts/test.sh` (85 tests Swift) et `cd server && npm test` (36 tests du serveur, base D1 locale).

Serveur local pour les essais :
```
cd server
scripts/generate-signing-key dev1          # puis remplir .dev.vars (voir server/README.md)
npm run db:migrate:local
scripts/issue-license --plan single --credits 3 --note essai
npx wrangler dev --port 8787
open -n "Aman Check.app" --args --publish-server http://127.0.0.1:8787
```

| Vérification | Ce qu'il faut constater | Critère |
|---|---|---|
| Parcours vendeur | Contrôle → Rapport → « Publier un rapport vérifiable… » (⇧⌘P) → la feuille liste « Envoyé et rendu public » / « Jamais envoyé » → clé → « Vérifier » affiche le solde → « Publier » → QR code, lien, « Copier le lien », « Copier le texte pour l'annonce », « Retirer de la publication » ; le PDF exporté porte le QR code, l'identifiant public et l'empreinte | §3, §8 |
| Machines et téléphones | Sur la machine de développement **et sur un Mac Apple Silicon** : contrôle, publication, scan du QR code depuis un téléphone **Android** et un **iPhone** ; page lisible en moins de 3 secondes en 4G | §12 |
| Coupure réseau | Couper le Wi-Fi pendant la publication : message « Le serveur n'a pas pu être joint… », rapport local intact et exportable en PDF de niveau 1 ; rallumer, republier : même identifiant public, **un seul crédit décompté** (`GET /v1/licenses/me`) | §12 |
| Retrait | « Retirer de la publication » : la page affiche « Ce rapport a été retiré par son auteur », sans contenu ; le badge repasse en Niveau 1 | §5 |
| Périphériques externes | Test clavier avec un clavier USB/Bluetooth branché : écran d'attente, le test démarre seul au débranchement. Idem trackpad avec une souris | §8 prérequis |

Fait automatiquement (mode `--snapshot` avec `--snapshot-publish-key` et le serveur local) : publication réelle depuis l'app, archive JSON, PDF de niveau 2 et fiche A5 ; les QR codes rendus ont été relus par CoreImage. Captures de la page publique (5 états, téléphone 390 px) : `docs/screenshots/online-page/`.

Non fait : achat de test en bac à sable (aucun compte chez le prestataire), déploiement Cloudflare (nom de domaine non choisi).
