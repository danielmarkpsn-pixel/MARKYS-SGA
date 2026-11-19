# MARKYS SGA — histórico e reconciliação do schema

## Projeto remoto
- Supabase `MARKYS SGA`, ref `vibybosdqavejvqsuvph`.
- PostgreSQL 17, região `us-west-2`.
- Banco criado em 19/11/2026, inicialmente sem tabelas operacionais.
- A baseline e as migrações abaixo foram aplicadas diretamente ao projeto novo e registradas no histórico remoto.

## Migrações aplicadas
1. `markys_sga_profiles_baseline`
2. `restore_service_role_profiles_privileges`
3. `operational_foundation`
4. `visit_timestamp_integrity`
5. `public_waiting_room`
6. `visit_called_status`
7. `reception_workflow_fields`
8. `patient_documents_storage`
9. `visit_exam_called_status`
10. `public_calls_without_exams`
11. `reception_multisala_and_call_stations`
12. `professional_shared_queue_read_access`
13. `shared_queue_privileges_and_rls`
14. `reception_room_professional_alignment`
15. `professionals_all_rooms_access`
16. `enable_operational_realtime`
17. `public_waiting_room_security_invoker`
18. `consolidate_rls_policies`

## Estrutura verificada
Tabelas públicas:
- `profiles`
- `patients`
- `professionals`
- `rooms`
- `patient_visits`
- `visit_exams`

RLS está habilitada nas seis tabelas. O banco contém três salas de recepção iniciais e nenhum cadastro de paciente.

## Tela pública
A view `public_waiting_room_calls` foi alterada para `security_invoker=true`. A role `anon` não tem SELECT de tabela em `patients`; recebe apenas SELECT nas colunas `id` e `public_display_name`. Também não recebe colunas de CPF, empresa ou nome de exames. Políticas RLS limitam as linhas às chamadas ativas do dia.

## Migrações excluídas do diretório online
A fila JSON antiga, RPCs `favmed_*` e buckets de mídia antigos não são usados pelo frontend Vite. Foram removidos do diretório `online/supabase/migrations` para evitar que uma futura execução de `supabase db push` crie estruturas desnecessárias. O banco novo não recebeu essas estruturas.

## Regras para mudanças futuras
- Não apagar nem editar migrações já aplicadas; adicionar novas migrações incrementais.
- Aplicar migrações em ordem e conferir o histórico remoto após cada lote.
- Toda tabela exposta no schema `public` precisa de RLS e políticas específicas.
- Não usar SECURITY DEFINER em views. Funções privilegiadas devem ficar em schema não exposto e validar a identidade quando aplicável.
- Não inserir dados reais antes dos testes de autenticação e autorização com contas sintéticas.
