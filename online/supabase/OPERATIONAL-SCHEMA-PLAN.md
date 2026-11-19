# MARKYS SGA — plano do schema operacional

## Tabelas
- `profiles`: identidade, perfil e estado da conta.
- `patients`: cadastro do paciente e dados administrativos.
- `professionals`: vínculo de profissionais a perfis.
- `rooms`: salas e destinos de atendimento.
- `patient_visits`: atendimento, status, prioridade, ASO e horários.
- `visit_exams`: exames individuais, sala e status.

## Autorização
- Master e recepção: administração da fila e dados administrativos conforme grants.
- Profissional: acesso aos atendimentos/exames compartilhados conforme as políticas atuais, sem alterar campos administrativos protegidos.
- Sala: acesso restrito à sala atribuída quando esse perfil for utilizado.
- Anônimo: somente leitura da view pública sanitizada.

## Armazenamento
Bucket `patient-documents` privado, PDF apenas, com políticas por perfil. Nenhum bucket público para documentos de pacientes.

## Integridade e operação
- Timestamps de início/conclusão definidos por triggers no banco.
- Conclusão de exame registrada pelo banco, não pelo navegador.
- RLS habilitada e forçada em todas as tabelas operacionais.
- Realtime somente nas tabelas necessárias à atualização das telas.
- Nenhum dado real em testes automatizados.
