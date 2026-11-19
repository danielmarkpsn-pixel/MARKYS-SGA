-- Keep the PostgREST-facing public RPC SECURITY INVOKER. Its private helper
-- is SECURITY DEFINER but returns only the current day's sanitized call board.
create or replace function app_private.markys_get_public_queue_internal(p_day text)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog as $$
declare v_today text; v_queue jsonb; v_version bigint; v_public jsonb;
begin
 v_today:=to_char(timezone('America/Manaus',now()),'YYYY-MM-DD');
 if p_day is null or p_day !~ '^\\d{4}-\\d{2}-\\d{2}$' or p_day<>v_today then
  raise exception 'A tela de chamadas só pode consultar o dia atual' using errcode='22023';
 end if;
 select s.queue,s.version into v_queue,v_version from app_private.markys_sga_queue_state s where s.singleton=true;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',p.value->'id','name',coalesce(nullif(trim(p.value->>'name'),''),'Paciente'),
  'room',p.value->'room','rooms',p.value->'rooms','services',p.value->'services','service',p.value->'service',
  'serviceStates',(select coalesce(jsonb_object_agg(st.key,jsonb_build_object('status',st.value->'status','updatedAt',st.value->'updatedAt','callLabel',st.value->'callLabel')),'{}'::jsonb) from jsonb_each(coalesce(p.value->'serviceStates','{}'::jsonb)) st),
  'status',p.value->'status','priority',p.value->'priority','created',p.value->'created','time',p.value->'time','day',p.value->'day',
  'receptionCall',case when jsonb_typeof(p.value->'receptionCall')='object' then jsonb_build_object('status',p.value->'receptionCall'->'status','service',p.value->'receptionCall'->'service','callLabel',p.value->'receptionCall'->'callLabel','updatedAt',p.value->'receptionCall'->'updatedAt') else null end
 )),'[]'::jsonb) into v_public from jsonb_array_elements(coalesce(v_queue,'[]'::jsonb)) p(value)
 where p.value->>'day'=v_today and (p.value->>'status' in ('Chamado','Atendendo') or exists(
  select 1 from jsonb_each(coalesce(p.value->'serviceStates','{}'::jsonb)) st where st.value->>'status' in ('Chamado','Atendendo')));
 return jsonb_build_object('queue',v_public,'version',coalesce(v_version,0));
end; $$;
revoke all on function app_private.markys_get_public_queue_internal(text) from public,authenticated;
grant usage on schema app_private to anon;
grant execute on function app_private.markys_get_public_queue_internal(text) to anon;
create or replace function public.markys_get_public_queue(p_day text)
returns jsonb language sql stable security invoker set search_path='' as
$$ select app_private.markys_get_public_queue_internal(p_day); $$;
revoke all on function public.markys_get_public_queue(text) from public,authenticated;
grant execute on function public.markys_get_public_queue(text) to anon;
