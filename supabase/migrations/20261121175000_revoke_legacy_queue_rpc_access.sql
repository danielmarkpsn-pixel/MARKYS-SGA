-- Disable the legacy single-queue RPCs after the client cutover.
-- The new tenant-aware RPCs are the only operational queue API.
revoke execute on function public.markys_get_queue() from public, anon, authenticated;
revoke execute on function public.markys_update_queue_patient(text,jsonb,jsonb) from public, anon, authenticated;
revoke execute on function public.markys_update_queue_patients(jsonb) from public, anon, authenticated;
revoke execute on function public.markys_get_public_queue(text) from public, anon, authenticated;