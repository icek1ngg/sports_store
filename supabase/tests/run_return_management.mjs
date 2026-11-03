// Return management (manager) migration/SQL/concurrency runner. Isolated
// native PostgreSQL 17 fixture only; never contacts Supabase/cloud, resets or
// drops a database. The SQL suite rolls back; the committed race fixture is
// removed in its finally block.
import { readFile, readdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const testDir = dirname(fileURLToPath(import.meta.url));
const root = resolve(testDir, '..');
const require = createRequire(resolve(root, '.temp/p011_pg_runtime/package.json'));
const { Client } = require('pg');
const database = process.argv[2] || `p011_mh15_return_mgmt_${Date.now()}`;
if (!/^p011_[a-z0-9_]+$/.test(database)) throw new Error('database must use p011_ prefix');
const options = { host: '127.0.0.1', port: 55439, user: 'postgres', database: 'postgres' };

const admin = new Client(options);
await admin.connect();
try {
  const version = (await admin.query('show server_version')).rows[0].server_version;
  const dataDirectory = (await admin.query('show data_directory')).rows[0].data_directory;
  if (!version.startsWith('17.')
      || resolve(dataDirectory).toLowerCase() !== resolve(root, '.temp/p011_native_data').toLowerCase()) {
    throw new Error('Refusing PostgreSQL outside the workspace PG17 fixture runtime');
  }
  await admin.query(`create database "${database}"`);
} finally {
  await admin.end();
}

const db = { ...options, database };
const client = new Client(db);
await client.connect();
try {
  await client.query("set sports_store.fixture_mode = 'p011_isolated'");
  await client.query(await readFile(resolve(testDir, 'fixtures/p011_auth_storage.sql.fixture'), 'utf8'));
  await client.query(await readFile(resolve(testDir, 'fixtures/mh13_storage_metadata.sql.fixture'), 'utf8'));
  const migrations = (await readdir(resolve(root, 'migrations'))).filter(n => n.endsWith('.sql')).sort();
  for (const name of migrations) {
    await client.query(await readFile(resolve(root, 'migrations', name), 'utf8'));
  }
  console.log(`Migrations applied: ${migrations.length} (last ${migrations.at(-1)})`);

  const result = await client.query(await readFile(resolve(testDir, 'return_management.sql'), 'utf8'));
  const pass = result.some(s => s.rows?.some(r => Object.values(r).includes('return_management.sql: PASS')));
  if (!pass || result.at(-1)?.command !== 'ROLLBACK') throw new Error('return_management.sql did not PASS + ROLLBACK');
  console.log('return_management.sql: PASS (transaction rolled back)');

  const phase2 = await client.query(await readFile(resolve(testDir, 'return_management_resolution.sql'), 'utf8'));
  const pass2 = phase2.some(s => s.rows?.some(r => Object.values(r).includes('return_management_resolution.sql: PASS')));
  if (!pass2 || phase2.at(-1)?.command !== 'ROLLBACK') throw new Error('return_management_resolution.sql did not PASS + ROLLBACK');
  console.log('return_management_resolution.sql: PASS (transaction rolled back)');

  await testConcurrency();
  console.log(`Return management SQL/concurrency: PASS (${database})`);
} finally {
  await client.end();
}

async function testConcurrency() {
  const ids = {
    customer: '15159000-0000-4000-8000-000000000001',
    manager: '15159000-0000-4000-8000-000000000002',
    shipper: '15159000-0000-4000-8000-000000000003',
    category: '15159000-0000-4000-8000-000000000010',
    product: '15159000-0000-4000-8000-000000000011',
    variant: '15159000-0000-4000-8000-000000000012',
  };
  const orders = ['15159100-0000-4000-8000-000000000001', '15159100-0000-4000-8000-000000000002'];
  const items = ['15159200-0000-4000-8000-000000000001', '15159200-0000-4000-8000-000000000002'];
  const returns = [];
  await client.query('begin');
  await client.query(`insert into auth.users (id, email) values
    ('${ids.customer}', 'race-c@example.invalid'), ('${ids.manager}', 'race-m@example.invalid'),
    ('${ids.shipper}', 'race-s@example.invalid')`);
  await client.query(`update public.profiles set role = case id
      when '${ids.manager}' then 'manager'::public.user_role
      when '${ids.shipper}' then 'shipper'::public.user_role else 'customer'::public.user_role end
    where id in ('${ids.customer}', '${ids.manager}', '${ids.shipper}')`);
  await client.query(`insert into public.categories (id, code, name) values ('${ids.category}', 'RACE15', 'race')`);
  await client.query(`insert into public.products (id, category_id, name) values ('${ids.product}', '${ids.category}', 'race')`);
  await client.query(`insert into public.product_variants (id, product_id, sku, label, price_vnd, on_hand, reserved, damaged)
    values ('${ids.variant}', '${ids.product}', 'RACE15-01', 'x', 100000, 5, 0, 0)`);
  for (let i = 0; i < 2; i++) {
    await client.query(`insert into public.orders (id, customer_id, request_id, status, recipient_name, recipient_phone,
        address_detail, latitude, longitude, subtotal_vnd, delivery_fee_vnd, delivered_at)
      values ('${orders[i]}', '${ids.customer}', gen_random_uuid(), 'delivered', 'Race', '0900000000',
        'Hà Nội', 21.03, 105.8, 100000, 30000, now() - interval '1 day')`);
    await client.query(`insert into public.order_items (id, order_id, product_id, variant_id, product_name, variant_label, unit_price_vnd, quantity)
      values ('${items[i]}', '${orders[i]}', '${ids.product}', '${ids.variant}', 'Race item', 'x', 100000, 1)`);
    const r = await client.query(`insert into public.return_requests (order_id, customer_id, request_id, reason, description, video_object_path)
      values ('${orders[i]}', '${ids.customer}', gen_random_uuid(), 'defective', 'race', 'race/${i}.mp4') returning id`);
    returns.push(r.rows[0].id);
  }
  await client.query('commit');

  const asManager = async (sql, params) => {
    const c = new Client(db);
    await c.connect();
    try {
      await c.query('begin');
      await c.query(`select set_config('request.jwt.claim.sub', $1, true),
        set_config('request.jwt.claims', $2, true)`,
        [ids.manager, JSON.stringify({ sub: ids.manager, role: 'authenticated' })]);
      await c.query('set local role authenticated');
      const row = (await c.query(sql, params)).rows[0];
      await c.query('commit');
      return { ok: true, value: Object.values(row)[0] };
    } catch (error) {
      await c.query('rollback').catch(() => {});
      return { ok: false, message: error.message };
    } finally {
      await c.end();
    }
  };
  const approve = (returnId, key, itemId) => asManager(
    'select public.approve_return_collection($1, $2, $3::jsonb, $4)',
    [returnId, key, JSON.stringify([{ order_item_id: itemId, quantity: 1 }]), ids.shipper]);

  try {
    // Double tap: same key six times at once -> one approval, identical ACKs.
    const key = '15159300-0000-4000-8000-000000000001';
    const same = await Promise.all(Array.from({ length: 6 }, () => approve(returns[0], key, items[0])));
    assert.ok(same.every(r => r.ok), JSON.stringify(same));
    assert.equal(new Set(same.map(r => JSON.stringify(r.value))).size, 1);
    // Two managers' screens with different keys -> exactly one wins.
    const keys = ['15159300-0000-4000-8000-000000000002', '15159300-0000-4000-8000-000000000003'];
    const race = await Promise.all(keys.map(k => approve(returns[1], k, items[1])));
    assert.equal(race.filter(r => r.ok).length, 1, JSON.stringify(race));
    assert.match(race.find(r => !r.ok).message, /STATE_CONFLICT/);

    const counts = (await client.query(`select
      (select count(*) from public.delivery_tasks where return_request_id = any($1::uuid[]))::int as tasks,
      (select count(*) from public.return_items where return_request_id = any($1::uuid[]))::int as items,
      (select count(*) from public.notifications where subject_id = any($1::uuid[]))::int as customer_notices`,
      [returns])).rows[0];
    assert.deepEqual(counts, { tasks: 2, items: 2, customer_notices: 2 });
    console.log('Concurrency: PASS (6 same-key taps -> 1 approval; 2 keys -> 1 approval + STATE_CONFLICT)');
  } finally {
    // Remove the committed race fixture (dependency order).
    await client.query('begin');
    await client.query(`delete from public.notifications where subject_id = any($1::uuid[])
      or recipient_id in ('${ids.customer}', '${ids.shipper}')`, [returns]);
    await client.query(`delete from private.return_management_requests where return_request_id = any($1::uuid[])`, [returns]);
    await client.query('commit');
  }
}
