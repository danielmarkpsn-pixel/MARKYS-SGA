-- Prevent the public waiting-room view from inheriting the creator's privileges.
-- Anonymous users receive only sanitized names and active call destinations.
alter table public.patients
  add column if not exists public_display_name text;

create or replace function private.set_public_display_name()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog
as $$
declare
  normalized_name text;
  name_parts text[];
begin
  normalized_name := trim(regexp_replace(trim(new.full_name), '\s+', ' ', 'g'));
  name_parts := regexp_split_to_array(normalized_name, ' ');
  if coalesce(array_length(name_parts, 1), 0) > 1 then
    new.public_display_name := name_parts[1] || ' ' || left(name_parts[array_length(name_parts, 1)], 1) || '.';
  else
    new.public_display_name := normalized_name;
  end if;
  return new;
end;
$$;
revoke all on function private.set_public_display_name() from public, anon, authenticated;

drop trigger if exists patients_set_public_display_name on public.patients;
create trigger patients_set_public_display_name
before insert or update of full_name on public.patients
for each row execute function private.set_public_display_name();

update public.patients
set public_display_name = case
  when position(' ' in trim(full_name)) > 0 then
    regexp_replace(trim(full_name), '\s+.*$', '') || ' ' ||
    left(regexp_replace(trim(full_name), '^.*\s+', ''), 1) || '.'
  else regexp_replace(trim(full_name), '\s+.*$', '')
end
where public_display_name is null;

-- Base-table access is limited to columns needed by the sanitized public view.
revoke all on table public.patients from anon;
revoke all on table public.patient_visits from anon;
revoke all on table public.visit_exams from anon;
revoke all on table public.rooms from anon;

grant select (id, public_display_name) on public.patients to anon;
grant select (id, patient_id, room_id, visit_date, status, updated_at)
  on public.patient_visits to anon;
grant select (id, visit_id, room_id, status, updated_at)
  on public.visit_exams to anon;
grant select (id, name) on public.rooms to anon;

drop policy if exists patients_public_waiting_room_select on public.patients;
create policy patients_public_waiting_room_select
on public.patients
for select to anon
using (
  exists (
    select 1
    from public.patient_visits v
    where v.patient_id = patients.id
      and v.visit_date = current_date
      and v.status <> 'cancelado'
      and (
        v.status in ('chamado', 'em_atendimento')
        or exists (
          select 1 from public.visit_exams e
          where e.visit_id = v.id
            and e.status in ('chamado', 'em_atendimento')
        )
      )
  )
);

drop policy if exists patient_visits_public_waiting_room_select on public.patient_visits;
create policy patient_visits_public_waiting_room_select
on public.patient_visits
for select to anon
using (
  visit_date = current_date
  and (
    status in ('chamado', 'em_atendimento')
    or (
      status <> 'cancelado'
      and exists (
        select 1 from public.visit_exams e
        where e.visit_id = patient_visits.id
          and e.status in ('chamado', 'em_atendimento')
      )
    )
  )
);

drop policy if exists visit_exams_public_waiting_room_select on public.visit_exams;
create policy visit_exams_public_waiting_room_select
on public.visit_exams
for select to anon
using (
  status in ('chamado', 'em_atendimento')
  and exists (
    select 1 from public.patient_visits v
    where v.id = visit_exams.visit_id
      and v.visit_date = current_date
      and v.status <> 'cancelado'
  )
);

drop policy if exists rooms_public_waiting_room_select on public.rooms;
create policy rooms_public_waiting_room_select
on public.rooms
for select to anon
using (
  exists (
    select 1 from public.patient_visits v
    where v.room_id = rooms.id
      and v.visit_date = current_date
      and (
        v.status in ('chamado', 'em_atendimento')
        or (
          v.status <> 'cancelado'
          and exists (
            select 1 from public.visit_exams e
            where e.visit_id = v.id
              and e.room_id = rooms.id
              and e.status in ('chamado', 'em_atendimento')
          )
        )
      )
  )
  or exists (
    select 1
    from public.visit_exams e
    join public.patient_visits v on v.id = e.visit_id
    where e.room_id = rooms.id
      and e.status in ('chamado', 'em_atendimento')
      and v.visit_date = current_date
      and v.status <> 'cancelado'
  )
);

create or replace view public.public_waiting_room_calls
with (security_barrier = true, security_invoker = true)
as
select
  p.public_display_name as display_name,
  coalesce(r.name, 'Recepção') as room_name,
  e.updated_at as called_at,
  e.status as call_status
from public.visit_exams e
join public.patient_visits v on v.id = e.visit_id
join public.patients p on p.id = v.patient_id
left join public.rooms r on r.id = e.room_id
where e.status in ('chamado', 'em_atendimento')
  and v.visit_date = current_date
  and v.status <> 'cancelado'
union all
select
  p.public_display_name as display_name,
  coalesce(r.name, 'Recepção') as room_name,
  v.updated_at as called_at,
  v.status as call_status
from public.patient_visits v
join public.patients p on p.id = v.patient_id
left join public.rooms r on r.id = v.room_id
where v.status in ('chamado', 'em_atendimento')
  and v.visit_date = current_date
  and not exists (
    select 1 from public.visit_exams e where e.visit_id = v.id
  );

revoke all on public.public_waiting_room_calls from public, authenticated;
grant select on public.public_waiting_room_calls to anon;
