# Aman Check — serveur du niveau 2

API de publication, page publique de vérification et webhook de paiement (cahier des charges du niveau 2).
Cloudflare Workers + Hono, base D1 (SQLite), signature Ed25519 (WebCrypto). Aucune dépendance côté page : HTML rendu sur le serveur, sans JavaScript.

## Routes

| Route | Appelant | Rôle |
|---|---|---|
| `POST /v1/reports` | App (`Authorization: Bearer <clé>`, `X-App-Version`) | Publie les octets exacts du `ConditionReport` |
| `DELETE /v1/reports/{publicId}` | App (`Bearer <jeton de gestion>`) | Retire un rapport et efface son contenu |
| `GET /v1/licenses/me` | App (`Bearer <clé>`) | Offre, crédits, date de fin, logo (Pro) |
| `GET /r/{publicId}` | Navigateur | Page publique (FR/EN, `?lang=`) |
| `GET /r/{publicId}.json` | Tiers | `reportBase64` (octets exacts) + bloc `publication` + message signé |
| `GET /.well-known/aman-check-keys.json` | Tiers | Clés publiques Ed25519 (`keyId` pour la rotation) |
| `POST /webhooks/payment` | Prestataire | Crée ou crédite une licence |
| `GET /confidentialite`, `GET /acheter` | Navigateur | Confidentialité ; redirection vers la page d'achat (`PURCHASE_URL`) |

Vérification indépendante : `sha256(base64decode(reportBase64)) == publication.sha256`, puis
`Ed25519.verify(publicKey[keyId], "publicId|sha256|publishedAt", signature)`.

## Développement

```sh
npm install
npm test                      # Vitest dans le runtime Workers, base D1 locale
npm run typecheck
npm run catalog               # régénère src/catalog.json depuis AmanCore (libellés de la page)
```

Serveur local : créer `.dev.vars` (jamais versionné) à partir de `scripts/generate-signing-key dev1` :

```
SIGNING_KEY_ID=dev1
SIGNING_PRIVATE_KEY=<private>
SIGNING_PUBLIC_KEYS=[{"keyId":"dev1","publicKey":"<public.publicKey>"}]
PAYMENT_WEBHOOK_SECRET=whsec_dev
IP_HASH_SECRET=<aléatoire>
PUBLIC_BASE_URL=http://127.0.0.1:8787
```

puis `npm run db:migrate:local`, `scripts/issue-license --plan single --credits 3`, `npx wrangler dev --port 8787`,
et lancer l'app avec `--publish-server http://127.0.0.1:8787` (seuls `127.0.0.1` et `localhost` sont acceptés).

## Administration

- `scripts/issue-license --plan single|pro [--credits N] [--months N] [--shop NOM] [--note TEXTE] [--remote] [--dry-run]` : clé créée à la main (boutiques pilotes, ventes encaissées localement). La clé n'est affichée qu'une fois.
- `scripts/set-logo --key CLÉ --logo logo.png [--shop NOM]` : logo de l'offre Pro (PNG, 32 Ko au plus).
- `scripts/generate-signing-key k2` : nouvelle paire Ed25519. Rotation : ajouter la clé publique à `SIGNING_PUBLIC_KEYS` (garder les anciennes), passer `SIGNING_KEY_ID`, remplacer `SIGNING_PRIVATE_KEY`.

## Mise en ligne (à faire)

1. Choisir le domaine (question ouverte §14) : `PUBLIC_BASE_URL` dans `wrangler.jsonc` **et** `PublishClient.productionBaseURL` dans l'app.
2. `wrangler d1 create aman-check`, reporter `database_id`, `npm run db:migrate:remote`.
3. `wrangler secret put` pour `SIGNING_PRIVATE_KEY`, `SIGNING_PUBLIC_KEYS`, `PAYMENT_WEBHOOK_SECRET`, `IP_HASH_SECRET`.
4. Prestataire de paiement : l'implémentation fournie (`src/payment/lemonsqueezy.ts`) est provisoire. Renseigner `PAYMENT_PRODUCTS` (identifiant de produit ou de variante → `single` / `pro`) et `PURCHASE_URL`. Pour en changer : nouvelle implémentation de `PaymentProvider`.
5. Faire relire le bandeau légal de niveau 2 (`Level2Text.disclaimer`) et la page `/confidentialite`.

## Choix à connaître

- Une nouvelle tentative (même clé, mêmes octets) renvoie la publication existante, sans crédit, avec un **nouveau** jeton de gestion : l'app n'avait peut-être jamais reçu le premier.
- Le crédit « 1 Mac pendant 30 jours » est ancré sur la publication qui l'a consommé : les republications de ce Mac sont gratuites jusqu'à 30 jours après, pas au-delà.
- Un rapport sans numéro de série lisible consomme toujours un crédit (pas de rattachement possible à un Mac).
- Les valeurs mesurées (« 32 Go », « En bonne santé ») restent dans la langue de l'app qui a produit le rapport ; les libellés suivent la langue du navigateur.
