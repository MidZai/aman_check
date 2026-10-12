/** Empreintes, signature Ed25519 et identifiants aléatoires (WebCrypto uniquement). */

/** Même alphabet que les identifiants de rapport de l'app : sans 0, O, 1, I. */
export const ID_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

const encoder = new TextEncoder();

export function toHex(bytes: ArrayBuffer | Uint8Array): string {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  return Array.from(view, (b) => b.toString(16).padStart(2, "0")).join("");
}

export function toBase64(bytes: ArrayBuffer | Uint8Array): string {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let binary = "";
  for (const b of view) binary += String.fromCharCode(b);
  return btoa(binary);
}

export function fromBase64(text: string): Uint8Array {
  const binary = atob(text.trim());
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

export async function sha256Hex(data: ArrayBuffer | Uint8Array | string): Promise<string> {
  const bytes = typeof data === "string" ? encoder.encode(data) : data;
  return toHex(await crypto.subtle.digest("SHA-256", bytes));
}

export async function hmacHex(secret: string, data: string | Uint8Array): Promise<string> {
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const bytes = typeof data === "string" ? encoder.encode(data) : data;
  return toHex(await crypto.subtle.sign("HMAC", key, bytes));
}

/** Comparaison à temps constant de deux chaînes hexadécimales. */
export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export function randomFromAlphabet(length: number): string {
  // Rejet des octets ≥ 256 - (256 % 32) = 256 : 32 divise 256, aucun biais.
  const bytes = crypto.getRandomValues(new Uint8Array(length));
  return Array.from(bytes, (b) => ID_ALPHABET[b % ID_ALPHABET.length]).join("");
}

/** Identifiant public : 12 caractères (32^12 ≈ 1,2 × 10^18), non énumérable. */
export function newPublicId(): string {
  return randomFromAlphabet(12);
}

/** « 7K3PQ2XDM4RT » → « 7K3P-Q2XD-M4RT ». */
export function formatPublicId(id: string): string {
  return `${id.slice(0, 4)}-${id.slice(4, 8)}-${id.slice(8, 12)}`;
}

/** Accepte « 7K3P-Q2XD-M4RT », en minuscules ou sans tirets ; `null` si le format est invalide. */
export function normalizePublicId(input: string): string | null {
  const compact = input.toUpperCase().replace(/-/g, "");
  if (compact.length !== 12) return null;
  for (const c of compact) if (!ID_ALPHABET.includes(c)) return null;
  return compact;
}

/** Jeton de gestion (retrait) : 32 octets aléatoires, renvoyé une seule fois. */
export function newManageToken(): string {
  return toHex(crypto.getRandomValues(new Uint8Array(32)));
}

/** Clé de licence : « ACK-XXXX-XXXX-XXXX-XXXX » (80 bits). */
export function newLicenseKey(): string {
  const raw = randomFromAlphabet(16);
  return `ACK-${raw.slice(0, 4)}-${raw.slice(4, 8)}-${raw.slice(8, 12)}-${raw.slice(12, 16)}`;
}

/** Les clés sont comparées sans tenir compte des espaces ni de la casse (saisie à la main). */
export function hashLicenseKey(key: string): Promise<string> {
  return sha256Hex(key.trim().toUpperCase());
}

/** Message signé : `publicId|sha256|publishedAt` (publié avec les clés sur /.well-known). */
export function signedMessage(publicId: string, sha256: string, publishedAt: string): string {
  return `${publicId}|${sha256}|${publishedAt}`;
}

export async function signEd25519(privateKeyPkcs8Base64: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey("pkcs8", fromBase64(privateKeyPkcs8Base64), { name: "Ed25519" }, false, ["sign"]);
  return toBase64(await crypto.subtle.sign({ name: "Ed25519" }, key, encoder.encode(message)));
}

export async function verifyEd25519(publicKeyRawBase64: string, message: string, signatureBase64: string): Promise<boolean> {
  const key = await crypto.subtle.importKey("raw", fromBase64(publicKeyRawBase64), { name: "Ed25519" }, false, ["verify"]);
  return crypto.subtle.verify({ name: "Ed25519" }, key, fromBase64(signatureBase64), encoder.encode(message));
}
