-- Keep the shared authentication bootstrap compatible with Financeiro users
-- without granting them access to patient queue data. Financeiro receives an
-- empty queue snapshot; only Master, Recepção and Profissional receive the queue.
CREATE OR REPLACE FUNCTION app_private.markys_get_queue_internal()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare v_role text; v_queue jsonb; v_version bigint; v_today date:=app_private.markys_sga_local_day();
begin
 select p.role into v_role from public.profiles p where p.id=auth.uid() and p.active=true;
 if v_role is null or v_role not in ('master','recepcao','profissional','financeiro') then
  raise exception 'Perfil inativo ou sem permissão para acessar a fila' using errcode='42501';
 end if;
 select s.version into v_version from app_private.markys_sga_queue_state s where s.singleton=true;
 if v_role='financeiro' then
  return jsonb_build_object('queue','[]'::jsonb,'version',coalesce(v_version,0));
 end if;
 select q.queue into v_queue from app_private.markys_sga_queue_days q where q.service_day=v_today;
 return jsonb_build_object('queue',coalesce(v_queue,'[]'::jsonb),'version',coalesce(v_version,0));
end; $function$;
