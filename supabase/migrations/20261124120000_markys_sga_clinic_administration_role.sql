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
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao', 'profissional'$old$, $new

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao', 'profissional', 'admin_clinica'$new$);
  v_def := replace(v_def, $old

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao'$old$, $new

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao', 'admin_clinica'$new$);
  execute v_def;

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master','recepcao','profissional'$old$, $new
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao', 'profissional'$old$, $new

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao', 'profissional', 'admin_clinica'$new$);
  v_def := replace(v_def, $old

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao'$old$, $new

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao', 'admin_clinica'$new$);
  execute v_def;

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao', 'profissional'$old$, $new

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao', 'profissional', 'admin_clinica'$new$);
  v_def := replace(v_def, $old

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao'$old$, $new

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao', 'admin_clinica'$new$);
  execute v_def;

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao', 'profissional'$old$, $new
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao', 'profissional'$old$, $new

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao', 'profissional', 'admin_clinica'$new$);
  v_def := replace(v_def, $old

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao'$old$, $new

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao', 'admin_clinica'$new$);
  execute v_def;

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao', 'profissional', 'admin_clinica'$new$);
  v_def := replace(v_def, $old
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao', 'profissional'$old$, $new

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao', 'profissional', 'admin_clinica'$new$);
  v_def := replace(v_def, $old

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao'$old$, $new

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao', 'admin_clinica'$new$);
  execute v_def;

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao'$old$, $new
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao', 'profissional'$old$, $new

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao', 'profissional', 'admin_clinica'$new$);
  v_def := replace(v_def, $old

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao'$old$, $new

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao', 'admin_clinica'$new$);
  execute v_def;

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao', 'profissional'$old$, $new

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao', 'profissional', 'admin_clinica'$new$);
  v_def := replace(v_def, $old

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao'$old$, $new

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
master', 'recepcao', 'admin_clinica'$new$);
  execute v_def;

  select pg_get_functiondef('public.markys_sga_queue_write_tenant(jsonb,uuid)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_sga_queue_write_tenant(jsonb,uuid) não encontrada'; end if;
  v_def := replace(v_def, $old$'master','recepcao','profissional'$old$, $new$'master','recepcao','profissional','admin_clinica'$new$);
  v_def := replace(v_def, $old$'master', 'recepcao', 'profissional'$old$, $new$'master', 'recepcao', 'profissional', 'admin_clinica'$new$);
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

-- Expand tenant-scoped Storage restrictive policies. The clinic folder check is
-- deliberately preserved, so clinic administrators cannot cross tenant boundaries.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_scope on storage.objects as restrictive
for all to authenticated
using (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','profissional','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)))
with check (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','admin_clinica']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)));

-- Insurance/pricing, service catalog and service documents are part of the
-- clinic-wide Administration module. Other staff retain only their prior reads.
drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurances_insert_finance on public.markys_insurances;
drop policy if exists markys_insurances_update_finance on public.markys_insurances;
drop policy if exists markys_insurances_delete_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_update_finance on public.markys_insurance_exam_prices;
drop policy if exists markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
drop policy if exists markys_service_items_update_finance on public.markys_service_document_items;
drop policy if exists markys_service_items_delete_finance on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao')));
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','admin_clinica')));

-- The service-document RPC is also an authorization boundary; update its role
-- check without changing its transactional business logic.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.markys_create_service_document(uuid,text,text,text,text,date,jsonb)'::regprocedure) into v_def;
  if v_def is null then raise exception 'RPC markys_create_service_document não encontrada'; end if;
  v_def := replace(v_def, $old$'master','financeiro','recepcao'$old$, $new$'master','admin_clinica','recepcao'$new$);
  v_def := replace(v_def, $old$'master', 'financeiro', 'recepcao'$old$, $new$'master', 'admin_clinica', 'recepcao'$new$);
  execute v_def;
end $$;
