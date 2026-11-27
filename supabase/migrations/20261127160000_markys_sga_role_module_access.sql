-- MARKYS SGA: perfis operacionais e permissões por módulo.
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
 check (role = any (array['master','recepcao','profissional','sala','financeiro','administrador']::text[]));

create or replace function public.markys_sga_queue_get_tenant(p_clinic_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog as $$
declare v_clinic uuid; v_role text; v_day date:=app_private.markys_sga_local_day(); v_queue jsonb; v_version bigint;
begin
 select p.role into v_role from public.profiles p where p.id=(select auth.uid()) and p.active=true;
 if v_role not in ('master','recepcao','profissional','financeiro','administrador') then
  raise exception 'Perfil sem permissão para fila' using errcode='42501';
 end if;
 v_clinic:=app_private.markys_sga_queue_clinic_for_user(p_clinic_id);
 select q.queue,q.version into v_queue,v_version from app_private.markys_sga_queue_tenants q
 where q.clinic_id=v_clinic and q.service_day=v_day;
 return jsonb_build_object('queue',coalesce(v_queue,'[]'::jsonb),'version',coalesce(v_version,0),'clinic_id',v_clinic);
end; $$;

create or replace function public.markys_sga_queue_write_tenant(p_changes jsonb,p_clinic_id uuid default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare
 v_clinic uuid; v_role text; v_day date:=app_private.markys_sga_local_day();
 v_queue jsonb; v_version bigint; v_next jsonb; v_change jsonb; v_id text;
 v_expected jsonb; v_patient jsonb; v_current jsonb; v_found boolean; v_total integer:=0;
begin
 v_clinic:=app_private.markys_sga_queue_clinic_for_user(p_clinic_id);
 select p.role into v_role from public.profiles p where p.id=(select auth.uid()) and p.active=true;
 if v_role not in ('master','recepcao','profissional','financeiro','administrador') then raise exception 'Perfil sem permissão para fila' using errcode='42501'; end if;
 if p_changes is null or jsonb_typeof(p_changes)<>'array' or jsonb_array_length(p_changes)>500 then raise exception 'Lista de alterações inválida' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtext('markys_sga_queue_tenant'),hashtext(v_clinic::text));
 select q.queue,q.version into v_queue,v_version from app_private.markys_sga_queue_tenants q where q.clinic_id=v_clinic and q.service_day=v_day for update;
 v_queue:=coalesce(v_queue,'[]'::jsonb); v_version:=coalesce(v_version,0);
 for v_change in select value from jsonb_array_elements(p_changes) loop
  v_id:=nullif(v_change->>'id',''); v_expected:=nullif(v_change->'expected','null'::jsonb); v_patient:=nullif(v_change->'patient','null'::jsonb);
  if v_id is null then raise exception 'Identificador inválido' using errcode='22023'; end if;
  if v_patient is not null and (jsonb_typeof(v_patient)<>'object' or v_patient->>'id' is distinct from v_id or v_patient->>'day' is distinct from v_day::text) then
   raise exception 'Registro de paciente inválido ou data fora do dia corrente' using errcode='22023';
  end if;
  select value into v_current from jsonb_array_elements(v_queue) where value->>'id'=v_id limit 1; v_found:=found;
  if (case when v_found then v_current else null end) is distinct from v_expected then raise exception 'QUEUE_CONFLICT: fila alterada; atualize antes de salvar' using errcode='40001'; end if;
  if v_role='profissional' and (not v_found or v_patient is null or
   (v_current-array['status','serviceStates','activeService','calledAt','calledService','calledLabel','callDisplayMode','attendingAt','attendedAt','exitTime','releasedAt']::text[])
   is distinct from
   (v_patient-array['status','serviceStates','activeService','calledAt','calledService','calledLabel','callDisplayMode','attendingAt','attendedAt','exitTime','releasedAt']::text[])) then
   raise exception 'Profissional só pode alterar andamento dos atendimentos existentes' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(case when value->>'id'=v_id then v_patient else value end order by ord),'[]'::jsonb)
   into v_next from jsonb_array_elements(v_queue) with ordinality as x(value,ord)
   where not(value->>'id'=v_id and v_patient is null);
  if not v_found and v_patient is not null then v_next:=v_next||jsonb_build_array(v_patient); end if;
  v_queue:=v_next; v_total:=v_total+1;
 end loop;
 if v_total>0 then
  insert into app_private.markys_sga_queue_tenants(clinic_id,service_day,queue,version,updated_by,updated_at)
  values(v_clinic,v_day,v_queue,v_version+1,(select auth.uid()),now())
  on conflict(clinic_id,service_day) do update set queue=excluded.queue,version=excluded.version,updated_by=excluded.updated_by,updated_at=excluded.updated_at;
  v_version:=v_version+1;
 end if;
 return jsonb_build_object('version',v_version,'clinic_id',v_clinic,'updated_at',now());
end; $$;

drop policy if exists markys_sga_staff_tenant_queue_broadcast_read on realtime.messages;
create policy markys_sga_staff_tenant_queue_broadcast_read on realtime.messages for select to authenticated
using ((select realtime.topic()) like 'markys-sga-queue-clinic-%' and exists(
 select 1 from public.profiles p where p.id=(select auth.uid()) and p.active=true
 and (p.role='master' or p.clinic_id::text=split_part((select realtime.topic()),'markys-sga-queue-clinic-',2))
 and p.role=any(array['master','recepcao','profissional','financeiro','administrador']::text[])
));

-- Permissões financeiras para Financeiro e Administrador, preservando Master.
drop policy if exists markys_finance_categories_access on public.markys_finance_categories;
create policy markys_finance_categories_access on public.markys_finance_categories for all to authenticated
 using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador')))
 with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador')));
drop policy if exists markys_finance_cost_centers_access on public.markys_finance_cost_centers;
create policy markys_finance_cost_centers_access on public.markys_finance_cost_centers for all to authenticated
 using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador')))
 with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador')));
drop policy if exists markys_finance_accounts_access on public.markys_finance_accounts;
create policy markys_finance_accounts_access on public.markys_finance_accounts for all to authenticated
 using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador')))
 with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador')));
drop policy if exists markys_finance_entries_access on public.markys_finance_entries;
create policy markys_finance_entries_access on public.markys_finance_entries for all to authenticated
 using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador')))
 with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador')));

drop policy if exists markys_insurances_read_staff on public.markys_insurances;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated
 using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador','recepcao','profissional')));
drop policy if exists markys_insurances_manage_finance on public.markys_insurances;
create policy markys_insurances_manage_finance on public.markys_insurances for all to authenticated
 using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador')))
 with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador')));
drop policy if exists markys_insurance_prices_read_staff on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated
 using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador','recepcao','profissional')));
drop policy if exists markys_insurance_prices_manage_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_manage_finance on public.markys_insurance_exam_prices for all to authenticated
 using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador')))
 with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador')));

drop policy if exists markys_service_docs_read_staff on public.markys_service_documents;
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated
 using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador','recepcao')));
drop policy if exists markys_service_docs_insert_staff on public.markys_service_documents;
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated
 with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador','recepcao')));
drop policy if exists markys_service_docs_manage_finance on public.markys_service_documents;
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated
 using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador')))
 with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador')));
drop policy if exists markys_service_items_read_staff on public.markys_service_document_items;
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated
 using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador','recepcao')));
drop policy if exists markys_service_items_insert_staff on public.markys_service_document_items;
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated
 with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador','recepcao')));
drop policy if exists markys_service_items_manage_finance on public.markys_service_document_items;
create policy markys_service_items_manage_finance on public.markys_service_document_items for all to authenticated
 using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador')))
 with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador')));

drop policy if exists markys_service_catalog_read_staff on public.markys_service_catalog;
create policy markys_service_catalog_read_staff on public.markys_service_catalog for select to authenticated
 using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador','recepcao','profissional')));
drop policy if exists markys_service_catalog_insert_finance on public.markys_service_catalog;
create policy markys_service_catalog_insert_finance on public.markys_service_catalog for insert to authenticated
 with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador')));
drop policy if exists markys_service_catalog_update_finance on public.markys_service_catalog;
create policy markys_service_catalog_update_finance on public.markys_service_catalog for update to authenticated
 using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador')))
 with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador')));
drop policy if exists markys_service_catalog_delete_finance on public.markys_service_catalog;
create policy markys_service_catalog_delete_finance on public.markys_service_catalog for delete to authenticated
 using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','administrador')));

create or replace function public.markys_create_service_document(p_insurance_id uuid,p_insurance_name text,p_patient_name text,p_patient_cpf text,p_patient_id text,p_service_date date,p_items jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_role text; v_number text; v_doc public.markys_service_documents%rowtype; v_total numeric(14,2);
begin
 select role into v_role from public.profiles where id=auth.uid() and active;
 if v_role is null or v_role not in ('master','financeiro','administrador','recepcao') then raise exception 'Acesso não autorizado para emitir documento de serviço.'; end if;
 if coalesce(trim(p_patient_name),'')='' or coalesce(trim(p_insurance_name),'')='' then raise exception 'Informe paciente e convênio.'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Inclua pelo menos um exame.'; end if;
 select coalesce(sum((x->>'quantity')::integer*(x->>'unit_amount')::numeric),0) into v_total from jsonb_array_elements(p_items) x where coalesce(trim(x->>'exam_name'),'')<>'' and (x->>'quantity')::integer>0 and (x->>'unit_amount')::numeric>=0;
 if v_total<0 then raise exception 'Valor inválido.'; end if;
 v_number:='MS-'||to_char(coalesce(p_service_date,current_date),'YYYYMMDD')||'-'||lpad(nextval('public.markys_service_document_seq')::text,6,'0');
 insert into public.markys_service_documents(document_number,insurance_id,insurance_name,patient_name,patient_cpf,patient_id,service_date,total_amount,created_by)
 values(v_number,p_insurance_id,trim(p_insurance_name),trim(p_patient_name),nullif(trim(p_patient_cpf),''),nullif(trim(p_patient_id),''),coalesce(p_service_date,current_date),v_total,auth.uid()) returning * into v_doc;
 insert into public.markys_service_document_items(document_id,exam_name,quantity,unit_amount,total_amount)
 select v_doc.id,trim(x->>'exam_name'),(x->>'quantity')::integer,(x->>'unit_amount')::numeric,(x->>'quantity')::integer*(x->>'unit_amount')::numeric from jsonb_array_elements(p_items) x where coalesce(trim(x->>'exam_name'),'')<>'' and (x->>'quantity')::integer>0 and (x->>'unit_amount')::numeric>=0;
 return jsonb_build_object('id',v_doc.id,'document_number',v_doc.document_number,'total_amount',v_doc.total_amount);
end $$;
revoke all on function public.markys_create_service_document(uuid,text,text,text,text,date,jsonb) from public,anon;
grant execute on function public.markys_create_service_document(uuid,text,text,text,text,date,jsonb) to authenticated;

-- O perfil Financeiro também pode operar a Recepção; Administrador tem acesso integral.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope on storage.objects as restrictive for all to authenticated
using (bucket_id <> 'markys-sga-documents' or (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','profissional','financeiro','administrador']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text))))
with check (bucket_id <> 'markys-sga-documents' or (bucket_id='markys-sga-documents'
 and private.current_active_role()=any(array['master','recepcao','financeiro','administrador']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text))));

drop policy if exists markys_sga_media_tenant_read on storage.objects;
create policy markys_sga_media_tenant_read on storage.objects as restrictive for select to authenticated
using (bucket_id <> 'markys-sga-media' or (bucket_id='markys-sga-media' and private.current_active_role()=any(array['master','recepcao','profissional','financeiro','administrador']::text[])));
drop policy if exists markys_sga_media_tenant_insert on storage.objects;
create policy markys_sga_media_tenant_insert on storage.objects as restrictive for insert to authenticated
with check (bucket_id <> 'markys-sga-media' or (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','financeiro','administrador']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text))));
drop policy if exists markys_sga_media_tenant_update on storage.objects;
create policy markys_sga_media_tenant_update on storage.objects as restrictive for update to authenticated
using (bucket_id <> 'markys-sga-media' or (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','financeiro','administrador']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text))))
with check (bucket_id <> 'markys-sga-media' or (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','financeiro','administrador']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text))));
drop policy if exists markys_sga_media_tenant_delete on storage.objects;
create policy markys_sga_media_tenant_delete on storage.objects as restrictive for delete to authenticated
using (bucket_id <> 'markys-sga-media' or (bucket_id='markys-sga-media'
 and private.current_active_role()=any(array['master','recepcao','financeiro','administrador']::text[])
 and (private.current_user_is_master() or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text))));
