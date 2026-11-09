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
const database = process.argv[2] || 'catalog_stride_fixture';
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
  const seed = await readFile(resolve(testDir, '../seeds/stride_apparel_shoes_20261108.sql'), 'utf8');
  await client.query(seed);
  const snapshot = async () => (await client.query(`select jsonb_build_object(
    'products',(select jsonb_agg(p order by id) from public.products p),
    'variants',(select jsonb_agg(v order by id) from public.product_variants v),
    'movements',(select jsonb_agg(m order by id) from public.inventory_movements m)
  ) as snapshot`)).rows[0].snapshot;
  const first = await snapshot();
  if (first.products.length !== 13 || first.variants.length !== 125 || first.movements.length !== 112) throw new Error('Unexpected seed counts');
  await client.query(seed);
  if (JSON.stringify(await snapshot()) !== JSON.stringify(first)) throw new Error('Seed replay changed existing data');
  await client.query("update public.product_variants set reserved=2,price_vnd=price_vnd+1000 where sku='DEMO-STRIDE-20261108-S01-C1-36'");
  const beforeReservationReplay = await snapshot();
  await client.query(seed);
  if (JSON.stringify(await snapshot()) !== JSON.stringify(beforeReservationReplay)) throw new Error('Seed reset a reservation or price');
  // RLS: the seeded catalog is read-only to customers; shippers cannot read it.
  await client.query("insert into auth.users(id,email) values ('71000000-0000-4000-8000-000000000001','stride-customer@example.invalid'),('71000000-0000-4000-8000-000000000002','stride-shipper@example.invalid')");
  await client.query("update public.profiles set role='shipper' where id='71000000-0000-4000-8000-000000000002'");
  await client.query('begin');
  await client.query("select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000001',true)");
  await client.query('set local role authenticated');
  const visible = (await client.query('select count(*) from public.products')).rows[0].count;
  if (visible !== '13') throw new Error('Customer cannot read seeded catalog');
  let denied=false;
  try { await client.query("update public.product_variants set on_hand=1000"); } catch(error) { if(error.code !== '42501') throw error; denied=true; }
  await client.query('rollback');
  if(!denied) throw new Error('Customer can change stock');
  await client.query('begin');
  await client.query("select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000002',true)");
  await client.query('set local role authenticated');
  if ((await client.query('select count(*) from public.products')).rows[0].count !== '0') throw new Error('Shipper can read customer catalog');
  await client.query('rollback');
  console.log('PASS: 13 products / 125 variants / 112 movements; replay unchanged; reservations and prices preserved; customer read and denied stock update; shipper read denied.');
} finally {
  await client.end();
}
