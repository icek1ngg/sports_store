// Local disposable database only. Never accepts a Cloud URL or credentials.
// PGlite validates SQL/roles/atomicity, not multi-connection races or hosted Auth.
import { readFile, readdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';

const runtime = resolve('supabase/.temp/b2_runtime');
const require = createRequire(resolve(runtime, 'package.json'));
const native = process.argv.includes('--native');
let db;
let database;
if (native) {
  const { Client } = require('pg');
  const options = { host: '127.0.0.1', port: 55448, user: 'postgres' };
  const admin = new Client({ ...options, database: 'postgres' });
  await admin.connect();
  try {
    const dir = (await admin.query('show data_directory')).rows[0].data_directory;
    if (resolve(dir).toLowerCase() !== resolve(runtime, 'native_data').toLowerCase()) {
      throw Error('Refusing PostgreSQL outside the dedicated B2 fixture directory');
    }
    database = `orders_b2_${Date.now()}`;
    await admin.query(`create database "${database}"`);
  } finally { await admin.end(); }
  const client = new Client({ ...options, database });
  await client.connect();
  db = { exec: async sql => {
    const result = await client.query(sql);
    return Array.isArray(result) ? result : [result];
  }, close: () => client.end() };
  console.log(`Native PostgreSQL disposable database ${database}; loopback only`);
} else {
  const { PGlite } = require('@electric-sql/pglite');
  db = new PGlite();
}
try {
  await db.exec("set sports_store.fixture_mode='p011_isolated'");
  await db.exec("set sports_store.qa_local_disposable='YES'");
  for (const name of ['p011_auth_storage.sql.fixture', 'mh13_storage_metadata.sql.fixture']) {
    await db.exec(await readFile(resolve('supabase/tests/fixtures', name), 'utf8'));
  }
  const files = (await readdir('supabase/migrations')).filter(n => n.endsWith('.sql')).sort();
  for (const name of files) {
    try { await db.exec(await readFile(resolve('supabase/migrations', name), 'utf8')); }
    catch (e) { throw new Error(`Migration ${name}: ${e.message}`, { cause: e }); }
    console.log(`LOCAL migration PASS ${name}`);
  }
  for (const name of ['orders_read_aggregates.sql', 'orders_transactional_mutations.sql']) {
    const statements = await db.exec(await readFile(resolve('supabase/tests', name), 'utf8'));
    const values = statements.flatMap(s => s.rows ?? []);
    console.log(`LOCAL SQL ${name}: ${JSON.stringify(values)}`);
  }
  console.log(`LOCAL B2 SQL PASS; ${files.length} migrations; Auth/Storage stubs; ${native ? 'native PostgreSQL' : 'concurrency NOT VERIFIED by PGlite'}`);
  await db.exec(await readFile('tool/live_demo/orders_b2_identity_postdeploy.sql', 'utf8'));
  console.log('LOCAL postdeploy fingerprints/grants metadata: PASS');
  if (process.argv.includes('--rollback-smoke')) {
    await db.exec(await readFile('tool/live_demo/orders_b2_identity_rollback.sql', 'utf8'));
    const check = await db.exec("select to_regprocedure('public.confirm_order(uuid,uuid)') is null as removed, to_regprocedure('public.get_order_details(uuid)') is not null as b1_preserved");
    if (!check[0].rows[0].removed || !check[0].rows[0].b1_preserved) throw Error('Rollback failed to preserve B1');
    console.log('LOCAL conditional rollback before business writes: PASS; B1 preserved');
    if (native) {
      for (const name of files.filter(n => n.startsWith('202611071716') || n.startsWith('20261107221505'))) {
        await db.exec(await readFile(resolve('supabase/migrations', name), 'utf8'));
      }
      console.log('LOCAL reapply only B2 after rollback smoke: PASS');
    }
  }
  if (native) console.log(`CONCURRENCY_DATABASE=${database}`);
} catch (error) {
  console.error(`LOCAL SQL FAIL: ${error.message}; code=${error.code}; where=${error.where ?? ''}`);
  process.exitCode = 1;
} finally { await db.close(); }
