import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(
  new URL("../supabase/migrations/20261125130000_markys_sga_tenant_queue_realtime.sql", import.meta.url),
  "utf8"
);
const tenantRpc = await readFile(
  new URL("../supabase/migrations/20261121160000_markys_sga_tenant_queue_rpc.sql", import.meta.url),
  "utf8"
);
const client = await readFile(new URL("../markys-cloud.js", import.meta.url), "utf8");

assert.match(tenantRpc, /create table if not exists app_private\.markys_sga_queue_tenants/);
assert.match(migration, /create or replace function app_private\.markys_sga_broadcast_tenant_queue_change/);
assert.match(migration, /after insert or update on app_private\.markys_sga_queue_tenants/);
assert.match(migration, /realtime\.send\([\s\S]*?'queue_changed'[\s\S]*?'markys-sga-queue-clinic-'/);
assert.match(migration, /jsonb_build_object\('clinic_id',new\.clinic_id,'version',new\.version\)/);
assert.match(migration, /realtime\.topic\(\)/);
assert.match(migration, /p\.role='master' or p\.clinic_id=c\.id/);
assert.match(migration, /c\.active=true/);
assert.match(migration, /p\.active=true/);
assert.match(migration, /p\.role=any\(array\['master','recepcao','profissional'\]::text\[\]\)/);
assert.match(client, /client\.channel\("markys-sga-queue-clinic-" \+ clinicId, \{ config: \{ private: true \} \}\)/);
assert.match(client, /\.on\("broadcast", \{ event: "queue_changed" \}/);

console.log("MARKYS SGA tenant queue Realtime guardrails passed.");
