-- Hardening RLS: remove overlapping permissive policies and run document RPC as invoker.
drop policy if exists markys_insurances_manage_finance on public.markys_insurances;
create policy markys_insurances_insert_finance on public.markys_insurances for insert to authenticated with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro')));
create policy markys_insurances_update_finance on public.markys_insurances for update to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro'))) with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro')));
create policy markys_insurances_delete_finance on public.markys_insurances for delete to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro')));
drop policy if exists markys_insurance_prices_manage_finance on public.markys_insurance_exam_prices;
create policy markys_insurance_prices_insert_finance on public.markys_insurance_exam_prices for insert to authenticated with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro')));
create policy markys_insurance_prices_update_finance on public.markys_insurance_exam_prices for update to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro'))) with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro')));
create policy markys_insurance_prices_delete_finance on public.markys_insurance_exam_prices for delete to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro')));
drop policy if exists markys_service_items_manage_finance on public.markys_service_document_items;
create policy markys_service_items_update_finance on public.markys_service_document_items for update to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro'))) with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro')));
create policy markys_service_items_delete_finance on public.markys_service_document_items for delete to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro')));
create index if not exists markys_insurances_created_by_idx on public.markys_insurances(created_by);
create index if not exists markys_insurance_exam_prices_created_by_idx on public.markys_insurance_exam_prices(created_by);
create index if not exists markys_service_documents_created_by_idx on public.markys_service_documents(created_by);
create or replace function public.markys_create_service_document(p_insurance_id uuid,p_insurance_name text,p_patient_name text,p_patient_cpf text,p_patient_id text,p_service_date date,p_items jsonb)
returns jsonb language plpgsql set search_path=public,pg_temp as $$
declare v_role text; v_number text; v_doc public.markys_service_documents%rowtype; v_total numeric(14,2);
begin
 select role into v_role from public.profiles where id=(select auth.uid()) and active;
 if v_role is null or v_role not in ('master','financeiro','recepcao') then raise exception 'Acesso não autorizado para emitir documento de serviço.'; end if;
 if p_patient_id is not null then select * into v_doc from public.markys_service_documents where patient_id=p_patient_id; if found then return jsonb_build_object('id',v_doc.id,'document_number',v_doc.document_number,'total_amount',v_doc.total_amount,'existing',true); end if; end if;
 if coalesce(trim(p_patient_name),'')='' or coalesce(trim(p_insurance_name),'')='' then raise exception 'Informe paciente e convênio.'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Inclua pelo menos um exame.'; end if;
 select coalesce(sum((x->>'quantity')::integer*(x->>'unit_amount')::numeric),0) into v_total from jsonb_array_elements(p_items) x where coalesce(trim(x->>'exam_name'),'')<>'' and (x->>'quantity')::integer>0 and (x->>'unit_amount')::numeric>=0;
 if v_total<0 then raise exception 'Valor inválido.'; end if;
 v_number:='MS-'||to_char(coalesce(p_service_date,current_date),'YYYYMMDD')||'-'||lpad(nextval('public.markys_service_document_seq')::text,6,'0');
 insert into public.markys_service_documents(document_number,insurance_id,insurance_name,patient_name,patient_cpf,patient_id,service_date,total_amount,created_by) values(v_number,p_insurance_id,trim(p_insurance_name),trim(p_patient_name),nullif(trim(p_patient_cpf),''),nullif(trim(p_patient_id),''),coalesce(p_service_date,current_date),v_total,(select auth.uid())) returning * into v_doc;
 insert into public.markys_service_document_items(document_id,exam_name,quantity,unit_amount,total_amount) select v_doc.id,trim(x->>'exam_name'),(x->>'quantity')::integer,(x->>'unit_amount')::numeric,(x->>'quantity')::integer*(x->>'unit_amount')::numeric from jsonb_array_elements(p_items) x where coalesce(trim(x->>'exam_name'),'')<>'' and (x->>'quantity')::integer>0 and (x->>'unit_amount')::numeric>=0;
 return jsonb_build_object('id',v_doc.id,'document_number',v_doc.document_number,'total_amount',v_doc.total_amount,'existing',false);
end $$;
