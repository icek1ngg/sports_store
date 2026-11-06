// P08.1 production migration/SQL/concurrency runner.  Isolated native
// PostgreSQL 17 only; it never contacts Supabase/cloud, resets, or drops a
// database.  The SQL suite itself rolls back all fixture rows.  The optional
// committed race fixture is cleaned in its finally block.
import { readFile, readdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { testReturnPickupProductionConcurrency } from './return_pickup_production_concurrency.mjs';

const testDir = dirname(fileURLToPath(import.meta.url));
const root = resolve(testDir, '..');
const runtime = resolve(root, '.temp/p011_pg_runtime');
const require = createRequire(resolve(runtime, 'package.json'));
const { Client } = require('pg');
const database = process.argv[2] || `p011_p081_return_pickup_${Date.now()}`;
if (!/^p011_[a-z0-9_]+$/.test(database)) {
  throw new Error('database must use p011_ prefix');
}

const options = {
  host: '127.0.0.1',
  port: 55439,
  user: 'postgres',
  database: 'postgres',
};

const admin = new Client(options);
await admin.connect();
try {
  const version = (await admin.query('show server_version')).rows[0].server_version;
  const dataDirectory = (await admin.query('show data_directory')).rows[0].data_directory;
  const expectedDirectory = resolve(root, '.temp/p011_native_data');
  if (!version.startsWith('17.')
      || resolve(dataDirectory).toLowerCase() !== expectedDirectory.toLowerCase()) {
    throw new Error('Refusing PostgreSQL outside the workspace PG17 fixture runtime');
  }
  // CREATE DATABASE intentionally fails when the requested name already
  // exists.  This runner never resets or drops an existing database.
  await admin.query(`create database "${database}"`);
  console.log(`P08.1 fixture environment: PostgreSQL ${version}; local Auth/Storage SQL stubs only.`);
} finally {
  await admin.end();
}

const client = new Client({ ...options, database });
await client.connect();
try {
  await client.query("set sports_store.fixture_mode = 'p011_isolated'");
  await client.query(await readFile(resolve(testDir, 'fixtures/p011_auth_storage.sql.fixture'), 'utf8'));

  const migrationDir = resolve(root, 'migrations');
  const migrations = (await readdir(migrationDir))
    .filter(name => name.endsWith('.sql'))
    .sort();
  for (const name of migrations) {
    await client.query(await readFile(resolve(migrationDir, name), 'utf8'));
    console.log(`Migration applied to isolated fixture: ${name}`);
  }

  const result = await client.query(
    await readFile(resolve(testDir, 'return_pickup_production.sql'), 'utf8'),
  );
  const pass = result.some(statement => statement.rows?.some(row =>
    Object.values(row).includes('return_pickup_production.sql: PASS')));
  if (!pass || result.at(-1)?.command !== 'ROLLBACK') {
    throw new Error('P08.1 production SQL suite did not return PASS + ROLLBACK');
  }
  console.log('return_pickup_production.sql: PASS (transaction rolled back)');

  const concurrencyAdmin = new Client({ ...options, database });
  await concurrencyAdmin.connect();
  try {
    await testReturnPickupProductionConcurrency(
      Client,
      { ...options, database },
      concurrencyAdmin,
    );
  } finally {
    await concurrencyAdmin.end();
  }
  console.log(`P08.1 production SQL/concurrency: PASS (${database}; SQL suite rolled back)`);
} finally {
  await client.end();
}

