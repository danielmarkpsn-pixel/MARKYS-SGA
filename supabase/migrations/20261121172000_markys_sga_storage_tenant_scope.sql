-- Tenant isolation for private patient documents and authenticated media operations.
-- Storage buckets were verified empty before this path/policy migration.
create policy markys_sga_documents_tenant_scope
on storage.objects as restrictive
for all to authenticated
using (
  bucket_id = 'markys-sga-documents'
  and private.current_active_role() = any(array['master','recepcao','profissional']::text[])
  and (
    private.current_user_is_master()
    or (storage.foldername(name))[1] = 'clinics'
       and (storage.foldername(name))[2] = private.current_user_clinic_id()::text
  )
)
with check (
  bucket_id = 'markys-sga-documents'
  and private.current_active_role() = any(array['master','recepcao']::text[])
  and (
    private.current_user_is_master()
    or (storage.foldername(name))[1] = 'clinics'
       and (storage.foldername(name))[2] = private.current_user_clinic_id()::text
  )
);

create policy markys_sga_media_tenant_scope
on storage.objects as restrictive
for all to authenticated
using (
  bucket_id = 'markys-sga-media'
  and private.current_active_role() = any(array['master','recepcao','profissional']::text[])
  and (
    private.current_user_is_master()
    or (storage.foldername(name))[1] = 'clinics'
       and (storage.foldername(name))[2] = private.current_user_clinic_id()::text
  )
)
with check (
  bucket_id = 'markys-sga-media'
  and private.current_active_role() = any(array['master','recepcao']::text[])
  and (
    private.current_user_is_master()
    or (storage.foldername(name))[1] = 'clinics'
       and (storage.foldername(name))[2] = private.current_user_clinic_id()::text
  )
);

-- The old private patient-documents bucket is unused by current MARKYS SGA code.
-- It contains zero objects; deny new access until it is retired or migrated.
create policy markys_sga_legacy_patient_documents_deny
on storage.objects as restrictive
for all to authenticated
using (bucket_id = 'patient-documents' and false)
with check (bucket_id = 'patient-documents' and false);