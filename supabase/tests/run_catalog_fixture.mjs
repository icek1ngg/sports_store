// Isolated PostgreSQL fixture runner, NOT a Supabase service/deployment test.
// Requires a locally running native PG17 test server and pg from the temporary
// embedded-postgres runtime; does not modify Flutter/package dependencies.
import { readFile, readdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const testDir = dirname(fileURLToPath(import.meta.url));
const runtime = resolve(testDir, '../.temp/catalog_pg_runtime');
const require = createRequire(resolve(runtime, 'package.json'));
const { Client } = require('pg');
const database = process.argv[2] || 'catalog_read_fixture';
if (!/^catalog_[a-z0-9_]+$/.test(database)) {
  throw new Error('Use a new catalog_ prefixed isolated test database name.');
}
const options = { host: '127.0.0.1', port: 55441, user: 'postgres', database: 'postgres' };
const admin = new Client(options);
await admin.connect();
try {
  const { rows } = await admin.query('SHOW server_version');
  if (!rows[0].server_version.startsWith('17.')) throw new Error('Requires PostgreSQL 17');
  const directory = await admin.query('SHOW data_directory');
  const expectedDirectory = resolve(testDir, '../.temp/catalog_pg_data');
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
  for (const name of ['database_security.sql', 'delivery_read_security.sql']) {
    const results = await client.query(await readFile(resolve(testDir, name), 'utf8'));
    const hasPass = results.some((result) => result.rows?.some((row) => Object.values(row).includes(`${name}: PASS`)));
    if (!hasPass || results.at(-1)?.command !== 'ROLLBACK') {
      throw new Error(`${name} did not finish all assertions with PASS + ROLLBACK`);
    }
    console.log(`${name}: PASS (SQL fixture, rolled back)`);
  }
  const seed = await readFile(resolve(testDir, '../seed_catalog_demo.sql'), 'utf8');
  await client.query(seed);
  const before = await client.query('select * from public.product_variants order by id');
  await client.query(seed);
  const after = await client.query('select * from public.product_variants order by id');
  if (JSON.stringify(before.rows) !== JSON.stringify(after.rows)) throw new Error('Seed changed existing variants');
  const counts = await client.query(`select (select count(*) from public.products) as products,
    (select count(*) from public.product_variants) as variants,
    (select count(*) from public.inventory_movements) as movements`);
  if (JSON.stringify(counts.rows[0]) !== JSON.stringify({products:'3',variants:'5',movements:'4'})) throw new Error('Wrong seed counts');
  // Existing demo stock is mutable: re-running must preserve a reservation.
  await client.query("update public.product_variants set reserved = 2 where sku = 'DEMO-CATALOG-RUN-40'");
  await client.query(seed);
  const stock = await client.query("select available_quantity from public.product_variants where sku = 'DEMO-CATALOG-RUN-40'");
  if (stock.rows[0].available_quantity !== '6') throw new Error('Reservation reset');
  await client.query("update public.products set name = '[DEMO] Other product' where id = '40000000-0000-4000-8000-000000000001'");
  let rejected = false;
  try { await client.query(seed); } catch (error) {
    await client.query('ROLLBACK');
    if (!error.message.includes('collision')) throw error;
    rejected = true;
  }
  if (!rejected) throw new Error('Seed overwrote a colliding product');
  console.log('PASS: seed twice = 3 products / 5 variants / 4 movements; reservation preserved; collision rejected.');
  const { rows } = await client.query(`
    select (select count(*) from auth.users) as users,
           (select count(*) from public.orders) as orders,
           (select count(*) from public.delivery_tasks) as tasks,
           (select count(*) from storage.objects) as objects`);
  if (Object.values(rows[0]).some((value) => value !== '0')) throw new Error('Fixture rows survived rollback');
  console.log('PASS: security fixtures rolled back; no users/orders/tasks/Storage objects remain. Demo catalog is retained only in the isolated local database.');
} finally {
  await client.end();
}
