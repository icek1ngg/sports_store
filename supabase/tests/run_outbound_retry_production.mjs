// P07.2 production migration/SQL/concurrency runner. Isolated local
// PostgreSQL only; it never deploys or contacts Supabase/cloud.
import { readFile, readdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { testOutboundRetryProductionConcurrency } from './outbound_retry_production_concurrency.mjs';

const testDir = dirname(fileURLToPath(import.meta.url));
const root = resolve(testDir, '..');
const runtime = resolve(root, '.temp/p011_pg_runtime');
const require = createRequire(resolve(runtime, 'package.json'));
const { Client } = require('pg');
const database = process.argv[2] || `p011_p072_production_${Date.now()}`;
if (!/^p011_[a-z0-9_]+$/.test(database)) {
  throw new Error('database must use p011_ prefix');
}

const options = { host: '127.0.0.1', port: 55439, user: 'postgres', database: 'postgres' };
const admin = new Client(options);
await admin.connect();
try {
  const version = (await admin.query('show server_version')).rows[0].server_version;
  const dataDirectory = (await admin.query('show data_directory')).rows[0].data_directory;
  const expectedDirectory = resolve(root, '.temp/p011_native_data');
  if (!version.startsWith('17.') || resolve(dataDirectory).toLowerCase() !== expectedDirectory.toLowerCase()) {
    throw new Error('Refusing PostgreSQL outside the workspace PG17 fixture runtime');
  }
  // CREATE DATABASE deliberately fails if the requested DB exists. This
  // runner never resets or drops an existing database.
  await admin.query(`create database "${database}"`);
  console.log(`P07.2 fixture environment: PostgreSQL ${version}; local Auth/Storage SQL stubs only.`);
} finally {
  await admin.end();
}

const client = new Client({ ...options, database });
await client.connect();
try {
  await client.query("set sports_store.fixture_mode = 'p011_isolated'");
  await client.query(await readFile(resolve(testDir, 'fixtures/p011_auth_storage.sql.fixture'), 'utf8'));
  const migrationDir = resolve(root, 'migrations');
  const migrations = (await readdir(migrationDir)).filter(name => name.endsWith('.sql')).sort();
  for (const name of migrations) {
    await client.query(await readFile(resolve(migrationDir, name), 'utf8'));
    console.log(`Migration applied to isolated fixture: ${name}`);
  }
  const result = await client.query(await readFile(resolve(testDir, 'outbound_retry_production.sql'), 'utf8'));
  const pass = result.some(statement => statement.rows?.some(row =>
    Object.values(row).includes('outbound_retry_production.sql: PASS')));
  if (!pass || result.at(-1)?.command !== 'ROLLBACK') {
    throw new Error('P07.2 production SQL suite did not return PASS + ROLLBACK');
  }
  console.log('outbound_retry_production.sql: PASS (transaction rolled back)');

  const concurrencyAdmin = new Client({ ...options, database });
  await concurrencyAdmin.connect();
  try {
    await testOutboundRetryProductionConcurrency(
      Client, { ...options, database }, concurrencyAdmin,
    );
  } finally {
    await concurrencyAdmin.end();
  }
  console.log(`P07.2 production SQL/concurrency: PASS (${database}; SQL transaction rolled back)`);
} finally {
  await client.end();
}
