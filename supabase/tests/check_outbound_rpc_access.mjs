// Live unauthenticated HTTP probe only. Never creates an Auth user or task.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';

const config = JSON.parse(await readFile(new URL('../../config/supabase.json', import.meta.url), 'utf8'));
const url = new URL(config.SUPABASE_URL);
const key = config.SUPABASE_PUBLISHABLE_KEY;
let publishable = typeof key === 'string' && key.startsWith('sb_publishable_');
if (!publishable && typeof key === 'string' && key.split('.').length === 3) {
  try { publishable = JSON.parse(Buffer.from(key.split('.')[1], 'base64url')).role === 'anon'; } catch { /* fail closed */ }
}
assert.ok(url.protocol === 'https:' && publishable, 'Requires configured HTTPS URL and client publishable/anon key');
for (const name of ['accept_delivery_task', 'start_delivery_task']) {
  const response = await fetch(new URL(`/rest/v1/rpc/${name}`, url), {
    method: 'POST',
    headers: { apikey: key, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_task_id: randomUUID(), p_request_id: randomUUID() }),
    signal: AbortSignal.timeout(15000),
  });
  const result = await response.json();
  assert.ok([401, 403].includes(response.status), `${name}: expected denied HTTP status, got ${response.status}`);
  assert.equal(result.code, '42501', `${name}: expected denied EXECUTE, not a missing RPC`);
  console.log(`${name}: live PostgREST PASS (unauthenticated denied, HTTP ${response.status}/42501; no key/token printed)`);
}
