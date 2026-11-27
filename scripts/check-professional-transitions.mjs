// Regression checks for professional attendance transitions in MARKYS SGA.
import { readFileSync } from "node:fs";
const ui = readFileSync("consultorio.html", "utf8");
const migration = readFileSync("supabase/migrations/20261127100000_markys_sga_professional_transition_service_validation_fix.sql", "utf8");
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
  "v_service=any(array(select trim(item) from unnest(string_to_array(v_current->>'service',',')) as split(item)))",
  "markys_sga_queue_write_tenant"
]) {
  if (!migration.includes(required)) throw new Error("Proteção SQL ausente: " + required);
}
console.log("MARKYS SGA professional transition checks passed.");
