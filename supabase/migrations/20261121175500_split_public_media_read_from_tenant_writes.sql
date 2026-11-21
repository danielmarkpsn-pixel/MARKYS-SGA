-- Public media can be viewed across clinics by design; write actions remain tenant-scoped.
drop policy if exists markys_sga_media_tenant_scope on storage.objects;
create policy markys_sga_media_tenant_read
on storage.objects as restrictive
for select to authenticated
using (
 bucket_id='markys-sga-media'
 and private.current_active_role() = any(array['master','recepcao','profissional']::text[])
);
create policy markys_sga_media_tenant_insert
on storage.objects as restrictive
for insert to authenticated
with check (
 bucket_id='markys-sga-media'
 and private.current_active_role() = any(array['master','recepcao']::text[])
 and (
  private.current_user_is_master()
  or (storage.foldername(name))[1]='clinics'
     and (storage.foldername(name))[2]=private.current_user_clinic_id()::text
 )
);
create policy markys_sga_media_tenant_update
on storage.objects as restrictive
for update to authenticated
using (
 bucket_id='markys-sga-media'
 and private.current_active_role() = any(array['master','recepcao']::text[])
 and (
  private.current_user_is_master()
  or (storage.foldername(name))[1]='clinics'
     and (storage.foldername(name))[2]=private.current_user_clinic_id()::text
 )
)
with check (
 bucket_id='markys-sga-media'
 and private.current_active_role() = any(array['master','recepcao']::text[])
 and (
  private.current_user_is_master()
  or (storage.foldername(name))[1]='clinics'
     and (storage.foldername(name))[2]=private.current_user_clinic_id()::text
 )
);
create policy markys_sga_media_tenant_delete
on storage.objects as restrictive
for delete to authenticated
using (
 bucket_id='markys-sga-media'
 and private.current_active_role() = any(array['master','recepcao']::text[])
 and (
  private.current_user_is_master()
  or (storage.foldername(name))[1]='clinics'
     and (storage.foldername(name))[2]=private.current_user_clinic_id()::text
 )
);