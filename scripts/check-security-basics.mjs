// MARKYS SGA — verificações básicas de segurança e consistência (rodam no CI).
// Falha (exit 1) quando encontra algo que já causou ou poderia causar problema:
//  1. senha ou código de autorização fixo no código do navegador;
//  2. chave secreta ou JWT no repositório;
//  3. referência a outro projeto Supabase (o SGA tem projeto exclusivo);
//  4. pacote importado em api/ que não está declarado no package.json;
//  5. cabeçalhos de segurança ausentes no vercel.json.
// Não substitui testes reais de RLS e de sessão em um banco de testes.
import { execFileSync } from "node:child_process";
import { readFileSync, existsSync } from "node:fs";
import { builtinModules } from "node:module";

const ALLOWED_SUPABASE_REFS = new Set(["vibybosdqavejvqsuvph"]);
const SELF = "scripts/check-security-basics.mjs";
const BINARY = /\.(zip|png|jpe?g|gif|webp|svg|mp3|mp4|webm|ico|woff2?)$/i;

const files = execFileSync("git", ["ls-files"], { encoding: "utf8" })
  .split("\n")
  .filter(f => f && f !== SELF && !BINARY.test(f));

const problems = [];
const fail = (file, line, message) => problems.push(`${file}${line ? ":" + line : ""} — ${message}`);

function eachLine(text, callback) {
  text.split("\n").forEach((content, index) => callback(content, index + 1));
}

const rules = [
  {
    // Ex.: password !== "1234", senha == '1234'
    regex: /\b(password|senha|pass|pin|passcode)\w*\s*[!=]==?\s*["'`][^"'`]{2,}["'`]/i,
    only: /\.(html|js|mjs|ts)$/i,
    message: "senha ou código fixo comparado no código; a autorização deve ser feita no servidor ou com a conta do usuário",
  },
  {
    regex: /sb_secret_[A-Za-z0-9_-]{10,}/,
    message: "chave secreta do Supabase no repositório",
  },
  {
    regex: /\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}/,
    message: "possível JWT (token ou chave) no repositório",
  },
  {
    regex: /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
    message: "chave privada no repositório",
  },
];

const refPattern = /\b([a-z0-9]{20})\.(?:storage\.)?supabase\.(?:co|in)\b/g;

for (const file of files) {
  if (!existsSync(file)) continue;
  let text;
  try {
    text = readFileSync(file, "utf8");
  } catch {
    continue;
  }
  eachLine(text, (content, number) => {
    for (const rule of rules) {
      if (rule.only && !rule.only.test(file)) continue;
      if (rule.regex.test(content)) fail(file, number, rule.message);
    }
    for (const match of content.matchAll(refPattern)) {
      if (!ALLOWED_SUPABASE_REFS.has(match[1])) {
        fail(file, number, `projeto Supabase não autorizado (${match[1]}); use somente o projeto do MARKYS SGA`);
      }
    }
  });
}

// 4. Dependências usadas em api/ precisam estar declaradas.
const pkg = JSON.parse(readFileSync("package.json", "utf8"));
const declared = new Set([
  ...Object.keys(pkg.dependencies || {}),
  ...Object.keys(pkg.devDependencies || {}),
]);
const builtins = new Set([...builtinModules, ...builtinModules.map(name => "node:" + name)]);
for (const file of files.filter(f => /^api\/.+\.(js|mjs|ts)$/.test(f))) {
  const text = readFileSync(file, "utf8");
  const specifiers = [
    ...text.matchAll(/\bimport\s[^"'`]*?from\s*["']([^"']+)["']/g),
    ...text.matchAll(/\bimport\s*["']([^"']+)["']/g),
    ...text.matchAll(/\brequire\(\s*["']([^"']+)["']\s*\)/g),
  ].map(match => match[1]);
  for (const specifier of specifiers) {
    if (specifier.startsWith(".") || specifier.startsWith("/") || builtins.has(specifier)) continue;
    const name = specifier.startsWith("@") ? specifier.split("/").slice(0, 2).join("/") : specifier.split("/")[0];
    if (!declared.has(name)) fail(file, 0, `importa "${name}", que não está declarado no package.json (o deploy vai falhar)`);
  }
}

// 5. Cabeçalhos de segurança obrigatórios.
const vercel = JSON.parse(readFileSync("vercel.json", "utf8"));
const headerMap = new Map();
for (const block of vercel.headers || []) {
  if (block.source !== "/(.*)") continue;
  for (const header of block.headers || []) headerMap.set(String(header.key).toLowerCase(), String(header.value));
}
for (const required of [
  "content-security-policy",
  "x-content-type-options",
  "x-frame-options",
  "referrer-policy",
  "permissions-policy",
  "strict-transport-security",
]) {
  if (!headerMap.has(required)) fail("vercel.json", 0, `cabeçalho de segurança ausente: ${required}`);
}
const csp = headerMap.get("content-security-policy") || "";
for (const directive of ["script-src", "connect-src", "object-src 'none'", "base-uri", "frame-ancestors"]) {
  if (csp && !csp.includes(directive)) fail("vercel.json", 0, `CSP sem a diretiva ${directive}`);
}

if (problems.length) {
  console.error("Verificação de segurança do MARKYS SGA falhou:\n- " + problems.join("\n- "));
  process.exit(1);
}
console.log(`Verificação de segurança do MARKYS SGA aprovada (${files.length} arquivos rastreados analisados).`);
