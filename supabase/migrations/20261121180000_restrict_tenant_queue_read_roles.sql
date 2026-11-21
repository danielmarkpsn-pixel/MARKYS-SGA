create or replace function public.markys_sga_queue_get_tenant(p_clinic_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog as $$
declare v_clinic uuid; v_role text; v_day date:=app_private.markys_sga_local_day(); v_queue jsonb; v_version bigint;
begin
 select p.role into v_role from public.profiles p
 where p.id=(select auth.uid()) and p.active=true;
 if v_role not in ('master','recepcao','profissional') then
  raise exception 'Perfil sem permissão para fila' using errcode='42501';
 end if;
 v_clinic:=app_private.markys_sga_queue_clinic_for_user(p_clinic_id);
 select q.queue,q.version into v_queue,v_version from app_private.markys_sga_queue_tenants q
 where q.clinic_id=v_clinic and q.service_day=v_day;
 return jsonb_build_object('queue',coalesce(v_queue,'[]'::jsonb),'version',coalesce(v_version,0),'clinic_id',v_clinic);
end; $$;