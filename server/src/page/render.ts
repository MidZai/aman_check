/**
 * Page publique de vérification (cahier des charges §7) : HTML rendu côté serveur, sans JavaScript,
 * sans police distante ni traceur, CSS embarqué, lisible sur un téléphone tenu d'une main.
 * Chaque statut a une icône ET un texte. Le bandeau « Valide » n'est jamais vert.
 */
import catalog from "../catalog.json";
import type { ReportRow, ReportState } from "../reports";
import type { ConditionReport, ReportMeasurement } from "../validate";
import { daysSince, fill, formatDate, modelName, pack, type Lang, type Pack } from "./i18n";
import { displayText, isJudgement, resultFor, severity, summarize, toCheck } from "./summary";

export function esc(value: unknown): string {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;"); // attributs toujours entre guillemets doubles : l'apostrophe reste lisible
}

// Icônes (traits SVG en ligne, couleur héritée) : mêmes formes que les SF Symbols de l'app.
const ICONS: Record<string, string> = {
  good: '<circle cx="12" cy="12" r="9"/><path d="m8 12.5 2.6 2.6L16 9.6"/>',
  watch: '<path d="M12 3.5 2.8 19.5h18.4z"/><path d="M12 10v4.2M12 17v.2"/>',
  problem: '<path d="M8.3 3h7.4L21 8.3v7.4L15.7 21H8.3L3 15.7V8.3z"/><path d="m9 9 6 6M15 9l-6 6"/>',
  notTested: '<circle cx="12" cy="12" r="9" stroke-dasharray="3 3"/>',
  unavailable: '<circle cx="12" cy="12" r="9"/><path d="M9.6 9.5a2.5 2.5 0 1 1 3.4 2.3c-.6.3-1 .8-1 1.5v.4M12 16.8v.2"/>',
  manualRequired: '<path d="M8 13V6.5a1.5 1.5 0 0 1 3 0V12m0-6.5v-1a1.5 1.5 0 0 1 3 0V12m0-5.5a1.5 1.5 0 0 1 3 0V14a7 7 0 0 1-7 7h-.5A6.5 6.5 0 0 1 5 16l-1.5-3a1.5 1.5 0 0 1 2.6-1.5L8 13"/>',
  notApplicable: '<circle cx="12" cy="12" r="9"/><path d="M8 12h8"/>',
  info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 7.8v.2"/>',
  unlocked: '<rect x="5" y="10.5" width="14" height="10" rx="2"/><path d="M8 10.5V7.5a4 4 0 0 1 7.7-1.5"/>',
  cloud: '<path d="M7 18.5h10.5a4 4 0 0 0 .6-7.95A6 6 0 0 0 6.6 9.6 4.5 4.5 0 0 0 7 18.5z"/>',
  building: '<path d="M4 21V5l8-2v18M12 8l8 2v11M3 21h18M7 8h2M7 12h2M7 16h2M15 13h2M15 17h2"/>',
  lock: '<rect x="5" y="10.5" width="14" height="10" rx="2"/><path d="M8 10.5V7.5a4 4 0 0 1 8 0v3"/>',
  shield: '<path d="M12 3 4.5 6v5.5c0 4.6 3.2 8.2 7.5 9.5 4.3-1.3 7.5-4.9 7.5-9.5V6z"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  link: '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',
  search: '<circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.4-4.4"/>',
};

function icon(name: string, cls = "i"): string {
  return `<svg class="${cls}" viewBox="0 0 24 24" aria-hidden="true">${ICONS[name] ?? ICONS.info}</svg>`;
}

/** Statut : icône + texte, jamais la couleur seule. Les informations sans jugement n'ont pas de pastille. */
function status(statusName: string, p: Pack, text?: string): string {
  const tone = isJudgement(statusName) || statusName === "manualRequired" ? statusName : "neutral";
  return `<span class="st st-${tone}">${icon(statusName)}<span>${esc(text ?? p.statuses[statusName as keyof typeof p.statuses]?.label ?? statusName)}</span></span>`;
}

const CSS = `
:root{color-scheme:light dark;--bg:#f5f6f8;--card:#fff;--text:#14171a;--muted:#5d6670;--rule:#e3e6ea;--ink:#0B2230;--water:#2E9FD6;
--good:#1f7a36;--watch:#a65300;--problem:#c4000f;--manual:#1a5cbf;--neutral:#5d6670;--banner:#eef1f4;--warn-bg:#fff4e5;--bad-bg:#fdeced}
@media (prefers-color-scheme:dark){:root{--bg:#0e1114;--card:#171b20;--text:#eef1f4;--muted:#9aa4ae;--rule:#2a3038;--ink:#e8f3fa;
--good:#4cc46a;--watch:#f0a54a;--problem:#ff6b6b;--manual:#7fb2ff;--neutral:#9aa4ae;--banner:#1d232a;--warn-bg:#2b2113;--bad-bg:#2e1517}}
*{box-sizing:border-box}html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--bg);color:var(--text);font:17px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Noto Sans","Noto Sans Arabic",sans-serif}
main{max-width:640px;margin:0 auto;padding:16px 16px 40px}
a{color:var(--water)}
.top{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-block-end:12px}
.brand{display:flex;align-items:center;gap:8px;font-weight:700}
.brand svg{width:28px;height:28px}
.lang{font-size:15px}
.i{width:1.1em;height:1.1em;flex:none;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round;vertical-align:-.15em}
.state{border-radius:14px;padding:16px;margin-block-end:14px;background:var(--banner);border-inline-start:5px solid var(--neutral)}
.state h1{font-size:20px;line-height:1.3;margin:0 0 6px;display:flex;gap:8px;align-items:flex-start}
.state h1 .i{width:24px;height:24px;margin-block-start:1px}
.state p{margin:4px 0;color:var(--muted)}
.state.warn{background:var(--warn-bg);border-color:var(--watch)}.state.warn h1{color:var(--watch)}
.state.bad{background:var(--bad-bg);border-color:var(--problem)}.state.bad h1{color:var(--problem)}
.card{background:var(--card);border:1px solid var(--rule);border-radius:14px;padding:16px;margin-block-end:14px}
h2{font-size:18px;margin:0 0 10px;display:flex;gap:8px;align-items:center}
.mac{font-size:24px;font-weight:700;line-height:1.2;margin:0 0 4px}
.serial{font:600 28px/1.2 ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:.06em}
dl{margin:0;display:grid;grid-template-columns:auto 1fr;gap:6px 14px}dt{color:var(--muted)}dd{margin:0;font-weight:500}
.verify{border:2px solid var(--water)}
.blocker{background:var(--bad-bg);border:1px solid var(--problem);color:var(--problem);border-radius:12px;padding:12px 14px;margin-block-end:10px;font-weight:600}
.blocker p{color:var(--text);font-weight:400;margin:4px 0 0}
.counters{display:grid;grid-template-columns:repeat(auto-fit,minmax(110px,1fr));gap:8px;margin:0;padding:0;list-style:none}
.counters li{background:var(--banner);border-radius:10px;padding:10px 12px;display:flex;flex-direction:column}
.counters b{font-size:26px;line-height:1.1}
.counters .st{font-size:14px}
.row{padding:10px 0;border-block-start:1px solid var(--rule)}.row:first-of-type{border-block-start:0;padding-block-start:0}
.row .l{display:flex;justify-content:space-between;gap:10px;align-items:baseline;flex-wrap:wrap}
.row .k{font-weight:600}.row .v{font-weight:500}
.row .n{color:var(--muted);font-size:15px;margin-block-start:3px}
.st{display:inline-flex;gap:5px;align-items:center;font-weight:600;font-size:15px;white-space:nowrap}
.st-good{color:var(--good)}.st-watch{color:var(--watch)}.st-problem{color:var(--problem)}.st-manualRequired{color:var(--manual)}.st-neutral{color:var(--neutral)}
.prov{font-size:13px;color:var(--muted);border:1px solid var(--rule);border-radius:99px;padding:1px 8px;white-space:nowrap}
ul.plain{margin:0;padding-inline-start:20px}ul.plain li{margin:4px 0}
ul.icons{list-style:none;padding-inline-start:0}ul.icons li{display:flex;gap:8px;align-items:flex-start}ul.icons .i{margin-block-start:.2em}
ul.icons+ul.icons{margin-block-start:10px}
details summary{cursor:pointer;font-weight:600;font-size:18px}
details h3{font-size:15px;margin:16px 0 6px;color:var(--muted);text-transform:uppercase;letter-spacing:.04em}
.mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:13px;word-break:break-all;color:var(--muted)}
.legal{font-size:14px;color:var(--muted)}
.legal p{margin:6px 0}
.badge{display:inline-block;border:1px solid var(--rule);border-radius:99px;padding:2px 10px;font-size:13px;font-weight:600;color:var(--muted)}
.locks{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:10px;margin-block-end:10px}
.lock{border-radius:14px;padding:14px;border:2px solid var(--neutral);background:var(--banner)}
.lock .t{display:flex;gap:8px;align-items:center;font-weight:700;font-size:16px;color:var(--text)}
.lock .t .i{width:22px;height:22px}
.lock .v{display:flex;gap:10px;align-items:center;margin:10px 0 6px}
.lock .v .i{width:34px;height:34px;stroke-width:2.2}
.lock .v b{display:block;font-size:22px;line-height:1.15}
.lock .v small{display:block;font-weight:600;font-size:14px}
.lock p{margin:4px 0 0;color:var(--muted);font-size:15px}
.lock.st-good{border-color:var(--good);background:color-mix(in srgb,var(--good) 9%,var(--card))}
.lock.st-problem{border-color:var(--problem);background:var(--bad-bg)}
.lock.st-watch{border-color:var(--watch);background:var(--warn-bg)}
.lock.st-manualRequired{border-color:var(--manual);background:color-mix(in srgb,var(--manual) 9%,var(--card))}
.lock.st-good .v,.lock.st-problem .v,.lock.st-watch .v,.lock.st-manualRequired .v{color:inherit}
.lock.st-good .v{color:var(--good)}.lock.st-problem .v{color:var(--problem)}.lock.st-watch .v{color:var(--watch)}.lock.st-manualRequired .v{color:var(--manual)}.lock.st-neutral .v{color:var(--neutral)}
footer{text-align:center;margin-block-start:22px;font-size:15px}
footer a.cta{display:inline-block;margin-block-start:6px;background:var(--ink);color:var(--card);padding:10px 16px;border-radius:10px;text-decoration:none;font-weight:600}
.shop{display:flex;align-items:center;gap:10px;margin-block-start:10px;color:var(--muted)}
.shop img{max-height:40px;max-width:120px}
`;

const RING = `<svg viewBox="0 0 32 32" aria-hidden="true"><circle cx="16" cy="16" r="12" fill="none" stroke="#2E9FD6" stroke-width="4"/><path d="M16 9c2.6 3.4 4 5.6 4 7.4a4 4 0 0 1-8 0c0-1.8 1.4-4 4-7.4z" style="fill:var(--ink)"/></svg>`;

interface Shell {
  p: Pack;
  title: string;
  description: string;
  url: string;
  body: string;
  baseUrl: string;
  downloadUrl: string;
}

function shell({ p, title, description, url, body, baseUrl, downloadUrl }: Shell): string {
  const switchUrl = `${url}${url.includes("?") ? "&" : "?"}lang=${p.chrome.switchLang}`;
  return `<!doctype html>
<html lang="${p.chrome.htmlLang}" dir="${p.chrome.dir}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow,noarchive">
<meta name="referrer" content="no-referrer">
<title>${esc(title)}</title>
<meta name="description" content="${esc(description)}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Aman Check">
<meta property="og:title" content="${esc(description)}">
<meta property="og:url" content="${esc(url)}">
<meta name="twitter:card" content="summary">
<style>${CSS}</style>
</head>
<body>
<main>
<div class="top"><span class="brand">${RING}Aman Check</span><a class="lang" href="${esc(switchUrl)}" hreflang="${p.chrome.switchLang}" lang="${p.chrome.switchLang}">${p.chrome.switchTo}</a></div>
${body}
<footer>
<p>${esc(p.text.footerCTA)}</p>
<a class="cta" href="${esc(downloadUrl)}">${esc(p.chrome.download)}</a>
<p><a href="${esc(baseUrl)}/confidentialite?lang=${p.lang}">${esc(p.chrome.privacy)}</a></p>
</footer>
</main>
</body>
</html>`;
}

export interface PageInput {
  lang: Lang;
  state: ReportState;
  row: ReportRow | null;
  report: ConditionReport | null;
  latestUrl: string | null;
  baseUrl: string;
  downloadUrl: string;
  now: Date;
  shop: { name: string | null; logoBase64: string | null } | null;
}

export function renderReportPage(input: PageInput): string {
  const p = pack(input.lang);
  const { row, report, now } = input;
  const url = row ? `${input.baseUrl}/r/${row.public_id}` : input.baseUrl;

  if (input.state === "notFound" || !row) {
    return shell({
      p, url, baseUrl: input.baseUrl, downloadUrl: input.downloadUrl,
      title: `${p.chrome.notFoundTitle} · Aman Check`, description: p.chrome.notFoundTitle,
      body: `<section class="state bad" role="status"><h1>${icon("problem")}${esc(p.text.stateNotFound)}</h1></section>`,
    });
  }

  const checkDate = formatDate(row.generated_at, p);
  const name = report ? modelName(report.profile.model as never, report.profile.modelIdentifier, p) : row.model_identifier;
  const description = fill(p.text.linkPreview, { model: name, date: checkDate });
  const ago = p.chrome.ago(daysSince(row.generated_at, now));

  // 1. Bandeau d'état.
  let banner: string;
  switch (input.state) {
    case "withdrawn":
      banner = `<section class="state bad" role="status"><h1>${icon("problem")}${esc(p.text.stateWithdrawn)}</h1></section>`;
      break;
    case "replaced":
      banner = `<section class="state warn" role="status"><h1>${icon("watch")}${esc(p.text.stateReplaced)}</h1>
<p>${esc(p.chrome.checkedOn)} ${esc(checkDate)} (${esc(ago)})</p>
${input.latestUrl ? `<p><a href="${esc(input.latestUrl)}?lang=${p.lang}">${icon("link")} ${esc(p.text.stateReplacedLink)}</a></p>` : ""}</section>`;
      break;
    case "old":
      banner = `<section class="state warn" role="status"><h1>${icon("clock")}${esc(p.text.stateOld)}</h1>
<p>${esc(p.chrome.checkedOn)} ${esc(checkDate)} (${esc(ago)})</p></section>`;
      break;
    default:
      banner = `<section class="state" role="status"><h1>${icon("shield")}${esc(fill(p.text.stateValid, { date: formatDate(row.published_at, p) }))}</h1>
<p>${esc(p.chrome.checkedOn)} ${esc(checkDate)} (${esc(ago)})</p>
<p>${esc(p.chrome.validUntil(formatDate(row.valid_until, p)))}</p></section>`;
  }

  const legal = legalBlock(p, row, report, input.baseUrl);
  if (input.state === "withdrawn" || !report) {
    const erased = input.state !== "withdrawn" ? `<section class="card"><p>${esc(p.text.stateErased)}</p></section>` : "";
    return shell({
      p, url, baseUrl: input.baseUrl, downloadUrl: input.downloadUrl,
      title: `${p.text.reportTitle} · Aman Check`, description: input.state === "withdrawn" ? p.text.stateWithdrawn : description,
      body: banner + erased + legal,
    });
  }

  const s = summarize(report, p);
  const m = (id: string) => report.measurements.find((x) => x.id === id);
  const value = (id: string) => {
    const x = m(id);
    return x && x.value != null ? displayText(x, p) : null;
  };

  // 2. Identité.
  const serial = row.serial_last4 ? `••••${row.serial_last4}` : p.statuses.unavailable.label;
  const ids: [string, string | null][] = [
    [p.chrome.modelYear, value("identity.model_year")],
    [p.chrome.processor, value("identity.chip")],
    [p.chrome.memory, value("identity.ram")],
    [p.chrome.storage, value("identity.storage_capacity")],
    [p.chrome.macOS, value("identity.macos")],
  ];
  const shop = input.shop && (input.shop.logoBase64 || input.shop.name)
    ? `<div class="shop">${input.shop.logoBase64 ? `<img alt="" src="data:image/png;base64,${input.shop.logoBase64}">` : ""}<span>${esc(input.shop.name ?? "")}</span></div>`
    : "";
  const identity = `<section class="card"><h2>${esc(p.chrome.identity)}</h2>
<p class="mac">${esc(name)}</p>
<dl>${ids.filter(([, v]) => v).map(([k, v]) => `<dt>${esc(k)}</dt><dd>${esc(v)}</dd>`).join("")}
<dt>${esc(p.chrome.serial)}</dt><dd class="serial">${esc(serial)}</dd></dl>
${report.sellerName ? `<p class="n">${esc(p.chrome.sellerBy(report.sellerName))}</p>` : ""}${shop}
<p><span class="badge">${esc(p.text.trustLevel2)}</span></p></section>`;

  // 3. Vérifiez que c'est bien ce Mac.
  const verify = `<section class="card verify"><h2>${icon("search")}${esc(p.text.checkThisMacTitle)}</h2>
<p>${esc(p.text.checkThisMac)}</p>
<ul class="plain">${p.lists.buyerChecks.map((c) => `<li>${esc(c)}</li>`).join("")}</ul>
<p class="n">${esc(p.text.pdfMatch)}</p></section>`;

  // 4. Bloqueurs, en rouge et en tête.
  const blockers = s.blockers.length
    ? `<section aria-label="${esc(p.chrome.blockers)}">${s.blockers.map((b) => `<div class="blocker">${icon("lock")} ${esc(p.metrics[b.id as keyof typeof p.metrics]?.label ?? b.id)}${esc(p.chrome.colon)}${esc(displayText(b, p))}${b.detail || b.note ? `<p>${esc(b.detail ?? b.note)}</p>` : ""}</div>`).join("")}</section>`
    : "";
  const simulated = report.simulated ? `<div class="blocker">${esc(p.text.simulatedWarning)}</div>` : "";

  // 5. Compteurs, sans note globale.
  const counters = `<section class="card"><ul class="counters">${p.chrome.counters(s).filter(([k, n]) => k !== "manualRequired" || n > 0)
    .map(([k, n, label]) => `<li><b>${n}</b>${status(k, p, label)}</li>`).join("")}</ul>
<p class="n">${esc(p.chrome.testsDone(s.testsDone, s.testsPlanned))}</p></section>`;

  // 6. Verrouillages : iCloud et MDM en grand, teintés par leur verdict (icône + texte), le firmware en ligne simple.
  const lockTile = (x: ReportMeasurement) => {
    const tone = isJudgement(x.status) || x.status === "manualRequired" ? x.status : "neutral";
    const verdict = x.status === "good" ? "unlocked" : x.status === "problem" ? "lock" : x.status;
    const label = p.metrics[x.id]?.label ?? x.id;
    return `<div class="lock st-${tone}"><div class="t">${icon(x.id === "security.activation_lock" ? "cloud" : "building")}${esc(label)}</div>
<div class="v">${icon(verdict)}<span><b>${esc(displayText(x, p))}</b><small>${esc(p.statuses[x.status]?.label ?? x.status)}</small></span></div>
${x.detail ? `<p>${esc(x.detail)}</p>` : ""}${x.note ? `<p>${esc(x.note)}</p>` : ""}</div>`;
  };
  const keyLocks = ["security.activation_lock", "security.mdm"].map((id) => m(id)).filter(Boolean) as ReportMeasurement[];
  const firmware = m("security.firmware_password");
  const locks = keyLocks.length || firmware
    ? `<section class="card" aria-label="${esc(p.chrome.locks)}"><h2>${icon("lock")}${esc(p.chrome.locks)}</h2>
<div class="locks">${keyLocks.map(lockTile).join("")}</div>${firmware ? row_(firmware, p) : ""}</section>`
    : "";

  // 7. Batterie et SSD : mesures essentielles, avec les phrases de l'app.
  const essentials = report.measurements.filter((x) => {
    const info = p.metrics[x.id as keyof typeof p.metrics];
    return info && (info.section === "battery" || info.section === "storage") && info.level === "essential";
  });
  const batterySSD = essentials.length ? section(p.chrome.batteryAndSSD, essentials, p, true) : "";

  // 8. Tests guidés, un par ligne, avec provenance.
  const tests = `<section class="card"><h2>${esc(p.chrome.guidedTests)}</h2>${report.plannedTests.map((t) => {
    const r = resultFor(report, t);
    const st = r?.status ?? "notTested";
    const summary = r && st !== "notTested" ? r.summary : null;
    return `<div class="row"><div class="l"><span class="k">${esc(p.tests[t as keyof typeof p.tests]?.title ?? t)}</span>${status(st, p)}</div>
${summary ? `<div class="n">${esc(summary)}</div>` : ""}${r && st !== "notTested" ? `<div class="n"><span class="prov">${esc(p.provenance[r.provenance as keyof typeof p.provenance]?.label ?? r.provenance)}</span></div>` : ""}</div>`;
  }).join("")}</section>`;

  // 9. À vérifier avant l'achat.
  const points = toCheck(report, p);
  const check = `<section class="card"><h2>${esc(p.chrome.toCheckTitle)}</h2>${points.length
    ? points.map((pt) => `<div class="row"><div class="l"><span class="v">${esc(pt.title)}</span>${status(pt.status, p)}</div>${pt.detail ? `<div class="n">${esc(pt.detail)}</div>` : ""}</div>`).join("")
    : `<p>${esc(p.chrome.nothingToCheck)}</p>`}</section>`;

  // 10. Détails avancés, repliés.
  const advanced = `<section class="card"><details><summary>${esc(p.chrome.advanced)}</summary>${catalog.sectionOrder.map((sec) => {
    const rows = report.measurements.filter((x) => p.metrics[x.id as keyof typeof p.metrics]?.section === sec);
    if (!rows.length) return "";
    return `<h3>${esc(p.sections[sec as keyof typeof p.sections])}</h3>${rows.map((x) => row_(x, p, true)).join("")}`;
  }).join("")}</details></section>`;

  // 11. Ce que ce rapport prouve et ne prouve pas.
  const proves = `<section class="card"><h2>${esc(p.text.provesTitle)}</h2>
<ul class="plain icons">${p.lists.proves.map((x) => `<li><span class="st-good">${icon("good")}</span><span>${esc(x)}</span></li>`).join("")}</ul>
<ul class="plain icons">${p.lists.doesNotProve.map((x) => `<li><span class="st-neutral">${icon("notApplicable")}</span><span>${esc(x)}</span></li>`).join("")}</ul></section>`;

  return shell({
    p, url, baseUrl: input.baseUrl, downloadUrl: input.downloadUrl,
    title: `${p.text.reportTitle} · ${name} · Aman Check`, description,
    body: banner + identity + simulated + blockers + locks + verify + counters + batterySSD + tests + check + advanced + proves + legal,
  });
}

function row_(x: ReportMeasurement, p: Pack, withMethod = false): string {
  const info = p.metrics[x.id as keyof typeof p.metrics];
  const label = info?.label ?? p.statuses.info.label;
  const judged = info?.isJudged || x.value == null || x.status === "manualRequired";
  const notes = [x.detail, x.note].filter(Boolean).map((t) => esc(t)).join(" · ");
  return `<div class="row"><div class="l"><span class="k">${esc(label)}</span>${judged ? status(x.status, p) : ""}</div>
<div class="v">${esc(displayText(x, p))}</div>${notes ? `<div class="n">${notes}</div>` : ""}
<div class="n"><span class="prov">${esc(x.value == null ? p.statuses.unavailable.label : p.provenance[x.provenance as keyof typeof p.provenance]?.label ?? x.provenance)}</span>${withMethod && x.method ? ` <span class="mono">${esc(x.method)}</span>` : ""}</div></div>`;
}

function section(title: string, rows: ReportMeasurement[], p: Pack, sorted: boolean, iconName?: string): string {
  if (!rows.length) return "";
  const list = sorted ? rows : [...rows].sort((a, b) => severity(a.status) - severity(b.status));
  return `<section class="card"><h2>${iconName ? icon(iconName) : ""}${esc(title)}</h2>${list.map((x) => row_(x, p)).join("")}</section>`;
}

function legalBlock(p: Pack, row: ReportRow, report: ConditionReport | null, baseUrl: string): string {
  return `<section class="card legal">
<p>${esc(p.text.disclaimer)}</p>
<p>${esc(p.chrome.publicId)}${esc(p.chrome.colon)}<b>${esc(row.public_id)}</b> · ${esc(p.chrome.reportId)} ${esc(row.report_id)}</p>
<p>${esc(p.chrome.fingerprint)}${esc(p.chrome.colon)}<span class="mono">${esc(row.sha256)}</span></p>
<p>${esc(p.chrome.appVersion)} ${esc(row.app_version)}${report ? ` · ${esc(p.chrome.procedure)} ${esc(report.procedureVersion)}` : ""}</p>
<p><a href="${esc(baseUrl)}/r/${esc(row.public_id)}.json">${esc(p.chrome.verifyIndependently)}</a></p>
</section>`;
}

/** Page de confidentialité (§10), en langage simple. TODO: à faire relire avant la mise en ligne. */
export function renderPrivacyPage(lang: Lang, baseUrl: string, downloadUrl: string, contact: string, retentionDays: number): string {
  const p = pack(lang);
  const fr = lang === "fr";
  const body = `<section class="card"><h2>${fr ? "Confidentialité" : "Privacy"}</h2>
<p>${fr ? "Aman Check fonctionne sur votre Mac. Rien n'est envoyé sans votre accord : seul le contenu du rapport d'état quitte le Mac, quand vous choisissez de le publier, après un écran qui liste ce qui sera envoyé."
    : "Aman Check runs on your Mac. Nothing is sent without your consent: only the content of the condition report leaves the Mac, when you choose to publish it, after a screen listing what will be sent."}</p></section>
<section class="card"><h2>${esc(p.text.sentTitle)}</h2><ul class="plain">${p.lists.sent.map((x) => `<li>${esc(x)}</li>`).join("")}</ul></section>
<section class="card"><h2>${esc(p.text.neverSentTitle)}</h2><ul class="plain">${p.lists.neverSent.map((x) => `<li>${esc(x)}</li>`).join("")}</ul></section>
<section class="card"><h2>${fr ? "Ce que nous conservons" : "What we keep"}</h2><ul class="plain">
<li>${fr ? `Le contenu d'un rapport est effacé ${retentionDays} jours après sa publication, ou immédiatement s'il est retiré. Il ne reste ensuite que l'identifiant, l'empreinte, les dates et l'état.`
    : `The content of a report is erased ${retentionDays} days after it is published, or immediately if it is withdrawn. Only the identifier, fingerprint, dates and state remain.`}</li>
<li>${fr ? "Les adresses IP ne sont pas journalisées : elles servent seulement, sous forme hachée, à limiter les abus pendant une heure au plus."
    : "IP addresses are not logged: they are only used, hashed, to limit abuse for one hour at most."}</li>
<li>${fr ? "Aucun cookie, aucun traceur, aucune police ni script tiers sur les pages de rapport."
    : "No cookies, no trackers, no third-party fonts or scripts on report pages."}</li>
<li>${fr ? "Pour un achat, le prestataire de paiement encaisse ; nous ne gardons ni e-mail ni nom, seulement la référence de commande."
    : "For a purchase, the payment provider collects the payment; we keep neither e-mail nor name, only the order reference."}</li>
</ul></section>
<section class="card"><h2>${fr ? "Demander un retrait" : "Ask for a withdrawal"}</h2>
<p>${fr ? "L'auteur d'un rapport peut le retirer à tout moment depuis l'app. Pour toute autre demande :" : "The author of a report can withdraw it at any time from the app. For any other request:"}
<a href="mailto:${esc(contact)}">${esc(contact)}</a></p></section>`;
  return shell({ p, url: `${baseUrl}/confidentialite`, baseUrl, downloadUrl, title: `${fr ? "Confidentialité" : "Privacy"} · Aman Check`,
    description: fr ? "Confidentialité d'Aman Check" : "Aman Check privacy", body });
}

/** Accueil minimal et page d'achat indisponible. */
export function renderSimplePage(lang: Lang, baseUrl: string, downloadUrl: string, heading: string, text: string): string {
  const p = pack(lang);
  return shell({ p, url: baseUrl, baseUrl, downloadUrl, title: `${heading} · Aman Check`, description: heading,
    body: `<section class="card"><h2>${esc(heading)}</h2><p>${esc(text)}</p></section>` });
}
