/**
 * Limites de débit (cahier des charges §6) : 10 publications par heure et par clé,
 * 60 lectures par minute et par adresse IP sur /r/.
 * Les adresses IP ne sont jamais stockées en clair : HMAC avec un secret, purgé après une heure (§10).
 */
import { hmacHex } from "./crypto";
import type { Env } from "./env";

export const HOUR_MS = 60 * 60 * 1000;

/** Incrémente le compteur de la fenêtre courante ; `false` si la limite est dépassée. */
export async function allow(db: D1Database, bucket: string, limit: number, windowMs: number, now: Date): Promise<boolean> {
  const windowStart = Math.floor(now.getTime() / windowMs) * windowMs;
  const row = await db
    .prepare(
      `INSERT INTO rate_limits (bucket, window_start, count) VALUES (?1, ?2, 1)
       ON CONFLICT (bucket, window_start) DO UPDATE SET count = count + 1
       RETURNING count`,
    )
    .bind(bucket, windowStart)
    .first<{ count: number }>();
  return (row?.count ?? 1) <= limit;
}

export async function ipBucket(env: Env, request: Request): Promise<string> {
  const ip = request.headers.get("CF-Connecting-IP") ?? "local";
  return `ip:${(await hmacHex(env.IP_HASH_SECRET || "aman-check", ip)).slice(0, 32)}`;
}

/** Purge des fenêtres de plus d'une heure (tâche planifiée). */
export async function purgeRateLimits(db: D1Database, now: Date): Promise<void> {
  await db.prepare("DELETE FROM rate_limits WHERE window_start < ?1").bind(now.getTime() - HOUR_MS).run();
}
