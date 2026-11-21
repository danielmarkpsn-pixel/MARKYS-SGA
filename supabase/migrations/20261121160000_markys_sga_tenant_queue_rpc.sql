-- MARKYS SGA: clinic-scoped queue storage and RPC foundation.
-- Legacy queue RPCs remain untouched until the client migration is verified.
create table if not exists app_private.markys_sga_queue_tenants (
  clinic_id uuid not null references public.markys_clinics(id) on delete cascade,
  service_day date not null,
  queue jsonb not null default '[]'::jsonb check(jsonb_typeof(queue)='array'),
  version bigint not null default 0,
  updated_by uuid,
  updated_at timestamptz not null default now(),
  primary key (clinic_id, service_day)
);
alter table app_private.markys_sga_queue_tenants enable row level security;
revoke all on table app_private.markys_sga_queue_tenants from public,anon,authenticated;
drop policy if exists markys_sga_queue_tenants_deny_direct_access on app_private.markys_sga_queue_tenants;
create policy markys_sga_queue_tenants_deny_direct_access on app_private.markys_sga_queue_tenants for all to public using(false) with check(false);

create or replace function app_private.markys_sga_queue_clinic_for_user(p_requested_clinic uuid default null)
returns uuid language plpgsql stable security definer set search_path=pg_catalog as $$
declare v_role text; v_clinic uuid; v_active boolean;
begin
 select p.role,p.clinic_id into v_role,v_clinic from public.profiles p
 where p.id=(select auth.uid()) and p.active=true;
 if v_role is null then raise exception 'Perfil inativo' using errcode='42501'; end if;
 if v_role='master' then
   if p_requested_clinic is null then raise exception 'Master deve selecionar uma clínica' using errcode='22023'; end if;
   v_clinic:=p_requested_clinic;
 else
   if p_requested_clinic is not null and p_requested_clinic is distinct from v_clinic then
     raise exception 'Acesso a outra clínica não permitido' using errcode='42501';
   end if;
 end if;
 select c.active into v_active from public.markys_clinics c where c.id=v_clinic;
 if v_active is distinct from true then raise exception 'Clínica inativa ou inexistente' using errcode='42501'; end if;
 return v_clinic;
end; $$;
revoke all on function app_private.markys_sga_queue_clinic_for_user(uuid) from public,anon;
grant execute on function app_private.markys_sga_queue_clinic_for_user(uuid) to authenticated;

create or replace function public.markys_sga_queue_get_tenant(p_clinic_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog as $$
declare v_clinic uuid; v_day date:=app_private.markys_sga_local_day(); v_queue jsonb; v_version bigint;
begin
 v_clinic:=app_private.markys_sga_queue_clinic_for_user(p_clinic_id);
 select q.queue,q.version into v_queue,v_version from app_private.markys_sga_queue_tenants q
 where q.clinic_id=v_clinic and q.service_day=v_day;
 return jsonb_build_object('queue',coalesce(v_queue,'[]'::jsonb),'version',coalesce(v_version,0),'clinic_id',v_clinic);
end; $$;

create or replace function public.markys_sga_queue_write_tenant(p_changes jsonb,p_clinic_id uuid default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare
 v_clinic uuid; v_role text; v_day date:=app_private.markys_sga_local_day();
 v_queue jsonb; v_version bigint; v_next jsonb; v_change jsonb; v_id text;
 v_expected jsonb; v_patient jsonb; v_current jsonb; v_found boolean; v_total integer:=0;
begin
 v_clinic:=app_private.markys_sga_queue_clinic_for_user(p_clinic_id);
 select p.role into v_role from public.profiles p where p.id=(select auth.uid()) and p.active=true;
 if v_role not in ('master','recepcao','profissional') then raise exception 'Perfil sem permissão para fila' using errcode='42501'; end if;
 if p_changes is null or jsonb_typeof(p_changes)<>'array' or jsonb_array_length(p_changes)>500 then
   raise exception 'Lista de alterações inválida' using errcode='22023';
 end if;
 perform pg_advisory_xact_lock(hashtext('markys_sga_queue_tenant'),hashtext(v_clinic::text));
 select q.queue,q.version into v_queue,v_version from app_private.markys_sga_queue_tenants q
 where q.clinic_id=v_clinic and q.service_day=v_day for update;
 v_queue:=coalesce(v_queue,'[]'::jsonb); v_version:=coalesce(v_version,0);
 for v_change in select value from jsonb_array_elements(p_changes) loop
  v_id:=nullif(v_change->>'id',''); v_expected:=nullif(v_change->'expected','null'::jsonb); v_patient:=nullif(v_change->'patient','null'::jsonb);
  if v_id is null then raise exception 'Identificador inválido' using errcode='22023'; end if;
  if v_patient is not null and (jsonb_typeof(v_patient)<>'object' or v_patient->>'id' is distinct from v_id or v_patient->>'day' is distinct from v_day::text) then
   raise exception 'Registro de paciente inválido ou data fora do dia corrente' using errcode='22023';
  end if;
  select value into v_current from jsonb_array_elements(v_queue) where value->>'id'=v_id limit 1; v_found:=found;
  if (case when v_found then v_current else null end) is distinct from v_expected then
   raise exception 'QUEUE_CONFLICT: fila alterada; atualize antes de salvar' using errcode='40001';
  end if;
  if v_role='profissional' and (not v_found or v_patient is null or
   (v_current-array['status','serviceStates','activeService','calledAt','calledService','calledLabel','callDisplayMode','attendingAt','attendedAt','exitTime','releasedAt']::text[])
   is distinct from
   (v_patient-array['status','serviceStates','activeService','calledAt','calledService','calledLabel','callDisplayMode','attendingAt','attendedAt','exitTime','releasedAt']::text[])) then
   raise exception 'Profissional só pode alterar andamento dos atendimentos existentes' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(case when value->>'id'=v_id then v_patient else value end order by ord),'[]'::jsonb)
   into v_next from jsonb_array_elements(v_queue) with ordinality as x(value,ord)
   where not(value->>'id'=v_id and v_patient is null);
  if not v_found and v_patient is not null then v_next:=v_next||jsonb_build_array(v_patient); end if;
  v_queue:=v_next; v_total:=v_total+1;
 end loop;
 if v_total>0 then
  insert into app_private.markys_sga_queue_tenants(clinic_id,service_day,queue,version,updated_by,updated_at)
  values(v_clinic,v_day,v_queue,v_version+1,(select auth.uid()),now())
  on conflict(clinic_id,service_day) do update set queue=excluded.queue,version=excluded.version,updated_by=excluded.updated_by,updated_at=excluded.updated_at;
  v_version:=v_version+1;
 end if;
 return jsonb_build_object('version',v_version,'clinic_id',v_clinic,'updated_at',now());
end; $$;

create or replace function public.markys_sga_public_queue_tenant(p_day text,p_clinic_slug text)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog as $$
declare v_day date:=app_private.markys_sga_local_day(); v_clinic uuid; v_queue jsonb; v_version bigint; v_public jsonb;
begin
 if p_day is null or p_day !~ '^\d{4}-\d{2}-\d{2}$' or p_day<>v_day::text then
  raise exception 'A tela pública só consulta o dia atual' using errcode='22023';
 end if;
 select c.id into v_clinic from public.markys_clinics c where c.slug=p_clinic_slug and c.active=true;
 if v_clinic is null then raise exception 'Clínica não encontrada ou inativa' using errcode='42501'; end if;
 select q.queue,q.version into v_queue,v_version from app_private.markys_sga_queue_tenants q where q.clinic_id=v_clinic and q.service_day=v_day;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',p.value->'id','name',coalesce(nullif(trim(p.value->>'name'),''),'Paciente'),
  'room',p.value->'room','rooms',p.value->'rooms','services',p.value->'services','service',p.value->'service',
  'serviceStates',(select coalesce(jsonb_object_agg(st.key,jsonb_build_object('status',st.value->'status','updatedAt',st.value->'updatedAt','callLabel',st.value->'callLabel')),'{}'::jsonb) from jsonb_each(coalesce(p.value->'serviceStates','{}'::jsonb)) st),
  'status',p.value->'status','priority',p.value->'priority','created',p.value->'created','time',p.value->'time','day',p.value->'day',
  'receptionCall',case when jsonb_typeof(p.value->'receptionCall')='object' then jsonb_build_object('status',p.value->'receptionCall'->'status','service',p.value->'receptionCall'->'service','callLabel',p.value->'receptionCall'->'callLabel','updatedAt',p.value->'receptionCall'->'updatedAt') else null end
 )),'[]'::jsonb) into v_public from jsonb_array_elements(coalesce(v_queue,'[]'::jsonb)) p(value)
 where p.value->>'day'=v_day::text and (p.value->>'status' in ('Chamado','Atendendo')
 or exists(select 1 from jsonb_each(coalesce(p.value->'serviceStates','{}'::jsonb)) st where st.value->>'status' in ('Chamado','Atendendo'))
 or p.value->'receptionCall'->>'status'='Chamado');
 return jsonb_build_object('queue',v_public,'version',coalesce(v_version,0),'clinic_slug',p_clinic_slug);
end; $$;

revoke all on function public.markys_sga_queue_get_tenant(uuid) from public,anon;
revoke all on function public.markys_sga_queue_write_tenant(jsonb,uuid) from public,anon;
revoke all on function public.markys_sga_public_queue_tenant(text,text) from public,authenticated;
grant execute on function public.markys_sga_queue_get_tenant(uuid) to authenticated;
grant execute on function public.markys_sga_queue_write_tenant(jsonb,uuid) to authenticated;
grant execute on function public.markys_sga_public_queue_tenant(text,text) to anon;

-- Realtime topic includes tenant id. This function intentionally only publishes
-- clinic/version metadata, not patient payload.
create or replace function app_private.markys_sga_broadcast_tenant_queue_change()
returns trigger language plpgsql security definer set search_path=pg_catalog as $$
begin
 perform realtime.send(jsonb_build_object('version',new.version,'clinic_id',new.clinic_id),
  'queue_changed','markys-sga-queue-clinic-'||new.clinic_id::text,true);
 return null;
end; $$;
drop trigger if exists markys_sga_queue_tenant_broadcast on app_private.markys_sga_queue_tenants;
create trigger markys_sga_queue_tenant_broadcast after insert or update on app_private.markys_sga_queue_tenants
for each row execute function app_private.markys_sga_broadcast_tenant_queue_change();
revoke all on function app_private.markys_sga_broadcast_tenant_queue_change() from public,anon,authenticated;

create policy markys_sga_staff_tenant_queue_broadcast_read on realtime.messages for select to authenticated
using ((select realtime.topic()) like 'markys-sga-queue-clinic-%' and exists(
 select 1 from public.profiles p where p.id=(select auth.uid()) and p.active=true
 and (p.role='master' or p.clinic_id::text=split_part((select realtime.topic()),'markys-sga-queue-clinic-',2))
 and p.role=any(array['master','recepcao','profissional']::text[])
));

-- Existing clinics remain queued with empty snapshots; old singleton queue stays active
-- until client releases tenant-aware RPCs, avoiding a production cutover without UI support.
comment on table app_private.markys_sga_queue_tenants is 'Tenant-specific queue snapshots. New tenant RPCs use this table; legacy queue remains live until app cutover.';
