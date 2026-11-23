-- Public waiting-room projection: active calls only, masked patient names, no clinical or queue metadata.
create or replace function public.markys_sga_public_queue_tenant(p_day text,p_clinic_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog
as $$
declare
  v_day date:=app_private.markys_sga_local_day();
  v_clinic uuid;
  v_queue jsonb;
  v_version bigint;
  v_public jsonb;
begin
  if p_day is null or p_day !~ '^\\d{4}-\\d{2}-\\d{2}$' or p_day<>v_day::text then
    raise exception 'A tela pública só consulta o dia atual' using errcode='22023';
  end if;

  select c.id into v_clinic
  from public.markys_clinics c
  where c.slug=p_clinic_slug and c.active=true;

  if v_clinic is null then
    raise exception 'Clínica não encontrada ou inativa' using errcode='42501';
  end if;

  select q.queue,q.version into v_queue,v_version
  from app_private.markys_sga_queue_tenants q
  where q.clinic_id=v_clinic and q.service_day=v_day;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',p.value->'id',
    'name',case
      when cardinality(names.parts)=0 then 'Paciente'
      when cardinality(names.parts)=1 then names.parts[1]
      else names.parts[1]||' '||upper(left(names.parts[cardinality(names.parts)],1))||'.'
    end,
    'room',p.value->'room',
    'rooms',p.value->'rooms',
    'services',p.value->'services',
    'service',p.value->'service',
    'serviceStates',(
      select coalesce(jsonb_object_agg(st.key,jsonb_build_object(
        'status',st.value->'status',
        'updatedAt',st.value->'updatedAt',
        'callLabel',st.value->'callLabel'
      )),'{}'::jsonb)
      from jsonb_each(coalesce(p.value->'serviceStates','{}'::jsonb)) st
      where st.value->>'status' in ('Chamado','Atendendo')
    ),
    'status',p.value->'status',
    'receptionCall',case
      when jsonb_typeof(p.value->'receptionCall')='object'
       and p.value->'receptionCall'->>'status'='Chamado'
      then jsonb_build_object(
        'status',p.value->'receptionCall'->'status',
        'service',p.value->'receptionCall'->'service',
        'callLabel',p.value->'receptionCall'->'callLabel',
        'updatedAt',p.value->'receptionCall'->'updatedAt'
      )
      else null
    end
  )),'[]'::jsonb) into v_public
  from jsonb_array_elements(coalesce(v_queue,'[]'::jsonb)) p(value)
  cross join lateral (
    select case
      when trim(coalesce(p.value->>'name',''))=''
        then array[]::text[]
      else regexp_split_to_array(trim(p.value->>'name'),'\\s+')
    end as parts
  ) names
  where p.value->>'day'=v_day::text
    and (
      p.value->>'status' in ('Chamado','Atendendo')
      or exists(
        select 1 from jsonb_each(coalesce(p.value->'serviceStates','{}'::jsonb)) st
        where st.value->>'status' in ('Chamado','Atendendo')
      )
      or p.value->'receptionCall'->>'status'='Chamado'
    );

  return jsonb_build_object(
    'queue',v_public,
    'version',coalesce(v_version,0),
    'clinic_slug',p_clinic_slug
  );
end;
$$;

revoke all on function public.markys_sga_public_queue_tenant(text,text) from public,authenticated;
grant execute on function public.markys_sga_public_queue_tenant(text,text) to anon;
