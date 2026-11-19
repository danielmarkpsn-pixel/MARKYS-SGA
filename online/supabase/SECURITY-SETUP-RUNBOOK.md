# MARKYS SGA — runbook de segurança pré-produção

## Projeto
Supabase `MARKYS SGA` — `vibybosdqavejvqsuvph`.

## Segredos e variáveis
- Vercel: `VITE_SUPABASE_URL` e `VITE_SUPABASE_PUBLISHABLE_KEY` (valores públicos).
- Supabase Edge Function: chave de serviço/secret somente em Secrets gerenciados pelo Supabase.
- Nunca colocar `service_role`, `sb_secret_*`, senha ou token em `VITE_*`, no frontend ou no Git.

## Autenticação
- Cadastro público desativado.
- Login anônimo desativado.
- Master inicial provisionado por procedimento administrativo controlado.
- Usuários comuns criados somente pelo Master via Edge Function.
- Confirmar URLs de redirecionamento para o domínio oficial.
- SMTP e entrega de convites devem ser testados antes de convidar usuários.

## CORS da Edge Function
A função `master-users` aceita somente a origem oficial `https://markyssga.vercel.app`, o preview protegido `https://markyssga-git-setup-markys-sga-cloud-dan-markys.vercel.app` e `http://localhost:5173` para desenvolvimento. Não usar CORS curinga. Atualize a lista somente quando um domínio adicional for aprovado.

## Testes obrigatórios
- Sem sessão/token inválido: HTTP 401.
- Perfil diferente de Master: HTTP 403.
- Master inativo: HTTP 403.
- Origem não autorizada: HTTP 403.
- E-mail já cadastrado: HTTP 409, sem perfil duplicado.
- Limite de envio de convites: HTTP 429, sem repetição automática.
- Profissional não acessa registros fora das permissões definidas.
- Tela pública recebe somente nome abreviado, sala e horário da chamada.
- Conta inativa não acessa dados operacionais, inclusive com sessão antiga.

## Liberação
Não inserir dados reais até CI, testes com sessões reais de cada perfil, revisão RLS e Security Advisor aprovados. Manter plano de rollback e backups antes de mudanças de schema.
