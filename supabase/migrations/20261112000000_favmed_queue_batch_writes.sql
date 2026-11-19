-- Batch queue writes: validate every patient change and commit the daily queue once.
-- Staged for review. Do not apply to Supabase until the matching client release is ready.

create or replace function app_private.favmed_update_queue_patients(
  p_changes jsonb
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
  v_additions jsonb;
  v_change jsonb;
  v_id text;
  v_expected jsonb;
  v_patient jsonb;
  v_old jsonb;
  v_version bigint;
  v_new_version bigint;
  v_matches integer;
  v_change_count integer;
begin
  select p.role
    into v_role
    from public.profiles p
   where p.id = auth.uid()
     and p.active = true;

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
    select 1
      from jsonb_array_elements(p_changes) c(value)
     where jsonb_typeof(c.value) <> 'object'
        or not (c.value ? 'id')
        or not (c.value ? 'expected')
        or not (c.value ? 'patient')
        or nullif(btrim(c.value->>'id'), '') is null
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
    select 1
      from jsonb_array_elements(p_changes) c(value)
     group by c.value->>'id'
    having count(*) > 1
  ) then
    raise exception 'O lote contém alterações duplicadas para o mesmo paciente' using errcode = '22023';
  end if;

  if exists (
    select 1
      from jsonb_array_elements(p_changes) c(value)
     where jsonb_typeof(c.value->'patient') = 'object'
       and pg_column_size(c.value->'patient') > 33554432
  ) then
    raise exception 'Um registro de paciente excede o limite permitido' using errcode = '22023';
  end if;

  -- Serialize queue mutations once per batch, not once per patient.
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

  -- Validate all optimistic-concurrency expectations before changing anything.
  for v_change in
    select c.value from jsonb_array_elements(p_changes) c(value)
  loop
    v_id := v_change->>'id';
    v_expected := case
      when jsonb_typeof(v_change->'expected') = 'null' then null
      else v_change->'expected'
    end;
    v_patient := case
      when jsonb_typeof(v_change->'patient') = 'null' then null
      else v_change->'patient'
    end;

    select count(*)
      into v_matches
      from jsonb_array_elements(v_old_queue) q(value)
     where q.value->>'id' = v_id;

    if v_matches > 1 then
      raise exception 'A fila contém identificadores duplicados; nenhuma alteração foi aplicada' using errcode = '22023';
    end if;

    select q.value
      into v_old
      from jsonb_array_elements(v_old_queue) q(value)
     where q.value->>'id' = v_id
     limit 1;

    if v_old is distinct from v_expected then
      raise exception 'QUEUE_CONFLICT: este paciente foi alterado em outro dispositivo. Atualize e tente novamente.' using errcode = '40001';
    end if;

    if v_patient is null and v_old is null then
      raise exception 'Paciente não encontrado para remoção' using errcode = 'P0002';
    end if;

    if v_role = 'profissional' then
      if v_old is null or v_patient is null then
        raise exception 'O profissional só pode atualizar o andamento dos atendimentos existentes' using errcode = '42501';
      end if;

      if (v_old - array[
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
  end loop;

  -- Rebuild the JSON array once, preserving existing order and appending new patients.
  select coalesce(
           jsonb_agg(
             case
               when c.value is not null then c.value->'patient'
               else q.value
             end
             order by q.ordinality
           ) filter (
             where c.value is null
                or jsonb_typeof(c.value->'patient') <> 'null'
           ),
           '[]'::jsonb
         )
    into v_new_queue
    from jsonb_array_elements(v_old_queue) with ordinality q(value, ordinality)
    left join lateral (
      select x.value
        from jsonb_array_elements(p_changes) x(value)
       where x.value->>'id' = q.value->>'id'
       limit 1
    ) c on true;

  select coalesce(jsonb_agg(c.value->'patient'), '[]'::jsonb)
    into v_additions
    from jsonb_array_elements(p_changes) c(value)
   where jsonb_typeof(c.value->'expected') = 'null'
     and jsonb_typeof(c.value->'patient') = 'object';

  v_new_queue := v_new_queue || v_additions;

  if pg_column_size(v_new_queue) > 33554432 then
    raise exception 'A fila do dia excede o limite de 32 MB' using errcode = '22023';
  end if;

  -- Do not increment the version or broadcast when the resulting queue is unchanged.
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
      set queue = excluded.queue,
          updated_by = excluded.updated_by,
          updated_at = excluded.updated_at;
  end if;

  update app_private.favmed_queue_state
     set version = v_new_version,
         updated_by = auth.uid(),
         updated_at = now()
   where singleton = true;

  return jsonb_build_object('version', v_new_version, 'updated_at', now(), 'changed', true);
end;
$function$;

revoke all on function app_private.favmed_update_queue_patients(jsonb) from public, anon;
grant execute on function app_private.favmed_update_queue_patients(jsonb) to authenticated;

create or replace function public.favmed_update_queue_patients(p_changes jsonb)
returns jsonb
language sql
set search_path to ''
as $function$
  select app_private.favmed_update_queue_patients(p_changes);
$function$;

revoke all on function public.favmed_update_queue_patients(jsonb) from public, anon;
grant execute on function public.favmed_update_queue_patients(jsonb) to authenticated;
