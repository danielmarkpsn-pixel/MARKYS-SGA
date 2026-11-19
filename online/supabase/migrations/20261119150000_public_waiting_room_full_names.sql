-- The public display is explicitly required to show the patient's full name.
-- Keep the existing restricted public_display_name column and grants; do not expose
-- CPF, company, exam details, documents, or other patient fields.
create or replace function private.set_public_display_name()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog
as $$
begin
  new.public_display_name := trim(regexp_replace(trim(new.full_name), '\\s+', ' ', 'g'));
  return new;
end;
$$;

revoke all on function private.set_public_display_name() from public, anon, authenticated;

update public.patients
set public_display_name = trim(regexp_replace(trim(full_name), '\\s+', ' ', 'g'))
where public_display_name is distinct from trim(regexp_replace(trim(full_name), '\\s+', ' ', 'g'));
