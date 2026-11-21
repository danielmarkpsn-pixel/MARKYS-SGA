grant execute on function private.current_user_clinic_id() to authenticated, service_role;
do $$
declare t text;
begin
 foreach t in array array[
  'patients','patient_visits','visit_exams','rooms','professionals',
  'markys_finance_categories','markys_finance_cost_centers','markys_finance_accounts',
  'markys_finance_entries','markys_insurances','markys_insurance_exam_prices',
  'markys_service_catalog','markys_service_documents','markys_service_document_items'
 ] loop
  execute format(
   'alter table public.%I alter column clinic_id set default coalesce(private.current_user_clinic_id(), %L::uuid)',
   t,'00000000-0000-4000-8000-000000000001'
  );
 end loop;
end $$;