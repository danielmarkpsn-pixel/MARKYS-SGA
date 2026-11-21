
-- Phase 1 foundation: clinic registry and tenant keys. Existing data is assigned
-- to the legacy clinic. Tenant enforcement is intentionally phased separately.
create table if not exists public.markys_clinics (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 160),
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{1,79}$'),
  active boolean not null default true,
  logo_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.markys_clinics enable row level security;
revoke all on public.markys_clinics from anon, authenticated;
grant all on public.markys_clinics to service_role;

insert into public.markys_clinics (id,name,slug,active)
values ('00000000-0000-4000-8000-000000000001','Clínica Principal (dados atuais)','clinica-principal',true)
on conflict (id) do nothing;

alter table public.profiles add column if not exists clinic_id uuid references public.markys_clinics(id);
alter table public.patients add column if not exists clinic_id uuid references public.markys_clinics(id);
alter table public.patient_visits add column if not exists clinic_id uuid references public.markys_clinics(id);
alter table public.visit_exams add column if not exists clinic_id uuid references public.markys_clinics(id);
alter table public.rooms add column if not exists clinic_id uuid references public.markys_clinics(id);
alter table public.professionals add column if not exists clinic_id uuid references public.markys_clinics(id);
alter table public.markys_finance_categories add column if not exists clinic_id uuid references public.markys_clinics(id);
alter table public.markys_finance_cost_centers add column if not exists clinic_id uuid references public.markys_clinics(id);
alter table public.markys_finance_accounts add column if not exists clinic_id uuid references public.markys_clinics(id);
alter table public.markys_finance_entries add column if not exists clinic_id uuid references public.markys_clinics(id);
alter table public.markys_insurances add column if not exists clinic_id uuid references public.markys_clinics(id);
alter table public.markys_insurance_exam_prices add column if not exists clinic_id uuid references public.markys_clinics(id);
alter table public.markys_service_catalog add column if not exists clinic_id uuid references public.markys_clinics(id);
alter table public.markys_service_documents add column if not exists clinic_id uuid references public.markys_clinics(id);
alter table public.markys_service_document_items add column if not exists clinic_id uuid references public.markys_clinics(id);

update public.profiles
set clinic_id = case when role='master' then null else '00000000-0000-4000-8000-000000000001'::uuid end
where clinic_id is null;
update public.patients set clinic_id='00000000-0000-4000-8000-000000000001' where clinic_id is null;
update public.patient_visits set clinic_id='00000000-0000-4000-8000-000000000001' where clinic_id is null;
update public.visit_exams set clinic_id='00000000-0000-4000-8000-000000000001' where clinic_id is null;
update public.rooms set clinic_id='00000000-0000-4000-8000-000000000001' where clinic_id is null;
update public.professionals set clinic_id='00000000-0000-4000-8000-000000000001' where clinic_id is null;
update public.markys_finance_categories set clinic_id='00000000-0000-4000-8000-000000000001' where clinic_id is null;
update public.markys_finance_cost_centers set clinic_id='00000000-0000-4000-8000-000000000001' where clinic_id is null;
update public.markys_finance_accounts set clinic_id='00000000-0000-4000-8000-000000000001' where clinic_id is null;
update public.markys_finance_entries set clinic_id='00000000-0000-4000-8000-000000000001' where clinic_id is null;
update public.markys_insurances set clinic_id='00000000-0000-4000-8000-000000000001' where clinic_id is null;
update public.markys_insurance_exam_prices set clinic_id='00000000-0000-4000-8000-000000000001' where clinic_id is null;
update public.markys_service_catalog set clinic_id='00000000-0000-4000-8000-000000000001' where clinic_id is null;
update public.markys_service_documents set clinic_id='00000000-0000-4000-8000-000000000001' where clinic_id is null;
update public.markys_service_document_items set clinic_id='00000000-0000-4000-8000-000000000001' where clinic_id is null;

alter table public.patients alter column clinic_id set not null;
alter table public.patient_visits alter column clinic_id set not null;
alter table public.visit_exams alter column clinic_id set not null;
alter table public.rooms alter column clinic_id set not null;
alter table public.professionals alter column clinic_id set not null;
alter table public.markys_finance_categories alter column clinic_id set not null;
alter table public.markys_finance_cost_centers alter column clinic_id set not null;
alter table public.markys_finance_accounts alter column clinic_id set not null;
alter table public.markys_finance_entries alter column clinic_id set not null;
alter table public.markys_insurances alter column clinic_id set not null;
alter table public.markys_insurance_exam_prices alter column clinic_id set not null;
alter table public.markys_service_catalog alter column clinic_id set not null;
alter table public.markys_service_documents alter column clinic_id set not null;
alter table public.markys_service_document_items alter column clinic_id set not null;

alter table public.patients alter column clinic_id set default '00000000-0000-4000-8000-000000000001';
alter table public.patient_visits alter column clinic_id set default '00000000-0000-4000-8000-000000000001';
alter table public.visit_exams alter column clinic_id set default '00000000-0000-4000-8000-000000000001';
alter table public.rooms alter column clinic_id set default '00000000-0000-4000-8000-000000000001';
alter table public.professionals alter column clinic_id set default '00000000-0000-4000-8000-000000000001';
alter table public.markys_finance_categories alter column clinic_id set default '00000000-0000-4000-8000-000000000001';
alter table public.markys_finance_cost_centers alter column clinic_id set default '00000000-0000-4000-8000-000000000001';
alter table public.markys_finance_accounts alter column clinic_id set default '00000000-0000-4000-8000-000000000001';
alter table public.markys_finance_entries alter column clinic_id set default '00000000-0000-4000-8000-000000000001';
alter table public.markys_insurances alter column clinic_id set default '00000000-0000-4000-8000-000000000001';
alter table public.markys_insurance_exam_prices alter column clinic_id set default '00000000-0000-4000-8000-000000000001';
alter table public.markys_service_catalog alter column clinic_id set default '00000000-0000-4000-8000-000000000001';
alter table public.markys_service_documents alter column clinic_id set default '00000000-0000-4000-8000-000000000001';
alter table public.markys_service_document_items alter column clinic_id set default '00000000-0000-4000-8000-000000000001';

create index if not exists patients_clinic_id_idx on public.patients(clinic_id);
create index if not exists patient_visits_clinic_id_date_idx on public.patient_visits(clinic_id,visit_date);
create index if not exists visit_exams_clinic_id_idx on public.visit_exams(clinic_id);
create index if not exists rooms_clinic_id_idx on public.rooms(clinic_id);
create index if not exists professionals_clinic_id_idx on public.professionals(clinic_id);
create index if not exists markys_finance_categories_clinic_id_idx on public.markys_finance_categories(clinic_id);
create index if not exists markys_finance_cost_centers_clinic_id_idx on public.markys_finance_cost_centers(clinic_id);
create index if not exists markys_finance_accounts_clinic_id_idx on public.markys_finance_accounts(clinic_id);
create index if not exists markys_finance_entries_clinic_id_idx on public.markys_finance_entries(clinic_id);
create index if not exists markys_insurances_clinic_id_idx on public.markys_insurances(clinic_id);
create index if not exists markys_insurance_exam_prices_clinic_id_idx on public.markys_insurance_exam_prices(clinic_id);
create index if not exists markys_service_catalog_clinic_id_idx on public.markys_service_catalog(clinic_id);
create index if not exists markys_service_documents_clinic_id_idx on public.markys_service_documents(clinic_id);
create index if not exists markys_service_document_items_clinic_id_idx on public.markys_service_document_items(clinic_id);

-- CPF and room names must be unique per clinic, not globally.
alter table public.patients drop constraint if exists patients_cpf_key;
create unique index if not exists patients_clinic_cpf_unique on public.patients(clinic_id,cpf) where cpf is not null;
alter table public.rooms drop constraint if exists rooms_name_key;
create unique index if not exists rooms_clinic_name_unique on public.rooms(clinic_id,name);

create or replace function private.current_user_clinic_id()
returns uuid
language sql
stable
security definer
set search_path=''
as $$
  select p.clinic_id
  from public.profiles p
  where p.id = (select auth.uid())
    and p.active = true
    and p.role <> 'master'
  limit 1
$$;
revoke all on function private.current_user_clinic_id() from public;
grant execute on function private.current_user_clinic_id() to authenticated;

comment on table public.markys_clinics is 'Registry of clinics for MARKYS SGA multi-clinic rollout. Admin access via trusted service function only.';
comment on column public.profiles.clinic_id is 'Tenant clinic id. NULL reserved for global Master accounts.';
