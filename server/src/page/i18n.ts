/**
 * Langue de la page : libellés des mesures, statuts, tests et textes du niveau 2 venus de `catalog.json`
 * (exporté depuis AmanCore). Ici, seulement l'habillage propre à la page web.
 * Arabe prévu ensuite : `dir` est déjà géré, la mise en page n'utilise que des propriétés logiques.
 */
import catalog from "../catalog.json";

export type Lang = "fr" | "en";
export const LANGS: Lang[] = ["fr", "en"];

export interface MetricLabel {
  label: string;
  help?: string | null;
  section: string;
  level: string;
  isJudged: boolean;
}

/** Une langue de `catalog.json` (voir Sources/AmanCatalogExport/main.swift). */
export interface CatalogPack {
  metrics: Record<string, MetricLabel>;
  sections: Record<string, string>;
  statuses: Record<string, { label: string }>;
  provenance: Record<string, { label: string; short?: string | null }>;
  tests: Record<string, { title: string; subtitle: string }>;
  outcomes: Record<string, string>;
  text: Record<string, string>;
  lists: Record<"proves" | "doesNotProve" | "buyerChecks" | "sent" | "neverSent", string[]>;
  errors: Record<string, string>;
}

interface Chrome {
  htmlLang: string;
  dir: "ltr" | "rtl";
  locale: string;
  colon: string;
  yes: string;
  no: string;
  switchTo: string;
  switchLang: Lang;
  identity: string;
  serial: string;
  modelYear: string;
  processor: string;
  memory: string;
  storage: string;
  macOS: string;
  checkedOn: string;
  blockers: string;
  counters: (s: { good: number; watch: number; problem: number; notTested: number; toCheck: number }) => [string, number, string][];
  testsDone: (done: number, planned: number) => string;
  locks: string;
  batteryAndSSD: string;
  guidedTests: string;
  toCheckTitle: string;
  nothingToCheck: string;
  advanced: string;
  method: string;
  publicId: string;
  reportId: string;
  fingerprint: string;
  appVersion: string;
  procedure: string;
  verifyIndependently: string;
  download: string;
  privacy: string;
  sellerBy: (name: string) => string;
  testNotDone: (name: string) => string;
  testsNotDone: (n: number, names: string) => string;
  testInPerson: string;
  ago: (days: number) => string;
  notFoundTitle: string;
  validUntil: (date: string) => string;
  levelBadge: string;
}

export type Pack = CatalogPack & { lang: Lang; chrome: Chrome };

const rtf = (locale: string) => new Intl.RelativeTimeFormat(locale, { numeric: "auto" });

const chrome: Record<Lang, Chrome> = {
  fr: {
    htmlLang: "fr", dir: "ltr", locale: "fr-FR", colon: " : ", yes: "Oui", no: "Non",
    switchTo: "English", switchLang: "en",
    identity: "Le Mac contrôlé", serial: "N° de série", modelYear: "Année de commercialisation du modèle",
    processor: "Processeur", memory: "Mémoire", storage: "Stockage", macOS: "macOS installé",
    checkedOn: "Contrôle du", blockers: "Points bloquants",
    counters: (s) => [
      ["good", s.good, s.good > 1 ? "bons" : "bon"],
      ["watch", s.watch, "à surveiller"],
      ["problem", s.problem, s.problem > 1 ? "problèmes" : "problème"],
      ["notTested", s.notTested, s.notTested > 1 ? "non testés" : "non testé"],
      ["manualRequired", s.toCheck, "à vérifier soi-même"],
    ],
    testsDone: (d, p) => `${d} test${d > 1 ? "s" : ""} réalisé${d > 1 ? "s" : ""} sur ${p}`,
    locks: "Verrouillages", batteryAndSSD: "Batterie et SSD", guidedTests: "Tests guidés",
    toCheckTitle: "À vérifier avant l'achat", nothingToCheck: "Rien d'autre à vérifier.",
    advanced: "Détails avancés", method: "Méthode", publicId: "Identifiant public", reportId: "Rapport",
    fingerprint: "Empreinte SHA-256", appVersion: "Version de l'app", procedure: "Procédure",
    verifyIndependently: "Données brutes et signature (vérification indépendante)",
    download: "Télécharger Aman Check", privacy: "Confidentialité",
    sellerBy: (n) => `Contrôle effectué par : ${n}`,
    testNotDone: (n) => `Test non réalisé : ${n}`,
    testsNotDone: (c, n) => `${c} tests non réalisés : ${n}`,
    testInPerson: "À tester sur place avant l'achat.",
    ago: (d) => rtf("fr-FR").format(-d, "day"),
    notFoundTitle: "Rapport introuvable",
    validUntil: (d) => `Enregistrement valable jusqu'au ${d}`,
    levelBadge: "",
  },
  en: {
    htmlLang: "en", dir: "ltr", locale: "en-GB", colon: ": ", yes: "Yes", no: "No",
    switchTo: "Français", switchLang: "fr",
    identity: "The Mac that was checked", serial: "Serial no.", modelYear: "Model release year",
    processor: "Processor", memory: "Memory", storage: "Storage", macOS: "Installed macOS",
    checkedOn: "Check of", blockers: "Blocking issues",
    counters: (s) => [
      ["good", s.good, "good"],
      ["watch", s.watch, "to watch"],
      ["problem", s.problem, s.problem > 1 ? "problems" : "problem"],
      ["notTested", s.notTested, "not tested"],
      ["manualRequired", s.toCheck, "to check manually"],
    ],
    testsDone: (d, p) => `${d} of ${p} tests done`,
    locks: "Locks", batteryAndSSD: "Battery and SSD", guidedTests: "Guided tests",
    toCheckTitle: "To check before buying", nothingToCheck: "Nothing else to check.",
    advanced: "Advanced details", method: "Method", publicId: "Public identifier", reportId: "Report",
    fingerprint: "SHA-256 fingerprint", appVersion: "App version", procedure: "Procedure",
    verifyIndependently: "Raw data and signature (independent verification)",
    download: "Download Aman Check", privacy: "Privacy",
    sellerBy: (n) => `Check carried out by: ${n}`,
    testNotDone: (n) => `Test not done: ${n}`,
    testsNotDone: (c, n) => `${c} tests not done: ${n}`,
    testInPerson: "Test them in person before buying.",
    ago: (d) => rtf("en-GB").format(-d, "day"),
    notFoundTitle: "Report not found",
    validUntil: (d) => `Registration valid until ${d}`,
    levelBadge: "",
  },
};

export function pack(lang: Lang): Pack {
  return { ...(catalog.languages[lang] as unknown as CatalogPack), lang, chrome: chrome[lang] };
}

/** `?lang=en` l'emporte, puis `Accept-Language`, sinon français. */
export function pickLang(request: Request): Lang {
  const url = new URL(request.url);
  const forced = url.searchParams.get("lang");
  if (forced === "fr" || forced === "en") return forced;
  const header = request.headers.get("Accept-Language") ?? "";
  const ranked = header
    .split(",")
    .map((part) => {
      const [tag, q] = part.trim().split(";q=");
      return { tag: tag.toLowerCase(), q: q ? Number.parseFloat(q) : 1 };
    })
    .sort((a, b) => b.q - a.q);
  for (const { tag } of ranked) {
    if (tag.startsWith("fr")) return "fr";
    if (tag.startsWith("en")) return "en";
  }
  return "fr";
}

export function formatDate(iso: string, p: Pack): string {
  return new Intl.DateTimeFormat(p.chrome.locale, { day: "numeric", month: "long", year: "numeric", timeZone: "Europe/Paris" })
    .format(new Date(iso));
}

export function daysSince(iso: string, now: Date): number {
  return Math.max(0, Math.floor((now.getTime() - Date.parse(iso)) / 86_400_000));
}

/** « MacBook Pro (16 pouces, 2019) » : même règle que `MacModel.displayName`. */
export function modelName(model: { family?: string; inches?: number | null; variant?: string | null; year?: number; alsoYear?: number | null } | null | undefined,
  fallback: string, p: Pack): string {
  if (!model?.family || !model.year) return fallback;
  const parts: string[] = [];
  if (model.inches) parts.push(p.lang === "fr" ? `${model.inches} pouces` : `${model.inches}-inch`);
  if (model.variant) parts.push(model.variant);
  parts.push(model.alsoYear ? `${model.year} ${p.lang === "fr" ? "ou" : "or"} ${model.alsoYear}` : String(model.year));
  return `${model.family} (${parts.join(", ")})`;
}

export function fill(template: string, values: Record<string, string>): string {
  return template.replace(/\{(\w+)\}/g, (_, key: string) => values[key] ?? `{${key}}`);
}
