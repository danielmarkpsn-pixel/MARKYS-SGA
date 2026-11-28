import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(
  new URL("../supabase/migrations/20261125120000_markys_sga_tenant_queue_field_merge.sql", import.meta.url),
  "utf8"
);
const mergeMigration = await readFile(
  new URL("../supabase/migrations/20261119170000_markys_sga_daily_queue_field_merge.sql", import.meta.url),
  "utf8"
);
const tenantRpc = await readFile(
  new URL("../supabase/migrations/20261121160000_markys_sga_tenant_queue_rpc.sql", import.meta.url),
  "utf8"
);

assert.match(migration, /create or replace function public\.markys_sga_queue_write_tenant/);
assert.match(migration, /app_private\.markys_sga_merge_queue_patient_patch\(v_expected,v_current,v_patient,v_id\)/);
assert.match(mergeMigration, /create or replace function app_private\.markys_sga_merge_queue_patient_patch/);
assert.match(migration, /pg_advisory_xact_lock\(hashtext\('markys_sga_queue_tenant'\),hashtext\(v_clinic::text\)\)/);
assert.match(migration, /for update/);
assert.match(migration, /v_change_count<1 or v_change_count>500/);
assert.match(migration, /pg_column_size\(p_changes\)>8388608/);
assert.match(migration, /having count\(\*\)>1/);
assert.match(migration, /jsonb_agg[\s\S]*?order by q\.ordinality/);
assert.match(migration, /jsonb_agg\(m\.value->'patient' order by c\.ordinality\)/);
assert.match(migration, /if v_new_queue is not distinct from v_old_queue then/);
assert.match(migration, /v_new_version:=v_version\+1/);
assert.match(migration, /revoke all on function public\.markys_sga_queue_write_tenant\(jsonb,uuid\) from public,anon/);
assert.match(migration, /grant execute on function public\.markys_sga_queue_write_tenant\(jsonb,uuid\) to authenticated/);
assert.match(migration, /v_role='profissional'/);
assert.match(migration, /status','serviceStates','activeService'/);

// Guard against accidentally leaving the tenant RPC on whole-record optimistic equality.
assert.doesNotMatch(migration, /v_current is distinct from v_expected/);
assert.doesNotMatch(migration, /v_current\s*<>\s*v_expected/);
assert.match(tenantRpc, /create or replace function public\.markys_sga_queue_write_tenant/);

console.log("MARKYS SGA tenant queue field-merge guardrails passed.");
