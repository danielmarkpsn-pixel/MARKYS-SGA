import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const html = read("./index.html");
const cloud = read("./markys-cloud.js");
const publicApi = read("./api/public-queue.js");
const vercel = JSON.parse(read("./vercel.json"));
const migration = read("./supabase/migrations/20261123070000_require_recent_auth_for_queue_deletions.sql");
const databaseTests = read("./supabase/tests/security_regression.sql");

assert.doesNotMatch(html, /7931/, "A senha fixa antiga não pode voltar ao frontend.");
assert.match(html, /async function authorizeDeletion\(\)/, "A confirmação de exclusão deve existir.");
assert.match(html, /signInWithPassword\(\{email,password:typed\}\)/, "A exclusão online deve exigir reautenticação.");
assert.match(cloud, /markys_sga_queue_write_tenant/, "A escrita deve usar a RPC multi-clínica.");
assert.match(cloud, /vibybosdqavejvqsuvph\.supabase\.co/, "O cliente deve apontar para o Supabase do SGA.");
assert.doesNotMatch(cloud, /qzjkoyqm/i, "O cliente não pode apontar para o projeto Supabase do FAVMED.");
assert.doesNotMatch(publicApi, /qzjkoyqm/i, "A API pública não pode apontar para o projeto Supabase do FAVMED.");
assert.doesNotMatch(publicApi, /(?:cpf|birthDate)\s*:/i, "A API pública não deve serializar CPF ou nascimento.");
assert.match(publicApi, /RATE_LIMIT_MAX = 300/, "A API pública deve limitar requisições por IP.");
assert.match(publicApi, /rate_limit_exceeded/, "A API pública deve responder 429 ao exceder o limite.");
assert.match(publicApi, /Best-effort per-instance guard/, "O limite local não pode ser descrito como proteção distribuída.");
assert.match(html, /tus-js-client@4\.3\.1\/dist\/tus\.min\.js/, "A dependência tus precisa estar fixada.");
assert.match(migration, /auth\.jwt\(\)->>\x27auth_time\x27/, "A RPC deve validar o horário de autenticação.");
assert.match(migration, /REAUTH_REQUIRED/, "A RPC deve rejeitar exclusões sem reautenticação recente.");
assert.match(migration, /markys_sga_queue_deletion_audit/, "A exclusão deve gerar trilha de auditoria.");
assert.match(databaseTests, /Tenant isolation policy missing/, "Os testes SQL devem verificar isolamento por clínica.");
assert.match(databaseTests, /Direct access to tenant queue table must remain denied/, "Os testes SQL devem verificar acesso direto à fila.");
assert.equal(existsSync(new URL("./api/redis-check.js", import.meta.url)), false,
  "O endpoint redis-check não deve existir na raiz do SGA.");

const headers = new Map(vercel.headers[0].headers.map(({ key, value }) => [key.toLowerCase(), value]));
for (const key of ["content-security-policy", "x-content-type-options", "x-frame-options",
  "referrer-policy", "permissions-policy", "strict-transport-security"]) {
  assert.ok(headers.has(key), `Cabeçalho de segurança ausente: ${key}`);
}
const csp = headers.get("content-security-policy");
for (const directive of ["default-src 'self'", "object-src 'none'", "base-uri 'self'",
  "frame-ancestors 'self'", "frame-src 'self' https:"]) {
  assert.ok(csp.includes(directive), `Diretiva CSP ausente: ${directive}`);
}

delete process.env.SUPABASE_PUBLISHABLE_KEY;
const { default: publicQueueHandler } = await import("./api/public-queue.js");
function mockResponse() {
  return {
    statusCode: 200,
    headers: {},
    body: "",
    setHeader(name, value) { this.headers[name.toLowerCase()] = value; },
    end(body) { this.body = body; }
  };
}
for (let i = 0; i < 300; i += 1) {
  const response = mockResponse();
  await publicQueueHandler({ method: "GET", headers: { "x-real-ip": "192.0.2.77" }, query: {} }, response);
  assert.equal(response.statusCode, 500, "Requests below the configured limit should reach normal configuration checks.");
}
const limitedResponse = mockResponse();
await publicQueueHandler({ method: "GET", headers: { "x-real-ip": "192.0.2.77" }, query: {} }, limitedResponse);
assert.equal(limitedResponse.statusCode, 429, "The 301st request from one IP must be throttled.");
assert.equal(limitedResponse.headers["retry-after"], "60", "Rate-limited clients need a Retry-After header.");

console.log("Security regression checks passed.");
