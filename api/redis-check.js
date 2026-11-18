import { Redis } from "@upstash/redis";

const SUPABASE_URL = "https://qzjkoyqmjueosevzhxqa.supabase.co";
const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_jtcdZj5GJlxsbjUzKlLoFQ_u2IqjtuS";

function send(res, status, body) {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "no-store, max-age=0");
  res.end(JSON.stringify(body));
}

export default async function handler(req, res) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return send(res, 405, { ok: false, error: "method_not_allowed" });
  }

  const origin = req.headers.origin;
  const host = req.headers.host;
  if (!origin || !host) {
    return send(res, 403, { ok: false, error: "origin_required" });
  }

  try {
    if (new URL(origin).host !== host) {
      return send(res, 403, { ok: false, error: "origin_not_allowed" });
    }
  } catch {
    return send(res, 403, { ok: false, error: "origin_not_allowed" });
  }

  const authorization = req.headers.authorization || "";
  if (!authorization.startsWith("Bearer ") || authorization.length > 8192) {
    return send(res, 401, { ok: false, error: "authentication_required" });
  }

  try {
    const authResponse = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: {
        apikey: SUPABASE_PUBLISHABLE_KEY,
        Authorization: authorization,
      },
    });

    if (!authResponse.ok) {
      return send(res, 401, { ok: false, error: "invalid_session" });
    }

    const user = await authResponse.json();
    if (!user?.id) {
      return send(res, 401, { ok: false, error: "invalid_session" });
    }

    const profileUrl = new URL("/rest/v1/profiles", SUPABASE_URL);
    profileUrl.searchParams.set("id", `eq.${user.id}`);
    profileUrl.searchParams.set("select", "active,role");
    profileUrl.searchParams.set("limit", "1");

    const profileResponse = await fetch(profileUrl, {
      headers: {
        apikey: SUPABASE_PUBLISHABLE_KEY,
        Authorization: authorization,
      },
    });

    if (!profileResponse.ok) {
      return send(res, 403, { ok: false, error: "profile_check_failed" });
    }

    const profiles = await profileResponse.json();
    if (!Array.isArray(profiles) || profiles.length !== 1 || profiles[0].active !== true) {
      return send(res, 403, { ok: false, error: "active_profile_required" });
    }

    const redis = Redis.fromEnv();
    const key = `favmed:diagnostics:redis:${crypto.randomUUID()}`;
    const expected = "favmed-redis-ok";

    await redis.set(key, expected, { ex: 30 });
    const actual = await redis.get(key);
    await redis.del(key);

    if (actual !== expected) {
      return send(res, 503, { ok: false, error: "redis_roundtrip_failed" });
    }

    return send(res, 200, {
      ok: true,
      redis: "connected",
      read_write: "passed",
      ttl_seconds: 30,
      patient_data_used: false,
    });
  } catch {
    return send(res, 503, { ok: false, error: "redis_unavailable_or_configuration_error" });
  }
}
