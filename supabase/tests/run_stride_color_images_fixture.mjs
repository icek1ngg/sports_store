// Isolated PostgreSQL 17 fixture for color-image metadata, never Supabase cloud.
// Optional STRIDE_COLOR_ASSETS_READY=1 verifies the 52 local admin-upload source files.
// storage.objects rows below are SQL FIXTURES only, never real uploads.
import assert from 'node:assert/strict';
import { readFile, readdir, realpath } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { basename, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const testDir = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(testDir, '../..');
const require = createRequire(resolve(testDir, '../.temp/catalog_pg_runtime/package.json'));
const { Client } = require('pg');
const database = process.argv[2] || 'catalog_stride_color_images_fixture';
if (!/^catalog_[a-z0-9_]+$/.test(database)) throw new Error('Use a fresh catalog_ prefixed database.');
const options = { host: '127.0.0.1', port: 55441, user: 'postgres', database: 'postgres' };
const admin = new Client(options);
await admin.connect();
try {
  assert.match((await admin.query('SHOW server_version')).rows[0].server_version, /^17\./);
  // Some migrations deliberately create cluster-global roles exactly once.
  // For repeat runs, initialize a new catalog_color_images_pg_data_* directory
  // directly under this workspace's supabase/.temp and pass its path here.
  const requestedDirectory = process.env.STRIDE_COLOR_FIXTURE_PG_DATA;
  const expectedDirectory = await realpath(requestedDirectory || resolve(testDir, '../.temp/catalog_pg_data'));
  const tempDirectory = await realpath(resolve(testDir, '../.temp'));
  assert.equal(dirname(expectedDirectory).toLowerCase(), tempDirectory.toLowerCase(), 'PG data escaped workspace .temp');
  if (requestedDirectory) assert.match(basename(expectedDirectory), /^catalog_color_images_pg_data_[a-z0-9_]+$/i);
  assert.equal((await realpath((await admin.query('SHOW data_directory')).rows[0].data_directory)).toLowerCase(),
    expectedDirectory.toLowerCase(), 'Refusing PG outside the explicitly named workspace fixture.');
  // Existing databases deliberately fail. Never reset/drop other fixture data.
  await admin.query(`CREATE DATABASE "${database}"`);
} finally { await admin.end(); }
const client = new Client({ ...options, database });
await client.connect();
const snapshot = async () => (await client.query(`select jsonb_build_object(
  'products',(select jsonb_agg(p order by id) from public.products p),
  'variants',(select jsonb_agg(v order by id) from public.product_variants v),
  'movements',(select jsonb_agg(m order by id) from public.inventory_movements m),
  'storage_objects',(select jsonb_agg(o order by id) from storage.objects o),
  'storage_buckets',(select jsonb_agg(b order by id) from storage.buckets b),
  'orders',(select jsonb_agg(o order by id) from public.orders o),
  'order_items',(select jsonb_agg(i order by id) from public.order_items i)) as snapshot`)).rows[0].snapshot;
const imageFields = new Set(['image_path', 'image_paths', 'image_source', 'image_color']);
const stripVariantImageMetadata = ({updated_at, attributes, ...variant}) => ({
  ...variant,
  attributes: Object.fromEntries(Object.entries(attributes).filter(([key]) => !imageFields.has(key))),
});
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
  for (const seed of ['stride_apparel_shoes_20261108.sql', 'stride_color_expansion_20261108.sql']) {
    await client.query(await readFile(resolve(testDir, '../seeds', seed), 'utf8'));
  }
  const manifest = JSON.parse(await readFile(resolve(testDir, '../seeds/stride_color_images_20261109.json'), 'utf8'));
  const imageSeed = await readFile(resolve(testDir, '../seeds/stride_color_images_20261109.sql'), 'utf8');
  const base = JSON.parse(await readFile(resolve(testDir, '../seeds/stride_apparel_shoes_20261108.json'), 'utf8'));
  const colors = JSON.parse(await readFile(resolve(testDir, '../seeds/stride_color_expansion_20261108.json'), 'utf8'));
  assert.deepEqual(JSON.parse(imageSeed.split('$dataset$')[1]), manifest, 'SQL/JSON manifest mismatch');
  assert.equal(manifest.length, 52);
  assert.equal(manifest.filter(c => c.image_source === 'ai_color_preview').length,40);
  assert.equal(manifest.filter(c => c.image_source === 'catalog_reference').length,12);
  assert.equal(new Set(manifest.map(c => c.image_path)).size, 52);
  assert.equal(manifest.reduce((sum, c) => sum + c.sizes.length, 0), 340);
  for (const product of colors) {
    const productImages = manifest.filter(c => c.key === product.key);
    assert.equal(productImages.length, 4);
    assert.equal(new Set(productImages.map(c => c.color_index)).size, 4);
    for (const [index, color] of product.colors.entries()) {
      const entry = productImages.find(c => c.color_index === index + 1);
      const source = base.find(p => p.key === product.key);
      const isAi = index > 0 || product.key === 'S02';
      const extension = isAi ? 'png' : new URL(source.image).pathname.endsWith('.webp') ? 'webp' : 'jpg';
      assert.equal(entry.image_path, `demo/stride-colors-20261109/stride_color_20261109_${product.key}_C${index+1}.${extension}`);
      assert.equal(entry.local_source, `assets/images/stride_color_20261109_${product.key}_C${index+1}.${extension}`);
      assert.equal(entry.bucket, 'product-images');
      assert.deepEqual(entry.image_paths, [entry.image_path]);
      assert.equal(entry.image_source, isAi ? 'ai_color_preview' : 'catalog_reference');
      assert.equal(entry.image_color, color.name);
      assert.equal(entry.color, color.name);
      assert.equal(entry.category, product.category);
      assert.deepEqual(entry.sizes, product.sizes);
    }
  }
  if (process.env.STRIDE_COLOR_ASSETS_READY === '1') {
    for (const entry of manifest) {
      const data = await readFile(resolve(projectRoot, entry.local_source));
      assert(data.length > 1000, `Image file too small: ${entry.key}/C${entry.color_index}`);
      if (entry.image_path.endsWith('.png')) assert.equal(data.subarray(0,8).toString('hex'), '89504e470d0a1a0a');
      else if (entry.image_path.endsWith('.webp')) { assert.equal(data.toString('ascii',0,4), 'RIFF'); assert.equal(data.toString('ascii',8,12), 'WEBP'); }
      else assert.equal(data.subarray(0,2).toString('hex'), 'ffd8');
    }
    console.log('PASS: all 52 local upload-source files exist and match their format signatures.');
  }

  // SQL-only Storage stand-ins in the isolated fixture. This is not an upload.
  assert.equal((await client.query("select public from storage.buckets where id='product-images'")).rows[0].public,false);
  for (const entry of manifest) {
    await client.query('insert into storage.objects(bucket_id,name) values($1,$2)',[entry.bucket,entry.image_path]);
    // Simulate previously deployed asset: metadata; only image fields change.
    await client.query(`update public.product_variants set attributes=attributes || jsonb_build_object(
      'image_path',$1::text,'image_paths',jsonb_build_array($1::text),
      'image_source',$2::text,'image_color',$3::text) where sku like $4`,
      ['asset:'+entry.local_source,entry.image_source,entry.image_color,`DEMO-STRIDE-20261108-${entry.key}-C${entry.color_index}-%`]);
  }

  // Unrelated catalog data must remain byte-for-byte unchanged by the image seed.
  const unrelatedId = (await client.query(`insert into public.products(category_id,name,description,image_path)
    select id,'Unrelated fixture product','Merchant-owned catalog data','https://example.invalid/merchant.jpg'
    from public.categories where code='equipment' returning id`)).rows[0].id;
  await client.query(`insert into public.product_variants(product_id,sku,label,attributes,price_vnd,on_hand,reserved,damaged,is_active)
    values($1,'FIXTURE-NON-STRIDE-001','Merchant variant','{"merchant_note":"keep","image_path":"https://example.invalid/merchant.jpg"}',1234,7,1,0,true)`, [unrelatedId]);
  await client.query(`update public.product_variants set reserved=2,price_vnd=price_vnd+1000,
    attributes=attributes || '{"merchant_note":"keep","color_hex":"#112233","image_path":"https://example.invalid/old-color.jpg"}'::jsonb
    where sku='DEMO-STRIDE-20261108-S01-C1-36'`);
  await client.query(`update public.products set description=description || ' Merchant custom note remains.'
    where id=(select product_id from public.product_variants where sku='DEMO-STRIDE-20261108-S01-C1-36')`);
  await client.query(`update public.products set description='[DEMO STRIDE 20261108] Custom description without old boilerplate.'
    where id=(select product_id from public.product_variants where sku='DEMO-STRIDE-20261108-S02-C1-36')`);
  // Create one real local RPC order from the legacy image metadata. Changing
  // the catalog must not rewrite its snapshots, reservation or recorded totals.
  await client.query("insert into auth.users(id,email) values ('74000000-0000-4000-8000-000000000001','existing-image-order@example.invalid')");
  const orderedVariant=(await client.query("select id from public.product_variants where sku='DEMO-STRIDE-20261108-S01-C1-36'")).rows[0].id;
  await client.query('BEGIN');
  await client.query("select set_config('request.jwt.claim.sub','74000000-0000-4000-8000-000000000001',true)");
  await client.query('SET LOCAL ROLE authenticated');
  const placed=(await client.query(`select public.place_order(
    '74000000-0000-4000-8000-000000000002'::uuid,$1::jsonb,
    '[TEST] Existing image order','0900000000','[TEST] Hanoi fixture address',21.0285,105.8542) result`,
    [JSON.stringify([{variant_id:orderedVariant,quantity:1}])])).rows[0].result;
  await client.query('COMMIT');
  assert.equal(placed.ok,true,'Local order fixture did not commit');
  const before = await snapshot();
  assert.equal(before.orders.length,1);
  assert.equal(before.order_items.length,1);
  assert.equal(before.variants.length, 341);
  assert.equal(before.products.length, 14);
  assert.equal(before.movements.length, 328);
  // Missing the very last object must fail before ANY catalog update.
  const missingObject=before.storage_objects.find(o => o.name===manifest.at(-1).image_path);
  await client.query('delete from storage.objects where id=$1',[missingObject.id]);
  const missingObjectSnapshot=await snapshot();
  let missingObjectDenied=false;
  try { await client.query(imageSeed); } catch(error) {
    assert.equal(error.code,'P0001');
    assert.match(error.message,/Missing uploaded STRIDE Storage image/);
    missingObjectDenied=true;
    await client.query('ROLLBACK');
  }
  assert(missingObjectDenied,'Missing upload was accepted');
  assert.deepEqual(await snapshot(),missingObjectSnapshot,'Missing upload partially changed catalog data');
  await client.query('insert into storage.objects(id,bucket_id,name) values($1,$2,$3)',[missingObject.id,missingObject.bucket_id,missingObject.name]);
  assert.deepEqual(await snapshot(),before,'Repair of local missing-object fixture changed other data');
  await client.query("update storage.buckets set public=true where id='product-images'");
  const publicBucketSnapshot=await snapshot();
  let publicBucketDenied=false;
  try { await client.query(imageSeed); } catch(error) {
    assert.equal(error.code,'P0001');
    assert.match(error.message,/Expected private product-images Storage bucket/);
    publicBucketDenied=true;
    await client.query('ROLLBACK');
  }
  assert(publicBucketDenied,'Public bucket was accepted');
  assert.deepEqual(await snapshot(),publicBucketSnapshot,'Public bucket rejection changed catalog data');
  await client.query("update storage.buckets set public=false where id='product-images'");
  await client.query(imageSeed);
  const after = await snapshot();
  assert.equal(after.variants.length, before.variants.length, 'Image seed inserted/deleted variants');
  assert.equal(after.products.length, before.products.length, 'Image seed inserted/deleted products');
  assert.deepEqual(after.movements, before.movements, 'Image seed changed the stock ledger');
  assert.deepEqual(after.storage_objects,before.storage_objects,'Image seed wrote Storage object metadata');
  assert.deepEqual(after.storage_buckets,before.storage_buckets,'Image seed changed Storage buckets');
  assert.deepEqual(after.orders,before.orders,'Image seed changed an existing order');
  assert.deepEqual(after.order_items,before.order_items,'Image seed rewrote existing order snapshots');
  for (const original of before.variants) {
    const updated = after.variants.find(v => v.id === original.id);
    assert.deepEqual(stripVariantImageMetadata(updated), stripVariantImageMetadata(original), `Financial/stock/nonimage attributes changed: ${original.sku}`);
    if (original.sku === 'FIXTURE-NON-STRIDE-001') assert.deepEqual(updated, original);
  }
  const oldNote = 'Ảnh minh họa; ảnh có thể không thể hiện tất cả màu của biến thể.';
  const newNote = 'Ảnh màu dùng để minh họa dữ liệu demo; ảnh được tạo bằng AI có ghi chú riêng.';
  for (const original of before.products) {
    const updated = after.products.find(p => p.id === original.id);
    const { description: oldDescription, updated_at: oldTime, ...oldRest } = original;
    const { description: newDescription, updated_at: newTime, ...newRest } = updated;
    assert.deepEqual(newRest, oldRest, 'Product fields outside description changed');
    assert.equal(newDescription, original.id === unrelatedId ? oldDescription : oldDescription.replaceAll(oldNote,newNote));
    if (!oldDescription.includes(oldNote)) assert.equal(newTime,oldTime, 'Unchanged description timestamp was rewritten');
  }
  let count = 0;
  for (const entry of manifest) for (const size of entry.sizes) {
    const sku = `DEMO-STRIDE-20261108-${entry.key}-C${entry.color_index}-${size}`;
    const variant = after.variants.find(v => v.sku === sku);
    for (const field of imageFields) assert.deepEqual(variant.attributes[field], entry[field], `Image mapping mismatch ${sku}/${field}`);
    assert.equal(variant.attributes.demo, true);
    assert.equal(variant.attributes.local_source,undefined,'Local upload file path leaked into runtime attributes');
    assert.equal(variant.attributes.bucket,undefined,'Admin-only bucket field leaked into runtime attributes');
    assert.equal(variant.attributes.color, entry.color);
    assert.equal(variant.attributes.size, size);
    count++;
  }
  assert.equal(count,340);
  await client.query(imageSeed);
  assert.deepEqual(await snapshot(), after, 'Replay changed rows or timestamps');

  const firstSku = 'DEMO-STRIDE-20261108-S01-C1-36';
  const last = manifest.at(-1);
  const lastSku = `DEMO-STRIDE-20261108-${last.key}-C${last.color_index}-${last.sizes.at(-1)}`;
  const lastVariant = after.variants.find(v => v.sku === lastSku);
  const lastProduct = after.products.find(p => p.id === lastVariant.product_id);
  const assertAtomicRejection = async (setup, repair, pattern) => {
    await client.query(`update public.product_variants set attributes=attributes || '{"image_path":"asset:assets/images/tampered.png"}'::jsonb where sku=$1`, [firstSku]);
    await setup();
    const corrupt = await snapshot();
    let rejected=false;
    try { await client.query(imageSeed); } catch(error) {
      assert.equal(error.code,'P0001');
      assert.match(error.message,pattern);
      rejected=true;
      await client.query('ROLLBACK');
    }
    assert(rejected,'Expected image seed to reject invalid ownership/mapping');
    assert.deepEqual(await snapshot(),corrupt,'Rejected image seed partially updated rows/timestamps');
    await repair();
    await client.query(imageSeed);
  };
  await assertAtomicRejection(
    () => client.query('update public.product_variants set sku=$1 where sku=$2',['FIXTURE-MISSING-LAST-IMAGE',lastSku]),
    () => client.query('update public.product_variants set sku=$1 where sku=$2',[lastSku,'FIXTURE-MISSING-LAST-IMAGE']),
    /Missing STRIDE image variant/,
  );
  await assertAtomicRejection(
    () => client.query("update public.product_variants set attributes=jsonb_set(attributes,'{color}',to_jsonb('WRONG'::text)) where sku=$1",[lastSku]),
    () => client.query("update public.product_variants set attributes=jsonb_set(attributes,'{color}',to_jsonb($1::text)) where sku=$2",[last.color,lastSku]),
    /ownership\/color\/size collision/,
  );
  await assertAtomicRejection(
    () => client.query('update public.products set description=$1 where id=$2',['Not a seed-owned product',lastProduct.id]),
    () => client.query('update public.products set description=$1 where id=$2',[lastProduct.description,lastProduct.id]),
    /Missing\/colliding STRIDE image product/,
  );

  await client.query("insert into auth.users(id,email) values ('73000000-0000-4000-8000-000000000001','color-images-customer@example.invalid'),('73000000-0000-4000-8000-000000000002','color-images-shipper@example.invalid')");
  await client.query("update public.profiles set role='shipper' where id='73000000-0000-4000-8000-000000000002'");
  await client.query('BEGIN');
  await client.query("select set_config('request.jwt.claim.sub','73000000-0000-4000-8000-000000000001',true)");
  await client.query('SET LOCAL ROLE authenticated');
  assert.equal((await client.query("select count(*) from public.product_variants where sku like 'DEMO-STRIDE-20261108-%' and attributes ? 'image_path' and attributes ? 'image_paths'")).rows[0].count,'340');
  assert.equal((await client.query("select count(*) from storage.objects where bucket_id='product-images' and name like 'demo/stride-colors-20261109/%'")).rows[0].count,'52');
  let denied=false;
  try {
    const result=await client.query("update public.product_variants set attributes=attributes || '{\"image_path\":\"wrong\"}'::jsonb where sku=$1 returning id",[firstSku]);
    denied=result.rowCount===0; // RLS can deny by filtering every target row.
  } catch(error) { assert.equal(error.code,'42501'); denied=true; }
  await client.query('ROLLBACK');
  assert(denied,'Customer was allowed to write variant image metadata');
  await client.query('BEGIN');
  await client.query("select set_config('request.jwt.claim.sub','73000000-0000-4000-8000-000000000001',true)");
  await client.query('SET LOCAL ROLE authenticated');
  let uploadDenied=false;
  try { await client.query("insert into storage.objects(bucket_id,name) values('product-images','demo/stride-colors-20261109/customer-forbidden.png')"); }
  catch(error) { assert.equal(error.code,'42501'); uploadDenied=true; }
  await client.query('ROLLBACK');
  assert(uploadDenied,'Customer was allowed to upload catalog image metadata');
  await client.query('BEGIN');
  await client.query("select set_config('request.jwt.claim.sub','73000000-0000-4000-8000-000000000002',true)");
  await client.query('SET LOCAL ROLE authenticated');
  assert.equal((await client.query('select count(*) from public.product_variants')).rows[0].count,'0');
  assert.equal((await client.query("select count(*) from storage.objects where bucket_id='product-images'")).rows[0].count,'0');
  await client.query('ROLLBACK');
  console.log('PASS: 52 private Storage paths map to 340 existing variants; 40 AI / 12 reference images; local_source excluded from runtime metadata; missing objects and public bucket reject before catalog updates; SQL/JSON parity; price/stock/reservations/nonimage attributes/ledger/existing order snapshots/unrelated catalog/Storage metadata preserved; legacy asset paths migrated; replay preserves timestamps; missing/mismatched/unowned variants reject atomically; customer reads 340 variants/52 Storage objects but cannot write/upload; shipper catalog/Storage reads denied.');
} finally { await client.end(); }
