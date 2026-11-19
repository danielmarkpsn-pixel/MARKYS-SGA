-- Idempotent follow-up for the empty serviceStates object edge case.
-- The helper is repeated here so the migration history stays aligned with the
-- already-applied database migration sequence.
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