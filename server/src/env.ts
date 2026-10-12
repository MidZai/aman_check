/** Liaisons et configuration du Worker (wrangler.jsonc + secrets). */
export interface Env {
  DB: D1Database;
  PUBLIC_BASE_URL: string;
  MIN_APP_VERSION: string;
  VALIDITY_DAYS: string;
  RETENTION_DAYS: string;
  PRO_MONTHLY_CAP: string;
  PUBLISH_PER_HOUR: string;
  READS_PER_MINUTE: string;
  SIGNING_KEY_ID: string;
  PURCHASE_URL: string;
  PRICES: string;
  PAYMENT_PRODUCTS: string;
  CONTACT_EMAIL: string;
  DOWNLOAD_URL: string;
  /** Clé privée Ed25519 courante, PKCS#8 encodé en base64. */
  SIGNING_PRIVATE_KEY: string;
  /** Clés publiques servies sur /.well-known : JSON `[{ "keyId": "k1", "publicKey": "<base64 brut 32 octets>" }]`. */
  SIGNING_PUBLIC_KEYS: string;
  /** Secret partagé avec le prestataire de paiement (signature des webhooks). */
  PAYMENT_WEBHOOK_SECRET: string;
  /** Secret pour hacher les adresses IP des compteurs de débit. */
  IP_HASH_SECRET: string;
}

export interface Config {
  baseUrl: string;
  minAppVersion: string;
  validityDays: number;
  retentionDays: number;
  proMonthlyCap: number;
  publishPerHour: number;
  readsPerMinute: number;
}

export function config(env: Env): Config {
  const int = (value: string | undefined, fallback: number) => {
    const n = Number.parseInt(value ?? "", 10);
    return Number.isFinite(n) && n > 0 ? n : fallback;
  };
  return {
    baseUrl: (env.PUBLIC_BASE_URL || "").replace(/\/+$/, ""),
    minAppVersion: env.MIN_APP_VERSION || "1.0.0",
    validityDays: int(env.VALIDITY_DAYS, 30),
    retentionDays: int(env.RETENTION_DAYS, 90),
    proMonthlyCap: int(env.PRO_MONTHLY_CAP, 300),
    publishPerHour: int(env.PUBLISH_PER_HOUR, 10),
    readsPerMinute: int(env.READS_PER_MINUTE, 60),
  };
}

export const DAY_MS = 24 * 60 * 60 * 1000;
