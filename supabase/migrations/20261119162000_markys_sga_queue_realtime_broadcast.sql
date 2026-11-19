-- Private Realtime notification for staff queue updates. Only the queue version
-- is broadcast; patient data remains inside the protected RPC response.
create or replace function app_private.markys_sga_broadcast_queue_change()
returns trigger language plpgsql security definer set search_path=pg_catalog as $$
begin
  perform realtime.send(jsonb_build_object('version',new.version),'queue_changed','markys-sga-queue-staff',true);
  return null;
end; $$;
drop trigger if exists markys_sga_queue_broadcast on app_private.markys_sga_queue_state;
create trigger markys_sga_queue_broadcast after insert or update on app_private.markys_sga_queue_state
for each row execute function app_private.markys_sga_broadcast_queue_change();
drop policy if exists markys_sga_staff_queue_broadcast_read on realtime.messages;
create policy markys_sga_staff_queue_broadcast_read on realtime.messages for select to authenticated
using ((select realtime.topic())='markys-sga-queue-staff' and exists(
 select 1 from public.profiles p where p.id=auth.uid() and p.active=true
 and p.role=any(array['master','recepcao','profissional']::text[])
));
revoke all on function app_private.markys_sga_broadcast_queue_change() from public,anon,authenticated;
