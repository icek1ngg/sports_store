// P05.1 production migration/SQL test runner. Isolated local PostgreSQL only.
import { readFile, readdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { testOutboundCompletionProductionConcurrency } from './outbound_completion_production_concurrency.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const runtime = resolve(root, '.temp/p011_pg_runtime');
const require = createRequire(resolve(runtime, 'package.json'));
const { Client } = require('pg');
const database = process.argv[2] || `p011_p051_production_${Date.now()}`;
if (!/^p011_[a-z0-9_]+$/.test(database)) throw new Error('database must use p011_ prefix');
const options = { host: '127.0.0.1', port: 55439, user: 'postgres', database: 'postgres' };
const admin = new Client(options);
await admin.connect();
await admin.query(`create database "${database}"`);
await admin.end();
const client = new Client({ ...options, database });
await client.connect();
try {
  await client.query("set sports_store.fixture_mode = 'p011_isolated'");
  await client.query(await readFile(resolve(root, 'tests/fixtures/p011_auth_storage.sql.fixture'), 'utf8'));
  const files = (await readdir(resolve(root, 'migrations'))).filter(n => n.endsWith('.sql')).sort();
  for (const file of files) await client.query(await readFile(resolve(root, 'migrations', file), 'utf8'));
  const result = await client.query(await readFile(resolve(root, 'tests/outbound_completion_production.sql'), 'utf8'));
  const pass = result.some(r => r.rows?.some(row => Object.values(row).includes('outbound_completion_production.sql: PASS')));
  if (!pass) throw new Error('P05.1 production SQL suite did not return PASS');
  const concurrencyAdmin = new Client({ ...options, database });
  await concurrencyAdmin.connect();
  try {
    await testOutboundCompletionProductionConcurrency(Client, { ...options, database }, concurrencyAdmin);
  } finally {
    await concurrencyAdmin.end();
  }
  console.log(`P05.1 production SQL: PASS (${database}; transaction rolled back)`);
} finally {
  await client.end();
}
