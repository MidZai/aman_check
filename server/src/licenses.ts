/** Licences : création, lecture par clé, solde (cahier des charges §9). */
import { hashLicenseKey, newLicenseKey, randomFromAlphabet, toBase64 } from "./crypto";

export type Plan = "single" | "pro";

export interface LicenseRow {
  id: string;
  key_hash: string;
  plan: Plan;
  credits: number;
  valid_until: string | null;
  order_ref: string | null;
  status: "active" | "revoked";
  shop_name: string | null;
  logo: ArrayBuffer | number[] | null;
  created_at: string;
}

/** Lit la clé de `Authorization: Bearer …`. */
export function bearer(request: Request): string | null {
  const header = request.headers.get("Authorization") ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  return match ? match[1].trim() : null;
}

export async function findLicense(db: D1Database, key: string | null): Promise<LicenseRow | null> {
  if (!key) return null;
  const row = await db.prepare("SELECT * FROM licenses WHERE key_hash = ?1").bind(await hashLicenseKey(key)).first<LicenseRow>();
  return row && row.status === "active" ? row : null;
}

export function isProActive(license: LicenseRow, now: Date): boolean {
  return license.plan === "pro" && !!license.valid_until && Date.parse(license.valid_until) > now.getTime();
}

export interface NewLicense {
  plan: Plan;
  credits?: number;
  validUntil?: string | null;
  orderRef?: string | null;
  /** Clé fournie par le prestataire (envoyée par e-mail à l'acheteur) ; sinon générée ici. */
  key?: string;
  shopName?: string | null;
}

export async function createLicense(db: D1Database, input: NewLicense, now: Date): Promise<{ id: string; key: string }> {
  const key = input.key?.trim() || newLicenseKey();
  const id = `lic_${randomFromAlphabet(16)}`;
  await db
    .prepare(
      `INSERT INTO licenses (id, key_hash, plan, credits, valid_until, order_ref, status, shop_name, created_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, 'active', ?7, ?8)`,
    )
    .bind(id, await hashLicenseKey(key), input.plan, input.credits ?? 0, input.validUntil ?? null, input.orderRef ?? null,
      input.shopName ?? null, now.toISOString())
    .run();
  return { id, key };
}

/** Réponse de `GET /v1/licenses/me`. Aucune donnée personnelle. */
export async function licenseSummary(db: D1Database, license: LicenseRow, now: Date, proMonthlyCap: number) {
  const monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)).toISOString();
  const used = await db
    .prepare("SELECT COUNT(*) AS n FROM reports WHERE license_id = ?1 AND published_at >= ?2")
    .bind(license.id, monthStart)
    .first<{ n: number }>();
  const pro = license.plan === "pro";
  return {
    plan: license.plan,
    creditsRemaining: pro ? null : license.credits,
    validUntil: license.valid_until,
    active: pro ? isProActive(license, now) : license.credits > 0,
    publicationsThisMonth: used?.n ?? 0,
    monthlyCap: pro ? proMonthlyCap : null,
    shopName: pro ? license.shop_name : null,
    logo: pro && license.logo ? toBase64(license.logo instanceof ArrayBuffer ? license.logo : Uint8Array.from(license.logo)) : null,
  };
}
