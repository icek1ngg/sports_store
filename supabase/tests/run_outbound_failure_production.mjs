// P07.1 production migration/SQL/concurrency runner.  Isolated local
// PostgreSQL only; it never deploys or contacts Supabase/cloud.
import { readFile, readdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { testOutboundFailureProductionConcurrency } from './outbound_failure_production_concurrency.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const runtime = resolve(root, '.temp/p011_pg_runtime');
const require = createRequire(resolve(runtime, 'package.json'));
const { Client } = require('pg');
const database = process.argv[2] || `p011_p071_production_${Date.now()}`;
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
  const directory = (await admin.query('show data_directory')).rows[0].data_directory;
  if (!version.startsWith('17.') || resolve(directory).toLowerCase() !==
      resolve(root, '.temp/p011_native_data').toLowerCase()) {
    throw new Error('Refusing PostgreSQL outside the workspace PG17 fixture runtime');
  }
  await admin.query(`create database "${database}"`);
} finally {
  await admin.end();
}

const client = new Client({ ...options, database });
await client.connect();
try {
  await client.query("set sports_store.fixture_mode = 'p011_isolated'");
  await client.query(await readFile(resolve(root, 'tests/fixtures/p011_auth_storage.sql.fixture'), 'utf8'));
  const files = (await readdir(resolve(root, 'migrations')))
    .filter(name => name.endsWith('.sql'))
    .sort();
  for (const file of files) {
    await client.query(await readFile(resolve(root, 'migrations', file), 'utf8'));
  }
  const result = await client.query(
    await readFile(resolve(root, 'tests/outbound_failure_production.sql'), 'utf8'),
  );
  const pass = result.some(statement => statement.rows?.some(row =>
    Object.values(row).includes('outbound_failure_production.sql: PASS')));
  if (!pass || result.at(-1)?.command !== 'ROLLBACK') {
    throw new Error('P07.1 production SQL suite did not return PASS');
  }

  const concurrencyAdmin = new Client({ ...options, database });
  await concurrencyAdmin.connect();
  try {
    await testOutboundFailureProductionConcurrency(
      Client,
      { ...options, database },
      concurrencyAdmin,
    );
  } finally {
    await concurrencyAdmin.end();
  }
  console.log(`P07.1 production SQL/concurrency: PASS (${database}; SQL transaction rolled back)`);
} finally {
  await client.end();
}
