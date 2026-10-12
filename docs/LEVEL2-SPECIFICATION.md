# Aman Check — Cahier des charges du niveau 2 (rapport vérifiable en ligne)

Oct 11, 2026 · @Midou

## 1. Objectif et périmètre

Le niveau 2 permet à un vendeur de publier son rapport d'état sur une page web publique, accessible par un lien court et un QR code, que l'acheteur ouvre depuis son téléphone. C'est la fonction payante d'Aman Check ; le contrôle local (niveau 1) reste gratuit.

**Ce que la page prouve :**

- le rapport a bien été produit par l'app Aman Check, à la date indiquée ;
- son contenu n'a pas été modifié depuis sa publication ;
- il concerne un Mac dont le numéro de série se termine par les 4 caractères affichés.

**Ce que la page ne prouve pas, et doit dire clairement :**

- que le Mac est en bon état aujourd'hui (le rapport date du jour du contrôle) ;
- que les tests « constatés par l'utilisateur » sont exacts (ils sont déclaratifs) ;
- que le Mac n'est ni volé ni verrouillé après effacement.

**Livrables :** une API, une page publique de vérification, les changements dans l'app macOS (publication, QR code dans le PDF), le déblocage par paiement.

## 2. Règles produit

Les 12 règles produit du niveau 1 (voir `SPECIFICATION.md`) restent valables, y compris sur la page web. Une seule évolue.

| Règle | Application au niveau 2 |
| --- | --- |
| 11. Rien n'est envoyé sur le réseau | Devient : **rien n'est envoyé sans action explicite**. L'app ne fait aucune requête tant que l'utilisateur n'a pas cliqué sur « Publier le rapport » et confirmé l'écran qui liste ce qui sera envoyé. Aucune télémétrie, aucune vérification de mise à jour silencieuse. |
| 2. Lexique interdit | S'applique à la page web, au QR code et aux textes marketing. Le terme retenu est « rapport vérifiable » ou « rapport enregistré », jamais « certifié » ni « authentifié ». |
| 4. Pas de note globale | La page web affiche les mêmes compteurs que le PDF, bloqueurs en tête et en rouge. |
| 5 et 6. Provenance et niveau | Chaque ligne garde sa provenance. Le badge devient « Niveau 2 · Rapport enregistré en ligne ». |
| 10. Numéro de série | Seuls les 4 derniers caractères quittent le Mac. Le numéro complet n'est jamais envoyé, même haché sans sel (voir section 5). |
| 12. Aucune élévation de droits | Inchangé. |

Le texte du bandeau légal de `ReportText.swift` reçoit une variante niveau 2, à faire valider avant mise en ligne.

## 3. Parcours

### Vendeur (dans l'app)

1. Il lance le contrôle et les tests guidés, comme aujourd'hui.
2. Sur l'écran Rapport, un bouton « Publier un rapport vérifiable » apparaît à côté de « Exporter en PDF ».
3. Si des tests sont non réalisés ou si un bloqueur est présent, l'app le rappelle : « Votre rapport sera publié tel quel, avec 3 tests non réalisés. » La publication reste possible.
4. Un écran de confirmation liste exactement ce qui sera envoyé et ce qui ne le sera pas (section 10).
5. S'il n'a pas de crédit, il saisit une clé de licence ou ouvre la page d'achat dans son navigateur (section 9).
6. L'app publie, puis affiche le lien court, le QR code, un bouton « Copier le lien » et un texte prêt à coller dans une annonce.
7. Le PDF exporté ensuite porte le QR code, le lien et le badge niveau 2.
8. Il peut retirer le rapport à tout moment depuis l'app (« Retirer de la publication »).

### Acheteur (sur son téléphone, sans rien installer)

1. Il scanne le QR code du PDF ou de la fiche imprimée, ou ouvre le lien de l'annonce.
2. Il arrive sur la page publique : état de validité, date du contrôle, modèle, 4 derniers caractères du numéro de série, bloqueurs, compteurs, détail.
3. La page lui indique les vérifications à faire lui-même sur place : comparer les 4 caractères avec le numéro gravé sous le Mac, comparer la date du rapport avec celle de l'annonce, faire effacer le Mac devant lui.
4. Si le vendeur lui remet un PDF, il peut vérifier que ce PDF correspond à la page en comparant l'identifiant et la date ; le contenu qui fait foi est celui de la page.

## 4. Architecture

Trois composants à construire : la publication dans l'app, une API, une page publique. Le paiement est délégué à un prestataire.

&#91;embedded content: architecture du niveau 2 · 5 composants\]

L'app n'envoie rien à la page publique ni au prestataire de paiement : tout passe par l'API, qui est le seul composant à détenir la clé de signature.

| Brique | Choix recommandé | Raison |
| --- | --- | --- |
| API et page publique | Cloudflare Workers, TypeScript, routeur Hono | Pas de serveur à administrer, offre gratuite suffisante au démarrage, HTTPS natif |
| Base de données | Cloudflare D1 (SQLite) | Schéma simple, sauvegardes intégrées |
| Signature | Ed25519, clé privée stockée en secret du Worker | Standard, disponible dans WebCrypto et CryptoKit |
| Rendu de la page | HTML rendu côté serveur, sans framework, CSS embarqué | Page légère, lisible sur un téléphone bas de gamme en 3G |
| QR code | Généré dans l'app avec CoreImage (`CIQRCodeGenerator`) | Aucune dépendance, fonctionne hors ligne une fois le lien obtenu |
| Réseau dans l'app | `URLSession`, un seul hôte autorisé | Aucune bibliothèque tierce |
| Code serveur | Dossier `server/` à la racine du dépôt, avec ses propres tests | Le schéma JSON reste synchronisé avec `AmanCore` |

Le nom de domaine reste à choisir (question ouverte, section 14). Dans ce document, il est noté `DOMAINE`.

## 5. Intégrité du rapport

Le serveur conserve les octets exacts du rapport reçu, en calcule l'empreinte et la signe. La page publique est toujours rendue à partir de ces octets, jamais à partir d'un PDF.

**Identifiants**

- `reportId` : l'identifiant local actuel `AC-XXXX-XXXX`, conservé comme référence lisible.
- `publicId` : généré par le serveur, 12 caractères du même alphabet (sans 0, O, 1, I), affiché `XXXX-XXXX-XXXX`. C'est lui qui figure dans l'URL `https://DOMAINE/r/XXXX-XXXX-XXXX`. Il est assez long pour ne pas être devinable par énumération.

**Empreinte et signature**

1. L'app encode le `ConditionReport` comme aujourd'hui (clés triées, dates ISO 8601) et envoie ces octets tels quels.
2. Le serveur calcule `sha256` sur les octets reçus.
3. Le serveur signe en Ed25519 la chaîne `publicId | sha256 | publishedAt` et renvoie `publicId`, `sha256`, `publishedAt`, `signature`, `keyId`.
4. L'app enregistre ces cinq valeurs dans un bloc `publication` ajouté à l'archive JSON, à côté du rapport et sans le modifier.
5. Le PDF affiche le `publicId`, le lien, le QR code et les 8 premiers caractères de l'empreinte.

La clé publique est servie sur `https://DOMAINE/.well-known/aman-check-keys.json`, avec un `keyId` par clé pour permettre une rotation.

**Lien avec le Mac**

Aucun identifiant dérivé du numéro de série complet n'est envoyé dans cette version. Un hachage du numéro de série avec un sel embarqué dans l'app serait réversible par force brute. Le rapport est rattaché au Mac par le couple modèle + 4 derniers caractères, que l'acheteur compare avec la machine.

**États d'un rapport publié**

| État | Condition | Ce que voit l'acheteur |
| --- | --- | --- |
| Valide | Publié depuis 30 jours ou moins | Bandeau neutre : « Rapport enregistré le …, contenu non modifié depuis » |
| Ancien | Plus de 30 jours | Bandeau orange : « Ce rapport date de plus de 30 jours. Demandez un nouveau contrôle. » |
| Remplacé | Une publication plus récente existe pour la même clé et le même Mac | Bandeau orange avec lien vers la version récente |
| Retiré | Le vendeur l'a retiré | « Ce rapport a été retiré par son auteur », sans contenu |
| Introuvable | Identifiant inconnu | « Aucun rapport ne correspond à ce lien. Méfiez-vous d'un PDF dont le QR code mène ici. » |

Le bandeau « Valide » n'est jamais vert : la validité concerne l'enregistrement, pas l'état du Mac.

## 6. API

Sept routes, toutes en HTTPS sous `https://DOMAINE`. Les routes `/v1` répondent en JSON.

| Route | Appelant | Authentification | Rôle |
| --- | --- | --- | --- |
| `POST /v1/reports` | App | Clé de licence (`Authorization: Bearer`) | Publie un rapport. Corps = octets JSON du `ConditionReport`. En-tête `X-App-Version`. |
| `DELETE /v1/reports/{publicId}` | App | Jeton de gestion | Retire un rapport et efface son contenu |
| `GET /v1/licenses/me` | App | Clé de licence | Renvoie l'offre, les crédits restants, la date de fin |
| `GET /r/{publicId}` | Navigateur | Aucune | Page publique HTML |
| `GET /r/{publicId}.json` | Tiers | Aucune | Octets du rapport et bloc `publication`, pour vérification indépendante |
| `GET /.well-known/aman-check-keys.json` | Tiers | Aucune | Clés publiques de signature |
| `POST /webhooks/payment` | Prestataire de paiement | Signature du prestataire | Crée ou crédite une licence |

**Réponse de `POST /v1/reports` (201)** : `publicId`, `url`, `sha256`, `publishedAt`, `signature`, `keyId`, `validUntil`, `creditsRemaining`, `manageToken`. Le `manageToken` n'est renvoyé qu'une fois ; l'app le range dans le trousseau, le serveur n'en garde que le hachage.

**Contrôles du serveur avant d'accepter un rapport**

- Taille maximale 256 Ko, JSON valide, `schemaVersion` connue.
- Version de l'app supérieure ou égale à la version minimale configurée.
- Profil non simulé : un rapport produit avec `--simulate-model` est refusé.
- Champ numéro de série de 4 caractères au plus ; aucune sortie brute de diagnostic dans le corps.
- Cohérence : aucune mesure en statut jugé avec une valeur absente (même garde-fou que `Measurement`).
- Fraîcheur : date du rapport comprise entre 24 heures avant la réception et 10 minutes après. Un ancien rapport ne peut pas être publié comme neuf.

**Erreurs**

| Code HTTP | `error` | Message affiché dans l'app |
| --- | --- | --- |
| 400 | `invalid_report` | « Le rapport n'a pas pu être lu. Relancez le contrôle. » |
| 401 | `invalid_license` | « Cette clé n'est pas reconnue. » |
| 402 | `no_credit` | « Il ne reste plus de publication sur cette clé. » avec bouton d'achat |
| 413 | `too_large` | « Rapport trop volumineux. » |
| 422 | `report_too_old` | « Ce contrôle date de plus de 24 heures. Relancez-le avant de publier. » |
| 422 | `simulated_profile` | « Un profil simulé ne peut pas être publié. » |
| 426 | `app_too_old` | « Mettez à jour Aman Check pour publier. » |
| 429 | `rate_limited` | « Trop de tentatives. Réessayez dans quelques minutes. » |

Toute erreur réseau laisse le rapport local intact et exportable en niveau 1.

**Schéma de la base**

- `reports` : `public_id` (clé), `report_id`, `license_id`, `model_identifier`, `serial_last4`, `body` (octets), `sha256`, `signature`, `key_id`, `app_version`, `published_at`, `status`, `replaced_by`, `manage_token_hash`.
- `licenses` : `id`, `key_hash`, `plan` (`single`, `pro`), `credits`, `valid_until`, `order_ref`, `created_at`.

**Limites de débit** : 10 publications par heure et par clé ; 60 lectures par minute et par adresse IP sur `/r/`.

## 7. Page publique de vérification

La page est pensée pour un téléphone tenu dans une main, devant le vendeur : une colonne, gros caractères, l'essentiel visible sans défiler.

**Ordre du contenu, de haut en bas**

1. Bandeau d'état du rapport (section 5) avec la date du contrôle en toutes lettres et son ancienneté (« il y a 3 jours »).
2. Identité : nom du Mac, année de commercialisation du modèle, processeur, mémoire, stockage, macOS, n° de série `••••XXXX`.
3. Encadré « Vérifiez que c'est bien ce Mac » : comparer les 4 caractères avec le numéro gravé sous la machine ou affiché dans « À propos de ce Mac ».
4. Bloqueurs éventuels, en rouge.
5. Compteurs : bons, à surveiller, problèmes, non testés, à vérifier soi-même. Pas de note globale.
6. Verrouillages, avec leur limite affichée sous chaque verdict.
7. Batterie et SSD, avec les mêmes phrases d'interprétation que dans l'app.
8. Tests guidés, un par ligne, avec statut et provenance (mesuré ou constaté).
9. « À vérifier avant l'achat ».
10. Détails avancés, repliés.
11. Encadré « Ce que ce rapport prouve et ne prouve pas » (section 1).
12. Bandeau légal, identifiant public, empreinte, version de l'app et de la procédure.
13. Pied de page : « Contrôlez votre Mac gratuitement avec Aman Check » et lien de téléchargement.

**Exigences**

- Tous les libellés viennent de la même source que `MetricCatalog` : exporter le catalogue en JSON au moment du build pour le serveur, ne pas le recopier à la main.
- Français et anglais, selon la langue du navigateur, avec un lien pour changer. Arabe prévu ensuite : la mise en page doit accepter l'écriture de droite à gauche.
- Poids total de la page inférieur à 150 Ko, aucun script tiers, aucun traceur, aucune police distante.
- Lisible sans JavaScript. Thèmes clair et sombre.
- Icône et texte pour chaque statut, jamais la couleur seule.
- Balise `noindex` : les rapports ne doivent pas apparaître dans les moteurs de recherche.
- Aperçu de lien (Open Graph) sobre : « Rapport d'état · MacBook Pro 16 pouces, 2019 · contrôlé le 11 octobre 2026 ». Aucun verdict dans l'aperçu.

**QR code**

- Contenu : l'URL `https://DOMAINE/r/XXXX-XXXX-XXXX`, rien d'autre.
- Niveau de correction M, taille minimale 25 mm sur le PDF, marge blanche respectée.
- Le lien est aussi écrit en clair sous le QR code, pour pouvoir être tapé à la main.

## 8. Changements dans l'app macOS

La logique de publication va dans `AmanCore` (pure, testable avec des fixtures) ; seul l'appel réseau va dans `AmanCheck`.

**Prérequis à corriger avant tout (issus de la section 15 du rapport)**

- [ ] `runAnalysis` réinitialise les résultats de tests : un rapport publié ne doit pas porter des tests antérieurs au contrôle.
- [ ] Le profil simulé est inscrit dans le `ConditionReport` (champ `simulated`) et visible dans le PDF.
- [ ] Le test clavier refuse de démarrer tant qu'un clavier externe est branché, au lieu d'un simple avertissement. Même règle pour le trackpad avec une souris.
- [ ] Le numéro de série de la batterie est masqué dans l'export de diagnostic.

**Modèle (`AmanCore`)**

- `PublicationRecord` (Codable) : `publicId`, `url`, `sha256`, `publishedAt`, `signature`, `keyId`, `validUntil`.
- `PublishedReportArchive` : `report` (inchangé) + `publication`. Le `ConditionReport` et son `schemaVersion` ne changent pas, hormis le champ `simulated`.
- Le niveau affiché est dérivé : niveau 2 si un `PublicationRecord` existe pour le `reportId` courant, sinon niveau 1. Relancer le contrôle crée un nouveau `reportId` et repasse donc en niveau 1.
- `PublishError` : une valeur par code de la section 6, avec son message bilingue.

**Réseau (`AmanCheck`)**

- Un seul type, `PublishClient`, contient l'URL de base en dur et tous les appels `URLSession`. Aucun autre fichier n'ouvre de connexion.
- Délai maximal 20 secondes. En cas de coupure, une seconde tentative est sans risque : le serveur renvoie la publication existante pour une même clé et une même empreinte, sans consommer de crédit.
- Clé de licence et jetons de gestion rangés dans le trousseau, jamais dans `UserDefaults` ni dans le journal de diagnostic.

**Interface**

- Écran Rapport : nouveau bloc « Rapport vérifiable » sous les exports, avec quatre états : non publié, publication en cours, publié, erreur.
- État publié : QR code, lien, « Copier le lien », « Copier le texte pour l'annonce », date de fin de validité, « Retirer de la publication ».
- Feuille de confirmation avant envoi (section 10), avec un bouton « Publier » et un bouton « Annuler » de même poids visuel.
- Champ « Clé de licence » dans cette feuille, avec le solde affiché une fois la clé validée, et un lien « Obtenir une clé » qui ouvre le navigateur.
- Menu Contrôle : « Publier le rapport… » (⇧⌘P).
- Mention de bas d'écran mise à jour : « Rien n'est envoyé sans votre accord. »

**PDF**

- Page 1, en-tête à droite : QR code, lien en clair, `publicId`, badge « Niveau 2 · Rapport enregistré en ligne ».
- Pied de page : 8 premiers caractères de l'empreinte.
- Un PDF exporté avant publication reste un PDF de niveau 1, sans QR code.
- Nouveau format « Fiche » A5 pour les boutiques : nom du Mac, 4 chiffres clés, QR code en grand. Sans verdict global.

**Texte pour l'annonce (copié dans le presse-papiers)**

« Rapport d'état Aman Check du 11 octobre 2026, consultable ici : https://DOMAINE/r/XXXX-XXXX-XXXX »

## 9. Paiement et déblocage

L'achat se fait dans le navigateur, sur une page hébergée par un prestataire qui encaisse et gère la TVA. L'app ne voit jamais de moyen de paiement : elle ne manipule qu'une clé de licence.

| Offre | Ce que la clé donne | Prix de départ |
| --- | --- | --- |
| Rapport vérifiable | 1 crédit = 1 Mac pendant 30 jours, republications illimitées pour ce Mac | 4,99 € |
| Pro | Publications illimitées pendant la durée de l'abonnement, logo du magasin sur la page et le PDF, format Fiche | 19 € par mois ou 149 € par an |

**Règle de consommation d'un crédit**

- Une publication consomme un crédit si aucun rapport valide n'existe déjà pour la même clé, le même identifiant de modèle et les mêmes 4 caractères.
- Sinon, elle est gratuite et l'ancienne publication passe à l'état « Remplacé ».
- L'offre Pro ne décompte rien, avec un plafond technique de 300 publications par mois contre les abus.

**Circuit**

1. L'utilisateur clique sur « Obtenir une clé » ; le navigateur ouvre la page d'achat.
2. Après paiement, le prestataire lui envoie la clé par e-mail et appelle `POST /webhooks/payment`.
3. Le serveur vérifie la signature du webhook, puis crée la licence (hachage de la clé, offre, crédits ou date de fin).
4. L'utilisateur colle la clé dans l'app ; `GET /v1/licenses/me` confirme le solde.
5. Un remboursement ou une résiliation arrive par le même webhook : les crédits non utilisés sont annulés, les rapports déjà publiés restent en ligne jusqu'à leur terme.

**Exigences**

- Les prix et le plafond sont dans la configuration du serveur, pas dans le code de l'app.
- Le serveur ne stocke ni e-mail ni nom : seulement la référence de commande du prestataire.
- Un script d'administration `server/scripts/issue-license` crée des clés à la main. Il sert aux boutiques pilotes et aux ventes encaissées localement en Algérie, hors prestataire.
- Le code du webhook est isolé derrière une interface `PaymentProvider`, pour pouvoir changer de prestataire sans toucher au reste.

## 10. Confidentialité et données conservées

Seul le contenu du rapport d'état quitte le Mac, et seulement après confirmation. La feuille de confirmation affiche les deux listes ci-dessous, mot pour mot.

| Envoyé et rendu public | Jamais envoyé |
| --- | --- |
| Modèle, année, processeur, mémoire, stockage, version de macOS | Numéro de série complet du Mac |
| 4 derniers caractères du numéro de série | Numéros de série de la batterie, du SSD, des écrans |
| Mesures de batterie, de SSD, de verrouillages, de sans-fil | Nom du compte, nom de l'ordinateur, identifiant Apple |
| Résultats des tests guidés et leur date | Fichiers, photos, enregistrements audio ou vidéo des tests |
| Nom du vendeur ou du magasin, s'il a été saisi | Noms des réseaux Wi-Fi, appareils Bluetooth |
| Version de l'app et de la procédure | Journal de diagnostic et sorties brutes des commandes |

**Règles**

- Avant l'envoi, l'app vérifie par un test automatique que le JSON ne contient aucun champ de la colonne de droite. Un modèle de SSD est acceptable ; son numéro de série ne l'est pas.
- Le serveur ne journalise pas les adresses IP au-delà de la fenêtre de limitation de débit (1 heure).
- Le contenu d'un rapport est effacé 90 jours après sa publication, ou immédiatement s'il est retiré. Il ne reste ensuite que l'identifiant, l'empreinte, les dates et l'état.
- La page publique ne contient aucun traceur et aucun cookie.
- Une page `https://DOMAINE/confidentialite` reprend ces règles en langage simple, avec une adresse de contact pour demander un retrait.
- Le champ « Vendeur ou magasin » porte un rappel dans l'app : « Ce nom sera visible par toute personne ayant le lien. »

## 11. Anti-abus et limites assumées

Le niveau 2 empêche de modifier un rapport après coup ; il n'empêche pas un vendeur déterminé de fabriquer un faux rapport sur son propre Mac. Cette limite est écrite sur la page publique.

| Fraude | Réponse dans cette version | Reste possible |
| --- | --- | --- |
| Retoucher le PDF après export | La page en ligne fait foi ; le QR code y mène | Non, si l'acheteur ouvre la page |
| Publier le rapport d'un autre Mac, plus sain | 4 caractères du numéro de série à comparer avec la machine | Oui, si l'acheteur ne compare pas |
| Republier un vieux rapport comme récent | Contrôle de fraîcheur de 24 heures, date bien visible | Non |
| Fabriquer un QR code vers une fausse page | Le domaine est écrit sur le PDF et rappelé dans l'app | Oui, si l'acheteur ne lit pas l'adresse |
| Valider les tests avec un clavier ou une souris externes | Tests bloqués tant qu'un périphérique externe est branché | Partiellement |
| Répondre « tout va bien » aux tests déclaratifs | Provenance « constaté par l'utilisateur » affichée sur chaque ligne | Oui, assumé |
| Envoyer un JSON forgé à l'API sans passer par l'app | Clé de licence exigée, contrôles de cohérence, limites de débit | Oui, pour quelqu'un de technique |
| Exécuter l'app dans une machine virtuelle | Bloqueur rouge déjà présent, repris en tête de page (détection par un seul `sysctl`) | Oui, pour quelqu'un de technique |

Le dernier point ouvert (JSON forgé) ne se ferme vraiment qu'avec le niveau 3, où un réparateur partenaire fait le contrôle lui-même. Ne pas tenter de le masquer par de l'obscurcissement dans l'app.

## 12. Tests et critères d'acceptation

Le niveau 2 est livrable quand les 14 points ci-dessous passent, tests automatiques inclus.

**Tests unitaires `AmanCore` (Swift Testing, fixtures existantes)**

- [ ] L'archive `PublishedReportArchive` fait l'aller-retour JSON sans modifier un seul octet du rapport.
- [ ] Le niveau affiché est 2 avec une publication pour le `reportId` courant, 1 sinon, 1 après un nouveau contrôle.
- [ ] Le JSON prêt à l'envoi ne contient aucun champ interdit (numéros de série complets, nom d'hôte, sorties brutes).
- [ ] Chaque code d'erreur de l'API correspond à un message bilingue, sans identifiant technique.
- [ ] Un profil simulé ne peut pas être publié.
- [ ] Les textes de niveau 2 ne contiennent aucun mot du lexique interdit.

**Tests du serveur (Vitest, base D1 locale)**

- [ ] Publication valide : 201, empreinte égale au SHA-256 des octets envoyés, signature vérifiable avec la clé publique.
- [ ] Chaque contrôle de la section 6 produit son code d'erreur.
- [ ] Même clé et même empreinte envoyées deux fois : une seule publication, un seul crédit.
- [ ] Republication pour le même Mac : pas de crédit consommé, ancienne page à l'état « Remplacé ».
- [ ] Retrait avec un mauvais jeton refusé ; avec le bon jeton, le contenu est effacé.
- [ ] Webhook avec signature invalide rejeté ; webhook valide créditant la bonne offre.

**Vérifications manuelles**

- [ ] Sur la machine de développement et sur un Mac Apple Silicon : contrôle, publication, scan du QR code depuis un téléphone Android et un iPhone, page lisible en moins de 3 secondes en 4G.
- [ ] Coupure du Wi-Fi pendant la publication : message clair, rapport local intact, nouvelle tentative sans double décompte.

Ces deux points figurent dans `VERIFICATION.md`.

## 13. Ordre de travail

Cinq phases, chacune livrable et testable seule, validées une par une.

| Phase | Contenu | Validation attendue |
| --- | --- | --- |
| 0. Prérequis | Les 4 corrections de la section 8 | Tests existants verts, plus un test par correction |
| 1. Serveur | Schéma D1, `POST /v1/reports`, signature, `GET /r/{id}.json`, clés publiques, script `issue-license` | Tests serveur verts ; publication réussie avec `curl` et une fixture |
| 2. Page publique | Rendu HTML, états du rapport, français et anglais, export du `MetricCatalog` | Captures de la page sur téléphone pour les 5 états |
| 3. App | `PublicationRecord`, `PublishClient`, feuille de confirmation, bloc « Rapport vérifiable », QR code, PDF niveau 2, retrait | Parcours vendeur complet avec une clé créée à la main |
| 4. Paiement | Webhook, offres, `GET /v1/licenses/me`, lien d'achat, format Fiche et logo pour l'offre Pro | Achat de test de bout en bout en mode bac à sable |

Les phases 1 à 3 permettent déjà un pilote avec des boutiques, en créant les clés à la main. Le paiement en ligne peut attendre le choix définitif du prestataire.

## 14. Hors périmètre et questions ouvertes

**Hors périmètre de cette version**

- Comptes utilisateurs, tableau de bord web, historique des rapports en ligne.
- Niveau 3 (contrôle par un réparateur partenaire).
- Photos de l'état extérieur du Mac.
- Estimation de prix de revente.
- Application iPhone ou Windows.
- Mise à jour automatique de l'app.

**Questions ouvertes, à trancher avant la phase indiquée**

- [ ] Nom de domaine court et lisible sur un PDF imprimé (avant la phase 1).
- [ ] Prestataire de paiement : confirmer qu'il verse bien sur un compte bancaire algérien, et en quelle devise (avant la phase 4).
- [ ] Première publication offerte au lancement pour amorcer l'usage, ou payante dès le départ (avant la phase 4).
- [ ] Durée de validité de 30 jours et effacement à 90 jours : à confirmer (avant la phase 1).
- [ ] Tarif en dinars et mode d'encaissement local pour l'Algérie (avant le pilote boutiques).
- [ ] Texte du bandeau légal de niveau 2 et page de confidentialité : à faire relire (avant la mise en ligne).
- [ ] Identification « licence + modèle + 4 derniers caractères » côté serveur : sur les numéros de série à 12 caractères (Mac Intel, premiers M1), ces 4 caractères désignent la configuration, pas l'exemplaire ; deux Mac de même configuration sont confondus. À trancher avant d'en faire une clé de rattachement.
