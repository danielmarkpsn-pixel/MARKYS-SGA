const SUPABASE_URL = process.env.SUPABASE_URL || "https://vibybosdqavejvqsuvph.supabase.co";
const SUPABASE_PUBLISHABLE_KEY = process.env.SUPABASE_PUBLISHABLE_KEY;
const CACHE_TTL_MS = 5000;
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX = 300;
const queueCache = new Map();
// Best-effort per-instance guard. Use Vercel Firewall for distributed edge enforcement.
const rateLimits = new Map();
function clientAddress(req) {
  const realIp = req.headers["x-real-ip"];
  if (typeof realIp === "string" && realIp.trim()) return realIp.trim().slice(0, 80);
  return "unknown";
}
function isRateLimited(req) {
  const key = clientAddress(req);
  const now = Date.now();
  let entry = rateLimits.get(key);
  if (!entry || now - entry.startedAt >= RATE_LIMIT_WINDOW_MS) {
    entry = { startedAt: now, count: 0 };
  }
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
function manausDay() {
  const parts = new Intl.DateTimeFormat("en-CA", { timeZone:"America/Manaus", year:"numeric", month:"2-digit", day:"2-digit" }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map(part => [part.type,part.value]));
  return values.year+"-"+values.month+"-"+values.day;
}
function validPayload(v){return !!v&&typeof v==="object"&&Array.isArray(v.queue)&&Number.isFinite(Number(v.version))&&typeof v.clinic_id==="string"&&/^[0-9a-f-]{36}$/i.test(v.clinic_id);}
function send(res,status,body,cache="BYPASS"){
  res.statusCode=status;res.setHeader("Content-Type","application/json; charset=utf-8");
  res.setHeader("Cache-Control","no-store, max-age=0");res.setHeader("X-MARKYS-Queue-Cache",cache);res.end(JSON.stringify(body));
}
export default async function handler(req,res){
  if(req.method!=="GET"){res.setHeader("Allow","GET");return send(res,405,{ok:false,error:"method_not_allowed"});}
  if (isRateLimited(req)) {
    res.setHeader("Retry-After", "60");
    return send(res, 429, { ok: false, error: "rate_limit_exceeded" });
  }
  if(!SUPABASE_PUBLISHABLE_KEY)return send(res,500,{ok:false,error:"sga_supabase_key_not_configured"});
  const day=manausDay();
  const clinic=typeof req.query?.clinic==="string"?req.query.clinic:"clinica-principal";
  if(!/^[a-z0-9-]{1,80}$/.test(clinic))return send(res,400,{ok:false,error:"invalid_clinic_slug"});
  const cached=queueCache.get(clinic);
  if(cached&&cached.day===day&&Date.now()-cached.at<CACHE_TTL_MS)return send(res,200,cached.data,"HIT");
  let upstream;
  try{upstream=await fetch(SUPABASE_URL+"/rest/v1/rpc/markys_sga_public_queue_tenant",{method:"POST",headers:{apikey:SUPABASE_PUBLISHABLE_KEY,"Content-Type":"application/json"},body:JSON.stringify({p_day:day,p_clinic_slug:clinic}),cache:"no-store"});}
  catch(_){return send(res,502,{ok:false,error:"queue_source_unavailable"});}
  if(!upstream.ok)return send(res,502,{ok:false,error:"queue_source_rejected_request"});
  let payload;try{payload=await upstream.json();}catch(_){return send(res,502,{ok:false,error:"queue_source_invalid_response"});}
  if(!validPayload(payload)||payload.clinic_slug!==clinic)return send(res,502,{ok:false,error:"queue_source_invalid_payload"});
  queueCache.set(clinic,{day,data:payload,at:Date.now()});
  if(queueCache.size>20)queueCache.delete(queueCache.keys().next().value);
  return send(res,200,payload,"MISS");
}