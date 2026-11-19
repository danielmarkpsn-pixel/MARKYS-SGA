-- MARKYS SGA Finance module. Independent financial records with RLS.
create table if not exists public.markys_finance_categories (
 id uuid primary key default gen_random_uuid(), name text not null check(length(trim(name)) between 1 and 100),
 direction text not null check(direction in ('receivable','payable')), color text not null default '#64748b',
 active boolean not null default true, created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.markys_finance_cost_centers (
 id uuid primary key default gen_random_uuid(), name text not null check(length(trim(name)) between 1 and 100),
 description text, active boolean not null default true, created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.markys_finance_accounts (
 id uuid primary key default gen_random_uuid(), name text not null check(length(trim(name)) between 1 and 100),
 account_type text not null check(account_type in ('cash','checking','savings','credit_card','other')),
 institution text, initial_balance numeric(14,2) not null default 0, active boolean not null default true,
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.markys_finance_entries (
 id uuid primary key default gen_random_uuid(), direction text not null check(direction in ('receivable','payable')),
 description text not null check(length(trim(description)) between 1 and 240), counterparty text, patient_reference text,
 document_number text, amount numeric(14,2) not null check(amount>0), currency text not null default 'BRL' check(currency='BRL'),
 competence_date date not null default (now() at time zone 'America/Manaus')::date, due_date date not null, payment_date date,
 status text not null default 'pending' check(status in ('pending','paid','overdue','cancelled')),
 payment_method text check(payment_method in ('pix','cash','debit_card','credit_card','bank_transfer','boleto','insurance','other')),
 account_id uuid references public.markys_finance_accounts(id) on delete set null,
 category_id uuid references public.markys_finance_categories(id) on delete set null,
 cost_center_id uuid references public.markys_finance_cost_centers(id) on delete set null,
 installment_group uuid, installment_number integer check(installment_number is null or installment_number>0),
 installment_total integer check(installment_total is null or installment_total>0),
 recurrence text check(recurrence is null or recurrence in ('weekly','monthly','quarterly','yearly')), notes text,
 created_by uuid not null references auth.users(id), updated_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check((status='paid' and payment_date is not null) or status<>'paid'),
 check(installment_number is null or installment_total is null or installment_number<=installment_total)
);
create index if not exists markys_finance_entries_due_idx on public.markys_finance_entries(due_date,status,direction);
create index if not exists markys_finance_entries_competence_idx on public.markys_finance_entries(competence_date,direction);
create index if not exists markys_finance_entries_account_idx on public.markys_finance_entries(account_id,payment_date);
create index if not exists markys_finance_entries_category_idx on public.markys_finance_entries(category_id);
create index if not exists markys_finance_entries_installment_idx on public.markys_finance_entries(installment_group);
alter table public.markys_finance_categories enable row level security;
alter table public.markys_finance_cost_centers enable row level security;
alter table public.markys_finance_accounts enable row level security;
alter table public.markys_finance_entries enable row level security;
revoke all on public.markys_finance_categories,public.markys_finance_cost_centers,public.markys_finance_accounts,public.markys_finance_entries from anon,public;
grant select,insert,update,delete on public.markys_finance_categories,public.markys_finance_cost_centers,public.markys_finance_accounts,public.markys_finance_entries to authenticated;
create policy markys_finance_categories_access on public.markys_finance_categories for all to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro'))) with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro')));
create policy markys_finance_cost_centers_access on public.markys_finance_cost_centers for all to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro'))) with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro')));
create policy markys_finance_accounts_access on public.markys_finance_accounts for all to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro'))) with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro')));
create policy markys_finance_entries_access on public.markys_finance_entries for all to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro'))) with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro')));
