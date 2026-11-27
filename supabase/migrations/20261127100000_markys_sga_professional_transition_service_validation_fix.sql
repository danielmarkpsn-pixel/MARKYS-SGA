-- MARKYS SGA: server-side guard for professional queue state transitions.
-- Keeps clinic scoping, field-level merge, and role restrictions in the tenant RPC.
create or replace function public.markys_sga_queue_write_tenant(p_changes jsonb,p_clinic_id uuid default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare
 v_clinic uuid; v_role text; v_day date:=app_private.markys_sga_local_day();
 v_queue jsonb; v_version bigint; v_next jsonb; v_change jsonb; v_id text;
 v_expected jsonb; v_patient jsonb; v_current jsonb; v_found boolean; v_total integer:=0;
 v_old_states jsonb; v_new_states jsonb; v_service text; v_old_status text; v_new_status text;
 v_changed_states integer; v_service_valid boolean;
begin
 v_clinic:=app_private.markys_sga_queue_clinic_for_user(p_clinic_id);
 select p.role into v_role from public.profiles p where p.id=(select auth.uid()) and p.active=true;
 if v_role not in ('master','recepcao','profissional') then raise exception 'Perfil sem permissão para fila' using errcode='42501'; end if;
 if p_changes is null or jsonb_typeof(p_changes)<>'array' or jsonb_array_length(p_changes)>500 then
   raise exception 'Lista de alterações inválida' using errcode='22023';
 end if;
 perform pg_advisory_xact_lock(hashtext('markys_sga_queue_tenant'),hashtext(v_clinic::text));
 select q.queue,q.version into v_queue,v_version from app_private.markys_sga_queue_tenants q
 where q.clinic_id=v_clinic and q.service_day=v_day for update;
 v_queue:=coalesce(v_queue,'[]'::jsonb); v_version:=coalesce(v_version,0);
 for v_change in select value from jsonb_array_elements(p_changes) loop
  v_id:=nullif(v_change->>'id',''); v_expected:=nullif(v_change->'expected','null'::jsonb); v_patient:=nullif(v_change->'patient','null'::jsonb);
  if v_id is null then raise exception 'Identificador inválido' using errcode='22023'; end if;
  if v_patient is not null and (jsonb_typeof(v_patient)<>'object' or v_patient->>'id' is distinct from v_id or v_patient->>'day' is distinct from v_day::text) then
   raise exception 'Registro de paciente inválido ou data fora do dia corrente' using errcode='22023';
  end if;
  select value into v_current from jsonb_array_elements(v_queue) where value->>'id'=v_id limit 1; v_found:=found;
  if (case when v_found then v_current else null end) is distinct from v_expected then
   raise exception 'QUEUE_CONFLICT: fila alterada; atualize antes de salvar' using errcode='40001';
  end if;
  if v_role='profissional' and (not v_found or v_patient is null or
   (v_current-array['status','serviceStates','activeService','calledAt','calledService','calledLabel','callDisplayMode','attendingAt','attendedAt','exitTime','releasedAt']::text[])
   is distinct from
   (v_patient-array['status','serviceStates','activeService','calledAt','calledService','calledLabel','callDisplayMode','attendingAt','attendedAt','exitTime','releasedAt']::text[])) then
   raise exception 'Profissional só pode alterar andamento dos atendimentos existentes' using errcode='42501';
  end if;

  if v_role='profissional' then
   if jsonb_typeof(v_patient->'serviceStates')<>'object' then
    raise exception 'Estados do atendimento inválidos' using errcode='22023';
   end if;
   v_old_states:=case when jsonb_typeof(v_current->'serviceStates')='object' then v_current->'serviceStates' else '{}'::jsonb end;
   v_new_states:=v_patient->'serviceStates';
   v_changed_states:=0;
   for v_service in
    select keys.key from (
      select key from jsonb_object_keys(v_old_states)
      union
      select key from jsonb_object_keys(v_new_states)
    ) as keys
   loop
    if (v_old_states->v_service) is distinct from (v_new_states->v_service) then
     v_changed_states:=v_changed_states+1;
     v_old_status:=coalesce(v_old_states->v_service->>'status','Aguardando');
     v_new_status:=v_new_states->v_service->>'status';
     if v_new_status is null or v_new_status not in ('Aguardando','Chamado','Atendendo','Liberado') then
      raise exception 'Estado de atendimento inválido' using errcode='22023';
     end if;
     if jsonb_typeof(v_current->'services')='array' then
      v_service_valid:=(v_current->'services') ? v_service;
     elsif coalesce(v_current->>'service','')<>'' then
      v_service_valid:=v_service=any(array(select trim(item) from unnest(string_to_array(v_current->>'service',',')) as split(item));
     else
      v_service_valid:=v_current->>'room'=v_service;
     end if;
     if not coalesce(v_service_valid,false) then
      raise exception 'Profissional não pode alterar serviço não vinculado ao paciente' using errcode='42501';
     end if;
     if not (
       (v_old_status='Aguardando' and v_new_status='Chamado') or
       (v_old_status='Chamado' and v_new_status in ('Atendendo','Aguardando','Chamado')) or
       (v_old_status='Atendendo' and v_new_status='Liberado')
     ) then
      raise exception 'Transição inválida: % -> %',v_old_status,v_new_status using errcode='42501';
     end if;
    end if;
   end loop;
   if v_changed_states<>1 then
    raise exception 'Profissional deve alterar o andamento de apenas um serviço por ação' using errcode='42501';
   end if;
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
