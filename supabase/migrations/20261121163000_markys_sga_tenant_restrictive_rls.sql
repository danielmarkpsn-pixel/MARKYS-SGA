-- Tenant row isolation: restrictive policies AND the existing role-specific policies.
-- Master is global administrative role; all other active users are clinic-bound.
create or replace function private.current_user_is_master()
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active=true and p.role='master') $$;
revoke all on function private.current_user_is_master() from public,anon;
grant execute on function private.current_user_is_master() to authenticated;

do $$
declare t text;
begin
 foreach t in array array[
 'patients','patient_visits','visit_exams','rooms','professionals',
 'markys_finance_categories','markys_finance_cost_centers','markys_finance_accounts',
 'markys_finance_entries','markys_insurances','markys_insurance_exam_prices',
 'markys_service_catalog','markys_service_documents','markys_service_document_items'
 ] loop
  execute format('drop policy if exists markys_sga_tenant_restrict_%I on public.%I',t,t);
  execute format('create policy markys_sga_tenant_restrict_%I on public.%I as restrictive for all to authenticated using (private.current_user_is_master() or clinic_id=private.current_user_clinic_id()) with check (private.current_user_is_master() or clinic_id=private.current_user_clinic_id())',t,t);
 end loop;
end $$;
drop policy if exists markys_sga_profiles_tenant_restrict on public.profiles;
create policy markys_sga_profiles_tenant_restrict on public.profiles as restrictive for all to authenticated
using (private.current_user_is_master() or clinic_id=private.current_user_clinic_id())
with check (private.current_user_is_master() or clinic_id=private.current_user_clinic_id());

-- Clinics registry visible only to global Master role, using restrictive policy
-- to ensure no existing permissive policy can expose it to ordinary users.
drop policy if exists markys_sga_clinics_master_read on public.markys_clinics;
create policy markys_sga_clinics_master_permissive on public.markys_clinics for select to authenticated using (private.current_user_is_master());
create policy markys_sga_clinics_master_read on public.markys_clinics as restrictive for select to authenticated
using (private.current_user_is_master());
grant select on public.markys_clinics to authenticated;
