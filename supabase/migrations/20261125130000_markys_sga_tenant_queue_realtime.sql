-- MARKYS SGA: emit private, clinic-scoped Realtime events for the tenant queue.
-- The legacy trigger watches markys_sga_queue_state; tenant writes use
-- markys_sga_queue_tenants, so without this trigger staff screens miss updates.
create or replace function app_private.markys_sga_broadcast_tenant_queue_change()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog
as $$
begin
  perform realtime.send(
    jsonb_build_object('clinic_id',new.clinic_id,'version',new.version),
    'queue_changed',
    'markys-sga-queue-clinic-'||new.clinic_id::text,
    true
  );
  return null;
end;
$$;

drop trigger if exists markys_sga_tenant_queue_broadcast on app_private.markys_sga_queue_tenants;
create trigger markys_sga_tenant_queue_broadcast
after insert or update on app_private.markys_sga_queue_tenants
for each row execute function app_private.markys_sga_broadcast_tenant_queue_change();

revoke all on function app_private.markys_sga_broadcast_tenant_queue_change() from public,anon,authenticated;

drop policy if exists markys_sga_tenant_queue_broadcast_read on realtime.messages;
create policy markys_sga_tenant_queue_broadcast_read
on realtime.messages
for select
to authenticated
using (
  (select realtime.topic()) ~ '^markys-sga-queue-clinic-[0-9a-f-]{36}$'
  and exists (
    select 1
    from public.profiles p
    join public.markys_clinics c
      on c.id=substring((select realtime.topic()) from 25)::uuid
     and c.active=true
    where p.id=(select auth.uid())
      and p.active=true
      and p.role=any(array['master','recepcao','profissional']::text[])
      and (p.role='master' or p.clinic_id=c.id)
  )
);
