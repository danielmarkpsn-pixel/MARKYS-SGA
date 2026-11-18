import { Redis } from "@upstash/redis";

const SUPABASE_URL = "https://qzjkoyqmjueosevzhxqa.supabase.co";
const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_jtcdZj5GJlxsbjUzKlLoFQ_u2IqjtuS";
const CACHE_TTL_SECONDS = 5;

function send(res, status, body, cacheStatus) {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "no-store, max-age=0");
  res.setHeader("X-FAVMED-Redis-Cache", cacheStatus || "BYPASS");
  res.end(JSON.stringify(body));
}

function manausDay() {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Manaus",
    year: "numeric",
    month: "2-digit",
    day: "2-digit"
  }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map(part => [part.type, part.value]));
  return values.year + "-" + values.month + "-" + values.day;
}

function validPayload(value) {
  return !!value && typeof value === "object" &&
    Array.isArray(value.queue) && Number.isFinite(Number(value.version));
}

export default async function handler(req, res) {
  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return send(res, 405, { ok: false, error: "method_not_allowed" });
  }

  const day = manausDay();
  const cacheKey = "favmed:public-queue:v1:" + day;
  let redis = null;

  try {
    redis = Redis.fromEnv();
  } catch (_) {
    // Redis is an optimization only. Supabase remains the source of truth.
  }

  if (redis) {
    try {
      const cached = await redis.get(cacheKey);
      const payload = typeof cached === "string" ? JSON.parse(cached) : cached;
      if (validPayload(payload)) {
        return send(res, 200, payload, "HIT");
      }
    } catch (_) {
      // A cache read/parse failure must never prevent the Supabase fallback.
    }
  }

  // Coalesce simultaneous cache misses so several waiting-room displays do
  // not all query Supabase for the same snapshot at once. The short lock does
  // not extend the cache lifetime or delay normal single requests.
  let refreshLockAcquired = false;
  let refreshLockContended = false;
  if (redis) {
    try {
      const lockResult = await redis.set(cacheKey + ":refresh-lock", "1", { nx: true, ex: 3 });
      refreshLockAcquired = lockResult === "OK";
      refreshLockContended = !refreshLockAcquired;
    } catch (_) {
      // Lock failures are non-fatal; continue with the normal Supabase fallback.
    }
  }

  if (redis && refreshLockContended) {
    for (let attempt = 0; attempt < 5; attempt += 1) {
      await new Promise(resolve => setTimeout(resolve, 100));
      try {
        const cached = await redis.get(cacheKey);
        const payload = typeof cached === "string" ? JSON.parse(cached) : cached;
        if (validPayload(payload)) {
          return send(res, 200, payload, "HIT");
        }
      } catch (_) {
        // Retry briefly, then fall back to Supabase if the cache is still empty.
      }
    }
  }

  let upstream;
  try {
    upstream = await fetch(SUPABASE_URL + "/rest/v1/rpc/favmed_get_public_queue", {
      method: "POST",
      headers: {
        apikey: SUPABASE_PUBLISHABLE_KEY,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ p_day: day }),
      cache: "no-store"
    });
  } catch (_) {
    return send(res, 502, { ok: false, error: "queue_source_unavailable" }, redis ? "MISS" : "BYPASS");
  }

  if (!upstream.ok) {
    return send(res, 502, { ok: false, error: "queue_source_rejected_request" }, redis ? "MISS" : "BYPASS");
  }

  let payload;
  try {
    payload = await upstream.json();
  } catch (_) {
    return send(res, 502, { ok: false, error: "queue_source_invalid_response" }, redis ? "MISS" : "BYPASS");
  }

  if (!validPayload(payload)) {
    return send(res, 502, { ok: false, error: "queue_source_invalid_payload" }, redis ? "MISS" : "BYPASS");
  }

  let cacheStatus = "BYPASS";
  if (redis) {
    try {
      await redis.set(cacheKey, JSON.stringify(payload), { ex: CACHE_TTL_SECONDS });
      cacheStatus = "MISS";
    } catch (_) {
      // Redis write failure is non-fatal; the live Supabase result is still returned.
      cacheStatus = "BYPASS";
    }
  }

  return send(res, 200, payload, cacheStatus);
}
