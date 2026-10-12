/** Codes d'erreur de l'API (cahier des charges §6). Les messages affichés sont dans l'app (`PublishError`). */
export type ApiErrorCode =
  | "invalid_report"
  | "invalid_license"
  | "no_credit"
  | "too_large"
  | "report_too_old"
  | "simulated_profile"
  | "app_too_old"
  | "rate_limited"
  | "not_found"
  | "invalid_token"
  | "invalid_signature";

export const HTTP_STATUS: Record<ApiErrorCode, number> = {
  invalid_report: 400,
  invalid_license: 401,
  no_credit: 402,
  too_large: 413,
  report_too_old: 422,
  simulated_profile: 422,
  app_too_old: 426,
  rate_limited: 429,
  not_found: 404,
  invalid_token: 403,
  invalid_signature: 401,
};

export function apiError(code: ApiErrorCode, detail?: string, extra: Record<string, unknown> = {}): Response {
  return Response.json({ error: code, ...(detail ? { detail } : {}), ...extra }, {
    status: HTTP_STATUS[code],
    headers: { "Cache-Control": "no-store" },
  });
}
