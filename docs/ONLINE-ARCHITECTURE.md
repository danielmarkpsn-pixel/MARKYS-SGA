# MARKYS SGA — arquitetura online

## Ambientes independentes
- Aplicação: repositório `danielmarkpsn-pixel/MARKYS-SGA`, branch oficial `main`.
- Vercel: projeto `markyssga`, equipe `dan-markys`, raiz de aplicação `online/`.
- Supabase: projeto `MARKYS SGA`, referência `vibybosdqavejvqsuvph`.
- Região do banco: `us-west-2`.
- Nenhuma conexão, credencial, tabela ou implantação de outro produto pode ser reutilizada.

## Arquitetura
- Frontend: Vite, aplicação em `online/`.
- Autenticação: Supabase Auth, login por e-mail e senha, recuperação e convite.
- Banco: PostgreSQL com RLS habilitada e forçada nas tabelas operacionais.
- Administração: perfil Master provisionado por procedimento controlado; somente Master administra usuários.
- Perfis: `master`, `recepcao`, `profissional` e `sala`.
- Sala de espera: rota pública somente de leitura; view sanitizada sem CPF, nascimento, empresa, exames ou documentos.
- Segredos: chaves secretas apenas em Supabase Edge Function Secrets; nunca em Vite, navegador ou Git.

## Critérios de liberação
1. Baseline de perfis e migrações operacionais aplicadas no novo Supabase.
2. Edge Function administrativa implantada e limitada ao domínio oficial.
3. Variáveis públicas Vite configuradas no Vercel.
4. CI de sintaxe, segurança e build aprovado.
5. Testes reais com contas sintéticas para Master, recepção e profissional.
6. Testes negativos de RLS, usuário inativo, sessão expirada e painel público.
7. Revisão de segurança e advisors sem alertas críticos.
8. Só então cadastrar dados reais e liberar uso operacional.

## Regra de proteção
Não conectar o MARKYS SGA a projetos, bancos ou credenciais de outros sistemas. Não copiar dados reais para testes, commits, logs ou artefatos.
