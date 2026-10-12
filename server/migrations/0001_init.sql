-- Aman Check niveau 2 : schéma initial (cahier des charges §6).
-- Aucune donnée personnelle : ni e-mail, ni nom, ni adresse IP en clair.

CREATE TABLE licenses (
  id TEXT PRIMARY KEY,
  key_hash TEXT NOT NULL UNIQUE,            -- SHA-256 de la clé de licence, jamais la clé elle-même
  plan TEXT NOT NULL CHECK (plan IN ('single', 'pro')),
  credits INTEGER NOT NULL DEFAULT 0,       -- offre « single » : publications restantes
  valid_until TEXT,                         -- offre « pro » : fin de l'abonnement (ISO 8601)
  order_ref TEXT,                           -- référence de commande du prestataire, ou « manual:… »
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked')),
  shop_name TEXT,                           -- offre Pro : nom du magasin affiché avec le logo
  logo BLOB,                                -- offre Pro : logo PNG (32 Ko au plus)
  created_at TEXT NOT NULL
);
CREATE INDEX licenses_order_ref ON licenses (order_ref);

CREATE TABLE reports (
  public_id TEXT PRIMARY KEY,               -- 12 caractères, affiché XXXX-XXXX-XXXX
  report_id TEXT NOT NULL,                  -- identifiant local AC-XXXX-XXXX
  license_id TEXT NOT NULL REFERENCES licenses (id),
  model_identifier TEXT NOT NULL,
  serial_last4 TEXT NOT NULL,
  body BLOB,                                -- octets exacts reçus ; NULL après retrait ou après 90 jours
  sha256 TEXT NOT NULL,
  signature TEXT NOT NULL,
  key_id TEXT NOT NULL,
  app_version TEXT NOT NULL,
  generated_at TEXT NOT NULL,               -- date du contrôle (dans le rapport)
  published_at TEXT NOT NULL,
  valid_until TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'published' CHECK (status IN ('published', 'replaced', 'withdrawn')),
  replaced_by TEXT,
  manage_token_hash TEXT NOT NULL,
  consumed_credit INTEGER NOT NULL DEFAULT 0,
  credit_anchor_at TEXT NOT NULL,           -- début de la fenêtre de 30 jours du crédit consommé pour ce Mac
  content_erased_at TEXT
);
CREATE INDEX reports_license_mac ON reports (license_id, model_identifier, serial_last4, published_at);
CREATE INDEX reports_license_sha ON reports (license_id, sha256);
CREATE INDEX reports_published_at ON reports (published_at);

-- Limitation de débit : fenêtres glissantes par minute ou par heure.
-- Les clés « ip:… » sont des HMAC de l'adresse IP, purgés après une heure.
CREATE TABLE rate_limits (
  bucket TEXT NOT NULL,
  window_start INTEGER NOT NULL,
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (bucket, window_start)
);

-- Événements de paiement déjà traités (idempotence des webhooks).
CREATE TABLE payment_events (
  event_id TEXT PRIMARY KEY,
  received_at TEXT NOT NULL
);

-- Abonnement reçu avant la clé (l'ordre des webhooks n'est pas garanti).
CREATE TABLE pending_subscriptions (
  order_ref TEXT PRIMARY KEY,
  valid_until TEXT NOT NULL,
  received_at TEXT NOT NULL
);
