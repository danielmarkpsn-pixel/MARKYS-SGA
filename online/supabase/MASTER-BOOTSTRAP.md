# Provisionamento do primeiro Master — MARKYS SGA

## Ambiente
- Supabase: `MARKYS SGA`
- Project ref: `vibybosdqavejvqsuvph`
- Aplicação: https://markyssga.vercel.app/
- Edge Function: `master-users`, ativa, com `verify_jwt=false` porque valida o Bearer token no próprio código.

## Estado
O schema e a Edge Function estão implantados. Nenhuma conta Master foi criada automaticamente. Não há senha padrão ou credencial administrativa gravada no repositório.

## Criar o primeiro usuário
1. No Supabase, abra Authentication → Users.
2. Use Add user para criar/convidar o endereço de e-mail que será o administrador inicial. Não habilite cadastro público.
3. Confirme o UUID do usuário criado.
4. No SQL Editor do projeto MARKYS SGA, execute o comando abaixo, substituindo os dois valores indicados.

```sql
insert into public.profiles (id, display_name, role, active)
select
  id,
  'NOME DO ADMINISTRADOR',
  'master',
  true
from auth.users
where lower(email) = lower('EMAIL_DO_MASTER')
on conflict (id) do update
set display_name = excluded.display_name,
    role = 'master',
    active = true;
```

5. Confirme que exatamente um perfil Master ativo foi criado:
```sql
select id, display_name, role, active
from public.profiles
where role = 'master';
```
6. Acesse https://markyssga.vercel.app/master e teste o login.
7. Depois de entrar, crie usuários de Recepção e Profissional pela administração Master.

## Regras de segurança
- Não criar segundo Master sem aprovação.
- Não usar senha padrão compartilhada.
- Não expor `service_role` ou `sb_secret_*` no navegador, em variáveis `VITE_*` ou no Git.
- A Edge Function valida token Bearer, perfil Master ativo e CORS exato.
- Usuários comuns são criados somente pelo Master; cadastro público permanece desativado.
- Testar bloqueio de usuário inativo e acesso negado para perfis não-Master antes de liberar a operação.
