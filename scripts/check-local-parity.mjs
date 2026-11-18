import { readFileSync } from "node:fs";
import vm from "node:vm";

const htmlFiles = ["index.html", "consultorio.html", "importar-backup.html"];
for (const file of htmlFiles) {
  const source = readFileSync(file, "utf8");
  const scripts = source.split("<script").slice(1).map(block => {
    const openEnd = block.indexOf(">");
    const closeStart = block.indexOf("</script>");
    return openEnd >= 0 && closeStart >= 0 ? block.slice(openEnd + 1, closeStart) : "";
  }).filter(code => code.trim());
  for (let index = 0; index < scripts.length; index += 1) {
    new vm.Script(scripts[index], { filename: file + "#script-" + index });
  }
}

const reception = readFileSync("index.html", "utf8");
const professional = readFileSync("consultorio.html", "utf8");
const cloud = readFileSync("favmed-cloud.js", "utf8");
const auth = readFileSync("favmed-auth.js", "utf8");

for (const id of ["patientForm", "patientList", "calledDisplay", "publicScreen", "slideshowFiles", "visualizarFicha", "clearToday"]) {
  if (!reception.includes('id="' + id + '"')) throw new Error("Tela local da recepção perdeu o elemento " + id);
}
if (!professional.includes("FAVMED — Painel do profissional")) throw new Error("Painel profissional local não encontrado.");
if (!reception.includes("FAVMED_LOCAL_MODE") || !professional.includes("FAVMED_LOCAL_MODE") || !auth.includes("if (localMode)")) {
  throw new Error("O modo local precisa continuar sem autenticação.");
}
for (const rpc of ["favmed_get_queue", "favmed_update_queue_patient"]) {
  if (!cloud.includes(rpc)) throw new Error("Integração Supabase ausente: " + rpc);
}
for (const feature of ["uploadPatientDocument", "listSlideshow", "uploadSlideshow"]) {
  if (!cloud.includes(feature)) throw new Error("Integração Storage ausente: " + feature);
}
if (cloud.includes("data && data.path") || !cloud.includes("const storedPath = path;")) {
  throw new Error("O envio de documentos deve usar o caminho de Storage gerado antes do upload.");
}
if (!cloud.includes('conflict.code = "QUEUE_CONFLICT"') ||
    !cloud.includes('if (error && error.code === "QUEUE_CONFLICT")')) {
  throw new Error("Conflitos da fila devem invalidar o snapshot local para impedir novas gravações desatualizadas.");
}
if (!reception.includes('e.code==="QUEUE_CONFLICT"') ||
    !reception.includes('patients=await window.FAVMED_CLOUD.readQueue({publicMode:false})') ||
    !professional.includes('e.code==="QUEUE_CONFLICT"') ||
    !professional.includes('patients=await readQueue()')) {
  throw new Error("Recepção e profissional devem recarregar a fila após conflito de concorrência.");
}
if (!cloud.includes('rpc("favmed_update_queue_patients"') ||
    !cloud.includes('p_changes: changes.map') ||
    !cloud.includes('if (!isMissingRpc(error)) throw error;')) {
  throw new Error("As alterações da fila devem usar gravação em lote e manter compatibilidade com bancos sem a nova RPC.");
}
const batchMigration = readFileSync("supabase/migrations/20261112000000_favmed_queue_batch_writes.sql", "utf8");
for (const required of [
  "favmed_update_queue_patients",
  "pg_advisory_xact_lock",
  "QUEUE_CONFLICT",
  "jsonb_agg",
  "v_new_version := v_version + 1",
  "revoke all on function public.favmed_update_queue_patients(jsonb) from public, anon",
  "grant execute on function public.favmed_update_queue_patients(jsonb) to authenticated"
]) {
  if (!batchMigration.includes(required)) throw new Error("Migração de gravação em lote ausente ou incompleta: " + required);
}
if (reception.includes("dashboard-shell") || reception.includes("createRoot(")) {
  throw new Error("A interface reconstruída da pasta online não pode substituir a tela local.");
}

const dailyMigration = readFileSync("online/supabase/migrations/20261103153000_daily_queue_partition_and_cleanup.sql", "utf8");
for (const required of ["favmed_queue_days", "America/Manaus", "favmed_daily_cleanup", "33554432", "favmed-daily-reset"]) {
  if (!dailyMigration.includes(required)) throw new Error("Rotina diária ausente ou incompleta: " + required);
}
if (!dailyMigration.includes("delete from public.visit_exams") || !dailyMigration.includes("delete from public.patient_visits") || !dailyMigration.includes("delete from public.patients")) {
  throw new Error("A limpeza inicial dos dados antigos não está registrada na migração.");
}

const waitingRoomMigration = readFileSync("online/supabase/migrations/20261103180000_reception_waiting_room_access.sql", "utf8");
for (const required of ["v_role is null or v_role not in ('master', 'recepcao')", "security definer", "revoke all on function public.favmed_get_public_queue(text) from public, anon", "grant execute on function public.favmed_get_public_queue(text) to authenticated"]) {
  if (!waitingRoomMigration.includes(required)) throw new Error("Acesso seguro da sala de espera ausente ou incompleto: " + required);
}
for (const required of [
  'if (publicMode) {',
  'role: "public_display"',
  'cloud.resolveAuth({ role: "public_display", active: true })'
]) {
  if (!auth.includes(required)) throw new Error("A sala de espera deve abrir sem login: " + required);
}
for (const required of [
  'fetch("/api/public-queue", {',
  'cache: "no-store"',
  'credentials: "same-origin"'
]) {
  if (!cloud.includes(required)) throw new Error("A leitura pública da fila pelo endpoint com cache está ausente: " + required);
}
const publicQueueApi = readFileSync("api/public-queue.js", "utf8");
for (const required of [
  "Redis.fromEnv()",
  "CACHE_TTL_SECONDS",
  "favmed_get_public_queue",
  "validPayload",
  'cacheKey + ":refresh-lock"',
  "nx: true",
  "refreshLockContended",
  "attempt < 5"
]) {
  if (!publicQueueApi.includes(required)) throw new Error("O endpoint público da fila não possui a proteção esperada: " + required);
}
const publicDisplayMigration = readFileSync("online/supabase/migrations/20261106163834_public_waiting_room_display.sql", "utf8");
const publicDisplayGrantMigration = readFileSync("online/supabase/migrations/20261106164044_limit_waiting_room_rpc_to_anon.sql", "utf8");
if (!publicDisplayGrantMigration.includes("from authenticated") || !publicDisplayGrantMigration.includes("to anon")) {
  throw new Error("A RPC pública da sala deve ser acessível somente ao cliente anônimo dedicado.");
}
for (const required of [
  "if auth.uid() is not null then",
  "grant execute on function public.favmed_get_public_queue(text) to anon, authenticated",
  "p_day <> v_today::text",
  "'name', p.value->'name'",
  "'room', p.value->'room'"
]) {
  if (!publicDisplayMigration.includes(required)) throw new Error("Acesso público limitado da sala de espera ausente: " + required);
}
for (const forbidden of ["'cpf'", "'birthDate'", "'insurance'", "'document'"]) {
  if (publicDisplayMigration.includes(forbidden)) throw new Error("A fila pública não pode expor dados pessoais: " + forbidden);
}

console.log("FAVMED local parity checks passed.");
