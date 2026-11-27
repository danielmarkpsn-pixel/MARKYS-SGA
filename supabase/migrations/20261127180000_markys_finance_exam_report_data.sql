-- Dados históricos da fila para dashboard e relatórios financeiros por convênio.
create or replace function public.markys_finance_exam_report_data(
 p_from date,
 p_to date,
 p_insurance_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,app_private
as $$
declare
 v_role text;
 v_clinic_id uuid;
 v_rows jsonb;
begin
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>730 then
  raise exception 'Período inválido. Informe até 731 dias.' using errcode='22023';
 end if;
 select p.role into v_role
 from public.profiles p
 where p.id=(select auth.uid()) and p.active=true;
 if v_role is null or v_role not in ('master','financeiro','administrador') then
  raise exception 'Acesso não autorizado ao relatório financeiro.' using errcode='42501';
 end if;
 v_clinic_id:=app_private.markys_sga_queue_clinic_for_user(null);
 select coalesce(jsonb_agg(
   jsonb_build_object('service_day',q.service_day,'patient',patient_row.value)
   order by q.service_day, patient_row.value->>'name'
 ),'[]'::jsonb)
 into v_rows
 from app_private.markys_sga_queue_tenants q
 cross join lateral jsonb_array_elements(q.queue) as patient_row(value)
 where q.clinic_id=v_clinic_id
   and q.service_day between p_from and p_to
   and (p_insurance_id is null or patient_row.value->>'insuranceId'=p_insurance_id::text);
 return v_rows;
end;
$$;
revoke all on function public.markys_finance_exam_report_data(date,date,uuid) from public,anon;
grant execute on function public.markys_finance_exam_report_data(date,date,uuid) to authenticated;
