-- Consolidate permissive policies to reduce repeated RLS evaluation.
drop policy if exists profiles_select_own on public.profiles;
drop policy if exists profiles_select_staff_directory on public.profiles;
create policy profiles_select_authorized
on public.profiles
for select to authenticated
using (
  id = (select auth.uid())
  or (
    private.current_active_role() in ('master', 'recepcao')
    and role in ('profissional', 'sala')
    and active is true
  )
);

drop policy if exists patient_visits_update_reception on public.patient_visits;
drop policy if exists patient_visits_update_professional on public.patient_visits;
create policy patient_visits_update_authorized
on public.patient_visits
for update to authenticated
using (
  private.current_active_role() in ('master', 'recepcao')
  or (
    private.current_active_role() = 'profissional'
    and professional_id = (select auth.uid())
  )
)
with check (
  private.current_active_role() in ('master', 'recepcao')
  or (
    private.current_active_role() = 'profissional'
    and professional_id = (select auth.uid())
  )
);

drop policy if exists visit_exams_update_reception on public.visit_exams;
drop policy if exists visit_exams_update_professional on public.visit_exams;
drop policy if exists visit_exams_update_room on public.visit_exams;
create policy visit_exams_update_authorized
on public.visit_exams
for update to authenticated
using (
  private.current_active_role() in ('master', 'recepcao')
  or (
    private.current_active_role() = 'profissional'
    and private.professional_owns_visit(visit_id)
  )
  or (
    private.current_active_role() = 'sala'
    and exists (
      select 1 from public.rooms r
      where r.id = visit_exams.room_id
        and r.assigned_profile_id = (select auth.uid())
        and r.active is true
    )
  )
)
with check (
  private.current_active_role() in ('master', 'recepcao')
  or (
    private.current_active_role() = 'profissional'
    and private.professional_owns_visit(visit_id)
  )
  or (
    private.current_active_role() = 'sala'
    and exists (
      select 1 from public.rooms r
      where r.id = visit_exams.room_id
        and r.assigned_profile_id = (select auth.uid())
        and r.active is true
    )
  )
);
