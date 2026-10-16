# AMAN CHECK — Spécification technique et produit (v2, corrigée)

> Aman Check est une application macOS native (Swift) dérivée d'**Aman Disk** (lecteur S.M.A.R.T. type « CrystalDiskInfo pour Mac »).
> Elle produit un **rapport d'état** lisible par un non-technicien pour l'achat/vente de Mac d'occasion.
>
> **Règles de développement :**
> 1. **Aucune API, clé IOKit ou sortie de commande inventée.** En cas de doute : `// TODO: à valider sur machine réelle` et un repli.
> 2. **Une donnée absente ou incohérente n'est JAMAIS affichée en vert.** Elle devient « Non disponible » ou « Vérification manuelle requise ».
> 3. **Aucune fonction ne doit crasher si une clé ou une commande est absente.** Tout est optionnel et typé.
> 4. **Respect du lexique de la section 3** (mots interdits : « certifié », « garantie », « infalsifiable », « 100 % fonctionnel », « Grade A »).
> 5. **Les jetons de design (couleurs, polices, rayons, espacements, composants) viennent du code d'Aman Disk**, jamais devinés.
> 6. **Tests unitaires avec des fixtures** (sorties `ioreg` / `system_profiler` réelles, anonymisées) pour chaque collecteur.

---

## 1. Vision et positionnement

- **Produit :** un « contrôle d'état » de Mac d'occasion, simple, visuel, sans jargon, qui génère un **rapport d'état daté** (PDF d'abord, page web vérifiable ensuite).
- **Cibles :** acheteurs et vendeurs particuliers (Marketplace, Ouedkniss, Leboncoin, etc.), puis petits revendeurs / réparateurs.
- **Ce que l'acheteur veut savoir** (par ordre d'importance) :
  1. Le Mac est-il **bloqué** (Activation Lock iCloud, MDM d'entreprise, verrou firmware) ?
  2. **Batterie** : cycles et capacité réelle par rapport à l'origine.
  3. **Stockage** : santé du SSD, heures de fonctionnement du SSD, quantité de données écrites.
  4. **Caractéristiques réelles** : modèle, puce/CPU, GPU, RAM, stockage, jusqu'à quelle version de macOS il est supporté.
  5. **Ce qui marche** : écran (pixels morts, taches), clavier, trackpad, haut-parleurs, caméra, micro, Wi-Fi, Bluetooth, ports.
- **Relation avec Aman Disk :** Aman Disk reste une app autonome pour public technique. Aman Check **réutilise son moteur de lecture du stockage** via un module partagé. On ne fusionne pas les deux apps.
- **Identité visuelle :** hériter d'Aman Disk (thème sombre par défaut, mêmes couleurs, même typographie, mêmes composants). Public non technique : gros chiffres, jauges, statuts colorés, vocabulaire simple, détails techniques repliables dans une section « Avancé ».

---

## 2. Principe de confiance : trois niveaux (à afficher clairement)

Le point faible de tout outil de ce type : **le rapport est généré sur la machine du vendeur, par le vendeur.** Un vendeur peut modifier l'app, tester un autre Mac, ou valider un test manuel sans l'avoir fait. On ne promet donc pas plus que ce qu'on peut prouver.

| Niveau | Nom | Ce que ça prouve | Phase |
|---|---|---|---|
| **1** | Rapport d'état local | Instantané automatique + tests déclarés par la personne. Aucune certification. | MVP |
| **2** | Rapport enregistré en ligne | Le contenu consulté via QR code est identique à celui enregistré à telle date. Reste un autodiagnostic. | Phase 4 |
| **3** | Contrôle vérifié par un tiers | Un réparateur/revendeur partenaire suit la procédure publique et engage sa responsabilité. Seul niveau qui justifie un label « vérifié ». | Phase 5+ |

Chaque rapport affiche son niveau en en-tête. **Le MVP est de niveau 1 et ne le dissimule pas.**

---

## 3. Lexique et règles de communication

**Interdit :** « certifié », « certificat », « garantie », « infalsifiable », « 100 % fonctionnel », « Grade A/B/C », « testé et approuvé », tout score global flatteur calculé alors que des tests manquent.

**Autorisé :**
- « Rapport d'état au 12/10/2026 »
- « Mesuré automatiquement » / « Constaté par l'utilisateur » / « Non testé » / « Non disponible »
- « 6 tests sur 8 réalisés »
- « Heures de fonctionnement du SSD » (jamais « heures du Mac »)
- « Données écrites sur le SSD » (jamais « TBW », qui désigne l'endurance annoncée par le constructeur)
- « Année de commercialisation du modèle » (jamais une « date de fabrication » inventée)

**Bandeau de bas de rapport (obligatoire) :**
> « Ce rapport est un instantané établi à la date indiquée. Les valeurs marquées *Mesuré automatiquement* proviennent du système du Mac testé ; les valeurs marquées *Constaté par l'utilisateur* sont déclaratives. Ce document ne constitue ni une certification ni une garantie. »

---

## 4. Modèle de données commun (fondation du projet)

Toute information collectée est une `Measurement`. C'est la décision d'architecture centrale.

```swift
enum CheckStatus {
    case good              // Bon
    case watch             // À surveiller
    case problem           // Problème détecté
    case notTested         // Non testé
    case unavailable       // Non disponible (donnée inaccessible sur cette machine)
    case manualRequired    // Vérification manuelle requise
    case notApplicable     // Sans objet (ex. batterie sur iMac)
}

enum Provenance {
    case measuredAuto      // lu par l'app depuis le système
    case userObserved      // constaté et déclaré par l'utilisateur
    case derived           // calculé à partir d'autres mesures
}

struct Measurement<Value> {
    let id: String                 // ex. "battery.health_percent"
    let value: Value?              // nil si indisponible
    let unit: String?              // "%", "h", "To", "cycles"…
    let status: CheckStatus
    let provenance: Provenance
    let method: String?            // ex. "NominalChargeCapacity/DesignCapacity"
    let collectedAt: Date
    let note: String?              // explication affichable (« pourquoi non disponible »)
}
```

**Règles :**
- `value == nil` ⇒ `status` ∈ {`unavailable`, `notTested`, `manualRequired`, `notApplicable`}, **jamais** `good`.
- Chaque collecteur renvoie des `Measurement`, jamais de simples `String`/`Int`.
- Le rapport (PDF, web) est un **rendu pur** de la liste de `Measurement` + métadonnées. Aucune logique de collecte dans la couche de rendu.
- **Synthèse globale :** pas de note unique. Afficher les compteurs : « X bons · Y à surveiller · Z problèmes · N non testés ». Un blocage (Activation Lock / MDM détecté) est toujours remonté en tête, en rouge.

---

## 5. Architecture

```
AmanCheck (app macOS, SwiftUI + AppKit où nécessaire)
├── AmanCore            (Swift Package) Measurement, CheckStatus, Provenance, thèmes
├── AmanStorageKit      (Swift Package) lecture SMART/NVMe extraite d'Aman Disk — partagée avec Aman Disk
├── Collectors/         un collecteur par domaine, protocole commun
│   ├── IdentityCollector
│   ├── BatteryCollector
│   ├── StorageCollector      (appelle AmanStorageKit)
│   ├── SecurityCollector     (Activation Lock, MDM, firmware)
│   └── ConnectivityCollector (Wi-Fi, Bluetooth)
├── InteractiveTests/   un module par test avec résultat pass / fail / skipped / aborted
│   ├── ScreenTest, KeyboardTest, TrackpadTest, AudioTest,
│   └── CameraMicTest, PortsTest, TouchIDTest
├── Report/             ReportModel → PDF (rendu natif) ; plus tard : ReportUploader
└── UI/                 navigation latérale, tableau de bord, mode rapport
```

```swift
protocol Collector {
    var id: String { get }
    var isApplicable: Bool { get }          // ex. batterie : false sur iMac
    func collect() async -> [Measurement<AnyHashable>]
}
```

**Choix techniques :**
- Swift natif (SwiftUI + AppKit). Pas d'Electron/Tauri : le produit dépend de l'intégration système, pas de la facilité du PDF.
- Préférer les **API directes** (IOKit via `IORegistryEntryCreateCFProperties`, `sysctl`, `ProcessInfo`, frameworks Apple) aux sorties texte de `ioreg`/`system_profiler`. N'utiliser `Process` + parsing que comme repli ou pour les commandes sans API (`profiles`).
- Les commandes shell doivent avoir un **timeout**, capturer stderr, et ne jamais bloquer l'UI.
- **Détection des capacités de la machine** avant tout : type (portable / iMac / mini / Studio / Pro), batterie présente, clavier/trackpad intégrés, caméra/micro/haut-parleurs, Touch ID, Apple Silicon vs Intel vs Intel+T2. Le rapport et l'UI s'adaptent (un iMac n'a pas de batterie ni de test trackpad intégré).
- **Version minimale de macOS :** à définir d'après Aman Disk. Ne pas utiliser d'API plus récentes sans `#available` et repli.

---

## 6. Collecteurs — spécification détaillée

> Toutes les commandes/clés ci-dessous sont des **pistes à valider sur machine réelle** (Intel, T2, Apple Silicon). Les clés IOKit varient selon la génération et la version de macOS.

### 6.1 Identité et caractéristiques

| Donnée | Source | Notes |
|---|---|---|
| Identifiant modèle (`MacBookPro18,3`) | `sysctl hw.model` | Clé de la table modèles |
| Nom commercial + année de sortie | **Table embarquée** `model_identifier → {nom, année, écran, macOS max supporté}` | À construire et maintenir. Si identifiant inconnu : afficher l'identifiant brut + « Modèle non reconnu » |
| Puce / CPU | `sysctl machdep.cpu.brand_string`, `system_profiler SPHardwareDataType` | |
| Cœurs CPU | `hw.physicalcpu`, `hw.logicalcpu`, `hw.perflevel0/1.physicalcpu` (Apple Silicon) | |
| Cœurs GPU | `system_profiler SPDisplaysDataType` (« Total Number of Cores ») | Peut être absent sur Intel |
| RAM | `hw.memsize` | Indiquer « mémoire unifiée » sur Apple Silicon |
| Capacité de stockage | diskutil / IOKit | |
| Version macOS | `ProcessInfo.operatingSystemVersion` | |
| Numéro de série | `IOPlatformSerialNumber` | **Ne jamais afficher en entier dans un rapport partageable** (voir 9) |
| Date de fabrication | ❌ **non récupérable** sur les Mac récents (numéros aléatoires depuis 2021) | Afficher seulement « Année de commercialisation du modèle ». N'afficher une date de fabrication que pour d'anciens numéros à 12 caractères et en l'étiquetant « estimée » |
| macOS maximal supporté | Table modèles | Argument de vente (durée de vie logicielle restante). Source à vérifier à chaque release de macOS |

Optionnel : lien vers la vérification de couverture Apple (checkcoverage.apple.com) pour que l'acheteur contrôle lui-même le numéro de série.

### 6.2 Batterie (portables uniquement)

**Lire, si présents :** `CycleCount`, `DesignCapacity`, `MaxCapacity`, `AppleRawMaxCapacity`, `NominalChargeCapacity`, `IsCharging`, `ExternalConnected`, `Temperature`, `PermanentFailureStatus`. Compléter avec l'état déclaré par macOS (`system_profiler SPPowerDataType` : *Condition*, *Maximum Capacity* si présent).

**Algorithme (ne PAS utiliser une formule unique) :**
1. Si aucune batterie détectée ⇒ `notApplicable`.
2. Rassembler les candidats de « capacité maximale actuelle » dans l'ordre de préférence : `NominalChargeCapacity` → `AppleRawMaxCapacity` → `MaxCapacity`.
3. **Contrôle d'unité :** `MaxCapacity` est en mAh sur Intel, mais sur Apple Silicon récent il peut être exprimé en pourcentage (valeur ≤ ~100). Si `MaxCapacity ≤ 150`, ne pas le traiter comme des mAh.
4. `santé % = capacité_max_actuelle (mAh) / DesignCapacity (mAh) × 100`.
5. **Contrôle de cohérence :** `DesignCapacity` > 0 ; ratio entre 0,3 et 1,2 ; si le ratio dépasse 100 % légèrement, plafonner l'affichage à 100 % et le noter.
6. **Recoupement :** comparer avec « Maximum Capacity » de `SPPowerDataType` s'il existe. Écart > 5 points ⇒ marquer « Vérification manuelle requise » et afficher les deux valeurs en Avancé.
7. Si une étape échoue : `unavailable` avec note explicative. **Pas de pourcentage inventé.**
8. Toujours stocker `method` (ex. « NominalChargeCapacity / DesignCapacity ») et l'afficher dans la section Avancé.

**Seuils d'affichage (configurables, à ajuster) :** ≥ 80 % Bon · 70–79 % À surveiller · < 70 % ou état « Service recommandé » = Problème. Cycles : comparer au cycle maximum du modèle (table par modèle ; la plupart des portables récents sont donnés pour 1000 cycles à 80 % — à vérifier dans la doc Apple pour chaque génération).

### 6.3 Stockage (module Aman Disk réutilisé)

- Via `AmanStorageKit` : statut SMART global, **heures de fonctionnement du SSD**, **données écrites** (NVMe : « Data Units Written » × 512 000 octets ; convertir en To), pourcentage d'usure (« Percentage Used »), spare disponible, erreurs média, température, capacité, type (NVMe / AHCI / SATA).
- **Prévoir l'indisponibilité :** les SSD AHCI/anciens et certains contrôleurs exposent moins d'attributs. Afficher « Non disponible sur ce SSD » avec explication courte, jamais un zéro.
- Libellés : « Heures de fonctionnement du SSD », « Données écrites sur le SSD ». Ne jamais écrire « le Mac a fonctionné X heures ».
- Interprétation commerciale (texte simple) : ex. « Écritures modérées — usage compatible avec de la bureautique » à partir de seuils prudents ; ne pas dramatiser ni minimiser. Seuils à définir avec moi.
- Test de vitesse (lecture/écriture séquentielle) : **optionnel**, désactivé par défaut (durée, usure inutile).

### 6.4 Sécurité et verrouillages — priorité maximale, verdict prudent

États possibles pour **chaque** contrôle : `Aucun signal détecté` · `Signal détecté` · `Vérification impossible` · `Vérification complémentaire nécessaire`. **Jamais de vert par défaut.**

**Activation Lock**
- Piste : `system_profiler SPHardwareDataType` → champ « Activation Lock Status » (Macs T2 et Apple Silicon uniquement). Absent sur Mac sans T2 ⇒ `unavailable` + explication.
- ⚠️ **Limite à expliquer dans le rapport :** si le vendeur est encore connecté à son compte iCloud / Localiser actif, le statut sera « Activé » — c'est normal avant la remise. Le vrai risque apparaît après effacement et déconnexion, ce que l'outil ne peut pas simuler. Texte conseillé : « Avant l'achat, demandez au vendeur de se déconnecter d'iCloud, de désactiver Localiser et d'effacer le Mac, puis vérifiez que l'assistant de configuration n'exige aucun identifiant. »
- Signal complémentaire possible (à valider, surtout Intel) : présence d'un jeton Localiser dans la NVRAM.

**MDM / enrôlement automatisé (DEP/ABM)**
- Piste : `profiles status -type enrollment` (sorties du type « Enrolled via DEP: Yes/No », « MDM enrollment: Yes/No »). Parser de façon tolérante (la sortie varie selon la version de macOS) ; en cas de sortie inattendue ⇒ `Vérification impossible`.
- ⚠️ **Limite :** un Mac effacé appartenant à une organisation peut ne se révéler qu'à l'assistant de configuration, une fois connecté à Internet. Message : « Un contrôle depuis la session actuelle ne remplace pas la vérification de l'assistant de configuration après effacement. »
- Détecter aussi la présence de profils de configuration installés si accessible sans droits admin ; sinon l'indiquer.

**Mot de passe firmware / verrouillage de récupération**
- Intel : `firmwarepasswd -check` nécessite généralement les droits administrateur. Ne pas demander d'élévation dans le MVP ⇒ `Vérification manuelle requise` avec instruction : « Démarrez en maintenant Option : si un mot de passe est demandé, le Mac est verrouillé. »
- Apple Silicon : pas de mot de passe firmware classique ; le verrouillage de récupération passe par MDM. Indiquer « Non applicable / voir MDM ».

**SIP, Secure Boot, FileVault** (infos secondaires utiles) : `csrutil status`, état Secure Boot si disponible, FileVault actif. Afficher en Avancé, avec avertissement si SIP désactivé (signe de bidouillage).

**Détection de contournement (anti-triche légère) :** détecter l'exécution en machine virtuelle (`kern.hv_vmm_present`, indicateurs CPU) et l'indiquer en rouge dans le rapport (« Rapport généré dans une machine virtuelle »).

### 6.5 Connectivité

- **Wi-Fi :** interface présente, alimentée, scan qui renvoie des réseaux (CoreWLAN). Attention : les noms de réseaux peuvent exiger l'autorisation de localisation sur macOS récents ; le test doit fonctionner **sans** lire les SSID (présence + scan non vide suffisent). Résultat mesuré automatiquement.
- **Bluetooth :** contrôleur présent et allumable (CoreBluetooth / IOBluetooth). Déclarer `NSBluetoothAlwaysUsageDescription`.
- **Ports :** test guidé « branchez un périphérique USB dans chaque port » avec détection d'arrivée via notifications IOKit USB. Résultat par port (mesuré). Port de charge : détecté via l'état d'alimentation de la batterie quand on branche le chargeur.

### 6.6 Capteurs

Section « Capteurs » de l'analyse automatique (ventilateurs, température), et trois tests guidés (capot, luminosité ambiante, rétroéclairage du clavier). Origine : un acheteur a reçu un Mac dont le capteur de réveil était défectueux, ce qu'aucun contrôle ne voyait. Les verdicts sont décidés dans `AmanCore/SensorAnalysis.swift` (testés) ; la lecture est faite par l'app (`SensorCollector`, cible C `CSMC`).

| Capteur | Libellé FR / EN | Source | Provenance | Machines |
|---|---|---|---|---|
| Ventilateurs | « Ventilateurs » / « Fans » | SMC, clé `FNum` | Mesuré automatiquement | Tous (« Pas de ventilateur sur ce modèle » pour MacBook Air Apple Silicon et MacBook 12 pouces, d'après le catalogue) |
| Vitesse | « Vitesse des ventilateurs » / « Fan speed » | SMC, `F0Ac`, `F1Ac`… | Mesuré automatiquement | Mac avec ventilateur |
| Température du processeur | « Température du processeur » / « Processor temperature » | SMC : Intel `TCXC`, `TC0E`, `TC0F`, `TC0D`, `TC0P` (la première lisible) ; Apple Silicon moyenne des clés `Tp*` | Mesuré automatiquement | Tous |
| Capot | « Capteur du capot » / « Lid sensor » | `AppleClamshellState` (IOPMrootDomain), notifications de veille et de réveil (`NSWorkspace`) ; sinon réponse de la personne | Mesuré automatiquement, ou Constaté par l'utilisateur | Portables |
| Luminosité ambiante | « Capteur de luminosité » / « Ambient light sensor » | 1) Le capteur lui-même, par l'interface HID publique (norme HID *Sensors* : page 0x20, usage Lumière ambiante 0x41, champ Éclairement 0x4D1, en lux ; périphérique intégré seulement, pour ne pas lire le capteur d'un écran Apple externe) ; 2) à défaut, luminosité de l'écran intégré par `IODisplayGetFloatParameter` (Intel) ; 3) sinon réponse de la personne. Pas d'API privée | Mesuré automatiquement, ou Constaté par l'utilisateur | Portables et iMac (tous ont ce capteur, à côté de la caméra ; pas les Mac mini, Studio et Pro) |
| Rétroéclairage du clavier | « Rétroéclairage du clavier » / « Keyboard backlight » | Question à la personne | Constaté par l'utilisateur | Portables |

**Lecture du SMC :** client utilisateur `AppleSMC`, lecture seule, sans droits administrateur. Le décodage suit le type annoncé par le SMC (`ui8`, `ui16`, `ui32`, `sp78`, `fpe2`, `flt`), pas la puce : sur le MacBookPro16,1, les vitesses sont en `flt` et les températures en `sp78`. Valeurs hors plage (température hors 5–130 °C, vitesse hors 0–12 000 tr/min) écartées, jamais affichées comme zéro.

**États :**
- Ventilateurs : *Information* (nombre lu, ou « Pas de ventilateur sur ce modèle ») ; *À surveiller* si le modèle a un ventilateur et que le Mac n'en signale aucun ; *Non disponible* si le SMC est illisible.
- Vitesse : *Information* seulement (au repos, un ventilateur peut être arrêté) ; leur réaction sous charge est jugée par le test de performance (§7.8).
- Température : *Information* ; *À surveiller* à partir de 95 °C au repos (seuil indicatif). **Jamais « problème » sur une seule température.**
- Capot : *Bon* si la fermeture et la réouverture sont vues par le capteur, ou la veille et le réveil par les notifications ; sinon question « L'écran s'est-il éteint à la fermeture du capot, et rallumé à l'ouverture ? » : oui → *Bon* (constaté) ; oui alors que l'état du capot était lisible et n'a pas bougé → *À surveiller* ; non → *Problème*. **Écran externe branché :** le Mac ne se met pas en veille capot fermé ; si l'état du capot est lisible, le test continue en le surveillant directement, sinon il demande de débrancher l'écran ou de passer (→ *Non testé*).
- Luminosité : le geste demandé est d'**éclairer le haut de l'écran avec la torche du téléphone** (ou, à défaut, de le couvrir de la main). Constaté sur le MacBookPro16,1 : pièce à 5,8 lux, la main ne fait presque rien baisser et la luminosité automatique de macOS baisse lentement, alors que la torche fait monter tout de suite. *Capteur lisible* : l'analyse affiche les lux mesurés (*Information*) ; dans le test, un écart net dans un sens ou dans l'autre (au moins 3 lux et un rapport de 3, la plus faible valeur comptée au moins 1 lux) → *Bon* (mesuré) dès qu'il apparaît, sans rien demander ; rien en 20 s → « Réessayer » ou « Il n'a pas réagi » → *À surveiller* (capteur masqué ou défectueux). La luminosité automatique n'intervient pas. *Capteur illisible* : la luminosité automatique doit être activée (bouton vers les réglages des moniteurs ; ce réglage n'est lisible par aucune interface publique) ; changement d'au moins 5 points de la luminosité de l'écran, dans un sens ou dans l'autre → *Bon* (mesuré) ; sinon question : changement vu → *Bon* (constaté) ; aucun → *À surveiller* ; « La luminosité automatique est désactivée » → *Non testé*.
- Rétroéclairage : oui → *Bon*, non → *Problème* (constaté).
- Tout test sauté ou interrompu → *Non testé*.

**Consignes (public non technique) :** personne ne sait où est le capteur de luminosité. L'écran montre un schéma du haut de l'écran (caméra au centre, zone visée entourée, torche qui l'éclaire pendant le test) et demande d'éclairer le haut et le milieu de l'écran, là où se trouve la caméra : inutile de trouver le capteur. Étapes numérotées ; boutons qui ouvrent la page de Réglages Système concernée (Moniteurs pour la luminosité automatique, Clavier pour l'éclairage en faible lumière) sans rien modifier ; lux ou luminosité de l'écran affichés en direct quand ils sont lisibles ; pour le rétroéclairage, chemin Touch Bar ou Centre de contrôle selon le modèle ; pour le capot, rappel que le Mac peut demander le mot de passe à la réouverture.

**Hors périmètre :** Touch ID (déjà testé), accéléromètre / capteur de mouvement (absent des Mac récents), capteur de charnière (trop incertain).

---

## 7. Tests interactifs

Chaque test se termine par un état : **Réussi · Échoué · Ignoré · Interrompu**. Un test ignoré ou interrompu = « Non testé » dans le rapport. Provenance indiquée pour chaque test.

### 7.1 Écran (provenance : constaté par l'utilisateur)
- Plein écran, couleurs unies successives : blanc, noir, rouge, vert, bleu (+ option gris moyen pour l'uniformité). Barre d'espace / flèches pour avancer, Échap pour quitter.
- **Instruction à afficher avant le test :** « Réglez la luminosité au maximum, nettoyez l'écran, approchez-vous. » (On ne force pas la luminosité par API privée.)
- À la fin : question simple « Avez-vous vu des points morts, des taches ou des fuites de lumière ? » (Non / Oui + zone). Toutes les couleurs doivent avoir été affichées pour valider le test.
- Gérer plusieurs écrans : tester l'écran intégré par défaut.
- Afficher en mesure automatique : résolution, type de dalle si connu, Retina, fréquence.

### 7.2 Clavier (provenance : **mesuré** pour les touches normales)
- Disposition virtuelle à l'écran. Chaque touche passe de grise à verte quand l'événement est reçu via `NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged])` (pas d'autorisation « Surveillance de l'entrée » : l'app doit avoir le focus).
- **Identifier les touches par `keyCode` physique, pas par caractère** : l'utilisateur peut avoir un clavier AZERTY, QWERTY, ISO ou ANSI (ou arabe). Détecter la disposition physique (`KBGetLayoutType` / ISO vs ANSI vs JIS) et adapter le dessin.
- Touches système (luminosité, volume, Touch ID, Launchpad…) : tenter la capture via les événements `.systemDefined` du moniteur local ; si impossible, **test guidé manuel** (« appuyez sur volume + et vérifiez que le volume monte ») avec provenance « constaté par l'utilisateur ».
- Rapport : « X touches sur Y détectées » et liste des touches non détectées.
- Ne pas bloquer les raccourcis système critiques ; prévoir une sortie claire.

### 7.3 Trackpad / souris
- Clic gauche/droit, glissement, geste à deux doigts (scroll), pincement, **Force Touch** (événements de pression `NSEvent.pressure` / `stage`) si le modèle le supporte. Résultat mesuré quand l'événement est reçu.

### 7.4 Audio
- Haut-parleurs : balayage de fréquence (sweep) puis tonalité test, canal **gauche** puis **droit** (via `AVAudioEngine` et panoramique). Question utilisateur : « Le son est-il net, sans grésillement ni vibration ? » (déclaratif).
- Prévenir de monter le volume. Attention au volume : commencer bas et monter progressivement pour ne pas agresser l'utilisateur.
- Micro : jauge de niveau d'entrée en direct (mesuré : niveau > seuil quand l'utilisateur parle/tape).

### 7.5 Caméra
- Aperçu en direct (`AVCaptureSession`). Résultat : l'image s'affiche (mesuré partiellement) + « L'image est-elle nette, sans taches ? » (déclaratif). Gérer l'absence de caméra (Mac mini, etc.).

### 7.6 Touch ID (si matériel présent)
- Détecter la présence via `LocalAuthentication` (`canEvaluatePolicy`). Test = demande d'authentification biométrique ; succès/échec mesurés. Si absent : `notApplicable`.

### 7.8 Performance (lancée par la personne)

Objectif : **détecter un Mac qui ne tient pas ses performances** sous charge (ventilateur hors service, pâte thermique sèche, puce abîmée), pas rivaliser avec Geekbench. **Aucun score affiché comme une note.** Page « Performance » de la barre latérale ; section « Performance » du rapport (PDF détaillé, JSON).

- **Lancement :** uniquement par le bouton « Lancer le test » / « Run the Test », jamais automatique, jamais dans l'assistant des tests guidés. Avant : encadré « Avant de commencer » (le Mac va chauffer et les ventilateurs souffler, c'est normal ; brancher le chargeur ; ne rien faire d'autre). Barre de progression, mesure en direct, température du processeur et vitesse des ventilateurs (§6.6), bouton « Annuler » → *Non testé*.
- **Déroulé (55 s) :** processeur 30 s (multiplication de matrices 1024 × 1024 en double précision, `cblas_dgemm` d'Accelerate, qui répartit le calcul sur tous les cœurs — sur Apple Silicon il peut utiliser le coprocesseur matriciel), GPU 20 s (noyau Metal compilé au lancement, multiplication-addition en simple précision ; pas de Metal → *Non disponible*), mémoire 5 s (copie de blocs de 256 Mo par morceaux de 1 Mo décalés de 64 octets, `memmove` appelé par son adresse : sans cela, macOS remappe les pages et le compilateur supprime les copies). Mesure par tranches de 2 s ; température et ventilateurs relevés à chaque tranche.
- **Stabilité (Calculé) :** moyenne des 3 premières tranches comparée aux 3 dernières, pour le processeur et pour le GPU ; la plus forte baisse compte. < 10 % → *Bon* ; 10–25 % → *À surveiller* ; > 25 % → *Problème*, avec « Les performances baissent fortement sous charge. Vérifiez la ventilation. » Hors *Bon*, le rapport conseille de laisser refroidir le Mac et de refaire le test (mesuré sur la machine de développement : un deuxième test enchaîné, Mac déjà chaud, a donné −66 % alors que le premier était stable).
- **Référence (Calculé) :** `Sources/AmanCheck/Performance/PerformanceReference.json`, `{ "identifiant de la puce" : { "cpu_gflops": x, "gpu_gflops": y, "source": "…" } }`, clé = `machdep.cpu.brand_string`. **Aucune valeur inventée** : seule la machine de développement y figure, processeur seulement (le même processeur Intel existe avec plusieurs GPU). Puce absente : valeur brute + « Pas encore de référence pour ce modèle » (*Information*). Référence présente : < 80 % → *À surveiller*, **jamais « problème »** sur ce seul critère ; sinon *Bon*. Appel à contribution dans l'app et le README (envoyer son JSON).
- **Ventilateurs sous charge :** vitesse du ventilateur le plus rapide au début et au plus fort. Restés à 0 tr/min alors que le modèle a un ventilateur **et** que le processeur a atteint 90 °C → *Problème* ; restés à 0 sans chauffer → *Information* (« N'ont pas eu besoin de démarrer », fréquent sur Apple Silicon).
- **Rapport :** stabilité, processeur, GPU, ventilateurs sous charge (Essentiel) ; copie mémoire, température maximale, conditions (durée, alimentation au début et à la fin, référence utilisée) en Avancé. Les tranches brutes sont dans la méthode de chaque mesure. Tant que le test n'a pas été lancé, une ligne *Non testé* (comptée comme telle).

### 7.7 Hors périmètre du MVP
- Stress test CPU/GPU prolongé, benchmarks comparatifs, test de charge de batterie. Le rendez-vous d'achat doit durer **quelques minutes**, pas une heure. (Ventilateurs et capteurs : §6.6.)

---

## 8. Rapport

### 8.1 Modes
- **Rapport simple (commercial)** : une page A4. Idéal pour imprimer/afficher.
- **Rapport détaillé** : pages supplémentaires avec valeurs avancées (méthodes de calcul, clés lues, attributs SMART, notes).
- Options de l'utilisateur : nom du vendeur/magasin (optionnel), logo (plus tard), masquer le numéro de série (par défaut : 4 derniers caractères seulement), langue.

### 8.2 Structure de la page 1
1. **En-tête :** « AMAN CHECK · RAPPORT D'ÉTAT », date/heure, version de l'app et de la procédure de test, identifiant du rapport, niveau de confiance (niveau 1).
2. **Identité :** nom commercial, année du modèle, puce, RAM, stockage, macOS actuel et macOS maximal supporté, 4 derniers caractères du numéro de série.
3. **Bloc « Verrouillages » (en premier, bien visible) :** Activation Lock · MDM · Firmware, chacun avec son verdict prudent et sa limite en une phrase.
4. **Quatre cartes chiffrées :** Batterie (santé % · cycles), Stockage (heures SSD · données écrites · santé), Configuration, Tests (« 6 / 8 réalisés »).
5. **Tests interactifs** : liste avec ✅ / ❌ / ⏭ non testé, et mention *mesuré* ou *constaté*.
6. **« À vérifier avant l'achat »** : liste auto-générée de tout ce qui est `unavailable`, `manualRequired`, `notTested` ou `watch`.
7. **Pied de page :** bandeau de la section 3, identifiant du rapport, légende du QR code hors ligne (§8.4).

**Règle :** aucun badge global flatteur. Si des tests manquent, le dire en haut du rapport.

### 8.3 Génération
- PDF natif depuis le `ReportModel` (rendu SwiftUI → PDF, ou `NSView` → PDF). Mise en page A4, polices embarquées, couleurs adaptées à l'impression noir et blanc (ne pas dépendre de la couleur seule : icône + texte avec chaque statut).
- Export PDF + aperçu avant impression. Sauvegarde du rapport au format JSON local (pour archivage et phase 4).
- Langues : français en premier ; structure i18n dès le départ (anglais ensuite ; arabe éventuel plus tard — prévoir le support RTL dans l'architecture).

### 8.4 Partage hors ligne (niveau 1)

Le niveau 2 (rapport publié en ligne, signé, QR code vers une page publique) est un sujet séparé (`docs/LEVEL2-SPECIFICATION.md`). Au niveau 1, rien ne quitte le Mac sans action de la personne.

- **Bouton « Partager… » / « Share… »** sur l'écran Rapport : feuille de partage de macOS (`NSSharingServicePicker`) avec le PDF (AirDrop, Messages, Mail…), écrit au clic dans un dossier temporaire avec les options en cours (simple ou détaillé). Réponse au besoin « je veux l'envoyer à l'acheteur depuis le Mac ».
- **Export JSON :** écran Rapport, menu de la barre d'outils et menu Contrôle › « Exporter le rapport en JSON… ».
- **QR code hors ligne :** page 1 du PDF de niveau 1, en haut à droite (la place du QR code du niveau 2, qui reste prioritaire quand le rapport est publié). Il contient un **résumé compact en texte brut**, une clé=valeur par ligne, lisible par n'importe quel lecteur de QR code, **sans URL ni serveur**, moins de 500 caractères (`AmanCore/OfflineSummary.swift`, testé) :
  ```
  AMAN CHECK SUMMARY v1
  date=2026-10-16T14:49:48+01:00
  report=AC-T9PG-TSX8
  model=MacBookPro16,1
  name=MacBook Pro (16 pouces, 2019)
  serial_last4=MD6R
  battery_cycles=512
  battery_capacity=83%
  ssd_hours=3572
  activation_lock=off
  mdm=no signal
  apple_account=SIGNED IN
  counts=good 7, watch 1, problem 0, not tested 13, check manually 2
  tests=0/12
  ```
  Clés et valeurs en anglais (le nom commercial suit la langue du rapport). Une valeur absente vaut `n/a` ; un verrou non jugé vaut `not verified`. Seuls les 4 derniers caractères du numéro de série y figurent ; le nom du vendeur n'y figure pas. Généré avec `CIFilter.qrCodeGenerator` (CoreImage, correction M).
- **Légende obligatoire** au pied de la page 1 : « Le code en haut à droite contient un résumé de ce rapport. Il ne prouve pas l'authenticité du rapport. » (lexique §3 : aucune promesse d'inviolabilité).
- **Réglage** (⌘,) « QR code de résumé dans le PDF », activé par défaut (préférence `report.offlineQR`).

---

## 9. Phase en ligne (plus tard) : rapport enregistré

**Ne pas construire avant d'avoir validé le MVP sur de vrais Mac.**

- L'app envoie le `ReportModel` (JSON canonique) à une API HTTPS. Le serveur : valide le schéma, **horodate côté serveur**, calcule un hash SHA-256 du contenu, attribue un identifiant aléatoire non devinable (≥ 128 bits, URL courte), stocke, et renvoie l'URL. L'app affiche le QR code.
- **Page publique** : version lecture seule du rapport, avec le niveau de confiance (2), la date serveur, la version de procédure, la mention « autodiagnostic », et un historique si le rapport est remplacé ou révoqué. Possibilité de **révoquer/expirer** un rapport.
- **Confidentialité :** n'afficher publiquement que les 4 derniers caractères du numéro de série ; conserver côté serveur un **hash salé** du numéro complet seulement si nécessaire (détection de doublons). Pas de données personnelles inutiles. Consentement explicite avant l'envoi.
- **Sécurité — ce qui ne marche PAS :** un HMAC avec une clé secrète embarquée dans l'app. La clé est extractible. Ne pas présenter cela comme une protection.
- **Pistes à étudier (non garanties) :**
  - Apple **App Attest** (`DCAppAttestService`) pour attester côté serveur que la requête vient de l'app légitime sur un appareil Apple. **Vérifier la compatibilité macOS et Developer ID avant de s'y fier.**
  - Rate limiting, détection de machines virtuelles, liaison du rapport à un hash du numéro de série.
  - Ces mesures réduisent la fraude simple mais **n'empêchent pas** un vendeur de tricher sur les tests manuels. Le niveau 3 (tiers) reste la seule vraie réponse.
- **Niveau 3 :** comptes revendeurs/réparateurs vérifiés, procédure de contrôle publique et versionnée, rapport signé par le compte du professionnel avec son identité affichée.

---

## 10. Distribution, signature, permissions

- **Distribution directe (site web)** avec compte Apple Developer : signature **Developer ID Application**, **Hardened Runtime**, notarisation (`xcrun notarytool submit … --wait`), puis `xcrun stapler staple` sur le `.dmg`. Distribuer un `.dmg` notarisé et agrafé.
- **État actuel (octobre 2026) :** pas encore de Developer ID (coût annuel). Les versions publiées sont signées ad hoc avec Hardened Runtime ; la notarisation est prête mais inactive : `scripts/notarize.sh`, `scripts/make-dmg.sh --notarize`, procédure complète dans `docs/RELEASE.md`. La signature ad hoc reste le comportement par défaut.
- **Premier lancement :** l'accueil affiche un encadré « Ce que fait et ne fait pas Aman Check » (lecture seule, aucune connexion, aucun mot de passe, aucun compte Apple nécessaire). « Compris » le masque définitivement (préférence locale `trustNotice.acknowledged`). Raison : l'avertissement Gatekeeper est le premier point d'abandon d'un public non technique.
- **Ligne « Compte Apple connecté » :** son aide précise que l'app elle-même n'a besoin d'aucun compte ; la ligne vérifie si le compte du vendeur est encore lié au Mac.
- **Mac App Store :** non visé. L'App Sandbox restreint l'accès IOKit aux contrôleurs de stockage nécessaires. On ne passe pas de temps à ça pour l'instant.
- **Expérience Gatekeeper :** avec signature + notarisation, l'utilisateur voit au plus **une** fenêtre de confirmation « app téléchargée depuis Internet — Ouvrir ? » au premier lancement. Ne pas promettre « zéro alerte ». Ne pas passer par une clé USB non signée : l'app non notarisée oblige à passer par Réglages Système > Confidentialité et sécurité.
- **Permissions à déclarer :**
  - `Info.plist` : `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSBluetoothAlwaysUsageDescription`, (éventuellement `NSLocationWhenInUseUsageDescription` si lecture des SSID Wi-Fi).
  - Entitlements Hardened Runtime : `com.apple.security.device.camera`, `com.apple.security.device.audio-input`.
  - **Pas** d'« Input Monitoring » (voir 7.2). **Pas** de droits administrateur dans le MVP (les contrôles qui en exigent passent en « vérification manuelle »).
- Messages de permission en français clair, expliquant pourquoi (« pour tester la caméra de ce Mac »). Gérer le refus : le test devient « Non testé », pas « Échoué ».
- Mises à jour : prévoir un mécanisme de mise à jour (ex. Sparkle) — à décider.

---

## 11. Matrice de compatibilité à tester (indispensable)

Le risque principal est la **diversité matérielle**. Chaque collecteur doit être validé sur :

| Famille | Exemple | Points sensibles |
|---|---|---|
| Intel sans T2, SSD AHCI/SATA | (mon Mac actuel) | SMART limité, pas d'Activation Lock lisible, firmware password |
| Intel avec T2 (2018–2020) | MacBook Pro 2019 | Activation Lock lisible, batterie en mAh |
| Apple Silicon M1 | MacBook Air M1 | Clés batterie, `MaxCapacity` en %, mémoire unifiée |
| Apple Silicon M2/M3/M4 | MacBook Pro/Air récents | Changements de clés selon macOS |
| Mac de bureau | iMac, Mac mini | Modules batterie/clavier/trackpad à masquer |

- Versions de macOS : plusieurs (la plus ancienne supportée par mon app jusqu'à la plus récente).
- Constituer un **jeu de fixtures** (sorties brutes anonymisées) par machine pour les tests automatisés.
- Prévoir un **mode « export de diagnostic »** (JSON brut de toutes les clés lues) pour que des testeurs (réparateurs, amis) m'envoient les données de leurs Mac sans effort.

---

## 12. Feuille de route et critères d'acceptation

**Phase 0 — Préparation**
- Extraire la lecture SMART d'Aman Disk dans `AmanStorageKit` (package Swift). Aman Disk continue de fonctionner à l'identique. Extraire les design tokens dans un `AmanDesign` partagé.

**Phase 1 — MVP : inventaire + rapport local**
- Modèle `Measurement`, collecteurs Identité / Batterie / Stockage, détection du type de Mac, tableau de bord, PDF 1 page + version détaillée.
- ✅ Critères : aucune valeur verte pour une donnée absente ; batterie avec méthode et contrôle de cohérence ; fixtures + tests unitaires ; testé sur ≥ 2 familles de Mac.

**Phase 2 — Tests interactifs**
- Écran, clavier (physique par `keyCode`), trackpad, audio, caméra/micro, Touch ID, ports.
- ✅ Critères : chaque test réussi/échoué/ignoré/interrompu ; refus de permission géré ; provenance affichée dans le rapport.

**Phase 3 — Verrouillages**
- Activation Lock, MDM, firmware, SIP/Secure Boot, détection VM, avec états prudents et explications de limites.
- ✅ Critères : jamais de vert par défaut ; textes validés ; testé sur Intel, T2, Apple Silicon.

**Phase 4 — Rapport en ligne**
- API, page publique, QR code, révocation, confidentialité, étude App Attest.
- ✅ Critères : version de procédure et date serveur affichées ; niveau 2 clairement indiqué ; aucun terme interdit.

**Phase 5 — Pilote avec 1–2 revendeurs / réparateurs**
- Retours terrain, ajustement des seuils, définition du niveau 3, modèle économique.

---

## 13. Pistes de monétisation (à tester, pas à figer)

- Version gratuite : diagnostic + rapport local (génère la confiance et la diffusion).
- Version professionnelle : logo/nom du magasin, historique des machines contrôlées, archivage, QR codes, rapports personnalisés — abonnement revendeur ou prix par rapport enregistré.
- Contrôle vérifié par un tiers (niveau 3) : offre distincte, plus chère, car sa valeur repose sur la procédure et la responsabilité du professionnel.
- Ne choisir le modèle qu'après les retours de quelques commerces. Garder les règles de vérification publiques et transparentes.

---

## 14. Résumé des erreurs corrigées par rapport à la v1 du document

1. « Infalsifiable » / HMAC à clé embarquée → trois niveaux de confiance, pas de promesse de certification.
2. Heures du SSD présentées comme heures du Mac → « Heures de fonctionnement du SSD » ; « TBW » → « Données écrites ».
3. Formule batterie unique → méthodes multiples, contrôle d'unités, recoupement, repli « Non disponible ».
4. Date de fabrication déduite du numéro de série → impossible sur Mac récents ; année de commercialisation du modèle uniquement.
5. Activation Lock / MDM en vert/rouge binaire → états prudents + limites expliquées (statut dépend de la session du vendeur).
6. Mot de passe firmware annoncé comme lisible → nécessite admin (Intel) ; vérification manuelle dans le MVP.
7. « Gatekeeper supprimé » → au plus une confirmation ; permissions caméra/micro distinctes.
8. « Grade A / 100 % fonctionnel » → compteurs honnêtes, tests non réalisés signalés.
9. Clavier identifié par caractère → par `keyCode` physique (AZERTY/QWERTY/ISO/ANSI).
10. Serveur et QR code en priorité → déplacés après un MVP local fiable testé sur plusieurs familles de Mac.

FIN DU DOCUMENT.
