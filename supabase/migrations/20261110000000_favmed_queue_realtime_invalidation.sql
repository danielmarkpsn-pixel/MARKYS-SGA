begin;

create or replace function app_private.broadcast_favmed_queue_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $function$
begin
  perform realtime.send(
    jsonb_build_object('version', new.version),
    'queue_changed',
    'favmed-queue-staff',
    true
  );
  return new;
end;
$function$;

revoke all on function app_private.broadcast_favmed_queue_change() from public, anon, authenticated;

drop trigger if exists favmed_queue_state_realtime_broadcast
  on app_private.favmed_queue_state;

create trigger favmed_queue_state_realtime_broadcast
after update of version on app_private.favmed_queue_state
for each row
when (old.version is distinct from new.version)
execute function app_private.broadcast_favmed_queue_change();

drop policy if exists favmed_staff_receive_queue_broadcast
  on realtime.messages;

create policy favmed_staff_receive_queue_broadcast
on realtime.messages
for select
to authenticated
using (
  (select realtime.topic()) = 'favmed-queue-staff'
  and extension = 'broadcast'
  and exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.active = true
      and p.role in ('master', 'recepcao', 'profissional')
  )
);

commit;
