-- MARKYS SGA cloud queue and private file storage.
-- This migration is isolated from the FAVMED project and does not modify
-- the SGA's normalized patient/visit tables or delete existing records.
create schema if not exists app_private;
revoke all on schema app_private from public, anon, authenticated;
grant usage on schema app_private to authenticated;

create table if not exists app_private.markys_sga_queue_state (
  singleton boolean primary key default true check (singleton=true),
  queue jsonb not null default '[]'::jsonb check (jsonb_typeof(queue)='array'),
  version bigint not null default 0,
  updated_by uuid,
  updated_at timestamptz not null default now()
);
alter table app_private.markys_sga_queue_state enable row level security;
revoke all on table app_private.markys_sga_queue_state from public,anon,authenticated;
drop policy if exists markys_sga_queue_state_deny_direct_access on app_private.markys_sga_queue_state;
create policy markys_sga_queue_state_deny_direct_access on app_private.markys_sga_queue_state
for all to public using(false) with check(false);

create or replace function app_private.markys_get_queue_internal()
returns jsonb language plpgsql stable security definer set search_path=pg_catalog as $$
declare v_role text; v_queue jsonb; v_version bigint;
begin
 select p.role into v_role from public.profiles p where p.id=auth.uid() and p.active=true;
 if v_role is null or v_role not in ('master','recepcao','profissional') then
  raise exception 'Perfil inativo ou sem permissão para acessar a fila' using errcode='42501';
 end if;
 select s.queue,s.version into v_queue,v_version from app_private.markys_sga_queue_state s where s.singleton=true;
 return jsonb_build_object('queue',coalesce(v_queue,'[]'::jsonb),'version',coalesce(v_version,0));
end; $$;
create or replace function public.markys_get_queue()
returns jsonb language sql stable security invoker set search_path='' as
$$ select app_private.markys_get_queue_internal(); $$;

create or replace function app_private.markys_update_queue_patients_internal(p_changes jsonb)
returns jsonb language plpgsql volatile security definer set search_path=pg_catalog as $$
declare
 v_role text; v_queue jsonb; v_version bigint; v_new_queue jsonb;
 v_change jsonb; v_id text; v_expected jsonb; v_patient jsonb;
 v_old jsonb; v_found boolean; v_count integer:=0;
begin
 select p.role into v_role from public.profiles p where p.id=auth.uid() and p.active=true;
 if v_role is null or v_role not in ('master','recepcao','profissional') then
  raise exception 'Perfil sem permissão para alterar a fila' using errcode='42501';
 end if;
 if p_changes is null or jsonb_typeof(p_changes)<>'array' or jsonb_array_length(p_changes)>500 then
  raise exception 'Lista de alterações inválida' using errcode='22023';
 end if;
 perform pg_advisory_xact_lock(hashtext('markys_sga_queue_state'));
 select s.queue,s.version into v_queue,v_version from app_private.markys_sga_queue_state s where s.singleton=true for update;
 v_queue:=coalesce(v_queue,'[]'::jsonb); v_version:=coalesce(v_version,0);
 for v_change in select value from jsonb_array_elements(p_changes) loop
  v_id:=nullif(v_change->>'id','');
  v_expected:=nullif(v_change->'expected','null'::jsonb);
  v_patient:=nullif(v_change->'patient','null'::jsonb);
  if v_id is null then raise exception 'Identificador inválido' using errcode='22023'; end if;
  if v_patient is not null and (jsonb_typeof(v_patient)<>'object' or v_patient->>'id' is distinct from v_id) then
   raise exception 'Registro de paciente inválido' using errcode='22023';
  end if;
  select value into v_old from jsonb_array_elements(v_queue) where value->>'id'=v_id limit 1;
  v_found:=found;
  if (case when v_found then v_old else null end) is distinct from v_expected then
   raise exception 'QUEUE_CONFLICT: a fila foi alterada em outro dispositivo' using errcode='40001';
  end if;
  if v_role='profissional' and (not v_found or v_patient is null or
   (v_old-array['status','serviceStates','activeService','calledAt','calledService','calledLabel','callDisplayMode','attendingAt','attendedAt','exitTime','releasedAt']::text[])
   is distinct from
   (v_patient-array['status','serviceStates','activeService','calledAt','calledService','calledLabel','callDisplayMode','attendingAt','attendedAt','exitTime','releasedAt']::text[])) then
   raise exception 'O profissional só pode atualizar o andamento dos atendimentos existentes' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(case when value->>'id'=v_id then v_patient else value end order by ord),'[]'::jsonb)
  into v_new_queue from jsonb_array_elements(v_queue) with ordinality as q(value,ord)
  where not(value->>'id'=v_id and v_patient is null);
  if not v_found and v_patient is not null then v_new_queue:=v_new_queue||jsonb_build_array(v_patient); end if;
  v_queue:=v_new_queue; v_count:=v_count+1;
 end loop;
 if v_count>0 then
  insert into app_private.markys_sga_queue_state(singleton,queue,version,updated_by,updated_at)
  values(true,v_queue,v_version+1,auth.uid(),now())
  on conflict(singleton) do update set queue=excluded.queue,version=excluded.version,updated_by=excluded.updated_by,updated_at=excluded.updated_at;
  v_version:=v_version+1;
 end if;
 return jsonb_build_object('version',v_version,'updated_at',now());
end; $$;
create or replace function public.markys_update_queue_patients(p_changes jsonb)
returns jsonb language sql volatile security invoker set search_path='' as
$$ select app_private.markys_update_queue_patients_internal(p_changes); $$;

create or replace function public.markys_get_public_queue(p_day text)
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

revoke all on function app_private.markys_get_queue_internal() from public,anon;
revoke all on function app_private.markys_update_queue_patients_internal(jsonb) from public,anon,authenticated;
revoke all on function public.markys_get_queue() from public,anon;
revoke all on function public.markys_update_queue_patients(jsonb) from public,anon;
revoke all on function public.markys_get_public_queue(text) from public,authenticated;
grant execute on function app_private.markys_get_queue_internal() to authenticated;
grant execute on function app_private.markys_update_queue_patients_internal(jsonb) to authenticated;
grant execute on function public.markys_get_queue() to authenticated;
grant execute on function public.markys_update_queue_patients(jsonb) to authenticated;
grant execute on function public.markys_get_public_queue(text) to anon;

insert into storage.buckets(id,name,public,file_size_limit)
values('markys-sga-documents','markys-sga-documents',false,52428800),('markys-sga-media','markys-sga-media',false,52428800)
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit;
drop policy if exists markys_sga_documents_read on storage.objects;
drop policy if exists markys_sga_documents_insert on storage.objects;
drop policy if exists markys_sga_documents_delete on storage.objects;
drop policy if exists markys_sga_media_read on storage.objects;
drop policy if exists markys_sga_media_insert on storage.objects;
drop policy if exists markys_sga_media_delete on storage.objects;
create policy markys_sga_documents_read on storage.objects for select to authenticated using(bucket_id='markys-sga-documents' and private.current_active_role()=any(array['master','recepcao','profissional']::text[]));
create policy markys_sga_documents_insert on storage.objects for insert to authenticated with check(bucket_id='markys-sga-documents' and private.current_active_role()=any(array['master','recepcao']::text[]));
create policy markys_sga_documents_delete on storage.objects for delete to authenticated using(bucket_id='markys-sga-documents' and private.current_active_role()=any(array['master','recepcao']::text[]));
create policy markys_sga_media_read on storage.objects for select to authenticated using(bucket_id='markys-sga-media' and private.current_active_role()=any(array['master','recepcao','profissional']::text[]));
create policy markys_sga_media_insert on storage.objects for insert to authenticated with check(bucket_id='markys-sga-media' and private.current_active_role()=any(array['master','recepcao']::text[]));
create policy markys_sga_media_delete on storage.objects for delete to authenticated using(bucket_id='markys-sga-media' and private.current_active_role()=any(array['master','recepcao']::text[]));
