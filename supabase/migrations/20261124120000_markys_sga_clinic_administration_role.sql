-- MARKYS SGA: role model v1.
-- Admin-clinica is a tenant-scoped operational administrator, never a global Master.
-- Existing 'financeiro' profiles are retained for explicit reassignment; no account is deleted or auto-promoted.

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role = any (array[
  'master'::text, 'recepcao'::text, 'profissional'::text, 'admin_clinica'::text,
  'financeiro'::text, 'sala'::text
]));

-- Replace the tenant queue RPC definitions from their installed versions, changing
-- only the explicit staff-role allowlists. Clinic binding remains enforced by the
-- existing tenant resolver; only Master may request a different clinic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_sga_queue_get_tenant(uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_get_tenant(uuid) não encontrada'; end if;
  v_def := replace(v_def, "('master','recepcao','profissional')", "('master','recepcao','profissional','admin_clinica')");
  v_def := replace(v_def, "('master', 'recepcao', 'profissional')", "('master', 'recepcao', 'profissional', 'admin_clinica')");
  execute v_def;

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, "('master','recepcao','profissional')", "('master','recepcao','profissional','admin_clinica')");
  v_def := replace(v_def, "('master', 'recepcao', 'profissional')", "('master', 'recepcao', 'profissional', 'admin_clinica')");
  execute v_def;
end $$;

-- Finance is now an Administration-only module; legacy finance profiles no longer pass RLS.
drop policy if exists markys_finance_categories_access on public.markys_finance_categories;
drop policy if exists markys_finance_cost_centers_access on public.markys_finance_cost_centers;
drop policy if exists markys_finance_accounts_access on public.markys_finance_accounts;
drop policy if exists markys_finance_entries_access on public.markys_finance_entries;
create policy markys_finance_categories_access on public.markys_finance_categories for all to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_finance_cost_centers_access on public.markys_finance_cost_centers for all to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_finance_accounts_access on public.markys_finance_accounts for all to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_finance_entries_access on public.markys_finance_entries for all to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- Administration may view and manage tenant documents/media. The clinic path scope
-- remains enforced by the existing storage tenant policies.
drop policy if exists markys_sga_documents_read on storage.objects;
drop policy if exists markys_sga_documents_insert on storage.objects;
drop policy if exists markys_sga_documents_delete on storage.objects;
drop policy if exists markys_sga_media_read on storage.objects;
drop policy if exists markys_sga_media_insert on storage.objects;
drop policy if exists markys_sga_media_delete on storage.objects;
create policy markys_sga_documents_read on storage.objects for select to authenticated
using (bucket_id='markys-sga-documents' and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[]));
create policy markys_sga_documents_insert on storage.objects for insert to authenticated
with check (bucket_id='markys-sga-documents' and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[]));
create policy markys_sga_documents_delete on storage.objects for delete to authenticated
using (bucket_id='markys-sga-documents' and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[]));
create policy markys_sga_media_read on storage.objects for select to authenticated
using (bucket_id='markys-sga-media' and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[]));
create policy markys_sga_media_insert on storage.objects for insert to authenticated
with check (bucket_id='markys-sga-media' and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[]));
create policy markys_sga_media_delete on storage.objects for delete to authenticated
using (bucket_id='markys-sga-media' and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[]));

drop policy if exists markys_sga_staff_tenant_queue_broadcast_read on realtime.messages;
create policy markys_sga_staff_tenant_queue_broadcast_read on realtime.messages for select to authenticated
using ((select realtime.topic()) like 'markys-sga-queue-clinic-%' and exists(
 select 1 from public.profiles p where p.id=(select auth.uid()) and p.active=true
 and (p.role='master' or p.clinic_id::text=split_part((select realtime.topic()),'markys-sga-queue-clinic-',2))
 and p.role=any(array['master','recepcao','profissional','admin_clinica']::text[])
));

-- Public waiting-room endpoints are deliberately unchanged and remain anonymous/read-only.
