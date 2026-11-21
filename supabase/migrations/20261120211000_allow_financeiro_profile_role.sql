-- Permite que o perfil financeiro seja criado pelo painel Master.
-- A Edge Function master-users já aceita o papel "financeiro".
alter table public.profiles
  drop constraint if exists profiles_role_check;

alter table public.profiles
  add constraint profiles_role_check
  check (role = any (array[
    'master'::text,
    'recepcao'::text,
    'profissional'::text,
    'sala'::text,
    'financeiro'::text
  ]));
