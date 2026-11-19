-- Update one patient atomically instead of replacing the entire daily queue.
-- This migration is intentionally staged in Git only; do not run it in production yet.

create or replace function app_private.favmed_update_queue_patient(
  p_patient_id text,
  p_patient jsonb,
  p_expected_patient jsonb
)
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
  v_old jsonb;
  v_version bigint;
  v_new_version bigint;
  v_matches integer;
begin
  select p.role
    into v_role
    from public.profiles p
   where p.id = auth.uid()
     and p.active = true;

  if coalesce(v_role, '') not in ('master', 'recepcao', 'profissional') then
    raise exception 'Perfil sem permissão para alterar a fila' using errcode = '42501';
  end if;

  if p_patient_id is null or length(btrim(p_patient_id)) = 0 then
    raise exception 'Identificador do paciente inválido' using errcode = '22023';
  end if;

  if p_patient is not null then
    if jsonb_typeof(p_patient) <> 'object'
       or p_patient->>'id' is distinct from p_patient_id
       or p_patient->>'day' is distinct from v_today::text then
      raise exception 'Registro de paciente inválido ou de outra data' using errcode = '22023';
    end if;
    if pg_column_size(p_patient) > 33554432 then
      raise exception 'Registro do paciente excede o limite permitido' using errcode = '22023';
    end if;
  end if;

  -- Keep the same serialization boundary as the legacy whole-queue writer.
  perform pg_advisory_xact_lock(hashtext('favmed_queue_state'));

  insert into app_private.favmed_queue_state(singleton, queue, version)
  values (true, '[]'::jsonb, 0)
  on conflict (singleton) do nothing;

  select s.version
    into v_version
    from app_private.favmed_queue_state s
   where s.singleton = true
   for update;

  v_version := coalesce(v_version, 0);

  select q.queue
    into v_old_queue
    from app_private.favmed_queue_days q
   where q.service_day = v_today
   for update;

  v_old_queue := coalesce(v_old_queue, '[]'::jsonb);

  select count(*)
    into v_matches
    from jsonb_array_elements(v_old_queue) x(value)
   where x.value->>'id' = p_patient_id;

  if v_matches > 1 then
    raise exception 'A fila contém identificadores duplicados; nenhuma alteração foi aplicada' using errcode = '22023';
  end if;

  select x.value
    into v_old
    from jsonb_array_elements(v_old_queue) x(value)
   where x.value->>'id' = p_patient_id
   limit 1;

  -- Optimistic concurrency is now scoped to this patient, not the entire queue.
  if v_old is distinct from p_expected_patient then
    raise exception 'QUEUE_CONFLICT: este paciente foi alterado em outro dispositivo. Atualize e tente novamente.' using errcode = '40001';
  end if;

  if p_patient is null and v_old is null then
    raise exception 'Paciente não encontrado para remoção' using errcode = 'P0002';
  end if;

  if v_role = 'profissional' then
    if v_old is null or p_patient is null then
      raise exception 'O profissional só pode atualizar o andamento dos atendimentos existentes' using errcode = '42501';
    end if;

    if (v_old - array[
      'status','serviceStates','activeService','calledAt','calledService','calledLabel',
      'callDisplayMode','attendingAt','attendedAt','exitTime','releasedAt'
    ]::text[]) is distinct from
    (p_patient - array[
      'status','serviceStates','activeService','calledAt','calledService','calledLabel',
      'callDisplayMode','attendingAt','attendedAt','exitTime','releasedAt'
    ]::text[]) then
      raise exception 'O profissional só pode alterar o status dos atendimentos' using errcode = '42501';
    end if;
  end if;

  select coalesce(
           jsonb_agg(
             case
               when x.value->>'id' = p_patient_id and p_patient is not null then p_patient
               else x.value
             end
             order by x.ordinality
           ),
           '[]'::jsonb
         )
    into v_new_queue
    from jsonb_array_elements(v_old_queue) with ordinality x(value, ordinality)
   where not (x.value->>'id' = p_patient_id and p_patient is null);

  if v_old is null and p_patient is not null then
    v_new_queue := v_new_queue || jsonb_build_array(p_patient);
  end if;

  if pg_column_size(v_new_queue) > 33554432 then
    raise exception 'A fila do dia excede o limite de 32 MB' using errcode = '22023';
  end if;

  v_new_version := v_version + 1;

  if jsonb_array_length(v_new_queue) = 0 then
    delete from app_private.favmed_queue_days where service_day = v_today;
  else
    insert into app_private.favmed_queue_days(service_day, queue, updated_by, updated_at)
    values (v_today, v_new_queue, auth.uid(), now())
    on conflict (service_day) do update
      set queue = excluded.queue,
          updated_by = excluded.updated_by,
          updated_at = excluded.updated_at;
  end if;

  update app_private.favmed_queue_state
     set version = v_new_version,
         updated_by = auth.uid(),
         updated_at = now()
   where singleton = true;

  return jsonb_build_object('version', v_new_version, 'updated_at', now());
end;
$function$;

revoke all on function app_private.favmed_update_queue_patient(text, jsonb, jsonb) from public, anon;
grant execute on function app_private.favmed_update_queue_patient(text, jsonb, jsonb) to authenticated;

create or replace function public.favmed_update_queue_patient(
  p_patient_id text,
  p_patient jsonb,
  p_expected_patient jsonb
)
returns jsonb
language sql
set search_path to ''
as $function$
  select app_private.favmed_update_queue_patient(p_patient_id, p_patient, p_expected_patient);
$function$;

revoke all on function public.favmed_update_queue_patient(text, jsonb, jsonb) from public, anon;
grant execute on function public.favmed_update_queue_patient(text, jsonb, jsonb) to authenticated;
