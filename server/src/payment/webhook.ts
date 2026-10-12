/** `POST /webhooks/payment` : crée ou crédite une licence (cahier des charges §9). */
import type { Env } from "../env";
import { sha256Hex } from "../crypto";
import { apiError } from "../errors";
import { createLicense, type Plan } from "../licenses";
import { isoSeconds } from "../reports";
import { lemonSqueezy } from "./lemonsqueezy";
import type { PaymentEvent, PaymentProvider } from "./provider";

/** Prestataire actif. Pour en changer : nouvelle implémentation de `PaymentProvider`. */
export const activeProvider: PaymentProvider = lemonSqueezy;

export function productPlans(env: Env): Record<string, Plan> {
  try {
    const parsed = JSON.parse(env.PAYMENT_PRODUCTS || "{}") as Record<string, string>;
    return Object.fromEntries(Object.entries(parsed).filter(([, plan]) => plan === "single" || plan === "pro")) as Record<string, Plan>;
  } catch {
    return {};
  }
}

export async function handlePaymentWebhook(env: Env, request: Request, now: Date, provider = activeProvider): Promise<Response> {
  const raw = new Uint8Array(await request.arrayBuffer());
  if (!(await provider.verify(raw, request.headers, env.PAYMENT_WEBHOOK_SECRET))) return apiError("invalid_signature");

  // Le prestataire peut renvoyer le même webhook : il n'est appliqué qu'une fois.
  const eventId = `${provider.name}:${await sha256Hex(raw)}`;
  const seen = await env.DB.prepare("SELECT 1 FROM payment_events WHERE event_id = ?1").bind(eventId).first();
  if (seen) return Response.json({ ok: true, duplicate: true });

  const event = provider.parse(raw, request.headers, productPlans(env));
  const result = await applyPaymentEvent(env.DB, event, now);
  await env.DB.prepare("INSERT INTO payment_events (event_id, received_at) VALUES (?1, ?2)").bind(eventId, isoSeconds(now)).run();
  return Response.json({ ok: true, ...result });
}

export async function applyPaymentEvent(db: D1Database, event: PaymentEvent, now: Date): Promise<Record<string, unknown>> {
  switch (event.kind) {
    case "grant": {
      const existing = await db.prepare("SELECT id FROM licenses WHERE order_ref = ?1").bind(event.orderRef).first<{ id: string }>();
      if (existing) return { applied: "grant", licenseId: existing.id, alreadyExists: true };
      let validUntil = event.validUntil;
      if (event.plan === "pro") {
        const pending = await db.prepare("SELECT valid_until FROM pending_subscriptions WHERE order_ref = ?1").bind(event.orderRef)
          .first<{ valid_until: string }>();
        // En attendant l'événement d'abonnement : un mois.
        validUntil = pending?.valid_until ?? validUntil ?? new Date(now.getTime() + 31 * 86_400_000).toISOString();
      }
      const { id } = await createLicense(db, {
        plan: event.plan,
        credits: event.plan === "single" ? 1 : 0,
        validUntil: event.plan === "pro" ? validUntil : null,
        orderRef: event.orderRef,
        key: event.licenseKey,
      }, now);
      return { applied: "grant", licenseId: id, plan: event.plan };
    }
    case "subscription": {
      const result = await db.prepare("UPDATE licenses SET valid_until = ?1 WHERE order_ref = ?2 AND plan = 'pro'")
        .bind(event.validUntil, event.orderRef).run();
      if (result.meta.changes === 0) {
        await db.prepare(
          `INSERT INTO pending_subscriptions (order_ref, valid_until, received_at) VALUES (?1, ?2, ?3)
           ON CONFLICT (order_ref) DO UPDATE SET valid_until = excluded.valid_until`,
        ).bind(event.orderRef, event.validUntil, isoSeconds(now)).run();
      }
      return { applied: "subscription", validUntil: event.validUntil };
    }
    case "revoke": {
      await db.prepare("UPDATE licenses SET credits = 0, valid_until = CASE WHEN plan = 'pro' THEN ?1 ELSE valid_until END WHERE order_ref = ?2")
        .bind(now.toISOString(), event.orderRef).run();
      return { applied: "revoke" };
    }
    case "ignore":
      return { applied: "ignore", reason: event.reason };
  }
}
