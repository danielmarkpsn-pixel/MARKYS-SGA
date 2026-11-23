import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const html = read("./index.html");
const cloud = read("./markys-cloud.js");
const publicApi = read("./api/public-queue.js");
const vercel = JSON.parse(read("./vercel.json"));

assert.doesNotMatch(html, /7931/, "A senha fixa antiga não pode voltar ao frontend.");
assert.match(html, /async function authorizeDeletion\(\)/, "A confirmação de exclusão deve existir.");
assert.match(html, /signInWithPassword\(\{email,password:typed\}\)/, "A exclusão online deve exigir reautenticação.");
assert.match(cloud, /markys_sga_queue_write_tenant/, "A escrita deve usar a RPC multi-clínica.");
assert.match(cloud, /vibybosdqavejvqsuvph\.supabase\.co/, "O cliente deve apontar para o Supabase do SGA.");
assert.doesNotMatch(cloud, /qzjkoyqm/i, "O cliente não pode apontar para o projeto Supabase do FAVMED.");
assert.doesNotMatch(publicApi, /qzjkoyqm/i, "A API pública não pode apontar para o projeto Supabase do FAVMED.");
assert.doesNotMatch(publicApi, /(?:cpf|birthDate)\s*:/i, "A API pública não deve serializar CPF ou nascimento.");
assert.match(html, /tus-js-client@4\.3\.1\/dist\/tus\.min\.js/, "A dependência tus precisa estar fixada.");
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
console.log("Security regression checks passed.");
