import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import catalog from "../src/catalog.json";
import { call, license, NOW, publish, reportBytes, setNow } from "./helpers";

beforeEach(() => setNow(NOW));

async function published(options: Parameters<typeof reportBytes>[0] = {}) {
  const { key } = await license("single", 5);
  return (await publish(key, reportBytes(options))).json<Record<string, any>>();
}

const FORBIDDEN = ["certifi", "garanti", "authentifi", "infalsifiable", "100 % fonctionnel", "grade a", "testé et approuvé", "warrant", "certified", "authenticated"];

describe("Page publique (§7)", () => {
  it("état Valide : bandeau neutre (jamais vert), contenu dans l'ordre, sans note globale", async () => {
    const pub = await published({ serial: "Q2XD" });
    const res = await call(`/r/${pub.publicId}`, { headers: { "Accept-Language": "fr-FR,fr;q=0.9" } });
    expect(res.status).toBe(200);
    expect(res.headers.get("X-Robots-Tag")).toContain("noindex");
    expect(res.headers.get("Set-Cookie")).toBeNull();
    const html = await res.text();

    expect(html).toContain('<html lang="fr"');
    expect(html).toContain('<meta name="robots" content="noindex');
    expect(html).toContain("Rapport enregistré le 11 octobre 2026, contenu non modifié depuis.");
    expect(html).not.toMatch(/class="state[^"]*good/);
    expect(html).toContain("••••Q2XD");
    expect(html).toContain("Niveau 2 · Rapport enregistré en ligne");
    expect(html).toContain("Vérifiez que c'est bien ce Mac");
    expect(html).toContain("Constaté par l'utilisateur");
    expect(html).toContain("Ce que ce rapport prouve et ne prouve pas");
    expect(html).toContain(pub.sha256);

    // Ordre : état, identité, vérification, compteurs, verrouillages, batterie/SSD, tests, à vérifier, avancé, preuves, légal.
    const order = ["Rapport enregistré le", "Le Mac contrôlé", "class=\"locks\"", "Vérifiez que c'est bien ce Mac", "class=\"counters\"",
      "Batterie et SSD", "Tests guidés", "À vérifier avant l'achat", "Détails avancés", "Ce que ce rapport prouve", "Empreinte SHA-256",
      "Contrôlez votre Mac gratuitement"];
    const positions = order.map((needle) => html.indexOf(needle));
    expect(positions.every((p) => p >= 0)).toBe(true);
    expect([...positions].sort((a, b) => a - b)).toEqual(positions);

    expect(html.toLowerCase()).not.toMatch(/score|note globale|\/ ?10\b|\/ ?100\b/);
    for (const word of FORBIDDEN) expect(html.toLowerCase()).not.toContain(word);
  });

  it("aucun script, aucune ressource distante, poids < 150 Ko, thèmes clair et sombre", async () => {
    const pub = await published();
    const html = await (await call(`/r/${pub.publicId}`)).text();
    expect(html).not.toMatch(/<script/i);
    expect(html).not.toMatch(/<link[^>]+stylesheet/i);
    expect(html).not.toMatch(/src="https?:/i);
    expect(html).not.toMatch(/@import|@font-face|url\(/i);
    expect(new TextEncoder().encode(html).byteLength).toBeLessThan(150 * 1024);
    expect(html).toContain("prefers-color-scheme:dark");
  });

  it("chaque statut a une icône et un texte, jamais la couleur seule", async () => {
    const pub = await published();
    const html = await (await call(`/r/${pub.publicId}`)).text();
    const pills = html.match(/<span class="st st-[^"]+">[\s\S]*?<\/span><\/span>/g) ?? [];
    expect(pills.length).toBeGreaterThan(5);
    for (const pill of pills) {
      expect(pill).toContain("<svg");
      expect(pill.replace(/<[^>]+>/g, "").trim().length).toBeGreaterThan(0);
    }
  });

  it("anglais selon le navigateur, lien pour changer de langue, libellés du catalogue", async () => {
    const pub = await published();
    const en = await (await call(`/r/${pub.publicId}`, { headers: { "Accept-Language": "en-US,en;q=0.9" } })).text();
    expect(en).toContain('<html lang="en"');
    expect(en).toContain("Report registered on 11 October 2026, content unchanged since.");
    expect(en).toContain(catalog.languages.en.metrics["security.activation_lock"].label);
    expect(en).toContain(`/r/${pub.publicId}?lang=fr`);
    const forced = await (await call(`/r/${pub.publicId}?lang=fr`, { headers: { "Accept-Language": "en" } })).text();
    expect(forced).toContain(catalog.languages.fr.metrics["security.activation_lock"].label);
  });

  it("aperçu de lien sobre, sans verdict", async () => {
    const pub = await published();
    const html = await (await call(`/r/${pub.publicId}?lang=fr`)).text();
    const og = /<meta property="og:title" content="([^"]+)"/.exec(html)?.[1];
    expect(og).toBe("Rapport d'état · MacBook Pro (16 pouces, 2019) · contrôlé le 11 octobre 2026");
  });

  it("état Ancien : bandeau orange après 30 jours", async () => {
    const pub = await published();
    setNow(new Date("2026-11-20T12:00:00Z"));
    const html = await (await call(`/r/${pub.publicId}?lang=fr`)).text();
    expect(html).toContain('class="state warn"');
    expect(html).toContain("Ce rapport date de plus de 30 jours. Demandez un nouveau contrôle.");
  });

  it("état Introuvable : 404 et mise en garde contre un PDF qui mène ici", async () => {
    const res = await call("/r/ZZZZ-ZZZZ-ZZZZ?lang=fr");
    expect(res.status).toBe(404);
    expect(await res.text()).toContain("Aucun rapport ne correspond à ce lien. Méfiez-vous d'un PDF dont le QR code mène ici.");
    expect((await call("/r/pas-un-identifiant")).status).toBe(404);
  });

  it("iCloud et MDM en grand, avant les compteurs, teintés par leur verdict avec icône et texte", async () => {
    const pub = await published();
    const html = await (await call(`/r/${pub.publicId}?lang=fr`)).text();
    const tiles = html.match(/<div class="lock st-[^"]+">[\s\S]*?<\/div>\n?(?:<p>[\s\S]*?<\/p>)*<\/div>/g) ?? [];
    expect(tiles.length).toBe(2);
    expect(tiles[0]).toContain("Verrouillage d'activation iCloud");
    expect(tiles[1]).toContain("Gestion par une entreprise (MDM)");
    for (const tile of tiles) {
      expect(tile).toContain('class="lock st-good"');
      expect(tile).toContain("Aucun signal détecté");
      expect(tile).toContain("<svg");
    }
    expect(html.indexOf('class="locks"')).toBeLessThan(html.indexOf('class="counters"'));
  });

  it("bloqueur remonté en tête, en rouge, avant les compteurs", async () => {
    const pub = await published({
      mutate: (r) => {
        const lock = r.measurements.find((m: any) => m.id === "security.activation_lock");
        lock.status = "problem";
        lock.display = "Signal détecté";
        lock.value = { text: { _0: "activation_lock_enabled" } };
      },
    });
    const html = await (await call(`/r/${pub.publicId}?lang=fr`)).text();
    const blocker = html.indexOf('class="blocker"');
    expect(blocker).toBeGreaterThan(0);
    expect(blocker).toBeLessThan(html.indexOf('class="counters"'));
    expect(html).toContain("Signal détecté");
  });

  it("textes partagés avec l'app : aucun mot du lexique interdit dans le catalogue", () => {
    for (const lang of ["fr", "en"] as const) {
      const pack = catalog.languages[lang];
      const all = JSON.stringify({ text: { ...pack.text, disclaimerLevel1: "" }, lists: pack.lists }).toLowerCase();
      for (const word of FORBIDDEN) expect(all).not.toContain(word);
    }
  });

  it("page de confidentialité et clés publiques accessibles", async () => {
    const privacy = await (await call("/confidentialite?lang=fr")).text();
    expect(privacy).toContain("Numéro de série complet du Mac");
    expect(privacy).toContain("90 jours");
    const keys = await (await call("/.well-known/aman-check-keys.json")).json<Record<string, any>>();
    expect(keys.algorithm).toBe("Ed25519");
    expect(keys.keys[0].keyId).toBe("test1");
    expect(env.SIGNING_PUBLIC_KEYS).toContain(keys.keys[0].publicKey);
  });
});
