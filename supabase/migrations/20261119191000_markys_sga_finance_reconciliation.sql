alter table public.markys_finance_entries add column if not exists reconciled boolean not null default false;
alter table public.markys_finance_entries add column if not exists reconciled_at timestamptz;
create index if not exists markys_finance_entries_reconciliation_idx on public.markys_finance_entries(account_id,payment_date,reconciled) where status='paid';