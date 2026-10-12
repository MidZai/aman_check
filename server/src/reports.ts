/** Publication, retrait et lecture des rapports (cahier des charges §5, §6, §9). */
import { config, DAY_MS, type Env } from "./env";
import {
  formatPublicId, newManageToken, newPublicId, normalizePublicId, sha256Hex, signEd25519, signedMessage,
} from "./crypto";
import { apiError } from "./errors";
import { bearer, findLicense, isProActive, type LicenseRow } from "./licenses";
import { allow, HOUR_MS } from "./ratelimit";
import { MAX_REPORT_BYTES, validateReport } from "./validate";

export interface ReportRow {
  public_id: string;
  report_id: string;
  license_id: string;
  model_identifier: string;
  serial_last4: string;
  /** D1 renvoie les BLOB sous forme de tableau d'octets. */
  body: ArrayBuffer | number[] | null;
  sha256: string;
  signature: string;
  key_id: string;
  app_version: string;
  generated_at: string;
  published_at: string;
  valid_until: string;
  status: "published" | "replaced" | "withdrawn";
  replaced_by: string | null;
  manage_token_hash: string;
  consumed_credit: number;
  credit_anchor_at: string;
  content_erased_at: string | null;
}

/** Dates sans millisecondes, comme celles de l'app. */
export function isoSeconds(date: Date): string {
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

export function publicationBlock(env: Env, row: ReportRow) {
  return {
    publicId: row.public_id,
    url: `${config(env).baseUrl}/r/${row.public_id}`,
    sha256: row.sha256,
    publishedAt: row.published_at,
    signature: row.signature,
    keyId: row.key_id,
    validUntil: row.valid_until,
  };
}

async function remainingCredits(db: D1Database, licenseId: string): Promise<number | null> {
  const row = await db.prepare("SELECT plan, credits FROM licenses WHERE id = ?1").bind(licenseId).first<{ plan: string; credits: number }>();
  return row && row.plan === "single" ? row.credits : null;
}

/** Le jeton de gestion n'est connu que de l'app : le serveur n'en garde que le hachage. */
async function issueManageToken(db: D1Database, publicId: string): Promise<string> {
  const token = newManageToken();
  await db.prepare("UPDATE reports SET manage_token_hash = ?1 WHERE public_id = ?2").bind(await sha256Hex(token), publicId).run();
  return token;
}

export async function readBody(request: Request): Promise<Uint8Array | null> {
  const declared = Number.parseInt(request.headers.get("Content-Length") ?? "", 10);
  if (Number.isFinite(declared) && declared > MAX_REPORT_BYTES) return null;
  const bytes = new Uint8Array(await request.arrayBuffer());
  return bytes.byteLength > MAX_REPORT_BYTES ? null : bytes;
}

/** `POST /v1/reports` */
export async function publishReport(env: Env, request: Request, now: Date): Promise<Response> {
  const cfg = config(env);
  const license = await findLicense(env.DB, bearer(request));
  if (!license) return apiError("invalid_license");

  if (!(await allow(env.DB, `publish:${license.id}`, cfg.publishPerHour, HOUR_MS, now))) return apiError("rate_limited");

  const bytes = await readBody(request);
  if (!bytes) return apiError("too_large");

  const validation = validateReport(bytes, { now, minAppVersion: cfg.minAppVersion, appVersionHeader: request.headers.get("X-App-Version") });
  if (!validation.ok) return apiError(validation.error, validation.detail);
  const { report, modelIdentifier, serialLast4 } = validation;
  const sha256 = await sha256Hex(bytes);

  // Nouvelle tentative après une coupure : même clé, même empreinte → même publication, sans crédit.
  const existing = await env.DB
    .prepare("SELECT * FROM reports WHERE license_id = ?1 AND sha256 = ?2 AND status != 'withdrawn' ORDER BY published_at DESC LIMIT 1")
    .bind(license.id, sha256)
    .first<ReportRow>();
  if (existing) {
    // L'app n'a peut-être jamais reçu le premier jeton : on en émet un nouveau, l'ancien cesse de valoir.
    const manageToken = await issueManageToken(env.DB, existing.public_id);
    return Response.json(
      { ...publicationBlock(env, existing), creditsRemaining: await remainingCredits(env.DB, license.id), manageToken, replayed: true },
      { status: 200, headers: { "Cache-Control": "no-store" } },
    );
  }

  // Règle de consommation (§9) : gratuit si ce Mac a déjà consommé un crédit sur cette clé depuis moins de 30 jours.
  const sameMac = serialLast4.length > 0;
  const previous = sameMac
    ? await env.DB
        .prepare(
          `SELECT credit_anchor_at FROM reports WHERE license_id = ?1 AND model_identifier = ?2 AND serial_last4 = ?3
           ORDER BY published_at DESC LIMIT 1`,
        )
        .bind(license.id, modelIdentifier, serialLast4)
        .first<{ credit_anchor_at: string }>()
    : null;
  const withinWindow = !!previous && Date.parse(previous.credit_anchor_at) + cfg.validityDays * DAY_MS > now.getTime();

  let consumedCredit = 0;
  let creditAnchor = isoSeconds(now);
  if (withinWindow) {
    creditAnchor = previous!.credit_anchor_at;
  } else {
    const refusal = await consumeCredit(env.DB, license, now, cfg.proMonthlyCap);
    if (refusal) return refusal;
    consumedCredit = license.plan === "single" ? 1 : 0;
  }

  const publicId = formatPublicId(newPublicId());
  const publishedAt = isoSeconds(now);
  const validUntil = isoSeconds(new Date(now.getTime() + cfg.validityDays * DAY_MS));
  const keyId = env.SIGNING_KEY_ID || "k1";
  const signature = await signEd25519(env.SIGNING_PRIVATE_KEY, signedMessage(publicId, sha256, publishedAt));
  const manageToken = newManageToken();

  const statements = [
    env.DB
      .prepare(
        `INSERT INTO reports (public_id, report_id, license_id, model_identifier, serial_last4, body, sha256, signature, key_id,
           app_version, generated_at, published_at, valid_until, status, manage_token_hash, consumed_credit, credit_anchor_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, 'published', ?14, ?15, ?16)`,
      )
      .bind(publicId, report.reportID, license.id, modelIdentifier, serialLast4, bytes, sha256, signature, keyId,
        request.headers.get("X-App-Version") ?? report.appVersion, report.generatedAt, publishedAt, validUntil,
        await sha256Hex(manageToken), consumedCredit, creditAnchor),
  ];
  if (sameMac) {
    // L'ancienne page reste en ligne, à l'état « Remplacé », avec un lien vers la nouvelle.
    statements.push(
      env.DB
        .prepare(
          `UPDATE reports SET status = 'replaced', replaced_by = ?1
           WHERE license_id = ?2 AND model_identifier = ?3 AND serial_last4 = ?4 AND status = 'published' AND public_id != ?1`,
        )
        .bind(publicId, license.id, modelIdentifier, serialLast4),
    );
  }
  try {
    await env.DB.batch(statements);
  } catch (error) {
    if (consumedCredit) await env.DB.prepare("UPDATE licenses SET credits = credits + 1 WHERE id = ?1").bind(license.id).run();
    throw error;
  }

  return Response.json(
    {
      publicId, url: `${cfg.baseUrl}/r/${publicId}`, sha256, publishedAt, signature, keyId, validUntil,
      creditsRemaining: await remainingCredits(env.DB, license.id), manageToken,
    },
    { status: 201, headers: { "Cache-Control": "no-store" } },
  );
}

/** Décompte d'un crédit, ou réponse 402. Pro : rien n'est décompté, plafond technique mensuel. */
async function consumeCredit(db: D1Database, license: LicenseRow, now: Date, proMonthlyCap: number): Promise<Response | null> {
  if (license.plan === "pro") {
    if (!isProActive(license, now)) return apiError("no_credit", "abonnement terminé");
    const monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)).toISOString();
    const used = await db
      .prepare("SELECT COUNT(*) AS n FROM reports WHERE license_id = ?1 AND published_at >= ?2")
      .bind(license.id, monthStart)
      .first<{ n: number }>();
    return (used?.n ?? 0) >= proMonthlyCap ? apiError("no_credit", "plafond mensuel atteint") : null;
  }
  const result = await db.prepare("UPDATE licenses SET credits = credits - 1 WHERE id = ?1 AND credits > 0").bind(license.id).run();
  return result.meta.changes === 1 ? null : apiError("no_credit");
}

/** `DELETE /v1/reports/{publicId}` : retrait par l'auteur, contenu effacé immédiatement (§10). */
export async function withdrawReport(env: Env, request: Request, rawId: string, now: Date): Promise<Response> {
  const id = normalizePublicId(rawId);
  if (!id) return apiError("not_found");
  const publicId = formatPublicId(id);
  const row = await env.DB.prepare("SELECT manage_token_hash, status FROM reports WHERE public_id = ?1").bind(publicId).first<ReportRow>();
  if (!row) return apiError("not_found");
  const token = bearer(request);
  if (!token || (await sha256Hex(token)) !== row.manage_token_hash) return apiError("invalid_token");
  await env.DB
    .prepare("UPDATE reports SET status = 'withdrawn', body = NULL, content_erased_at = ?1 WHERE public_id = ?2")
    .bind(isoSeconds(now), publicId)
    .run();
  return Response.json({ publicId, status: "withdrawn" }, { headers: { "Cache-Control": "no-store" } });
}

export async function findReport(db: D1Database, rawId: string): Promise<ReportRow | null> {
  const id = normalizePublicId(rawId);
  if (!id) return null;
  return db.prepare("SELECT * FROM reports WHERE public_id = ?1").bind(formatPublicId(id)).first<ReportRow>();
}

export type ReportState = "valid" | "old" | "replaced" | "withdrawn" | "notFound";

export function reportState(row: ReportRow | null, now: Date): ReportState {
  if (!row) return "notFound";
  if (row.status === "withdrawn") return "withdrawn";
  if (row.status === "replaced") return "replaced";
  return Date.parse(row.valid_until) < now.getTime() ? "old" : "valid";
}

/** Version la plus récente d'une chaîne de remplacements. */
export async function latestVersion(db: D1Database, row: ReportRow): Promise<ReportRow> {
  let current = row;
  for (let hops = 0; hops < 20 && current.replaced_by; hops++) {
    const next = await db.prepare("SELECT * FROM reports WHERE public_id = ?1").bind(current.replaced_by).first<ReportRow>();
    if (!next) break;
    current = next;
  }
  return current;
}

/** `GET /r/{publicId}.json` : octets exacts (base64) et bloc de publication, pour vérification indépendante. */
export async function reportJson(env: Env, rawId: string, now: Date): Promise<Response> {
  const row = await findReport(env.DB, rawId);
  if (!row) return apiError("not_found");
  const state = reportState(row, now);
  const latest = state === "replaced" ? await latestVersion(env.DB, row) : null;
  return Response.json(
    {
      state,
      publication: publicationBlock(env, row),
      signedMessage: signedMessage(row.public_id, row.sha256, row.published_at),
      reportBase64: row.body ? bytesToBase64(row.body) : null,
      replacedBy: latest && latest.public_id !== row.public_id ? `${config(env).baseUrl}/r/${latest.public_id}` : null,
      keys: `${config(env).baseUrl}/.well-known/aman-check-keys.json`,
    },
    { headers: { "Cache-Control": "no-store", "X-Robots-Tag": "noindex, nofollow" } },
  );
}

/** Octets d'une colonne BLOB, quelle que soit la forme renvoyée par D1. */
export function blobBytes(blob: ArrayBuffer | ArrayLike<number> | null | undefined): Uint8Array | null {
  if (blob == null) return null;
  return blob instanceof ArrayBuffer ? new Uint8Array(blob) : Uint8Array.from(blob as ArrayLike<number>);
}

export function bytesToBase64(body: ArrayBuffer | ArrayLike<number>): string {
  let binary = "";
  for (const b of blobBytes(body)!) binary += String.fromCharCode(b);
  return btoa(binary);
}

/** Tâche planifiée : contenu effacé 90 jours après publication (§10). */
export async function eraseExpiredContent(db: D1Database, now: Date, retentionDays: number): Promise<void> {
  const limit = isoSeconds(new Date(now.getTime() - retentionDays * DAY_MS));
  await db
    .prepare("UPDATE reports SET body = NULL, content_erased_at = ?1 WHERE body IS NOT NULL AND published_at < ?2")
    .bind(isoSeconds(now), limit)
    .run();
}

