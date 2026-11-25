-- MARKYS SGA: apply the same field-level optimistic merge to clinic-scoped queue writes.
-- Additive only: no production database change occurs until this migration is applied.
create or replace function public.markys_sga_queue_write_tenant(p_changes jsonb,p_clinic_id uuid default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare
 v_clinic uuid; v_role text; v_day date:=app_private.markys_sga_local_day();
 v_old_queue jsonb; v_new_queue jsonb; v_additions jsonb; v_change jsonb; v_id text;
 v_expected jsonb; v_patient jsonb; v_current jsonb; v_merged jsonb;
 v_merged_changes jsonb:='[]'::jsonb; v_version bigint; v_new_version bigint;
 v_matches integer; v_change_count integer;
begin
 v_clinic:=app_private.markys_sga_queue_clinic_for_user(p_clinic_id);
 select p.role into v_role from public.profiles p
 where p.id=(select auth.uid()) and p.active=true;
 if coalesce(v_role,'') not in ('master','recepcao','profissional') then
  raise exception 'Perfil sem permissão para fila' using errcode='42501';
 end if;
 if p_changes is null or jsonb_typeof(p_changes)<>'array' then
  raise exception 'Lista de alterações inválida' using errcode='22023';
 end if;
 v_change_count:=jsonb_array_length(p_changes);
 if v_change_count<1 or v_change_count>200 then
  raise exception 'A operação deve conter entre 1 e 200 alterações' using errcode='22023';
 end if;
 if pg_column_size(p_changes)>8388608 then
  raise exception 'O lote de alterações excede o limite de 8 MB' using errcode='22023';
 end if;
 if exists(
  select 1 from jsonb_array_elements(p_changes) c(value)
  where jsonb_typeof(c.value)<>'object'
   or not(c.value?'id') or not(c.value?'expected') or not(c.value?'patient')
   or nullif(btrim(c.value->>'id'),'') is null
   or (jsonb_typeof(c.value->'expected')<>'null' and
       (jsonb_typeof(c.value->'expected')<>'object'
        or c.value->'expected'->>'id' is distinct from c.value->>'id'
        or c.value->'expected'->>'day' is distinct from v_day::text))
   or (jsonb_typeof(c.value->'patient')<>'null' and
       (jsonb_typeof(c.value->'patient')<>'object'
        or c.value->'patient'->>'id' is distinct from c.value->>'id'
        or c.value->'patient'->>'day' is distinct from v_day::text))
 ) then
  raise exception 'Uma ou mais alterações possuem identificador, paciente ou data inválidos' using errcode='22023';
 end if;
 if exists(
  select 1 from jsonb_array_elements(p_changes) c(value)
  group by c.value->>'id' having count(*)>1
 ) then
  raise exception 'O lote contém alterações duplicadas para o mesmo paciente' using errcode='22023';
 end if;

 -- Serialize writes per clinic and lock the current day's authoritative snapshot.
 perform pg_advisory_xact_lock(hashtext('markys_sga_queue_tenant'),hashtext(v_clinic::text));
 select q.queue,q.version into v_old_queue,v_version
 from app_private.markys_sga_queue_tenants q
 where q.clinic_id=v_clinic and q.service_day=v_day
 for update;
 v_old_queue:=coalesce(v_old_queue,'[]'::jsonb);
 v_version:=coalesce(v_version,0);

 -- Validate and merge every requested patch before changing the stored snapshot.
 -- Any conflict aborts the whole transaction: no partial batch is committed.
 for v_change in select c.value from jsonb_array_elements(p_changes) c(value) loop
  v_id:=v_change->>'id';
  v_expected:=case when jsonb_typeof(v_change->'expected')='null' then null else v_change->'expected' end;
  v_patient:=case when jsonb_typeof(v_change->'patient')='null' then null else v_change->'patient' end;
  select count(*) into v_matches
  from jsonb_array_elements(v_old_queue) q(value) where q.value->>'id'=v_id;
  if v_matches>1 then
   raise exception 'A fila contém identificadores duplicados; nenhuma alteração foi aplicada' using errcode='22023';
  end if;
  select q.value into v_current
  from jsonb_array_elements(v_old_queue) q(value) where q.value->>'id'=v_id limit 1;

  if v_role='profissional' then
   if v_expected is null or v_patient is null or v_current is null then
    raise exception 'Profissional só pode alterar andamento de atendimentos existentes' using errcode='42501';
   end if;
   if (v_expected-array['status','serviceStates','activeService','calledAt','calledService','calledLabel','callDisplayMode','attendingAt','attendedAt','exitTime','releasedAt']::text[])
      is distinct from
      (v_patient-array['status','serviceStates','activeService','calledAt','calledService','calledLabel','callDisplayMode','attendingAt','attendedAt','exitTime','releasedAt']::text[]) then
    raise exception 'Profissional só pode alterar andamento dos atendimentos' using errcode='42501';
   end if;
  end if;

  v_merged:=app_private.markys_sga_merge_queue_patient_patch(v_expected,v_current,v_patient,v_id);
  v_merged_changes:=v_merged_changes||jsonb_build_array(jsonb_build_object('id',v_id,'patient',v_merged));
 end loop;

 -- Preserve existing queue order and remove records whose merged state is null.
 select coalesce(jsonb_agg(
   case when m.value is not null then m.value->'patient' else q.value end
   order by q.ordinality
 ) filter(where m.value is null or jsonb_typeof(m.value->'patient')<>'null'),'[]'::jsonb)
 into v_new_queue
 from jsonb_array_elements(v_old_queue) with ordinality q(value,ordinality)
 left join lateral(
   select x.value from jsonb_array_elements(v_merged_changes) x(value)
   where x.value->>'id'=q.value->>'id' limit 1
 ) m on true;

 -- Append newly inserted patients in the original request order.
 select coalesce(jsonb_agg(m.value->'patient' order by c.ordinality),'[]'::jsonb)
 into v_additions
 from jsonb_array_elements(v_merged_changes) m(value)
 join jsonb_array_elements(p_changes) with ordinality c(value,ordinality)
   on c.value->>'id'=m.value->>'id'
 where jsonb_typeof(c.value->'expected')='null'
   and jsonb_typeof(m.value->'patient')='object';
 v_new_queue:=v_new_queue||coalesce(v_additions,'[]'::jsonb);

 if pg_column_size(v_new_queue)>33554432 then
  raise exception 'A fila da clínica excede o limite de 32 MB' using errcode='22023';
 end if;
 if v_new_queue is not distinct from v_old_queue then
  return jsonb_build_object('version',v_version,'clinic_id',v_clinic,'changed',false,'updated_at',now());
 end if;

 v_new_version:=v_version+1;
 insert into app_private.markys_sga_queue_tenants(clinic_id,service_day,queue,version,updated_by,updated_at)
 values(v_clinic,v_day,v_new_queue,v_new_version,(select auth.uid()),now())
 on conflict(clinic_id,service_day) do update
 set queue=excluded.queue,version=excluded.version,updated_by=excluded.updated_by,updated_at=excluded.updated_at;

 return jsonb_build_object('version',v_new_version,'clinic_id',v_clinic,'changed',true,'updated_at',now());
end; $$;

revoke all on function public.markys_sga_queue_write_tenant(jsonb,uuid) from public,anon;
grant execute on function public.markys_sga_queue_write_tenant(jsonb,uuid) to authenticated;
