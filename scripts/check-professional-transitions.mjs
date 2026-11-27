// Regression checks for professional attendance transitions in MARKYS SGA.
import { readFileSync } from "node:fs";
const ui = readFileSync("consultorio.html", "utf8");
const migration = readFileSync("supabase/migrations/20261127090000_markys_sga_professional_transition_guard.sql", "utf8");
const uiGuard = 'allowedTransitions={call:["Aguardando"],repeat:["Chamado"],attend:["Chamado"],cancel:["Chamado"],release:["Atendendo"]}';
if (!ui.includes(uiGuard) || !ui.includes("Ação inválida para o estado atual do atendimento")) {
  throw new Error("Guard de transição na interface profissional está ausente.");
}
for (const required of [
  "Profissional só pode alterar andamento dos atendimentos existentes",
  "v_changed_states<>1",
  "v_old_status='Aguardando' and v_new_status='Chamado'",
  "v_old_status='Chamado' and v_new_status in ('Atendendo','Aguardando','Chamado')",
  "v_old_status='Atendendo' and v_new_status='Liberado'",
  "Profissional não pode alterar serviço não vinculado ao paciente",
  "markys_sga_queue_write_tenant"
]) {
  if (!migration.includes(required)) throw new Error("Proteção SQL ausente: " + required);
}
console.log("MARKYS SGA professional transition checks passed.");
