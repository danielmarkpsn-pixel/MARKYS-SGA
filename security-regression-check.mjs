import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const html = read("./index.html");
const cloud = read("./markys-cloud.js");
const auth = read("./markys-auth.js");
const adminLogins = read("./admin-logins.html");
const finance = read("./financeiro.html");
const masterUsers = read("./supabase/functions/master-users/index.ts");
const roleMigration = read("./supabase/migrations/20261124120000_markys_sga_clinic_administration_role.sql");
const publicApi = read("./api/public-queue.js");
const publicMediaApi = read("./api/public-media.js");
const vercel = JSON.parse(read("./vercel.json"));
const { default: publicMediaHandler, inferType, isSupportedMediaType, absoluteSignedUrl } = await import("./api/public-media.js");
const migration = read("./supabase/migrations/20261123070000_require_recent_auth_for_queue_deletions.sql");
const mediaMigration = read("./supabase/migrations/20261123130000_private_tenant_media.sql");
const databaseTests = read("./supabase/tests/security_regression.sql");

assert.doesNotMatch(html, /7931/, "A senha fixa antiga não pode voltar ao frontend.");
assert.match(html, /async function authorizeDeletion\(\)/, "A confirmação de exclusão deve existir.");
assert.match(html, /signInWithPassword\(\{email,password:typed\}\)/, "A exclusão online deve exigir reautenticação.");
assert.match(cloud, /markys_sga_queue_write_tenant/, "A escrita deve usar a RPC multi-clínica.");
assert.match(auth, /professionalMode && !\["master", "profissional", "admin_clinica"\]/, "Somente Profissional, Administração e Master acessam o painel profissional.");
assert.match(auth, /!\["master", "recepcao", "admin_clinica"\]/, "Somente Recepção, Administração e Master acessam a recepção autenticada.");
assert.match(auth, /financeMode && !\["master", "admin_clinica"\]/, "Financeiro deve ser restrito à Administração e Master.");
assert.match(finance, /!\["master","admin_clinica"\]\.includes\(profile\.role\)/, "O próprio módulo financeiro deve validar Administração e Master.");
assert.match(auth, /if \(publicMode\) \{\s*cloud\.resolveAuth\(\{ role: "public_display", active: true \}\)/, "A sala de espera deve abrir sem sessão autenticada.");
assert.match(auth, /location\.pathname === "\/sala"/, "A rota pública da sala deve ser reconhecida.");
assert.match(adminLogins, /value="admin_clinica"/, "O painel Master deve permitir criar Administração da clínica.");
assert.match(auth, /adminLoginsMode && profile\.role !== "master"/, "A rota de gestão de logins deve ser exclusiva do Master.");
assert.match(adminLogins, /client\.auth\.getUser\(\)/, "A página de gestão deve validar sessão antes de carregar dados.");
assert.match(adminLogins, /profile\.role!=="master"/, "A página de gestão deve bloquear a interface para perfis não-Master.");
assert.match(masterUsers, /caller\.role !== "master"/, "A Edge Function deve continuar protegendo operações de clínicas e logins.");
assert.doesNotMatch(adminLogins, /<option value="financeiro">/, "Financeiro não pode ser uma função nova.");
assert.match(masterUsers, /new Set\(\["recepcao", "profissional", "admin_clinica"\]\)/, "A Edge Function deve aceitar somente os três perfis operacionais.");
assert.match(roleMigration, /markys_sga_queue_write_tenant/, "A migração deve atualizar a autorização da RPC de fila.");
assert.doesNotMatch(roleMigration, /\bend\s+\$;/, "Blocos DO da migração de Administração devem encerrar com delimitador SQL válido.");
assert.match(roleMigration, /revoke all on function app_private\.markys_get_queue_internal\(\) from public, anon, authenticated/i, "A RPC legada de fila não pode continuar acessível a usuários autenticados.");
assert.match(roleMigration, /regexp_replace\(v_def,[\s\S]*v_role not in[\s\S]*admin_clinica/, "As RPCs de fila devem receber o perfil Administração com validação explícita.");
assert.match(roleMigration, /Não foi possível incluir admin_clinica na autorização de exclusão da fila/, "A migração deve falhar se a permissão de exclusão não for atualizada.");
assert.match(roleMigration, /bucket_id <> 'markys-sga-documents'/, "A política restritiva de documentos não pode bloquear outros buckets.");
assert.match(roleMigration, /bucket_id <> 'markys-sga-media'/, "A política restritiva de mídia não pode bloquear outros buckets.");
assert.match(roleMigration, /drop policy if exists markys_sga_media_tenant_read/, "A política de leitura de mídia deve ser substituída para incluir Administração.");
assert.match(roleMigration, /drop policy if exists markys_sga_media_tenant_update/, "A política de atualização de mídia deve ser substituída para incluir Administração.");
assert.match(roleMigration, /role in \('master','admin_clinica'\)/, "O módulo financeiro deve ser exclusivo da Administração e Master.");
assert.match(roleMigration, /current_user_clinic_id\(\)::text/, "O acesso de Administração ao Storage deve continuar isolado por clínica.");
assert.match(cloud, /vibybosdqavejvqsuvph\.supabase\.co/, "O cliente deve apontar para o Supabase do SGA.");
assert.doesNotMatch(cloud, /qzjkoyqm/i, "O cliente não pode apontar para o projeto Supabase do FAVMED.");
assert.doesNotMatch(publicApi, /qzjkoyqm/i, "A API pública não pode apontar para o projeto Supabase do FAVMED.");
assert.doesNotMatch(publicApi, /(?:cpf|birthDate)\s*:/i, "A API pública não deve serializar CPF ou nascimento.");
assert.match(publicApi, /RATE_LIMIT_MAX = 300/, "A API pública deve limitar requisições por IP.");
assert.match(publicApi, /rate_limit_exceeded/, "A API pública deve responder 429 ao exceder o limite.");
assert.doesNotMatch(publicApi, /x-forwarded-for/, "A API não deve confiar em IP encaminhado pelo cliente.");
assert.doesNotMatch(publicMediaApi, /x-forwarded-for/, "A API de mídia não deve confiar em IP encaminhado pelo cliente.");
assert.match(publicApi, /Best-effort per-instance guard/, "O limite local não pode ser descrito como proteção distribuída.");
assert.match(publicMediaApi, /SUPABASE_SERVICE_ROLE_KEY/, "A API de mídia deve usar chave privilegiada apenas no servidor.");
assert.match(publicMediaApi, /active: "eq.true"/, "A API de mídia deve validar que a clínica está ativa.");
assert.match(publicMediaApi, /object\/sign/, "A API de mídia deve entregar URLs assinadas.");
assert.match(publicMediaApi, /MAX_SIGNED_MEDIA_ITEMS = 100/, "A API pública deve limitar quantos arquivos assina por solicitação.");
assert.match(publicMediaApi, /limit: 200/, "A listagem de mídia deve ter limite de objetos.");
assert.equal(inferType({ name: "foto.jpg" }), "image/jpeg", "JPEG .jpg deve ser aceito como image/jpeg.");
assert.equal(inferType({ name: "video.mov" }), "video/quicktime", "MOV deve ser normalizado para video/quicktime.");
assert.equal(inferType({ name: "video.m4v" }), "video/x-m4v", "M4V deve ser normalizado para video/x-m4v.");
assert.equal(isSupportedMediaType("image/jpeg"), true, "JPEG deve ser permitido na mídia pública.");
assert.equal(isSupportedMediaType("video/mp4"), true, "MP4 deve ser permitido na mídia pública.");
assert.equal(isSupportedMediaType("image/svg+xml"), false, "SVG deve ser rejeitado na mídia pública.");
assert.equal(isSupportedMediaType("application/octet-stream"), false, "Arquivos binários genéricos devem ser rejeitados.");
assert.equal(absoluteSignedUrl("/object/sign/markys-sga-media/clinics/example/media/foto.jpg?token=x"),
  "https://vibybosdqavejvqsuvph.supabase.co/storage/v1/object/sign/markys-sga-media/clinics/example/media/foto.jpg?token=x",
  "URLs relativas assinadas devem ser normalizadas para o host do Supabase do SGA.");
assert.equal(absoluteSignedUrl("https://evil.example/storage/v1/object/sign/markys-sga-media/file.jpg?token=x"), "",
  "A API não pode devolver URLs assinadas de um host externo.");
assert.equal(absoluteSignedUrl("https://vibybosdqavejvqsuvph.supabase.co/other/path"), "",
  "A API deve aceitar somente caminhos de objeto assinado do Storage.");
assert.match(cloud, /api\/public-media\?clinic=/, "A tela pública deve carregar mídia pela API isolada por clínica.");
assert.match(cloud, /createSignedUrl\("markys-sga-media"/, "O painel autenticado deve usar URLs assinadas para mídia privada.");
assert.doesNotMatch(cloud, /getPublicUrl\(path\)/, "O cliente não deve gerar URLs públicas de mídia clínica.");
assert.match(mediaMigration, /set public=false/, "O bucket de mídia clínica deve ser privado.");
assert.match(mediaMigration, /drop policy if exists markys_sga_media_public_list/i, "A listagem anônima do bucket deve ser removida.");
assert.match(html, /tus-js-client@4\.3\.1\/dist\/tus\.min\.js/, "A dependência tus precisa estar fixada.");
assert.match(migration, /auth\.jwt\(\)->>\x27auth_time\x27/, "A RPC deve validar o horário de autenticação.");
assert.match(migration, /REAUTH_REQUIRED/, "A RPC deve rejeitar exclusões sem reautenticação recente.");
assert.match(migration, /markys_sga_queue_deletion_audit/, "A exclusão deve gerar trilha de auditoria.");
assert.match(databaseTests, /Tenant isolation policy missing/, "Os testes SQL devem verificar isolamento por clínica.");
assert.match(databaseTests, /Direct access to tenant queue table must remain denied/, "Os testes SQL devem verificar acesso direto à fila.");
assert.match(databaseTests, /Clinic slideshow media bucket must be private/, "Os testes SQL devem verificar a privacidade da mídia.");
assert.match(databaseTests, /Anonymous listing of clinic slideshow media must be removed/, "Os testes SQL devem verificar a remoção da listagem anônima.");
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

const mediaMethodResponse = mockResponse();
await publicMediaHandler({ method: "POST", headers: {}, query: {} }, mediaMethodResponse);
assert.equal(mediaMethodResponse.statusCode, 405, "The public media endpoint must reject non-GET methods.");
const mediaConfigResponse = mockResponse();
await publicMediaHandler({ method: "GET", headers: {}, query: { clinic: "clinica-principal" } }, mediaConfigResponse);
assert.equal(mediaConfigResponse.statusCode, 500, "The public media endpoint must fail closed without its server-only key.");

console.log("Security regression checks passed.");
