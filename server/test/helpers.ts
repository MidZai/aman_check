import { env } from "cloudflare:workers";
import { createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import worker, { clock } from "../src/index";
import { createLicense, type Plan } from "../src/licenses";
import fixtureText from "./fixtures/report.json?raw";

export const NOW = new Date("2026-10-11T12:00:00Z");
let serialCounter = 0;

export function setNow(date: Date) {
  clock.now = () => date;
}

export async function call(path: string, init: RequestInit = {}): Promise<Response> {
  const ctx = createExecutionContext();
  const response = await worker.fetch(new Request(`https://verif.test${path}`, init), env, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}

export async function license(plan: Plan = "single", credits = 1, validUntil: string | null = null) {
  return createLicense(env.DB, { plan, credits, validUntil, orderRef: `test:${crypto.randomUUID()}` }, NOW);
}

/** Rapport d'exemple encodé par l'app (AmanCatalogExport), avec une date de contrôle et un Mac au choix. */
export function reportBytes(options: { generatedAt?: string; serial?: string; mutate?: (r: Record<string, any>) => void } = {}): Uint8Array {
  const serial = options.serial ?? uniqueSerial();
  let text = fixtureText
    .replace(/"generatedAt" : "[^"]+"/, `"generatedAt" : "${options.generatedAt ?? "2026-10-11T10:00:00Z"}"`)
    .replace(/"_0" : "Q2XD"/, `"_0" : "${serial}"`)
    .replace(/"••••Q2XD"/, `"••••${serial}"`);
  if (options.mutate) {
    const object = JSON.parse(text);
    options.mutate(object);
    text = JSON.stringify(object, null, 2);
  }
  return new TextEncoder().encode(text);
}

export function uniqueSerial(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  serialCounter++;
  const rand = crypto.getRandomValues(new Uint8Array(4));
  return Array.from(rand, (b) => alphabet[b % alphabet.length]).join("");
}

export function publish(key: string, body: Uint8Array | string, headers: Record<string, string> = {}) {
  return call("/v1/reports", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json", "X-App-Version": "1.0.0", ...headers },
    body,
  });
}
