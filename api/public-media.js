const SUPABASE_URL = process.env.SUPABASE_URL || "https://vibybosdqavejvqsuvph.supabase.co";
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const BUCKET = "markys-sga-media";
const SIGNED_URL_TTL_SECONDS = 3600;
const CACHE_TTL_MS = 30_000;
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX = 120;
// Avoid signing hundreds of assets in one anonymous request.
const MAX_SIGNED_MEDIA_ITEMS = 100;
const cache = new Map();
const rateLimits = new Map();

function send(res, status, body) {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "no-store, max-age=0");
  res.end(JSON.stringify(body));
}
function clientAddress(req) {
  const value = req.headers["x-real-ip"];
  return typeof value === "string" && value.trim() ? value.split(",")[0].trim().slice(0, 80) : "unknown";
}
function isRateLimited(req) {
  const key = clientAddress(req);
  const now = Date.now();
  let entry = rateLimits.get(key);
  if (!entry || now - entry.startedAt >= RATE_LIMIT_WINDOW_MS) entry = { startedAt: now, count: 0 };
  entry.count += 1;
  rateLimits.set(key, entry);
  if (rateLimits.size > 5000) {
    for (const [address, value] of rateLimits) {
      if (now - value.startedAt >= RATE_LIMIT_WINDOW_MS) rateLimits.delete(address);
    }
    if (rateLimits.size > 5000) rateLimits.delete(rateLimits.keys().next().value);
  }
  return entry.count > RATE_LIMIT_MAX;
}
async function upstream(path, options = {}) {
  return fetch(SUPABASE_URL + path, {
    ...options,
    headers: {
      apikey: SERVICE_ROLE_KEY,
      Authorization: "Bearer " + SERVICE_ROLE_KEY,
      ...(options.headers || {})
    },
    cache: "no-store"
  });
}
function absoluteSignedUrl(value) {
  if (typeof value !== "string" || !value) return "";
  if (/^https?:\/\//i.test(value)) return value;
  if (value.startsWith("/storage/v1/")) return SUPABASE_URL + value;
  return SUPABASE_URL + "/storage/v1" + (value.startsWith("/") ? value : "/" + value);
}
export function isSupportedMediaType(type) {
  return /^(image\/(png|jpeg|gif|webp|avif)|video\/(mp4|webm|ogg|quicktime|x-m4v))$/i.test(type);
}
export function inferType(item) {
  const metadata = item && item.metadata || {};
  const known = metadata.mimetype || metadata.contentType;
  if (known) {
    const normalized = String(known).toLowerCase();
    if (normalized === "image/jpg") return "image/jpeg";
    if (normalized === "video/mov") return "video/quicktime";
    if (normalized === "video/m4v") return "video/x-m4v";
    return normalized;
  }
  const name = String(item && item.name || "").replace(/^\d+_/, "");
  const extension = name.split(".").pop().toLowerCase();
  if (/\.(mp4|webm|ogg)$/i.test(name)) return "video/" + extension;
  if (/\.(mov)$/i.test(name)) return "video/quicktime";
  if (/\.(m4v)$/i.test(name)) return "video/x-m4v";
  if (/\.(png|gif|webp|avif)$/i.test(name)) return "image/" + extension;
  if (/\.(jpg|jpeg)$/i.test(name)) return "image/jpeg";
  return "application/octet-stream";
}
export default async function handler(req, res) {
  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return send(res, 405, { ok: false, error: "method_not_allowed" });
  }
  if (isRateLimited(req)) {
    res.setHeader("Retry-After", "60");
    return send(res, 429, { ok: false, error: "rate_limit_exceeded" });
  }
  if (!SERVICE_ROLE_KEY) return send(res, 500, { ok: false, error: "media_service_not_configured" });
  const clinic = typeof req.query?.clinic === "string" ? req.query.clinic : "clinica-principal";
  if (!/^[a-z0-9-]{1,80}$/.test(clinic)) return send(res, 400, { ok: false, error: "invalid_clinic_slug" });
  const cached = cache.get(clinic);
  if (cached && Date.now() - cached.at < CACHE_TTL_MS) return send(res, 200, cached.data);

  try {
    const clinicQuery = new URLSearchParams({ select: "id", slug: "eq." + clinic, active: "eq.true", limit: "1" });
    const clinicResponse = await upstream("/rest/v1/markys_clinics?" + clinicQuery.toString());
    if (!clinicResponse.ok) return send(res, 502, { ok: false, error: "clinic_lookup_failed" });
    const clinics = await clinicResponse.json();
    const clinicId = Array.isArray(clinics) && clinics[0] && clinics[0].id;
    if (typeof clinicId !== "string" || !/^[0-9a-f-]{36}$/i.test(clinicId)) {
      return send(res, 404, { ok: false, error: "clinic_not_found" });
    }

    const prefix = "clinics/" + clinicId + "/media";
    const listResponse = await upstream("/storage/v1/object/list/" + BUCKET, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ prefix, limit: 200, sortBy: { column: "name", order: "asc" } })
    });
    if (!listResponse.ok) return send(res, 502, { ok: false, error: "media_list_failed" });
    const files = await listResponse.json();
    if (!Array.isArray(files)) return send(res, 502, { ok: false, error: "media_list_invalid" });

    const safeFiles = files.filter(item => item && item.id && typeof item.name === "string" &&
      item.name !== "." && item.name !== ".." && !/[\\/]/.test(item.name));
    const selectedFiles = safeFiles.slice(0, MAX_SIGNED_MEDIA_ITEMS);
    const items = (await Promise.all(selectedFiles.map(async item => {
      const type = inferType(item);
      if (!isSupportedMediaType(type)) return null;
      const path = prefix + "/" + item.name;
      const signResponse = await upstream("/storage/v1/object/sign/" + BUCKET + "/" + path.split("/").map(encodeURIComponent).join("/"), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ expiresIn: SIGNED_URL_TTL_SECONDS })
      });
      if (!signResponse.ok) throw new Error("signed_url_failed");
      const signed = await signResponse.json();
      const signedUrl = absoluteSignedUrl(signed && (signed.signedURL || signed.signedUrl));
      if (!signedUrl) throw new Error("signed_url_missing");
      const displayName = item.name.replace(/^\d+_/, "");
      return { name: displayName, type, url: signedUrl };
    }))).filter(Boolean);

    const data = { ok: true, clinic_slug: clinic, items };
    cache.set(clinic, { at: Date.now(), data });
    if (cache.size > 20) cache.delete(cache.keys().next().value);
    return send(res, 200, data);
  } catch (_) {
    return send(res, 502, { ok: false, error: "media_source_unavailable" });
  }
}
