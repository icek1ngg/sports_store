// Isolated PostgreSQL fixture runner, NOT a Supabase service/deployment test.
// Requires a locally running native PG17 test server and pg from the temporary
// embedded-postgres runtime; does not modify Flutter/package dependencies.
import { readFile, readdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { testAssignmentConcurrency } from './outbound_assignment_concurrency.mjs';
import { testCodReceiptConcurrency } from './cod_receipt_concurrency.mjs';
import { testOutboundCommandsDemo } from './outbound_commands_demo_concurrency.mjs';
import { testAcceptStartConcurrency } from './outbound_accept_start_concurrency.mjs';
import { testOutboundCompletionProductionConcurrency } from './outbound_completion_production_concurrency.mjs';
import { testOutboundFailureProductionConcurrency } from './outbound_failure_production_concurrency.mjs';
import { testOutboundRetryProductionConcurrency } from './outbound_retry_production_concurrency.mjs';
import { testDeliveryReportingProductionConcurrency } from './delivery_reporting_production_concurrency.mjs';
import { testReturnPickupProductionConcurrency } from './return_pickup_production_concurrency.mjs';

const testDir = dirname(fileURLToPath(import.meta.url));
const runtime = resolve(testDir, '../.temp/p011_pg_runtime');
const require = createRequire(resolve(runtime, 'package.json'));
const { Client } = require('pg');
const database = process.argv[2] || 'p011_read_fixture';
const runOutboundDemo = process.argv.slice(3).includes('--p041-demo');
const runCompletionFixture = process.argv.slice(3).includes('--p051-fixture');
if (!/^p011_[a-z0-9_]+$/.test(database)) {
  throw new Error('Use a new p011_ prefixed isolated test database name.');
}
const options = { host: '127.0.0.1', port: 55439, user: 'postgres', database: 'postgres' };
const admin = new Client(options);
await admin.connect();
try {
  const { rows } = await admin.query('SHOW server_version');
  if (!rows[0].server_version.startsWith('17.')) throw new Error('Requires PostgreSQL 17');
  const directory = await admin.query('SHOW data_directory');
  const expectedDirectory = resolve(testDir, '../.temp/p011_native_data');
  if (resolve(directory.rows[0].data_directory).toLowerCase() !== expectedDirectory.toLowerCase()) {
    throw new Error('Refusing PostgreSQL outside this workspace fixture directory.');
  }
  // Deliberately fail if the database exists: never reset/drop existing data.
  await admin.query(`CREATE DATABASE "${database}"`);
  console.log(`Fixture environment: PostgreSQL ${rows[0].server_version}; local Auth/Storage SQL stubs only.`);
} finally {
  await admin.end();
}

const client = new Client({ ...options, database });
await client.connect();
try {
  await client.query("SET sports_store.fixture_mode = 'p011_isolated'");
  await client.query(await readFile(resolve(testDir, 'fixtures/p011_auth_storage.sql.fixture'), 'utf8'));
  const migrationDir = resolve(testDir, '../migrations');
  const migrations = (await readdir(migrationDir)).filter((name) => name.endsWith('.sql')).sort();
  const completionFixture = runCompletionFixture
    ? await readFile(resolve(testDir, 'fixtures/p051_completion.sql.fixture'), 'utf8') : null;
  for (const name of migrations) {
    await client.query('BEGIN');
    try {
      await client.query(await readFile(resolve(migrationDir, name), 'utf8'));
      await client.query('COMMIT');
      console.log(`Migration applied to isolated fixture: ${name}`);
    } catch (error) {
      await client.query('ROLLBACK');
      console.error(`Migration failed: ${name}`);
      throw error;
    }
  }
  for (const name of [
    'database_security.sql',
    'internal_auth_identity.sql',
    'delivery_read_security.sql',
    'delivery_task_list.sql',
    'delivery_task_detail.sql',
    'outbound_assignment.sql',
    'outbound_accept_start.sql',
    'outbound_completion_production.sql',
    'outbound_failure_production.sql',
    'outbound_retry_production.sql',
    'outbound_commands_dependencies.sql',
    'delivery_reporting_production.sql',
    'return_pickup_production.sql',
    'cod_collection_list.sql',
    'cod_receipt.sql',
    ...(runOutboundDemo ? ['outbound_commands_demo.sql'] : []),
    ...(runCompletionFixture ? ['outbound_completion.sql'] : []),
  ]) {
    let sql = await readFile(resolve(testDir, name), 'utf8');
    if (name === 'outbound_commands_dependencies.sql' || name === 'outbound_commands_demo.sql') {
      const isDemo = name === 'outbound_commands_demo.sql';
      const marker = isDemo ? '-- P041_DEMO_FIXTURE' : '-- P041_INTERFACE_FIXTURE';
      if (sql.split(marker).length !== 2) throw new Error('P04.1 fixture marker must occur exactly once');
      const fixture = await readFile(resolve(testDir, isDemo
        ? 'fixtures/p041_demo.sql.fixture' : 'fixtures/p041_outbound_commands.sql.fixture'), 'utf8');
      sql = sql.replace(marker, () => fixture);
    }
    if (name === 'outbound_completion.sql') {
      const marker = '-- P051_COMPLETION_FIXTURE';
      if (sql.split(marker).length !== 2) throw new Error('P05.1 fixture marker must occur exactly once');
      sql = sql.replace(marker, () => completionFixture);
    }
    const results = await client.query(sql);
    if (name === 'outbound_commands_demo.sql' || name === 'outbound_completion.sql') {
      for (const result of results) {
        for (const row of result.rows ?? []) {
          if (row.demo_step) console.log(`DEMO TRACE ${row.demo_step}: ${JSON.stringify(row.snapshot)}`);
        }
      }
    }
    const hasPass = results.some((result) => result.rows?.some((row) => Object.values(row).includes(`${name}: PASS`)));
    if (!hasPass || results.at(-1)?.command !== 'ROLLBACK') {
      throw new Error(`${name} did not finish all assertions with PASS + ROLLBACK`);
    }
    console.log(`${name}: PASS (SQL fixture, rolled back)`);
  }
  await testAssignmentConcurrency(Client, { ...options, database }, client);
  await testCodReceiptConcurrency(Client, { ...options, database }, client);
  await testAcceptStartConcurrency(Client, { ...options, database }, client);
  await testOutboundCompletionProductionConcurrency(Client, { ...options, database }, client);
  await testOutboundFailureProductionConcurrency(Client, { ...options, database }, client);
  await testOutboundRetryProductionConcurrency(Client, { ...options, database }, client);
  await testDeliveryReportingProductionConcurrency(Client, { ...options, database }, client);
  await testReturnPickupProductionConcurrency(Client, { ...options, database }, client);
  if (runOutboundDemo) {
    await testOutboundCommandsDemo(Client, { ...options, database }, client,
      await readFile(resolve(testDir, 'fixtures/p041_demo.sql.fixture'), 'utf8'));
  }
  if (runCompletionFixture) {
    const { testOutboundCompletionConcurrency } = await import('./outbound_completion_concurrency.mjs');
    await testOutboundCompletionConcurrency(Client, { ...options, database }, client, completionFixture);
  }
  const { rows } = await client.query(`
    select (select count(*) from auth.users) as users,
           (select count(*) from public.profiles) as profiles,
           (select count(*) from public.orders) as orders,
           (select count(*) from public.delivery_tasks) as tasks,
           (select count(*) from public.cod_collections) as cod,
           (select count(*) from private.delivery_assignment_requests) as assignment_requests,
           (select count(*) from private.delivery_assignment_audits) as assignment_audits,
           (select count(*) from private.cod_receipt_requests) as cod_receipt_requests,
           (select count(*) from private.outbound_command_requests) as outbound_command_requests,
           (select count(*) from private.outbound_completion_requests) as outbound_completion_requests,
           (select count(*) from private.outbound_completion_results) as outbound_completion_results,
           (select count(*) from private.outbound_dispatches) as outbound_dispatches,
           (select count(*) from private.outbound_custody_acceptances) as outbound_custody_acceptances,
           (select count(*) from private.return_pickup_requests) as return_pickup_requests,
           (select count(*) from private.return_pickup_task_items) as return_pickup_task_items,
           (select count(*) from private.return_pickup_custody) as return_pickup_custody,
           (select count(*) from private.return_pickup_assignment_audits) as return_pickup_assignment_audits,
           (select count(*) from private.return_pickup_failure_results) as return_pickup_failure_results,
           (select count(*) from private.return_pickup_handover_reports) as return_pickup_handover_reports,
           (select count(*) from public.business_events) as events,
           (select count(*) from public.notifications) as notifications,
           (select count(*) from storage.objects) as objects`);
  if (Object.values(rows[0]).some((value) => value !== '0')) throw new Error('Fixture rows survived rollback');
  console.log('PASS: SQL fixtures rolled back and concurrency fixtures cleaned; no users/profiles/orders/tasks/COD/assignment ledger/audit/Storage rows remain.');
} finally {
  await client.end();
}
