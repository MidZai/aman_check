// Outils communs aux scripts d'administration (Node, sans dépendance).
import { execFileSync } from "node:child_process";
import { createHash, randomBytes, randomInt } from "node:crypto";

export const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

export function random(length) {
  return Array.from({ length }, () => ALPHABET[randomInt(ALPHABET.length)]).join("");
}

/** Même hachage que le serveur (src/crypto.ts : hashLicenseKey). */
export function hashKey(key) {
  return createHash("sha256").update(key.trim().toUpperCase()).digest("hex");
}

export function sql(value) {
  if (value === null || value === undefined) return "NULL";
  if (typeof value === "number") return String(value);
  return `'${String(value).replace(/'/g, "''")}'`;
}

export function parseArgs(argv) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith("--")) {
      const next = argv[i + 1];
      if (next === undefined || next.startsWith("--")) args[a.slice(2)] = true;
      else { args[a.slice(2)] = next; i++; }
    } else args._.push(a);
  }
  return args;
}

/** Exécute une requête sur D1 (base locale par défaut, `--remote` pour la production). */
export function d1(command, { remote = false } = {}) {
  return execFileSync("npx", ["wrangler", "d1", "execute", "aman-check", remote ? "--remote" : "--local", "--command", command],
    { stdio: ["ignore", "pipe", "inherit"], encoding: "utf8" });
}

export { randomBytes };
