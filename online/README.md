# MARKYS SGA Online

Aplicação online independente do MARKYS SGA. O modo local em HTML/PowerShell continua separado e não inicializa conexão Supabase. A aplicação Vite em `online/` é a única aplicação publicada no Vercel.

## Ambientes exclusivos
- GitHub: `danielmarkpsn-pixel/MARKYS-SGA`, branch oficial `main`.
- Vercel: projeto `markyssga`, equipe `dan-markys`, diretório raiz `online/`.
- URL: https://markyssga.vercel.app/
- Supabase: projeto `MARKYS SGA`, ref `vibybosdqavejvqsuvph`.
- URL Supabase: https://vibybosdqavejvqsuvph.supabase.co

## Executar localmente
1. Copie `.env.example` para `.env.local`.
2. Preencha `VITE_SUPABASE_URL` e `VITE_SUPABASE_PUBLISHABLE_KEY` com os valores públicos do projeto MARKYS SGA.
3. Dentro desta pasta (`online`), execute `npm install` e `npm run dev`.
4. Valide com `npm run check` e `npm run build`.

Nunca coloque chaves secret/service_role no frontend, em variáveis `VITE_*` ou no Git. Variáveis `VITE_*` são incorporadas ao código entregue ao navegador e só podem conter valores públicos.

## Módulos e perfis
- `/master`: administração de contas; somente Master ativo.
- `/recepcao`: cadastro, fila, prioridade, ASO, documentos e configuração de salas.
- `/profissional`: fila e status de atendimentos/exames conforme permissões RLS.
- `/sala`: painel público de chamadas, sem login e somente leitura.

A tela pública consulta `public.public_waiting_room_calls`. A view usa `security_invoker=true`; o papel `anon` recebe somente colunas necessárias, com políticas RLS limitadas às chamadas do dia. Nome completo, CPF, empresa, exames e documentos não são expostos.

## Estado do novo banco
- PostgreSQL 17 ativo na região `us-west-2`.
- Seis tabelas operacionais criadas: `profiles`, `patients`, `professionals`, `rooms`, `patient_visits` e `visit_exams`.
- RLS habilitada nas seis tabelas.
- Três salas de recepção iniciais cadastradas.
- Bucket privado `patient-documents`.
- Edge Function `master-users` implantada com validação manual do token e CORS restrito.
- Migrações versionadas aplicadas ao projeto novo. Não há dados de pacientes de produção.
- O primeiro usuário Master ainda precisa ser provisionado; consulte [MASTER-BOOTSTRAP.md](supabase/MASTER-BOOTSTRAP.md).

## Validação
O build Vercel executa `npm run check && npm run build`. Os testes estáticos verificam os guardrails de autenticação, CORS, RLS, view pública e integridade de exames. A auditoria Supabase atual não apresenta alertas de segurança. Permanecem avisos informativos de índices ainda não usados porque o banco está vazio.

Antes de inserir dados reais, validar login real, convite, bloqueio, recuperação de senha e os fluxos completos com contas sintéticas de Master, recepção e profissional.

## Migrações
As migrações em `supabase/migrations/` são a fonte versionada do schema online. O banco remoto já recebeu a baseline, a estrutura operacional, os ajustes de integridade, permissões, Realtime, proteção da tela pública e consolidação de políticas. Migrações da antiga fila JSON e buckets de mídia foram excluídas do diretório de migrações online porque não são usadas por esta aplicação.
