-- Merge non-overlapping edits to the same patient safely.
-- Same-field conflicts remain protected with SQLSTATE 40001.
create or replace function app_private.favmed_merge_queue_patient_patch(
  p_expected jsonb, p_current jsonb, p_patient jsonb, p_patient_id text
)
returns jsonb
language plpgsql
set search_path to 'pg_catalog'
as $function$
declare
  v_merged jsonb;
  v_key text;
  v_service_key text;
  v_expected_has boolean;
  v_patient_has boolean;
  v_current_has boolean;
  v_expected_states jsonb;
  v_patient_states jsonb;
  v_current_states jsonb;
  v_merged_states jsonb;
  v_base_service_has boolean;
  v_client_service_has boolean;
  v_remote_service_has boolean;
begin
  if p_expected is not null and jsonb_typeof(p_expected) <> 'object' then
    raise exception 'Estado anterior do paciente inválido' using errcode = '22023';
  end if;
  if p_current is not null and jsonb_typeof(p_current) <> 'object' then
    raise exception 'Estado atual do paciente inválido' using errcode = '22023';
  end if;
  if p_patient is not null and jsonb_typeof(p_patient) <> 'object' then
    raise exception 'Novo estado do paciente inválido' using errcode = '22023';
  end if;

  if p_expected is null then
    if p_current is not null then
      raise exception 'QUEUE_CONFLICT: este paciente já foi cadastrado em outro dispositivo. Atualize e tente novamente.' using errcode = '40001';
    end if;
    if p_patient is null then
      raise exception 'Paciente não encontrado para remoção' using errcode = 'P0002';
    end if;
    return p_patient;
  end if;

  if p_patient is null then
    if p_current is distinct from p_expected then
      raise exception 'QUEUE_CONFLICT: este paciente foi alterado em outro dispositivo. Atualize e tente novamente.' using errcode = '40001';
    end if;
    return null;
  end if;

  if p_current is null then
    raise exception 'QUEUE_CONFLICT: este paciente foi removido em outro dispositivo. Atualize e tente novamente.' using errcode = '40001';
  end if;

  if p_expected->>'id' is distinct from p_patient_id
     or p_patient->>'id' is distinct from p_patient_id
     or p_expected->>'day' is distinct from p_patient->>'day' then
    raise exception 'Identificador ou data do paciente não podem ser alterados' using errcode = '22023';
  end if;

  v_merged := p_current;

  for v_key in
    select keys.key_name
      from (
        select jsonb_object_keys(p_expected) as key_name
        union
        select jsonb_object_keys(p_patient) as key_name
      ) keys
  loop
    v_expected_has := p_expected ? v_key;
    v_patient_has := p_patient ? v_key;

    if v_expected_has = v_patient_has
       and (not v_expected_has or p_expected->v_key is not distinct from p_patient->v_key) then
      continue;
    end if;

    if v_key = 'serviceStates'
       and (not v_expected_has or jsonb_typeof(p_expected->v_key) = 'object')
       and (not v_patient_has or jsonb_typeof(p_patient->v_key) = 'object')
       and (not (p_current ? v_key) or jsonb_typeof(p_current->v_key) = 'object') then

      v_expected_states := case when v_expected_has then p_expected->v_key else '{}'::jsonb end;
      v_patient_states := case when v_patient_has then p_patient->v_key else '{}'::jsonb end;
      v_current_states := case when p_current ? v_key then p_current->v_key else '{}'::jsonb end;
      v_merged_states := v_current_states;

      for v_service_key in
        select service_keys.key_name
          from (
            select jsonb_object_keys(v_expected_states) as key_name
            union
            select jsonb_object_keys(v_patient_states) as key_name
          ) service_keys
      loop
        v_base_service_has := v_expected_states ? v_service_key;
        v_client_service_has := v_patient_states ? v_service_key;
        v_remote_service_has := v_current_states ? v_service_key;

        if v_base_service_has = v_client_service_has
           and (not v_base_service_has or v_expected_states->v_service_key is not distinct from v_patient_states->v_service_key) then
          continue;
        end if;

        if (v_remote_service_has is distinct from v_base_service_has
            or (v_base_service_has and v_current_states->v_service_key is distinct from v_expected_states->v_service_key))
           and (v_remote_service_has is distinct from v_client_service_has
            or (v_client_service_has and v_current_states->v_service_key is distinct from v_patient_states->v_service_key)) then
          raise exception 'QUEUE_CONFLICT: o mesmo atendimento foi alterado em outro dispositivo. Atualize e tente novamente.' using errcode = '40001';
        end if;

        if v_client_service_has then
          v_merged_states := jsonb_set(v_merged_states, array[v_service_key], v_patient_states->v_service_key, true);
        else
          v_merged_states := v_merged_states - v_service_key;
        end if;
      end loop;

      if v_merged_states = '{}'::jsonb and not v_patient_has and not (p_current ? v_key) then
        v_merged := v_merged - v_key;
      else
        v_merged := jsonb_set(v_merged, array[v_key], v_merged_states, true);
      end if;
      continue;
    end if;

    v_current_has := p_current ? v_key;

    if (v_current_has is distinct from v_expected_has
        or (v_expected_has and p_current->v_key is distinct from p_expected->v_key))
       and (v_current_has is distinct from v_patient_has
        or (v_patient_has and p_current->v_key is distinct from p_patient->v_key)) then
      raise exception 'QUEUE_CONFLICT: o campo "%" deste paciente foi alterado em outro dispositivo. Atualize e tente novamente.', v_key using errcode = '40001';
    end if;

    if v_patient_has then
      v_merged := jsonb_set(v_merged, array[v_key], p_patient->v_key, true);
    else
      v_merged := v_merged - v_key;
    end if;
  end loop;

  return v_merged;
end;
$function$;

revoke all on function app_private.favmed_merge_queue_patient_patch(jsonb, jsonb, jsonb, text) from public, anon, authenticated;

create or replace function app_private.favmed_update_queue_patients(p_changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_role text;
  v_today date := app_private.favmed_local_day();
  v_old_queue jsonb;
  v_new_queue jsonb;
  v_additions jsonb;
  v_change jsonb;
  v_id text;
  v_expected jsonb;
  v_patient jsonb;
  v_old jsonb;
  v_merged jsonb;
  v_merged_changes jsonb := '[]'::jsonb;
  v_version bigint;
  v_new_version bigint;
  v_matches integer;
  v_change_count integer;
begin
  select p.role into v_role
    from public.profiles p
   where p.id = auth.uid() and p.active = true;

  if coalesce(v_role, '') not in ('master', 'recepcao', 'profissional') then
    raise exception 'Perfil sem permissão para alterar a fila' using errcode = '42501';
  end if;

  if p_changes is null or jsonb_typeof(p_changes) <> 'array' then
    raise exception 'As alterações da fila devem ser enviadas como uma lista JSON' using errcode = '22023';
  end if;

  v_change_count := jsonb_array_length(p_changes);
  if v_change_count < 1 or v_change_count > 200 then
    raise exception 'A operação deve conter entre 1 e 200 alterações' using errcode = '22023';
  end if;

  if pg_column_size(p_changes) > 8388608 then
    raise exception 'O lote de alterações excede o limite de 8 MB' using errcode = '22023';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_changes) c(value)
     where jsonb_typeof(c.value) <> 'object'
        or not (c.value ? 'id')
        or not (c.value ? 'expected')
        or not (c.value ? 'patient')
        or nullif(btrim(c.value->>'id'), '') is null
        or (
          jsonb_typeof(c.value->'expected') <> 'null'
          and (
            jsonb_typeof(c.value->'expected') <> 'object'
            or c.value->'expected'->>'id' is distinct from c.value->>'id'
            or c.value->'expected'->>'day' is distinct from v_today::text
          )
        )
        or (
          jsonb_typeof(c.value->'patient') <> 'null'
          and (
            jsonb_typeof(c.value->'patient') <> 'object'
            or c.value->'patient'->>'id' is distinct from c.value->>'id'
            or c.value->'patient'->>'day' is distinct from v_today::text
          )
        )
  ) then
    raise exception 'Uma ou mais alterações possuem identificador, paciente ou data inválidos' using errcode = '22023';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_changes) c(value)
     group by c.value->>'id'
    having count(*) > 1
  ) then
    raise exception 'O lote contém alterações duplicadas para o mesmo paciente' using errcode = '22023';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_changes) c(value)
     where jsonb_typeof(c.value->'patient') = 'object'
       and pg_column_size(c.value->'patient') > 33554432
  ) then
    raise exception 'Um registro de paciente excede o limite permitido' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtext('favmed_queue_state'));

  insert into app_private.favmed_queue_state(singleton, queue, version)
  values (true, '[]'::jsonb, 0)
  on conflict (singleton) do nothing;

  select s.version into v_version
    from app_private.favmed_queue_state s
   where s.singleton = true
   for update;
  v_version := coalesce(v_version, 0);

  select q.queue into v_old_queue
    from app_private.favmed_queue_days q
   where q.service_day = v_today
   for update;
  v_old_queue := coalesce(v_old_queue, '[]'::jsonb);

  for v_change in select c.value from jsonb_array_elements(p_changes) c(value)
  loop
    v_id := v_change->>'id';
    v_expected := case when jsonb_typeof(v_change->'expected') = 'null' then null else v_change->'expected' end;
    v_patient := case when jsonb_typeof(v_change->'patient') = 'null' then null else v_change->'patient' end;

    select count(*) into v_matches
      from jsonb_array_elements(v_old_queue) q(value)
     where q.value->>'id' = v_id;

    if v_matches > 1 then
      raise exception 'A fila contém identificadores duplicados; nenhuma alteração foi aplicada' using errcode = '22023';
    end if;

    select q.value into v_old
      from jsonb_array_elements(v_old_queue) q(value)
     where q.value->>'id' = v_id
     limit 1;

    if v_role = 'profissional' then
      if v_expected is null or v_patient is null then
        raise exception 'O profissional só pode atualizar o andamento dos atendimentos existentes' using errcode = '42501';
      end if;

      if (v_expected - array[
        'status','serviceStates','activeService','calledAt','calledService','calledLabel',
        'callDisplayMode','attendingAt','attendedAt','exitTime','releasedAt'
      ]::text[]) is distinct from
      (v_patient - array[
        'status','serviceStates','activeService','calledAt','calledService','calledLabel',
        'callDisplayMode','attendingAt','attendedAt','exitTime','releasedAt'
      ]::text[]) then
        raise exception 'O profissional só pode alterar o status dos atendimentos' using errcode = '42501';
      end if;
    end if;

    v_merged := app_private.favmed_merge_queue_patient_patch(v_expected, v_old, v_patient, v_id);
    v_merged_changes := v_merged_changes || jsonb_build_array(jsonb_build_object('id', v_id, 'patient', v_merged));
  end loop;

  select coalesce(
    jsonb_agg(
      case when c.value is not null then c.value->'patient' else q.value end
      order by q.ordinality
    ) filter (
      where c.value is null or jsonb_typeof(c.value->'patient') <> 'null'
    ),
    '[]'::jsonb
  )
  into v_new_queue
  from jsonb_array_elements(v_old_queue) with ordinality q(value, ordinality)
  left join lateral (
    select x.value
      from jsonb_array_elements(v_merged_changes) x(value)
     where x.value->>'id' = q.value->>'id'
     limit 1
  ) c on true;

  select coalesce(jsonb_agg(m.value->'patient'), '[]'::jsonb)
    into v_additions
    from jsonb_array_elements(v_merged_changes) m(value)
    join jsonb_array_elements(p_changes) c(value)
      on c.value->>'id' = m.value->>'id'
   where jsonb_typeof(c.value->'expected') = 'null'
     and jsonb_typeof(m.value->'patient') = 'object';

  v_new_queue := v_new_queue || v_additions;

  if pg_column_size(v_new_queue) > 33554432 then
    raise exception 'A fila do dia excede o limite de 32 MB' using errcode = '22023';
  end if;

  if v_new_queue is not distinct from v_old_queue then
    return jsonb_build_object('version', v_version, 'updated_at', now(), 'changed', false);
  end if;

  v_new_version := v_version + 1;

  if jsonb_array_length(v_new_queue) = 0 then
    delete from app_private.favmed_queue_days where service_day = v_today;
  else
    insert into app_private.favmed_queue_days(service_day, queue, updated_by, updated_at)
    values (v_today, v_new_queue, auth.uid(), now())
    on conflict (service_day) do update
      set queue = excluded.queue, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  end if;

  update app_private.favmed_queue_state
     set version = v_new_version, updated_by = auth.uid(), updated_at = now()
   where singleton = true;

  return jsonb_build_object('version', v_new_version, 'updated_at', now(), 'changed', true);
end;
$function$;

revoke all on function app_private.favmed_update_queue_patients(jsonb) from public, anon;
grant execute on function app_private.favmed_update_queue_patients(jsonb) to authenticated;

create or replace function app_private.favmed_update_queue_patient(
  p_patient_id text, p_patient jsonb, p_expected_patient jsonb
)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog'
as $function$
  select app_private.favmed_update_queue_patients(jsonb_build_array(jsonb_build_object(
    'id', p_patient_id,
    'expected', p_expected_patient,
    'patient', p_patient
  )));
$function$;

revoke all on function app_private.favmed_update_queue_patient(text, jsonb, jsonb) from public, anon;
grant execute on function app_private.favmed_update_queue_patient(text, jsonb, jsonb) to authenticated;