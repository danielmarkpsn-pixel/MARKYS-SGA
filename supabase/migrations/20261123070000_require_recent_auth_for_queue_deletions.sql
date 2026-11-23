-- Require a fresh password authentication for queue deletions and keep a minimal audit trail.
-- Patient identifiers are retained only to correlate the queue record; no name, CPF or birth date is copied.

create table if not exists app_private.markys_sga_queue_deletion_audit (
  id bigint generated always as identity primary key,
  clinic_id uuid not null,
  service_day date not null,
  patient_id text not null,
  removed_by uuid not null,
  removed_at timestamptz not null default now()
);

revoke all on table app_private.markys_sga_queue_deletion_audit from public, anon, authenticated;
revoke all on sequence app_private.markys_sga_queue_deletion_audit_id_seq from public, anon, authenticated;

create index if not exists markys_sga_queue_deletion_audit_clinic_day_idx
  on app_private.markys_sga_queue_deletion_audit (clinic_id, service_day, removed_at desc);

create or replace function public.markys_sga_queue_write_tenant(
  p_changes jsonb,
  p_clinic_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_clinic uuid;
  v_role text;
  v_user_id uuid;
  v_auth_time bigint;
  v_day date := app_private.markys_sga_local_day();
  v_queue jsonb;
  v_version bigint;
  v_next jsonb;
  v_change jsonb;
  v_id text;
  v_expected jsonb;
  v_patient jsonb;
  v_current jsonb;
  v_found boolean;
  v_total integer := 0;
begin
  v_user_id := (select auth.uid());
  v_clinic := app_private.markys_sga_queue_clinic_for_user(p_clinic_id);

  select p.role into v_role
  from public.profiles p
  where p.id = v_user_id and p.active = true;

  if v_role not in ('master', 'recepcao', 'profissional') then
    raise exception 'Perfil sem permissão para fila' using errcode = '42501';
  end if;

  if p_changes is null or jsonb_typeof(p_changes) <> 'array' or jsonb_array_length(p_changes) > 500 then
    raise exception 'Lista de alterações inválida' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtext('markys_sga_queue_tenant'), hashtext(v_clinic::text));

  select q.queue, q.version into v_queue, v_version
  from app_private.markys_sga_queue_tenants q
  where q.clinic_id = v_clinic and q.service_day = v_day
  for update;

  v_queue := coalesce(v_queue, '[]'::jsonb);
  v_version := coalesce(v_version, 0);

  for v_change in select value from jsonb_array_elements(p_changes)
  loop
    v_id := nullif(v_change->>'id', '');
    v_expected := nullif(v_change->'expected', 'null'::jsonb);
    v_patient := nullif(v_change->'patient', 'null'::jsonb);

    if v_id is null then
      raise exception 'Identificador inválido' using errcode = '22023';
    end if;

    if v_patient is not null and (
      jsonb_typeof(v_patient) <> 'object'
      or v_patient->>'id' is distinct from v_id
      or v_patient->>'day' is distinct from v_day::text
    ) then
      raise exception 'Registro de paciente inválido ou data fora do dia corrente' using errcode = '22023';
    end if;

    select value into v_current
    from jsonb_array_elements(v_queue)
    where value->>'id' = v_id
    limit 1;
    v_found := found;

    if (case when v_found then v_current else null end) is distinct from v_expected then
      raise exception 'QUEUE_CONFLICT: fila alterada; atualize antes de salvar novamente' using errcode = '40001';
    end if;

    -- Deleting a record is a privileged operation: require password reauthentication
    -- within the previous five minutes, checked from the signed Supabase JWT.
    if v_found and v_patient is null then
      v_auth_time := nullif(auth.jwt()->>'auth_time', '')::bigint;
      if v_auth_time is null or v_auth_time < extract(epoch from now())::bigint - 300 then
        raise exception 'REAUTH_REQUIRED: confirme sua senha novamente para excluir o paciente'
          using errcode = '42501';
      end if;

      if v_role not in ('master', 'recepcao') then
        raise exception 'Perfil sem permissão para excluir pacientes' using errcode = '42501';
      end if;

      insert into app_private.markys_sga_queue_deletion_audit
        (clinic_id, service_day, patient_id, removed_by)
      values
        (v_clinic, v_day, v_id, v_user_id);
    end if;

    if v_role = 'profissional' and (
      not v_found or v_patient is null
      or (v_current - array['status','serviceStates','activeService','calledAt','calledService','calledLabel','callDisplayMode','attendingAt','attendedAt','exitTime','releasedAt']::text[])
         is distinct from
         (v_patient - array['status','serviceStates','activeService','calledAt','calledService','calledLabel','callDisplayMode','attendingAt','attendedAt','exitTime','releasedAt']::text[])
    ) then
      raise exception 'Profissional só pode alterar andamento dos atendimentos existentes' using errcode = '42501';
    end if;

    select coalesce(
      jsonb_agg(case when value->>'id' = v_id then v_patient else value end order by ord),
      '[]'::jsonb
    ) into v_next
    from jsonb_array_elements(v_queue) with ordinality as x(value, ord)
    where not (value->>'id' = v_id and v_patient is null);

    if not v_found and v_patient is not null then
      v_next := v_next || jsonb_build_array(v_patient);
    end if;

    v_queue := v_next;
    v_total := v_total + 1;
  end loop;

  if v_total > 0 then
    insert into app_private.markys_sga_queue_tenants
      (clinic_id, service_day, queue, version, updated_by, updated_at)
    values
      (v_clinic, v_day, v_queue, v_version + 1, v_user_id, now())
    on conflict (clinic_id, service_day) do update
      set queue = excluded.queue,
          version = excluded.version,
          updated_by = excluded.updated_by,
          updated_at = excluded.updated_at;
    v_version := v_version + 1;
  end if;

  return jsonb_build_object('version', v_version, 'clinic_id', v_clinic, 'updated_at', now());
end;
$function$;
