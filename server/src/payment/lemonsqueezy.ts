/**
 * Lemon Squeezy (marchand de référence : encaisse et gère la TVA, envoie la clé par e-mail).
 * Choix provisoire : le prestataire définitif est une question ouverte (§14).
 * Signature : `X-Signature` = HMAC-SHA256 hexadécimal du corps brut avec le secret du webhook.
 */
import { hmacHex, timingSafeEqual } from "../crypto";
import type { Plan } from "../licenses";
import type { PaymentEvent, PaymentProvider } from "./provider";

interface Payload {
  meta?: { event_name?: string };
  data?: { id?: string; attributes?: Record<string, unknown> };
}

export const lemonSqueezy: PaymentProvider = {
  name: "lemonsqueezy",

  async verify(rawBody, headers, secret) {
    const signature = (headers.get("X-Signature") ?? "").trim().toLowerCase();
    if (!secret || !signature) return false;
    return timingSafeEqual(await hmacHex(secret, rawBody), signature);
  },

  parse(rawBody, headers, products): PaymentEvent {
    let payload: Payload;
    try {
      payload = JSON.parse(new TextDecoder().decode(rawBody)) as Payload;
    } catch {
      return { kind: "ignore", reason: "JSON illisible" };
    }
    const event = payload.meta?.event_name ?? headers.get("X-Event-Name") ?? "";
    const a = payload.data?.attributes ?? {};
    // Les événements de commande portent l'identifiant dans `data.id`, les autres dans `order_id`.
    const orderId = event.startsWith("order_") ? payload.data?.id ?? a.order_id : a.order_id;
    const orderRef = orderId != null ? `lemonsqueezy:order:${orderId}` : null;
    if (!orderRef) return { kind: "ignore", reason: `${event} sans commande` };
    const plan: Plan | undefined = products[String(a.variant_id ?? "")] ?? products[String(a.product_id ?? "")];
    const date = (value: unknown) => (typeof value === "string" && !Number.isNaN(Date.parse(value)) ? new Date(value).toISOString() : null);

    switch (event) {
      case "license_key_created": {
        if (!plan) return { kind: "ignore", reason: `produit ${a.product_id} non configuré` };
        if (typeof a.key !== "string" || !a.key) return { kind: "ignore", reason: "clé absente" };
        return { kind: "grant", orderRef, plan, licenseKey: a.key, validUntil: date(a.expires_at) };
      }
      case "subscription_created":
      case "subscription_updated":
      case "subscription_resumed":
      case "subscription_cancelled":
      case "subscription_expired":
      case "subscription_payment_success": {
        // Résiliation : l'abonnement court jusqu'à la fin de la période payée (`ends_at`).
        const status = String(a.status ?? "");
        const end = status === "expired" ? date(a.ends_at) ?? new Date().toISOString() : date(a.ends_at) ?? date(a.renews_at);
        return end ? { kind: "subscription", orderRef, validUntil: end } : { kind: "ignore", reason: `${event} sans date` };
      }
      case "order_refunded":
        return { kind: "revoke", orderRef };
      default:
        return { kind: "ignore", reason: event || "événement inconnu" };
    }
  },
};
