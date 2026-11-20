-- Convênios, tabelas de preços independentes e documentos internos de serviço.
create table if not exists public.markys_insurances (
 id uuid primary key default gen_random_uuid(), name text not null check(length(trim(name)) between 1 and 140), code text, contact_name text, contact_email text, contact_phone text, billing_notes text, active boolean not null default true, created_by uuid not null references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index if not exists markys_insurances_name_uq on public.markys_insurances(lower(trim(name)));
create table if not exists public.markys_insurance_exam_prices (
 id uuid primary key default gen_random_uuid(), insurance_id uuid not null references public.markys_insurances(id) on delete restrict, exam_name text not null check(length(trim(exam_name)) between 1 and 180), amount numeric(14,2) not null check(amount>=0), active boolean not null default true, notes text, created_by uuid not null references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(insurance_id,exam_name)
);
create index if not exists markys_insurance_exam_prices_active_idx on public.markys_insurance_exam_prices(insurance_id,active,exam_name);
create sequence if not exists public.markys_service_document_seq;
create table if not exists public.markys_service_documents (
 id uuid primary key default gen_random_uuid(), document_number text not null unique, insurance_id uuid references public.markys_insurances(id) on delete set null, insurance_name text not null, patient_name text not null, patient_cpf text, patient_id text, service_date date not null default (now() at time zone 'America/Manaus')::date, total_amount numeric(14,2) not null check(total_amount>=0), status text not null default 'open' check(status in ('open','billed','cancelled')), notes text, created_by uuid not null references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.markys_service_document_items (
 id uuid primary key default gen_random_uuid(), document_id uuid not null references public.markys_service_documents(id) on delete cascade, exam_name text not null, quantity integer not null default 1 check(quantity>0), unit_amount numeric(14,2) not null check(unit_amount>=0), total_amount numeric(14,2) not null check(total_amount>=0), created_at timestamptz not null default now()
);
create index if not exists markys_service_documents_insurance_date_idx on public.markys_service_documents(insurance_id,service_date desc);
create index if not exists markys_service_document_items_document_idx on public.markys_service_document_items(document_id);
alter table public.markys_insurances enable row level security;
alter table public.markys_insurance_exam_prices enable row level security;
alter table public.markys_service_documents enable row level security;
alter table public.markys_service_document_items enable row level security;
revoke all on public.markys_insurances,public.markys_insurance_exam_prices,public.markys_service_documents,public.markys_service_document_items from anon,public;
grant select,insert,update,delete on public.markys_insurances,public.markys_insurance_exam_prices,public.markys_service_documents,public.markys_service_document_items to authenticated;
grant usage,select on sequence public.markys_service_document_seq to authenticated;
create policy markys_insurances_read_staff on public.markys_insurances for select to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','recepcao','profissional')));
create policy markys_insurances_manage_finance on public.markys_insurances for all to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro'))) with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro')));
create policy markys_insurance_prices_read_staff on public.markys_insurance_exam_prices for select to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','recepcao','profissional')));
create policy markys_insurance_prices_manage_finance on public.markys_insurance_exam_prices for all to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro'))) with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro')));
create policy markys_service_docs_read_staff on public.markys_service_documents for select to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','recepcao')));
create policy markys_service_docs_insert_staff on public.markys_service_documents for insert to authenticated with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','recepcao')));
create policy markys_service_docs_manage_finance on public.markys_service_documents for update to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro'))) with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro')));
create policy markys_service_items_read_staff on public.markys_service_document_items for select to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','recepcao')));
create policy markys_service_items_insert_staff on public.markys_service_document_items for insert to authenticated with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro','recepcao')));
create policy markys_service_items_manage_finance on public.markys_service_document_items for all to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro'))) with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and p.role in ('master','financeiro')));
create or replace function public.markys_create_service_document(p_insurance_id uuid,p_insurance_name text,p_patient_name text,p_patient_cpf text,p_patient_id text,p_service_date date,p_items jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_role text; v_number text; v_doc public.markys_service_documents%rowtype; v_total numeric(14,2);
begin
 select role into v_role from public.profiles where id=auth.uid() and active;
 if v_role is null or v_role not in ('master','financeiro','recepcao') then raise exception 'Acesso não autorizado para emitir documento de serviço.'; end if;
 if coalesce(trim(p_patient_name),'')='' or coalesce(trim(p_insurance_name),'')='' then raise exception 'Informe paciente e convênio.'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Inclua pelo menos um exame.'; end if;
 select coalesce(sum((x->>'quantity')::integer*(x->>'unit_amount')::numeric),0) into v_total from jsonb_array_elements(p_items) x where coalesce(trim(x->>'exam_name'),'')<>'' and (x->>'quantity')::integer>0 and (x->>'unit_amount')::numeric>=0;
 if v_total<0 then raise exception 'Valor inválido.'; end if;
 v_number:='MS-'||to_char(coalesce(p_service_date,current_date),'YYYYMMDD')||'-'||lpad(nextval('public.markys_service_document_seq')::text,6,'0');
 insert into public.markys_service_documents(document_number,insurance_id,insurance_name,patient_name,patient_cpf,patient_id,service_date,total_amount,created_by)
 values(v_number,p_insurance_id,trim(p_insurance_name),trim(p_patient_name),nullif(trim(p_patient_cpf),''),nullif(trim(p_patient_id),''),coalesce(p_service_date,current_date),v_total,auth.uid()) returning * into v_doc;
 insert into public.markys_service_document_items(document_id,exam_name,quantity,unit_amount,total_amount)
 select v_doc.id,trim(x->>'exam_name'),(x->>'quantity')::integer,(x->>'unit_amount')::numeric,(x->>'quantity')::integer*(x->>'unit_amount')::numeric from jsonb_array_elements(p_items) x where coalesce(trim(x->>'exam_name'),'')<>'' and (x->>'quantity')::integer>0 and (x->>'unit_amount')::numeric>=0;
 return jsonb_build_object('id',v_doc.id,'document_number',v_doc.document_number,'total_amount',v_doc.total_amount);
end $$;
revoke all on function public.markys_create_service_document(uuid,text,text,text,text,date,jsonb) from public,anon;
grant execute on function public.markys_create_service_document(uuid,text,text,text,text,date,jsonb) to authenticated;
