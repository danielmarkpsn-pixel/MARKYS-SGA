-- Restrictive Storage policies must not block objects in other buckets.
drop policy if exists markys_sga_documents_tenant_scope on storage.objects;
create policy markys_sga_documents_tenant_scope
on storage.objects as restrictive
for all to authenticated
using (
 bucket_id <> 'markys-sga-documents'
 or (
  bucket_id = 'markys-sga-documents'
  and private.current_active_role() = any(array['master','recepcao','profissional']::text[])
  and (
   private.current_user_is_master()
   or ((storage.foldername(name))[1] = 'clinics' and (storage.foldername(name))[2] = private.current_user_clinic_id()::text)
  )
 )
)
with check (
 bucket_id <> 'markys-sga-documents'
 or (
  bucket_id = 'markys-sga-documents'
  and private.current_active_role() = any(array['master','recepcao']::text[])
  and (
   private.current_user_is_master()
   or ((storage.foldername(name))[1] = 'clinics' and (storage.foldername(name))[2] = private.current_user_clinic_id()::text)
  )
 )
);

drop policy if exists markys_sga_legacy_patient_documents_deny on storage.objects;
create policy markys_sga_legacy_patient_documents_deny
on storage.objects as restrictive
for all to authenticated
using (bucket_id <> 'patient-documents')
with check (bucket_id <> 'patient-documents');

drop policy if exists markys_sga_media_tenant_read on storage.objects;
create policy markys_sga_media_tenant_read
on storage.objects as restrictive
for select to authenticated
using (
 bucket_id <> 'markys-sga-media'
 or (bucket_id = 'markys-sga-media' and private.current_active_role() = any(array['master','recepcao','profissional']::text[]))
);

drop policy if exists markys_sga_media_tenant_insert on storage.objects;
create policy markys_sga_media_tenant_insert
on storage.objects as restrictive
for insert to authenticated
with check (
 bucket_id <> 'markys-sga-media'
 or (
  bucket_id='markys-sga-media'
  and private.current_active_role() = any(array['master','recepcao']::text[])
  and (
   private.current_user_is_master()
   or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)
  )
 )
);

drop policy if exists markys_sga_media_tenant_update on storage.objects;
create policy markys_sga_media_tenant_update
on storage.objects as restrictive
for update to authenticated
using (
 bucket_id <> 'markys-sga-media'
 or (
  bucket_id='markys-sga-media'
  and private.current_active_role() = any(array['master','recepcao']::text[])
  and (
   private.current_user_is_master()
   or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)
  )
 )
)
with check (
 bucket_id <> 'markys-sga-media'
 or (
  bucket_id='markys-sga-media'
  and private.current_active_role() = any(array['master','recepcao']::text[])
  and (
   private.current_user_is_master()
   or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)
  )
 )
);

drop policy if exists markys_sga_media_tenant_delete on storage.objects;
create policy markys_sga_media_tenant_delete
on storage.objects as restrictive
for delete to authenticated
using (
 bucket_id <> 'markys-sga-media'
 or (
  bucket_id='markys-sga-media'
  and private.current_active_role() = any(array['master','recepcao']::text[])
  and (
   private.current_user_is_master()
   or ((storage.foldername(name))[1]='clinics' and (storage.foldername(name))[2]=private.current_user_clinic_id()::text)
  )
 )
);