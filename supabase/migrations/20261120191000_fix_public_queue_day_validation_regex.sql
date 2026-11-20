create or replace function app_private.markys_get_public_queue_internal(p_day text)
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog'
as $function$
declare v_today date := app_private.markys_sga_local_day(); v_queue jsonb; v_version bigint; v_public jsonb;
begin
 if p_day is null or p_day !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or p_day <> v_today::text then raise exception 'A tela de chamadas só pode consultar o dia atual' using errcode='22023'; end if;
 select q.queue into v_queue from app_private.markys_sga_queue_days q where q.service_day=v_today;
 select s.version into v_version from app_private.markys_sga_queue_state s where s.singleton=true;
 select coalesce(jsonb_agg(jsonb_build_object('id',p.value->'id','name',coalesce(nullif(trim(p.value->>'name'),''),'Paciente'),'room',p.value->'room','rooms',p.value->'rooms','services',p.value->'services','service',p.value->'service','serviceStates',(select coalesce(jsonb_object_agg(st.key,jsonb_build_object('status',st.value->'status','updatedAt',st.value->'updatedAt','callLabel',st.value->'callLabel')),'{}'::jsonb) from jsonb_each(coalesce(p.value->'serviceStates','{}'::jsonb)) st),'status',p.value->'status','priority',p.value->'priority','created',p.value->'created','time',p.value->'time','day',p.value->'day','receptionCall',case when jsonb_typeof(p.value->'receptionCall')='object' then jsonb_build_object('status',p.value->'receptionCall'->'status','service',p.value->'receptionCall'->'service','callLabel',p.value->'receptionCall'->'callLabel','updatedAt',p.value->'receptionCall'->'updatedAt') else null end)),'[]'::jsonb) into v_public from jsonb_array_elements(coalesce(v_queue,'[]'::jsonb)) p(value)
 where p.value->>'day'=v_today::text and (p.value->>'status' in ('Chamado','Atendendo') or exists(select 1 from jsonb_each(coalesce(p.value->'serviceStates','{}'::jsonb)) st where st.value->>'status' in ('Chamado','Atendendo')) or p.value->'receptionCall'->>'status'='Chamado');
 return jsonb_build_object('queue',v_public,'version',coalesce(v_version,0));
end;
$function$;
