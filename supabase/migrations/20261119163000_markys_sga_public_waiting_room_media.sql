-- The hallway display is public, so only the dedicated slideshow bucket is public.
-- Patient documents remain in a separate private bucket.
update storage.buckets set public=true where id='markys-sga-media';
drop policy if exists markys_sga_media_public_list on storage.objects;
create policy markys_sga_media_public_list on storage.objects for select to anon
using(bucket_id='markys-sga-media');
