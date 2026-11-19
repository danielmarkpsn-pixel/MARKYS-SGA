-- Avoid recursive RLS evaluation between visits, exams, patients and rooms.
-- These narrowly scoped helpers run outside RLS, return booleans only, and are callable
-- by anon solely for the sanitized waiting-room view.
grant usage on schema private to anon;

create or replace function private.public_waiting_room_visit_has_active_exam(p_visit_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is null and exists (
    select 1
    from public.visit_exams e
    where e.visit_id = p_visit_id
      and e.status in ('chamado', 'em_atendimento')
  );
$$;

create or replace function private.public_waiting_room_visit_has_any_exam(p_visit_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is null and exists (
    select 1 from public.visit_exams e where e.visit_id = p_visit_id
  );
$$;

create or replace function private.public_waiting_room_visit_is_visible(p_visit_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is null and exists (
    select 1
    from public.patient_visits v
    where v.id = p_visit_id
      and v.visit_date = current_date
      and v.status <> 'cancelado'
  );
$$;

create or replace function private.public_waiting_room_patient_is_visible(p_patient_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is null and exists (
    select 1
    from public.patient_visits v
    where v.patient_id = p_patient_id
      and v.visit_date = current_date
      and v.status <> 'cancelado'
      and (
        v.status in ('chamado', 'em_atendimento')
        or exists (
          select 1
          from public.visit_exams e
          where e.visit_id = v.id
            and e.status in ('chamado', 'em_atendimento')
        )
      )
  );
$$;

create or replace function private.public_waiting_room_room_is_visible(p_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is null and (
    exists (
      select 1
      from public.patient_visits v
      where v.room_id = p_room_id
        and v.visit_date = current_date
        and v.status in ('chamado', 'em_atendimento')
    )
    or exists (
      select 1
      from public.visit_exams e
      join public.patient_visits v on v.id = e.visit_id
      where e.room_id = p_room_id
        and e.status in ('chamado', 'em_atendimento')
        and v.visit_date = current_date
        and v.status <> 'cancelado'
    )
  );
$$;

revoke all on function private.public_waiting_room_visit_has_active_exam(uuid) from public, authenticated;
revoke all on function private.public_waiting_room_visit_has_any_exam(uuid) from public, authenticated;
revoke all on function private.public_waiting_room_visit_is_visible(uuid) from public, authenticated;
revoke all on function private.public_waiting_room_patient_is_visible(uuid) from public, authenticated;
revoke all on function private.public_waiting_room_room_is_visible(uuid) from public, authenticated;
grant execute on function private.public_waiting_room_visit_has_active_exam(uuid) to anon;
grant execute on function private.public_waiting_room_visit_has_any_exam(uuid) to anon;
grant execute on function private.public_waiting_room_visit_is_visible(uuid) to anon;
grant execute on function private.public_waiting_room_patient_is_visible(uuid) to anon;
grant execute on function private.public_waiting_room_room_is_visible(uuid) to anon;

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
      and private.public_waiting_room_visit_has_active_exam(id)
    )
  )
);

drop policy if exists visit_exams_public_waiting_room_select on public.visit_exams;
create policy visit_exams_public_waiting_room_select
on public.visit_exams
for select to anon
using (
  status in ('chamado', 'em_atendimento')
  and private.public_waiting_room_visit_is_visible(visit_id)
);

drop policy if exists patients_public_waiting_room_select on public.patients;
create policy patients_public_waiting_room_select
on public.patients
for select to anon
using (private.public_waiting_room_patient_is_visible(id));

drop policy if exists rooms_public_waiting_room_select on public.rooms;
create policy rooms_public_waiting_room_select
on public.rooms
for select to anon
using (private.public_waiting_room_room_is_visible(id));

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
  and not private.public_waiting_room_visit_has_any_exam(v.id);

revoke all on public.public_waiting_room_calls from public, authenticated;
grant select on public.public_waiting_room_calls to anon;
