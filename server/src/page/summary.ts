/**
 * Compteurs, bloqueurs et « À vérifier avant l'achat » : même logique que `ReportSummary` et
 * `ReportInsights.toCheck` (Sources/AmanCore/Report.swift). Pas de note globale (règle 4).
 */
import catalog from "../catalog.json";
import type { ConditionReport, ReportMeasurement, ReportTest } from "../validate";
import type { Pack } from "./i18n";

const JUDGEMENTS = new Set(["good", "watch", "problem"]);
const FOLLOW_UP = new Set(["watch", "problem", "notTested", "unavailable", "manualRequired"]);

export interface Summary {
  good: number;
  watch: number;
  problem: number;
  notTested: number;
  toCheck: number;
  testsDone: number;
  testsPlanned: number;
  blockers: ReportMeasurement[];
}

export function severity(status: string): number {
  return (catalog.severity as Record<string, number>)[status] ?? 9;
}

export function isJudgement(status: string): boolean {
  return JUDGEMENTS.has(status);
}

export function resultFor(report: ConditionReport, test: string): ReportTest | undefined {
  return report.tests.find((t) => t.test === test);
}

export function summarize(report: ConditionReport, pack: Pack): Summary {
  const s: Summary = { good: 0, watch: 0, problem: 0, notTested: 0, toCheck: 0, testsDone: 0, testsPlanned: 0, blockers: [] };
  const count = (status: string) => {
    switch (status) {
      case "good": s.good++; break;
      case "watch": s.watch++; break;
      case "problem": s.problem++; break;
      case "notTested": s.notTested++; break;
      case "unavailable":
      case "manualRequired": s.toCheck++; break;
    }
  };
  for (const m of report.measurements) {
    const info = pack.metrics[m.id];
    if (!info || !info.isJudged) continue;
    // Seules les mesures « Essentiel » jugées comptent : le détail avancé ne gonfle pas les compteurs.
    if (info.level === "essential" || m.status === "problem" || m.status === "watch") count(m.status);
  }
  for (const test of report.plannedTests) {
    const result = resultFor(report, test);
    if (result) {
      count(result.status);
      if (result.outcome === "passed" || result.outcome === "failed") s.testsDone++;
    } else {
      s.notTested++;
    }
  }
  s.testsPlanned = report.plannedTests.length;
  s.blockers = report.measurements.filter((m) => catalog.blockers.includes(m.id) && m.status === "problem");
  return s;
}

export interface Point {
  key: string;
  status: string;
  title: string;
  detail: string | null;
}

export function displayText(m: ReportMeasurement, pack: Pack): string {
  if (m.display) return m.display;
  const v = m.value;
  if (v?.text) return v.text._0;
  if (v?.int) return `${v.int._0}${m.unit ? ` ${m.unit}` : ""}`;
  if (v?.double) return `${v.double._0}${m.unit ? ` ${m.unit}` : ""}`;
  if (v?.bool) return v.bool._0 ? pack.chrome.yes : pack.chrome.no;
  return pack.statuses[m.status]?.label ?? m.status;
}

export function toCheck(report: ConditionReport, pack: Pack): Point[] {
  const points: Point[] = [];
  for (const m of report.measurements) {
    const info = pack.metrics[m.id];
    if (!info || !FOLLOW_UP.has(m.status)) continue;
    // Détails avancés non disponibles : pas de quoi alerter l'acheteur.
    if (info.level === "advanced" && (m.status === "unavailable" || m.status === "notTested")) continue;
    points.push({ key: m.id, status: m.status, title: `${info.label}${pack.chrome.colon}${displayText(m, pack)}`, detail: m.note ?? m.detail ?? null });
  }
  const untested: string[] = [];
  for (const test of report.plannedTests) {
    const result = resultFor(report, test);
    const status = result?.status ?? "notTested";
    if (!FOLLOW_UP.has(status)) continue;
    const title = pack.tests[test]?.title ?? test;
    if (status === "notTested") {
      untested.push(title);
      continue;
    }
    points.push({ key: `test.${test}`, status, title: `${title}${pack.chrome.colon}${result?.summary ?? pack.statuses[status].label}`, detail: result?.details[0] ?? null });
  }
  if (untested.length) {
    points.push({
      key: "tests.notTested",
      status: "notTested",
      title: untested.length === 1 ? pack.chrome.testNotDone(untested[0]) : pack.chrome.testsNotDone(untested.length, untested.join(", ")),
      detail: pack.chrome.testInPerson,
    });
  }
  // Tri stable par gravité, comme `sorted` sur des clés égales dans l'app.
  return points.map((p, i) => ({ p, i })).sort((a, b) => severity(a.p.status) - severity(b.p.status) || a.i - b.i).map(({ p }) => p);
}
