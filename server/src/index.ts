/**
 * Aman Check niveau 2 : API, page publique de vérification et webhook de paiement (cahier des charges §4, §6).
 * Seul composant à détenir la clé de signature. Aucune journalisation des requêtes.
 */
import { Hono } from "hono";
import { config, type Env } from "./env";
import { apiError } from "./errors";
import { bearer, findLicense, licenseSummary } from "./licenses";
import { handlePaymentWebhook } from "./payment/webhook";
import { pickLang } from "./page/i18n";
import { renderPrivacyPage, renderReportPage, renderSimplePage } from "./page/render";
import { allow, ipBucket, purgeRateLimits } from "./ratelimit";
import {
  blobBytes, bytesToBase64, eraseExpiredContent, findReport, latestVersion, publishReport, reportJson, reportState, withdrawReport,
} from "./reports";
import type { ConditionReport } from "./validate";

/** Horloge injectable pour les tests. */
export const clock = { now: () => new Date() };

const app = new Hono<{ Bindings: Env }>();

/** Sécurité et confidentialité : pas de cookie, pas d'indexation, pas de référent. */
const PAGE_HEADERS = {
  "Content-Type": "text/html; charset=utf-8",
  "X-Robots-Tag": "noindex, nofollow, noarchive",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
  "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
  "Cache-Control": "no-store",
};

function html(body: string, status = 200): Response {
  return new Response(body, { status, headers: PAGE_HEADERS });
}

// ── API de l'app ────────────────────────────────────────────────────────────

app.post("/v1/reports", (c) => publishReport(c.env, c.req.raw, clock.now()));

app.delete("/v1/reports/:publicId", (c) => withdrawReport(c.env, c.req.raw, c.req.param("publicId"), clock.now()));

app.get("/v1/licenses/me", async (c) => {
  const now = clock.now();
  const license = await findLicense(c.env.DB, bearer(c.req.raw));
  if (!license) return apiError("invalid_license");
  return Response.json(await licenseSummary(c.env.DB, license, now, config(c.env).proMonthlyCap), { headers: { "Cache-Control": "no-store" } });
});

// ── Vérification publique ───────────────────────────────────────────────────

app.get("/.well-known/aman-check-keys.json", (c) => {
  let keys: { keyId: string; publicKey: string }[] = [];
  try {
    keys = JSON.parse(c.env.SIGNING_PUBLIC_KEYS || "[]");
  } catch {
    keys = [];
  }
  return Response.json({
    algorithm: "Ed25519",
    message: "publicId|sha256|publishedAt",
    sha256: "SHA-256 of the exact report bytes (reportBase64 in /r/{publicId}.json)",
    keys: keys.map((k) => ({ keyId: k.keyId, algorithm: "Ed25519", publicKey: k.publicKey, encoding: "base64-raw" })),
  }, { headers: { "Cache-Control": "public, max-age=3600" } });
});

app.get("/r/:id", async (c) => {
  const now = clock.now();
  const cfg = config(c.env);
  if (!(await allow(c.env.DB, `read:${await ipBucket(c.env, c.req.raw)}`, cfg.readsPerMinute, 60_000, now))) {
    return new Response("429", { status: 429, headers: { "Retry-After": "60" } });
  }
  const raw = c.req.param("id");
  if (raw.endsWith(".json")) return reportJson(c.env, raw.slice(0, -5), now);

  const row = await findReport(c.env.DB, raw);
  const state = reportState(row, now);
  let report: ConditionReport | null = null;
  if (row?.body && state !== "withdrawn") {
    report = JSON.parse(new TextDecoder().decode(blobBytes(row.body)!)) as ConditionReport;
  }
  const latest = row && state === "replaced" ? await latestVersion(c.env.DB, row) : null;
  let shop: { name: string | null; logoBase64: string | null } | null = null;
  if (row) {
    // Offre Pro : logo du magasin sur la page.
    const lic = await c.env.DB.prepare("SELECT plan, shop_name, logo FROM licenses WHERE id = ?1").bind(row.license_id)
      .first<{ plan: string; shop_name: string | null; logo: ArrayBuffer | number[] | null }>();
    if (lic?.plan === "pro") shop = { name: lic.shop_name, logoBase64: lic.logo ? bytesToBase64(lic.logo) : null };
  }
  const page = renderReportPage({
    lang: pickLang(c.req.raw), state, row, report, now, shop,
    latestUrl: latest && latest.public_id !== row?.public_id ? `${cfg.baseUrl}/r/${latest.public_id}` : null,
    baseUrl: cfg.baseUrl, downloadUrl: c.env.DOWNLOAD_URL || cfg.baseUrl,
  });
  return html(page, state === "notFound" ? 404 : 200);
});

app.get("/confidentialite", (c) => {
  const cfg = config(c.env);
  return html(renderPrivacyPage(pickLang(c.req.raw), cfg.baseUrl, c.env.DOWNLOAD_URL || cfg.baseUrl, c.env.CONTACT_EMAIL, cfg.retentionDays));
});
app.get("/privacy", (c) => c.redirect("/confidentialite?lang=en", 301));

/** « Obtenir une clé » dans l'app : redirige vers la page d'achat du prestataire. */
app.get("/acheter", (c) => {
  if (c.env.PURCHASE_URL) return c.redirect(c.env.PURCHASE_URL, 302);
  const cfg = config(c.env);
  const fr = pickLang(c.req.raw) === "fr";
  return html(renderSimplePage(fr ? "fr" : "en", cfg.baseUrl, c.env.DOWNLOAD_URL || cfg.baseUrl,
    fr ? "Achat bientôt disponible" : "Purchase coming soon",
    fr ? `L'achat en ligne n'est pas encore ouvert. Pour obtenir une clé, écrivez à ${c.env.CONTACT_EMAIL}.`
      : `Online purchase is not open yet. To get a key, write to ${c.env.CONTACT_EMAIL}.`), 200);
});

app.get("/", (c) => {
  const cfg = config(c.env);
  const fr = pickLang(c.req.raw) === "fr";
  return html(renderSimplePage(fr ? "fr" : "en", cfg.baseUrl, c.env.DOWNLOAD_URL || cfg.baseUrl, "Aman Check",
    fr ? "Rapport d'état d'un Mac d'occasion. Ouvrez le lien ou scannez le QR code reçu du vendeur pour consulter son rapport."
      : "Condition report for a used Mac. Open the link or scan the QR code you received from the seller to view the report."));
});

// ── Paiement ────────────────────────────────────────────────────────────────

app.post("/webhooks/payment", (c) => handlePaymentWebhook(c.env, c.req.raw, clock.now()));

app.notFound(() => apiError("not_found"));
app.onError((error) => {
  console.error("erreur", error instanceof Error ? error.message : "inconnue");
  return Response.json({ error: "server" }, { status: 500 });
});

export default {
  fetch: app.fetch,
  /** Tâche horaire : effacement à 90 jours, purge des compteurs de débit (§10). */
  async scheduled(_event: ScheduledController, env: Env): Promise<void> {
    const now = clock.now();
    await eraseExpiredContent(env.DB, now, config(env).retentionDays);
    await purgeRateLimits(env.DB, now);
  },
} satisfies ExportedHandler<Env>;
