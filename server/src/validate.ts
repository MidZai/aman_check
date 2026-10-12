/**
 * Contrôles du serveur avant d'accepter un rapport (cahier des charges §6).
 * Le schéma suit `ConditionReport` (Sources/AmanCore/Report.swift), encodé par l'app
 * avec des clés triées et des dates ISO 8601.
 */
import type { ApiErrorCode } from "./errors";
import { DAY_MS } from "./env";

export const MAX_REPORT_BYTES = 256 * 1024;
export const KNOWN_SCHEMA_VERSIONS = [1];

/** Valeur d'une mesure telle que Swift l'encode : `{"int":{"_0":83}}`, `{"text":{"_0":"…"}}`… */
export type EncodedValue = { int?: { _0: number }; double?: { _0: number }; text?: { _0: string }; bool?: { _0: boolean } };

export interface ReportMeasurement {
  id: string;
  value?: EncodedValue | null;
  unit?: string | null;
  status: string;
  provenance: string;
  method?: string | null;
  collectedAt: string;
  display?: string | null;
  detail?: string | null;
  note?: string | null;
}

export interface ReportTest {
  test: string;
  outcome: string;
  status: string;
  provenance: string;
  summary: string;
  details: string[];
  completedAt: string;
}

export interface ReportModel {
  displayName?: string;
  year?: number;
  [key: string]: unknown;
}

export interface ConditionReport {
  schemaVersion: number;
  procedureVersion: string;
  reportID: string;
  generatedAt: string;
  appVersion: string;
  trustLevel: number;
  profile: { modelIdentifier: string; model?: ReportModel | null; isSimulated?: boolean; kind?: string; [key: string]: unknown };
  measurements: ReportMeasurement[];
  tests: ReportTest[];
  plannedTests: string[];
  sellerName?: string | null;
  simulated?: boolean;
}

/** Clés de premier niveau autorisées : tout le reste (journal, sorties brutes…) est refusé. */
const TOP_LEVEL_KEYS = new Set([
  "schemaVersion", "procedureVersion", "reportID", "generatedAt", "appVersion", "trustLevel",
  "profile", "measurements", "tests", "plannedTests", "sellerName", "simulated",
]);

/** Clés qui trahiraient une sortie brute ou un identifiant matériel (§10, colonne « Jamais envoyé »). */
const FORBIDDEN_KEY = /serial|uuid|udid|hostname|host_name|computer_?name|user_?name|apple_?id|ssid|bssid|raw|events|stdout|stderr/i;

const JUDGED = new Set(["good", "watch", "problem", "info"]);
export const SERIAL_ID = "identity.serial";
const REPORT_ID = /^AC-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/;

export type ValidationResult =
  | { ok: true; report: ConditionReport; modelIdentifier: string; serialLast4: string }
  | { ok: false; error: ApiErrorCode; detail: string };

function fail(error: ApiErrorCode, detail: string): ValidationResult {
  return { ok: false, error, detail };
}

/** « 1.2.10 » ≥ « 1.2.9 » ; segments non numériques ignorés. */
export function compareVersions(a: string, b: string): number {
  const pa = a.split(/[.\s-]/).map((s) => Number.parseInt(s, 10) || 0);
  const pb = b.split(/[.\s-]/).map((s) => Number.parseInt(s, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (d !== 0) return d;
  }
  return 0;
}

export function measurementText(value: EncodedValue | null | undefined): string | null {
  if (!value) return null;
  if (value.text) return value.text._0;
  if (value.int) return String(value.int._0);
  if (value.double) return String(value.double._0);
  if (value.bool) return String(value.bool._0);
  return null;
}

function findForbiddenKey(node: unknown, path: string): string | null {
  if (Array.isArray(node)) {
    for (let i = 0; i < node.length; i++) {
      const hit = findForbiddenKey(node[i], `${path}[${i}]`);
      if (hit) return hit;
    }
  } else if (node && typeof node === "object") {
    for (const [key, value] of Object.entries(node)) {
      if (FORBIDDEN_KEY.test(key)) return `${path}.${key}`;
      const hit = findForbiddenKey(value, `${path}.${key}`);
      if (hit) return hit;
    }
  }
  return null;
}

export interface ValidationContext {
  now: Date;
  minAppVersion: string;
  /** En-tête `X-App-Version`. */
  appVersionHeader: string | null;
}

export function validateReport(bytes: Uint8Array, ctx: ValidationContext): ValidationResult {
  if (bytes.byteLength > MAX_REPORT_BYTES) return fail("too_large", `${bytes.byteLength} octets`);

  let parsed: unknown;
  try {
    parsed = JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes));
  } catch {
    return fail("invalid_report", "JSON illisible");
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return fail("invalid_report", "objet attendu");
  const r = parsed as ConditionReport;

  if (!KNOWN_SCHEMA_VERSIONS.includes(r.schemaVersion)) return fail("invalid_report", `schemaVersion ${r.schemaVersion}`);

  const appVersion = ctx.appVersionHeader?.trim() || (typeof r.appVersion === "string" ? r.appVersion : "");
  if (!appVersion || compareVersions(appVersion, ctx.minAppVersion) < 0) return fail("app_too_old", `version ${appVersion || "absente"}`);

  if (r.simulated === true || r.profile?.isSimulated === true) return fail("simulated_profile", "profil simulé");

  for (const key of Object.keys(r)) {
    if (!TOP_LEVEL_KEYS.has(key)) return fail("invalid_report", `champ non autorisé : ${key}`);
  }
  if (typeof r.reportID !== "string" || !REPORT_ID.test(r.reportID)) return fail("invalid_report", "reportID");
  if (typeof r.generatedAt !== "string" || Number.isNaN(Date.parse(r.generatedAt))) return fail("invalid_report", "generatedAt");
  if (!r.profile || typeof r.profile.modelIdentifier !== "string" || !r.profile.modelIdentifier || r.profile.modelIdentifier.length > 64) {
    return fail("invalid_report", "profile.modelIdentifier");
  }
  if (!Array.isArray(r.measurements) || !Array.isArray(r.tests) || !Array.isArray(r.plannedTests)) return fail("invalid_report", "listes");
  if (r.sellerName != null && (typeof r.sellerName !== "string" || r.sellerName.length > 120)) return fail("invalid_report", "sellerName");

  const forbidden = findForbiddenKey(r, "$");
  if (forbidden) return fail("invalid_report", `champ interdit : ${forbidden}`);

  let serialLast4 = "";
  for (const m of r.measurements) {
    if (!m || typeof m.id !== "string" || typeof m.status !== "string") return fail("invalid_report", "mesure mal formée");
    // Même garde-fou que `Measurement` : une donnée absente n'est jamais jugée.
    if (JUDGED.has(m.status) && (m.value === null || m.value === undefined)) {
      return fail("invalid_report", `mesure jugée sans valeur : ${m.id}`);
    }
    if (m.id === SERIAL_ID) {
      const text = measurementText(m.value);
      if (text !== null && (text.length > 4 || (m.display ?? "").replace(/•/g, "").length > 4)) {
        return fail("invalid_report", "numéro de série de plus de 4 caractères");
      }
      serialLast4 = text ?? "";
    }
  }

  const generated = Date.parse(r.generatedAt);
  const now = ctx.now.getTime();
  if (generated < now - DAY_MS) return fail("report_too_old", "contrôle de plus de 24 heures");
  if (generated > now + 10 * 60 * 1000) return fail("report_too_old", "date du contrôle dans le futur");

  return { ok: true, report: r, modelIdentifier: r.profile.modelIdentifier, serialLast4 };
}
