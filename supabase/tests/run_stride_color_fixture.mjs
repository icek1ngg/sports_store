// Isolated PostgreSQL 17 fixture only. Never connects to Supabase.
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const testDir = dirname(fileURLToPath(import.meta.url));
const require = createRequire(resolve(testDir, '../.temp/catalog_pg_runtime/package.json'));
const { Client } = require('pg');
const database = process.argv[2] || 'catalog_stride_colors_fixture';
if (!/^catalog_[a-z0-9_]+$/.test(database)) throw new Error('Use a fresh catalog_ prefixed database.');
const options = { host: '127.0.0.1', port: 55441, user: 'postgres', database: 'postgres' };
const admin = new Client(options);
await admin.connect();
try {
  assert.match((await admin.query('SHOW server_version')).rows[0].server_version, /^17\./);
  assert.equal(resolve((await admin.query('SHOW data_directory')).rows[0].data_directory).toLowerCase(),
    resolve(testDir, '../.temp/catalog_pg_data').toLowerCase(), 'Refusing PG outside this workspace.');
  // Deliberately fail for an existing database; never reset or delete it.
  await admin.query(`CREATE DATABASE "${database}"`);
} finally { await admin.end(); }
const client = new Client({ ...options, database });
await client.connect();
const snapshot = async () => (await client.query(`select jsonb_build_object(
  'products',(select jsonb_agg(p order by id) from public.products p),
  'variants',(select jsonb_agg(v order by id) from public.product_variants v),
  'movements',(select jsonb_agg(m order by id) from public.inventory_movements m)) as snapshot`)).rows[0].snapshot;
try {
  await client.query("SET sports_store.fixture_mode = 'p011_isolated'");
  await client.query(await readFile(resolve(testDir, 'fixtures/p011_auth_storage.sql.fixture'), 'utf8'));
  const migrationDir = resolve(testDir, '../migrations');
  for (const name of (await readdir(migrationDir)).filter(n => n.endsWith('.sql')).sort()) {
    await client.query('BEGIN');
    try {
      await client.query(await readFile(resolve(migrationDir, name), 'utf8'));
      await client.query('COMMIT');
    } catch (error) { await client.query('ROLLBACK'); throw error; }
  }
  const baseSeed = await readFile(resolve(testDir, '../seeds/stride_apparel_shoes_20261108.sql'), 'utf8');
  const colorSeed = await readFile(resolve(testDir, '../seeds/stride_color_expansion_20261108.sql'), 'utf8');
  const manifest = JSON.parse(await readFile(resolve(testDir, '../seeds/stride_color_expansion_20261108.json'), 'utf8'));
  const embedded = JSON.parse(colorSeed.split('$dataset$')[1]);
  assert.deepEqual(embedded, manifest, 'SQL/JSON manifest mismatch');
  await client.query(baseSeed);
  await client.query("update public.product_variants set reserved=2,price_vnd=price_vnd+1000,attributes=attributes || '{\"merchant_note\":\"keep\",\"color_hex\":\"#112233\"}'::jsonb where sku='DEMO-STRIDE-20261108-S01-C1-36'");
  const before = await snapshot();
  assert.equal(before.variants.length, 125);
  await client.query(colorSeed);
  const after = await snapshot();
  assert.equal(after.products.length, 13);
  assert.equal(after.variants.length, 340);
  assert.equal(after.movements.length, 327);
  assert.deepEqual(after.products, before.products, 'Product data was changed');
  for (const original of before.variants) {
    const current = after.variants.find(v => v.id === original.id);
    // First application may backfill only color_hex and its server update timestamp.
    const strip = ({ updated_at, attributes, ...v }) => ({ ...v, attributes: Object.fromEntries(Object.entries(attributes).filter(([k]) => k !== 'color_hex')) });
    assert.deepEqual(strip(current), strip(original), `Existing variant changed: ${original.sku}`);
    if ('color_hex' in original.attributes) assert.equal(current.attributes.color_hex, original.attributes.color_hex);
  }
  const originalIds = new Set(before.variants.map(v => v.id));
  assert.equal(after.variants.filter(v => !originalIds.has(v.id)).length, 215);
  for (const product of manifest) {
    assert.equal(product.colors.length, 4);
    assert.equal(new Set(product.colors.map(c => c.name)).size, 4);
    const variants = after.variants.filter(v => v.sku.startsWith(`DEMO-STRIDE-20261108-${product.key}-`));
    assert.equal(variants.length, 4 * product.sizes.length);
    for (const [i, color] of product.colors.entries()) for (const size of product.sizes) {
      const v = variants.find(v => v.sku === `DEMO-STRIDE-20261108-${product.key}-C${i+1}-${size}`);
      assert.equal(v.attributes.color, color.name);
      assert.equal(v.attributes.size, size);
      assert.match(v.attributes.color_hex, /^#[\da-f]{6}$/i);
      if (!originalIds.has(v.id)) {
        assert.equal(v.attributes.demo, true);
        assert.equal(v.attributes.image_path, undefined, 'Do not fabricate color photos');
        assert.equal(v.price_vnd, product.price_vnd);
        assert(v.on_hand >= 8 && v.on_hand <= 22);
        const ledger = after.movements.filter(m => m.variant_id === v.id);
        assert.equal(ledger.length, 1);
        assert.equal(ledger[0].on_hand_delta, v.on_hand);
        assert.equal(v.reserved, 0);
        assert.equal(v.damaged, 0);
      }
    }
  }
  await client.query(colorSeed);
  await client.query(baseSeed);
  assert.deepEqual(await snapshot(), after, 'Replay reset data or added ledger entries');
  await client.query("update public.product_variants set reserved=3,price_vnd=price_vnd+2500,attributes=attributes || '{\"merchant_note\":\"new variant edited\"}'::jsonb where sku='DEMO-STRIDE-20261108-S01-C4-36'");
  const edited = await snapshot();
  await client.query(colorSeed);
  assert.deepEqual(await snapshot(), edited, 'Replay reset a new-variant reservation or price');
  await client.query("update public.product_variants set attributes=attributes || '{\"color\":\"WRONG\"}'::jsonb where sku='DEMO-STRIDE-20261108-A08-C4-XXL'");
  // Remove one NEW fixture variant so the failed replay must roll back an insert,
  // not merely report a collision after a read-only pass. Only this isolated DB.
  await client.query("delete from public.inventory_movements where variant_id=(select id from public.product_variants where sku='DEMO-STRIDE-20261108-S01-C4-37')");
  await client.query("delete from public.product_variants where sku='DEMO-STRIDE-20261108-S01-C4-37'");
  const collision = await snapshot();
  let collisionDenied = false;
  try { await client.query(colorSeed); } catch (error) {
    assert.equal(error.code, 'P0001');
    assert.match(error.message, /color\/size SKU collision/);
    collisionDenied = true;
    await client.query('ROLLBACK');
  }
  assert(collisionDenied, 'Collision was not detected');
  assert.deepEqual(await snapshot(), collision, 'Collision did not roll back atomically');
  await client.query("update public.product_variants set attributes=attributes || '{\"color\":\"Xanh ngọc\"}'::jsonb where sku='DEMO-STRIDE-20261108-A08-C4-XXL'");

  await client.query(colorSeed);
  assert.equal((await snapshot()).variants.length, 340);

  await client.query("insert into auth.users(id,email) values ('72000000-0000-4000-8000-000000000001','colors-customer@example.invalid'),('72000000-0000-4000-8000-000000000002','colors-shipper@example.invalid')");
  await client.query("update public.profiles set role='shipper' where id='72000000-0000-4000-8000-000000000002'");
  await client.query('BEGIN');
  await client.query("select set_config('request.jwt.claim.sub','72000000-0000-4000-8000-000000000001',true)");
  await client.query('SET LOCAL ROLE authenticated');
  assert.equal((await client.query('select count(*) from public.products')).rows[0].count, '13');
  assert.equal((await client.query('select count(*) from public.product_variants')).rows[0].count, '340');
  let denied = false;
  try { await client.query('update public.product_variants set on_hand=1000'); } catch(error) { assert.equal(error.code,'42501'); denied=true; }
  await client.query('ROLLBACK');
  assert(denied, 'Customer was allowed to change stock');
  await client.query('BEGIN');
  await client.query("select set_config('request.jwt.claim.sub','72000000-0000-4000-8000-000000000002',true)");
  await client.query('SET LOCAL ROLE authenticated');
  assert.equal((await client.query('select count(*) from public.products')).rows[0].count, '0');
  assert.equal((await client.query('select count(*) from public.product_variants')).rows[0].count, '0');
  await client.query('ROLLBACK');
  console.log('PASS: 13 products / 340 color-size variants / 327 movements; 215 new variants; all 4-color matrices complete; existing reservations/prices/custom attributes preserved; replay unchanged; collisions rollback; customer reads allowed, stock writes denied; shipper catalog reads denied.');
} finally { await client.end(); }
