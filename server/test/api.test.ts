import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { hmacHex, sha256Hex, verifyEd25519 } from "../src/crypto";
import { call, license, NOW, publish, reportBytes, setNow } from "./helpers";

beforeEach(() => setNow(NOW));

describe("POST /v1/reports : publication valide", () => {
  it("201, empreinte = SHA-256 des octets envoyés, signature vérifiable avec la clé publique", async () => {
    const { key } = await license("single", 1);
    const bytes = reportBytes();
    const res = await publish(key, bytes);
    expect(res.status).toBe(201);
    const body = await res.json<Record<string, any>>();

    expect(body.sha256).toBe(await sha256Hex(bytes));
    expect(body.publicId).toMatch(/^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/);
    expect(body.url).toBe(`https://verif.test/r/${body.publicId}`);
    expect(body.publishedAt).toBe("2026-10-11T12:00:00Z");
    expect(body.validUntil).toBe("2026-11-10T12:00:00Z");
    expect(body.creditsRemaining).toBe(0);
    expect(body.manageToken).toMatch(/^[0-9a-f]{64}$/);

    const keys = await (await call("/.well-known/aman-check-keys.json")).json<Record<string, any>>();
    const publicKey = keys.keys.find((k: { keyId: string }) => k.keyId === body.keyId);
    expect(publicKey).toBeTruthy();
    expect(await verifyEd25519(publicKey.publicKey, `${body.publicId}|${body.sha256}|${body.publishedAt}`, body.signature)).toBe(true);
    expect(await verifyEd25519(publicKey.publicKey, `${body.publicId}|${body.sha256}|2026-10-12T00:00:00Z`, body.signature)).toBe(false);

    // Le serveur ne garde que le hachage du jeton de gestion.
    const row = await env.DB.prepare("SELECT manage_token_hash FROM reports WHERE public_id = ?1").bind(body.publicId).first<{ manage_token_hash: string }>();
    expect(row?.manage_token_hash).toBe(await sha256Hex(body.manageToken));
  });

  it("GET /r/{id}.json renvoie les octets exacts, vérifiables indépendamment", async () => {
    const { key } = await license("single", 1);
    const bytes = reportBytes();
    const pub = await (await publish(key, bytes)).json<Record<string, any>>();
    const json = await (await call(`/r/${pub.publicId}.json`)).json<Record<string, any>>();
    const back = Uint8Array.from(atob(json.reportBase64), (c) => c.charCodeAt(0));
    expect(await sha256Hex(back)).toBe(pub.sha256);
    expect(json.signedMessage).toBe(`${pub.publicId}|${pub.sha256}|${pub.publishedAt}`);
    expect(json.state).toBe("valid");
  });
});

describe("Contrôles du serveur (§6) : chaque contrôle produit son code d'erreur", () => {
  const cases: [string, number, string, (key: string) => Promise<Response>][] = [
    ["clé inconnue", 401, "invalid_license", () => publish("ACK-NOPE-NOPE-NOPE-NOPE", reportBytes())],
    ["sans clé", 401, "invalid_license", () => call("/v1/reports", { method: "POST", body: reportBytes() })],
    ["trop volumineux", 413, "too_large", (k) => publish(k, new Uint8Array(256 * 1024 + 1).fill(32))],
    ["JSON illisible", 400, "invalid_report", (k) => publish(k, "{pas du json")],
    ["schemaVersion inconnue", 400, "invalid_report", (k) => publish(k, reportBytes({ mutate: (r) => { r.schemaVersion = 99; } }))],
    ["version d'app trop ancienne", 426, "app_too_old", (k) => publish(k, reportBytes(), { "X-App-Version": "0.9.0" })],
    ["profil simulé", 422, "simulated_profile", (k) => publish(k, reportBytes({ mutate: (r) => { r.simulated = true; r.profile.isSimulated = true; } }))],
    ["numéro de série complet", 400, "invalid_report", (k) => publish(k, reportBytes({
      mutate: (r) => { r.measurements.find((m: any) => m.id === "identity.serial").value = { text: { _0: "C02ZK1ABQ2XD" } }; },
    }))],
    ["sortie brute de diagnostic", 400, "invalid_report", (k) => publish(k, reportBytes({ mutate: (r) => { r.raw = { SPPowerDataType: "…" }; } }))],
    ["clé d'identifiant matériel imbriquée", 400, "invalid_report", (k) => publish(k, reportBytes({
      mutate: (r) => { r.profile.sppower_battery_serial_number = "X"; },
    }))],
    ["mesure jugée sans valeur", 400, "invalid_report", (k) => publish(k, reportBytes({
      mutate: (r) => { const m = r.measurements.find((x: any) => x.id === "battery.health_percent"); delete m.value; m.status = "good"; },
    }))],
    ["contrôle de plus de 24 heures", 422, "report_too_old", (k) => publish(k, reportBytes({ generatedAt: "2026-10-10T11:59:00Z" }))],
    ["contrôle daté du futur", 422, "report_too_old", (k) => publish(k, reportBytes({ generatedAt: "2026-10-11T12:11:00Z" }))],
  ];

  for (const [name, status, code, run] of cases) {
    it(`${name} → ${status} ${code}`, async () => {
      const { key } = await license("single", 5);
      const res = await run(key);
      expect(res.status).toBe(status);
      expect((await res.json<{ error: string }>()).error).toBe(code);
    });
  }

  it("sans crédit → 402 no_credit", async () => {
    const { key } = await license("single", 0);
    const res = await publish(key, reportBytes());
    expect(res.status).toBe(402);
    expect((await res.json<{ error: string }>()).error).toBe("no_credit");
  });

  it("Pro expiré → 402 ; Pro actif : aucun décompte, plafond mensuel", async () => {
    const expired = await license("pro", 0, "2026-10-01T00:00:00Z");
    expect((await publish(expired.key, reportBytes())).status).toBe(402);
    const pro = await license("pro", 0, "2027-01-01T00:00:00Z");
    expect((await publish(pro.key, reportBytes())).status).toBe(201);
    expect((await publish(pro.key, reportBytes())).status).toBe(201);
  });

  it("plus de 10 publications par heure et par clé → 429 rate_limited", async () => {
    const { key } = await license("single", 50);
    const statuses: number[] = [];
    for (let i = 0; i < 11; i++) statuses.push((await publish(key, reportBytes())).status);
    expect(statuses.slice(0, 10).every((s) => s === 201)).toBe(true);
    expect(statuses[10]).toBe(429);
  });
});

describe("Crédits (§9)", () => {
  it("même clé et même empreinte envoyées deux fois : une seule publication, un seul crédit", async () => {
    const { id, key } = await license("single", 2);
    const bytes = reportBytes();
    const first = await (await publish(key, bytes)).json<Record<string, any>>();
    const again = await publish(key, bytes);
    expect(again.status).toBe(200);
    const second = await again.json<Record<string, any>>();
    expect(second.publicId).toBe(first.publicId);
    expect(second.creditsRemaining).toBe(1);
    // Nouveau jeton : l'app n'avait peut-être jamais reçu le premier.
    expect(second.manageToken).not.toBe(first.manageToken);
    const count = await env.DB.prepare("SELECT COUNT(*) AS n FROM reports WHERE license_id = ?1").bind(id).first<{ n: number }>();
    expect(count?.n).toBe(1);
  });

  it("republication pour le même Mac : pas de crédit consommé, ancienne page à l'état « Remplacé »", async () => {
    const { key } = await license("single", 1);
    const first = await (await publish(key, reportBytes({ serial: "M4RT" }))).json<Record<string, any>>();
    setNow(new Date("2026-10-12T09:00:00Z"));
    const res = await publish(key, reportBytes({ serial: "M4RT", generatedAt: "2026-10-12T08:30:00Z" }));
    expect(res.status).toBe(201);
    const second = await res.json<Record<string, any>>();
    expect(second.creditsRemaining).toBe(0);

    const old = await (await call(`/r/${first.publicId}.json`)).json<Record<string, any>>();
    expect(old.state).toBe("replaced");
    expect(old.replacedBy).toBe(second.url);
    const page = await (await call(`/r/${first.publicId}?lang=fr`)).text();
    expect(page).toContain("Un rapport plus récent existe pour ce Mac.");
    expect(page).toContain(`/r/${second.publicId}`);
  });

  it("un autre Mac sur la même clé consomme un nouveau crédit", async () => {
    const { key } = await license("single", 1);
    expect((await publish(key, reportBytes({ serial: "AAAA" }))).status).toBe(201);
    expect((await publish(key, reportBytes({ serial: "BBBB" }))).status).toBe(402);
  });
});

describe("Retrait (DELETE /v1/reports/{publicId})", () => {
  it("mauvais jeton refusé ; bon jeton : contenu effacé", async () => {
    const { key } = await license("single", 1);
    const pub = await (await publish(key, reportBytes())).json<Record<string, any>>();

    const wrong = await call(`/v1/reports/${pub.publicId}`, { method: "DELETE", headers: { Authorization: `Bearer ${"0".repeat(64)}` } });
    expect(wrong.status).toBe(403);
    expect((await wrong.json<{ error: string }>()).error).toBe("invalid_token");
    expect((await call(`/v1/reports/${pub.publicId}`, { method: "DELETE" })).status).toBe(403);

    const ok = await call(`/v1/reports/${pub.publicId}`, { method: "DELETE", headers: { Authorization: `Bearer ${pub.manageToken}` } });
    expect(ok.status).toBe(200);
    const row = await env.DB.prepare("SELECT body, status FROM reports WHERE public_id = ?1").bind(pub.publicId).first<{ body: unknown; status: string }>();
    expect(row?.body).toBeNull();
    expect(row?.status).toBe("withdrawn");
    const json = await (await call(`/r/${pub.publicId}.json`)).json<Record<string, any>>();
    expect(json.reportBase64).toBeNull();
    const page = await (await call(`/r/${pub.publicId}?lang=fr`)).text();
    expect(page).toContain("Ce rapport a été retiré par son auteur.");
    expect(page).not.toContain("Boutique Exemple");
  });
});

describe("Paiement (POST /webhooks/payment)", () => {
  const licenseKeyEvent = (key: string, productId: number, orderId: number) => JSON.stringify({
    meta: { event_name: "license_key_created" },
    data: { type: "license-keys", id: "1", attributes: { key, order_id: orderId, product_id: productId, variant_id: 0, status: "inactive", expires_at: null } },
  });

  async function send(body: string, secret = "whsec_test") {
    return call("/webhooks/payment", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Signature": await hmacHex(secret, body) },
      body,
    });
  }

  it("signature invalide rejetée, aucune licence créée", async () => {
    const body = licenseKeyEvent("FORGED-KEY-0001", 111, 9001);
    const res = await send(body, "mauvais-secret");
    expect(res.status).toBe(401);
    const me = await call("/v1/licenses/me", { headers: { Authorization: "Bearer FORGED-KEY-0001" } });
    expect(me.status).toBe(401);
  });

  it("webhook valide : crée la licence de la bonne offre, une seule fois ; remboursement : crédits annulés", async () => {
    const body = licenseKeyEvent("LS-SINGLE-KEY-42", 111, 9002);
    expect((await send(body)).status).toBe(200);
    expect((await (await send(body)).json<Record<string, any>>()).duplicate).toBe(true);

    const me = await (await call("/v1/licenses/me", { headers: { Authorization: "Bearer ls-single-key-42" } })).json<Record<string, any>>();
    expect(me.plan).toBe("single");
    expect(me.creditsRemaining).toBe(1);

    const refund = JSON.stringify({ meta: { event_name: "order_refunded" }, data: { type: "orders", id: "9002", attributes: { status: "refunded" } } });
    expect((await send(refund)).status).toBe(200);
    const after = await (await call("/v1/licenses/me", { headers: { Authorization: "Bearer LS-SINGLE-KEY-42" } })).json<Record<string, any>>();
    expect(after.creditsRemaining).toBe(0);
  });

  it("offre Pro : date de fin reprise de l'abonnement, même reçu avant la clé", async () => {
    const sub = JSON.stringify({
      meta: { event_name: "subscription_created" },
      data: { type: "subscriptions", id: "5", attributes: { order_id: 9003, product_id: 222, variant_id: 0, status: "active", renews_at: "2026-11-11T12:00:00.000000Z", ends_at: null } },
    });
    expect((await send(sub)).status).toBe(200);
    expect((await send(licenseKeyEvent("LS-PRO-KEY-7", 222, 9003))).status).toBe(200);
    const me = await (await call("/v1/licenses/me", { headers: { Authorization: "Bearer LS-PRO-KEY-7" } })).json<Record<string, any>>();
    expect(me.plan).toBe("pro");
    expect(me.active).toBe(true);
    expect(me.validUntil).toBe("2026-11-11T12:00:00.000Z");
    expect(me.monthlyCap).toBe(300);
  });
});

describe("Données conservées (§10)", () => {
  it("contenu effacé 90 jours après publication, compteurs IP purgés après une heure", async () => {
    const worker = (await import("../src/index")).default;
    const { key } = await license("single", 1);
    const pub = await (await publish(key, reportBytes())).json<Record<string, any>>();
    await call(`/r/${pub.publicId}`);

    setNow(new Date("2027-01-10T13:00:00Z"));
    await worker.scheduled({} as ScheduledController, env);
    const row = await env.DB.prepare("SELECT body, sha256 FROM reports WHERE public_id = ?1").bind(pub.publicId).first<{ body: unknown; sha256: string }>();
    expect(row?.body).toBeNull();
    expect(row?.sha256).toBe(pub.sha256);
    const ips = await env.DB.prepare("SELECT COUNT(*) AS n FROM rate_limits WHERE bucket LIKE 'read:%'").first<{ n: number }>();
    expect(ips?.n).toBe(0);
    const page = await (await call(`/r/${pub.publicId}?lang=fr`)).text();
    expect(page).toContain("effacé 90 jours après sa publication");
  });
});
