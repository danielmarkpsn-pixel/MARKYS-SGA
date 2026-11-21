-- Clinic isolation must also honor clinic activation state.
-- A disabled clinic resolves to no clinic for all authenticated tenant RLS checks.
create or replace function private.current_user_clinic_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.clinic_id
  from public.profiles p
  join public.markys_clinics c
    on c.id = p.clinic_id
   and c.active = true
  where p.id = (select auth.uid())
    and p.active = true
    and p.role <> 'master'
  limit 1
$$;