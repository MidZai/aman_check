/**
 * Interface du prestataire de paiement (cahier des charges §9) : changer de prestataire
 * revient à écrire une nouvelle implémentation, sans toucher au reste du serveur.
 * Le serveur ne garde ni e-mail ni nom : seulement la référence de commande.
 */
import type { Plan } from "../licenses";

export type PaymentEvent =
  /** Achat : crée la licence avec la clé envoyée à l'acheteur par le prestataire. */
  | { kind: "grant"; orderRef: string; plan: Plan; licenseKey: string; validUntil: string | null }
  /** Abonnement Pro créé, renouvelé ou résilié : nouvelle date de fin. */
  | { kind: "subscription"; orderRef: string; validUntil: string }
  /** Remboursement : crédits non utilisés annulés, abonnement arrêté. Les rapports publiés restent en ligne. */
  | { kind: "revoke"; orderRef: string }
  | { kind: "ignore"; reason: string };

export interface PaymentProvider {
  readonly name: string;
  /** Vérifie la signature du webhook sur les octets bruts reçus. */
  verify(rawBody: Uint8Array, headers: Headers, secret: string): Promise<boolean>;
  /** Traduit le webhook en événement neutre. `products` : identifiant de produit du prestataire → offre. */
  parse(rawBody: Uint8Array, headers: Headers, products: Record<string, Plan>): PaymentEvent;
}
