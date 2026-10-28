// Historical P08.3 CONTRACT FIXTURE ONLY, pinned to its 21-migration baseline.
// New production redelivery migrations are tested by their production runner.
// Runs on the existing workspace-only PG17 instance; never contacts Supabase.
import { readFile, readdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';

const testDir = import.meta.dirname;
const root = resolve(testDir, '..');
const require = createRequire(resolve(root, '.temp/p011_pg_runtime/package.json'));
const { Client } = require('pg');
const database = process.argv[2] ?? `p011_p083_${Date.now()}`;
assert.match(database, /^p011_p083_[a-z0-9_]+$/);
const options = {
  host: '127.0.0.1', port: 55439, user: 'postgres', database: 'postgres',
  connectionTimeoutMillis: 5000,
};
const admin = new Client(options);
await admin.connect();
try {
  const { rows: [server] } = await admin.query(
    'select current_setting(\'server_version\') as version, current_setting(\'data_directory\') as directory',
  );
  assert.ok(server.version.startsWith('17.'));
  assert.equal(
    resolve(server.directory).toLowerCase(),
    resolve(root, '.temp/p011_native_data').toLowerCase(),
    'Refusing a server outside this workspace fixture runtime',
  );
  // Existing database fails here; no reset/drop or reuse of a shared database.
  await admin.query(`create database "${database}"`);
} finally {
  await admin.end();
}

const client = new Client({ ...options, database });
await client.connect();
try {
  await client.query("set sports_store.fixture_mode = 'p011_isolated'");
  await client.query(await readFile(resolve(testDir, 'fixtures/p011_auth_storage.sql.fixture'), 'utf8'));
  const migrations = (await readdir(resolve(root, 'migrations')))
    .filter(name => name.endsWith('.sql') && name <= '20261028011128_return_pickup_store_handover.sql').sort();
  for (const name of migrations) {
    await client.query(await readFile(resolve(root, 'migrations', name), 'utf8'));
  }
  const publicFunctionsBefore = (await client.query(`select p.oid::regprocedure::text as signature
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' order by 1`)).rows;
  assert.equal((await client.query(`select count(*)::int as count
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in
      ('assign_redelivery_task','complete_redelivery','fail_redelivery_task')`
  )).rows[0].count, 0, 'P08.3 must remain fixture-only; unexpected production RPC exists');
  const businessCountsSql = `select
    (select count(*) from public.profiles) as profiles,
    (select count(*) from public.orders) as orders,
    (select count(*) from public.delivery_tasks) as tasks,
    (select count(*) from public.return_requests) as returns,
    (select count(*) from public.return_items) as items,
    (select count(*) from public.delivery_attempts) as attempts,
    (select count(*) from public.cod_collections) as cod,
    (select count(*) from public.inventory_movements) as movements,
    (select count(*) from public.business_events) as events,
    (select count(*) from public.notifications) as notifications`;
  const businessCountsBefore = (await client.query(businessCountsSql)).rows;
  await client.query('begin');
  const fixtureSql = await readFile(resolve(testDir, 'fixtures/p083_redelivery.sql.fixture'), 'utf8');
  await client.query('savepoint environment_guard');
  await client.query("set local sports_store.fixture_mode = 'disabled'");
  await assert.rejects(() => client.query(fixtureSql), 'Fixture must reject an unmarked environment');
  await client.query('rollback to savepoint environment_guard');
  await client.query(fixtureSql);
  const results = await client.query(await readFile(resolve(testDir, 'redelivery_contract_fixture.sql'), 'utf8'));
  assert.ok(results.some(result => result.rows?.some(row =>
    Object.values(row).includes('redelivery_contract_fixture.sql: PASS'))));
  assert.equal(results.at(-1)?.command, 'ROLLBACK');
  const publicFunctionsAfter = (await client.query(`select p.oid::regprocedure::text as signature
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' order by 1`)).rows;
  assert.deepEqual(publicFunctionsAfter, publicFunctionsBefore);
  assert.deepEqual((await client.query(businessCountsSql)).rows, businessCountsBefore);
  assert.equal((await client.query(
    "select count(*)::int as count from pg_namespace where nspname='p083_fixture'",
  )).rows[0].count, 0);
  console.log(`P08.3 fixture PASS: ${migrations.length} migrations; contract suite ROLLBACK; no production RPC added (${database}).`);
  console.log('Historical contract fixture only: use the production runner for current receipt/inspection/redelivery acceptance. Not RLS/Auth/concurrency acceptance.');
} finally {
  await client.query('rollback').catch(() => {});
  await client.end();
}
