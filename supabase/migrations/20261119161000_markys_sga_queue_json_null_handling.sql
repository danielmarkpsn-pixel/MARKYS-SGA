-- Handle JSON nulls emitted by the browser for newly created and removed queue records.
-- The main function is replaced with nullif(..., 'null'::jsonb) handling.
create or replace function app_private.markys_update_queue_patients_internal(p_changes jsonb)
returns jsonb language plpgsql volatile security definer set search_path=pg_catalog as $$
declare v_role text; v_queue jsonb; v_version bigint; v_new_queue jsonb; v_change jsonb; v_id text; v_expected jsonb; v_patient jsonb; v_old jsonb; v_found boolean; v_count integer:=0;
begin
 select p.role into v_role from public.profiles p where p.id=auth.uid() and p.active=true;
 if v_role is null or v_role not in ('master','recepcao','profissional') then raise exception 'Perfil sem permissão para alterar a fila' using errcode='42501'; end if;
 if p_changes is null or jsonb_typeof(p_changes)<>'array' or jsonb_array_length(p_changes)>500 then raise exception 'Lista de alterações inválida' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtext('markys_sga_queue_state'));
 select s.queue,s.version into v_queue,v_version from app_private.markys_sga_queue_state s where s.singleton=true for update;
 v_queue:=coalesce(v_queue,'[]'::jsonb); v_version:=coalesce(v_version,0);
 for v_change in select value from jsonb_array_elements(p_changes) loop
  v_id:=nullif(v_change->>'id',''); v_expected:=nullif(v_change->'expected','null'::jsonb); v_patient:=nullif(v_change->'patient','null'::jsonb);
  if v_id is null then raise exception 'Identificador inválido' using errcode='22023'; end if;
  if v_patient is not null and (jsonb_typeof(v_patient)<>'object' or v_patient->>'id' is distinct from v_id) then raise exception 'Registro inválido' using errcode='22023'; end if;
  select value into v_old from jsonb_array_elements(v_queue) where value->>'id'=v_id limit 1; v_found:=found;
  if (case when v_found then v_old else null end) is distinct from v_expected then raise exception 'QUEUE_CONFLICT: a fila foi alterada em outro dispositivo' using errcode='40001'; end if;
  if v_role='profissional' and (not v_found or v_patient is null or (v_old-array['status','serviceStates','activeService','calledAt','calledService','calledLabel','callDisplayMode','attendingAt','attendedAt','exitTime','releasedAt']::text[]) is distinct from (v_patient-array['status','serviceStates','activeService','calledAt','calledService','calledLabel','callDisplayMode','attendingAt','attendedAt','exitTime','releasedAt']::text[])) then raise exception 'O profissional só pode atualizar o andamento dos atendimentos existentes' using errcode='42501'; end if;
  select coalesce(jsonb_agg(case when value->>'id'=v_id then v_patient else value end order by ord),'[]'::jsonb) into v_new_queue from jsonb_array_elements(v_queue) with ordinality as q(value,ord) where not(value->>'id'=v_id and v_patient is null);
  if not v_found and v_patient is not null then v_new_queue:=v_new_queue||jsonb_build_array(v_patient); end if;
  v_queue:=v_new_queue; v_count:=v_count+1;
 end loop;
 if v_count>0 then insert into app_private.markys_sga_queue_state(singleton,queue,version,updated_by,updated_at) values(true,v_queue,v_version+1,auth.uid(),now()) on conflict(singleton) do update set queue=excluded.queue,version=excluded.version,updated_by=excluded.updated_by,updated_at=excluded.updated_at; v_version:=v_version+1; end if;
 return jsonb_build_object('version',v_version,'updated_at',now());
end; $$;
