-- Run against the MARKYS SGA database after applying migrations.
-- Assertions intentionally inspect authorization metadata without reading patient records.
do $$
declare
  v_definition text;
  v_public_definition text;
begin
  if not exists (
    select 1 from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='profiles' and c.relrowsecurity
  ) then
    raise exception 'RLS must remain enabled on public.profiles';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='profiles'
      and policyname='markys_sga_profiles_tenant_restrict'
      and qual ilike '%current_user_is_master%'
      and qual ilike '%current_user_clinic_id%'
  ) then
    raise exception 'Tenant isolation policy missing from public.profiles';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname='app_private' and tablename='markys_sga_queue_tenants'
      and policyname='markys_sga_queue_tenants_deny_direct_access'
      and qual='false'
  ) then
    raise exception 'Direct access to tenant queue table must remain denied';
  end if;

  if to_regclass('app_private.markys_sga_queue_deletion_audit') is null then
    raise exception 'Queue deletion audit table is missing';
  end if;

  if has_table_privilege('anon','app_private.markys_sga_queue_deletion_audit','select')
     or has_table_privilege('authenticated','app_private.markys_sga_queue_deletion_audit','select')
     or has_table_privilege('anon','app_private.markys_sga_queue_deletion_audit','insert')
     or has_table_privilege('authenticated','app_private.markys_sga_queue_deletion_audit','insert') then
    raise exception 'Client roles must not access the deletion audit table directly';
  end if;

  if has_function_privilege('anon','public.markys_sga_queue_write_tenant(jsonb,uuid)','execute')
     or has_function_privilege('public','public.markys_sga_queue_write_tenant(jsonb,uuid)','execute')
     or not has_function_privilege('authenticated','public.markys_sga_queue_write_tenant(jsonb,uuid)','execute') then
    raise exception 'Queue write RPC grants must be authenticated-only';
  end if;

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure)
    into v_definition;

  select pg_get_functiondef('public.markys_sga_public_queue_tenant(text,text)'::regprocedure)
    into v_public_definition;

  if not has_function_privilege('anon','public.markys_sga_public_queue_tenant(text,text)','execute')
     or has_function_privilege('authenticated','public.markys_sga_public_queue_tenant(text,text)','execute')
     or has_function_privilege('public','public.markys_sga_public_queue_tenant(text,text)','execute') then
    raise exception 'Public queue RPC must be callable only by anon for the public waiting-room screen';
  end if;

  if v_public_definition ilike '%cpf%'
     or v_public_definition ilike '%birth_date%'
     or v_public_definition not ilike '%status%'
     or v_public_definition not ilike '%p_day<>v_day::text%'
     or v_public_definition not ilike '%c.active=true%' then
    raise exception 'Public queue RPC must expose only its minimal same-day active-clinic projection';
  end if;

  if v_definition not ilike '%auth_time%'
     or v_definition not ilike '%REAUTH_REQUIRED%'
     or v_definition not ilike '%markys_sga_queue_deletion_audit%'
     or v_definition not ilike '%security definer%'
     or v_definition not ilike '%search_path TO ''pg_catalog''%' then
    raise exception 'Queue write RPC is missing required deletion safeguards';
  end if;
end;
$$;

select 'MARKYS SGA security regression assertions passed' as result;
