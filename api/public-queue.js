const SUPABASE_URL = process.env.SUPABASE_URL || "https://vibybosdqavejvqsuvph.supabase.co";
const SUPABASE_PUBLISHABLE_KEY = process.env.SUPABASE_PUBLISHABLE_KEY;
const CACHE_TTL_MS = 5000;
let cachedPayload = null;
let cachedAt = 0;
function manausDay() {
  const parts = new Intl.DateTimeFormat("en-CA", { timeZone:"America/Manaus", year:"numeric", month:"2-digit", day:"2-digit" }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map(part => [part.type,part.value]));
  return values.year+"-"+values.month+"-"+values.day;
}
function validPayload(v){return !!v&&typeof v==="object"&&Array.isArray(v.queue)&&Number.isFinite(Number(v.version));}
function send(res,status,body,cache="BYPASS"){
  res.statusCode=status;res.setHeader("Content-Type","application/json; charset=utf-8");
  res.setHeader("Cache-Control","no-store, max-age=0");res.setHeader("X-MARKYS-Queue-Cache",cache);res.end(JSON.stringify(body));
}
export default async function handler(req,res){
  if(req.method!=="GET"){res.setHeader("Allow","GET");return send(res,405,{ok:false,error:"method_not_allowed"});}
  if(!SUPABASE_PUBLISHABLE_KEY)return send(res,500,{ok:false,error:"sga_supabase_key_not_configured"});
  const day=manausDay();
  if(cachedPayload&&cachedPayload.day===day&&Date.now()-cachedAt<CACHE_TTL_MS)return send(res,200,cachedPayload.data,"HIT");
  let upstream;
  try{upstream=await fetch(SUPABASE_URL+"/rest/v1/rpc/markys_get_public_queue",{method:"POST",headers:{apikey:SUPABASE_PUBLISHABLE_KEY,"Content-Type":"application/json"},body:JSON.stringify({p_day:day}),cache:"no-store"});}
  catch(_){return send(res,502,{ok:false,error:"queue_source_unavailable"});}
  if(!upstream.ok)return send(res,502,{ok:false,error:"queue_source_rejected_request"});
  let payload;try{payload=await upstream.json();}catch(_){return send(res,502,{ok:false,error:"queue_source_invalid_response"});}
  if(!validPayload(payload))return send(res,502,{ok:false,error:"queue_source_invalid_payload"});
  cachedPayload={day,data:payload};cachedAt=Date.now();return send(res,200,payload,"MISS");
}