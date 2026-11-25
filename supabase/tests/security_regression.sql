-- Run against the MARKYS SGA database after applying migrations.
-- Assertions intentionally inspect authorization metadata without reading patient records.
do $$
declare
  v_definition text;
  v_public_definition text;
  v_queue_get_definition text;
  v_service_document_definition text;
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
     or v_public_definition ilike '%priority%'
     or v_public_definition ilike '%examsbyroom%'
     or v_public_definition ilike '%created%'
     or v_public_definition not ilike '%regexp_split_to_array%'
     or v_public_definition not ilike '%left(%'
     or v_public_definition not ilike '%status%'
     or v_public_definition not ilike '%p_day<>v_day::text%'
     or v_public_definition not ilike '%c.active=true%' then
    raise exception 'Public queue RPC must expose masked names and only active calls without clinical or queue metadata';
  end if;

  if exists (
    select 1 from storage.buckets where id='markys-sga-media' and public=true
  ) then
    raise exception 'Clinic slideshow media bucket must be private';
  end if;

  if exists (
    select 1 from pg_policies
    where schemaname='storage' and tablename='objects'
      and policyname='markys_sga_media_public_list'
  ) then
    raise exception 'Anonymous listing of clinic slideshow media must be removed';
  end if;

  if has_function_privilege('authenticated','app_private.markys_get_queue_internal()','execute')
     or has_function_privilege('anon','app_private.markys_get_queue_internal()','execute')
     or has_function_privilege('public','app_private.markys_get_queue_internal()','execute')
     or not has_function_privilege('service_role','app_private.markys_get_queue_internal()','execute') then
    raise exception 'Legacy global queue helper must not be executable by client roles';
  end if;

  -- Definitive clinic role model: Administration is operational and tenant-scoped,
  -- while the legacy Financeiro role must not retain financial permissions.
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.profiles'::regclass
      and conname='profiles_role_check'
      and pg_get_constraintdef(oid) ilike '%admin_clinica%'
  ) then
    raise exception 'profiles_role_check must include admin_clinica';
  end if;

  select pg_get_functiondef('public.markys_sga_queue_get_tenant(uuid)'::regprocedure)
    into v_queue_get_definition;
  if v_queue_get_definition not ilike '%admin_clinica%' then
    raise exception 'Clinic Administration must be authorized to read the tenant queue';
  end if;
  if v_definition not ilike '%admin_clinica%'
     or v_definition not ilike '%v_role not in (''master'', ''recepcao'', ''admin_clinica'')%' then
    raise exception 'Clinic Administration must be authorized to write and delete queue records with recent reauthentication';
  end if;

  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure)
    into v_service_document_definition;
  if v_service_document_definition not ilike '%admin_clinica%'
     or v_service_document_definition ilike '%financeiro%' then
    raise exception 'Service document RPC must replace Financeiro with clinic Administration';
  end if;

  if exists (
    select 1 from (values
      ('markys_finance_categories','markys_finance_categories_access'),
      ('markys_finance_cost_centers','markys_finance_cost_centers_access'),
      ('markys_finance_accounts','markys_finance_accounts_access'),
      ('markys_finance_entries','markys_finance_entries_access')
    ) as expected(tablename,policyname)
    where not exists (
      select 1 from pg_policies p
      where p.schemaname='public' and p.tablename=expected.tablename
        and p.policyname=expected.policyname
        and p.qual ilike '%admin_clinica%'
        and p.qual not ilike '%financeiro%'
        and p.with_check ilike '%admin_clinica%'
        and p.with_check not ilike '%financeiro%'
    )
  ) then
    raise exception 'Finance tables must allow Master/clinic Administration only, never legacy Financeiro';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname='storage' and tablename='objects'
      and policyname='markys_sga_documents_tenant_scope'
      and permissive='RESTRICTIVE'
      and qual ilike '%bucket_id <> ''markys-sga-documents''%'
      and qual ilike '%admin_clinica%'
      and qual ilike '%current_user_clinic_id%'
  ) then
    raise exception 'Documents Storage policy must preserve other buckets and clinic isolation for Administration';
  end if;

  if exists (
    select 1 from (values
      ('markys_sga_media_tenant_read','SELECT'),
      ('markys_sga_media_tenant_insert','INSERT'),
      ('markys_sga_media_tenant_update','UPDATE'),
      ('markys_sga_media_tenant_delete','DELETE')
    ) as expected(policyname,cmd)
    where not exists (
      select 1 from pg_policies p
      where p.schemaname='storage' and p.tablename='objects'
        and p.policyname=expected.policyname and p.cmd=expected.cmd
        and coalesce(p.qual,p.with_check) ilike '%bucket_id <> ''markys-sga-media''%'
        and coalesce(p.qual,p.with_check) ilike '%admin_clinica%'
        and coalesce(p.qual,p.with_check) ilike '%current_user_clinic_id%'
    )
  ) then
    raise exception 'Media Storage command policies must include Administration and tenant isolation';
  end if;

  if v_definition not ilike '%v_role is null%'
     or v_definition not ilike '%auth_time%'
     or v_definition not ilike '%REAUTH_REQUIRED%'
     or v_definition not ilike '%markys_sga_queue_deletion_audit%'
     or v_definition not ilike '%security definer%'
     or v_definition not ilike '%search_path TO ''pg_catalog''%' then
    raise exception 'Queue write RPC is missing required deletion safeguards';
  end if;
end;
$$;

select 'MARKYS SGA security regression assertions passed' as result;
