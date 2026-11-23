-- Keep clinic media private; the public waiting-room API issues short-lived,
-- clinic-scoped signed URLs after validating an active clinic slug.
update storage.buckets
set public=false
where id='markys-sga-media';

drop policy if exists markys_sga_media_public_list on storage.objects;
