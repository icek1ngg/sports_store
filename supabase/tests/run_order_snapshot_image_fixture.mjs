// Native PostgreSQL 17 fixture only. Never connects to Supabase or an existing
// cluster/database; Auth/Storage objects below come from the P01.1 SQL fixture.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtemp, open, readFile, readdir, realpath } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { createServer } from 'node:net';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const testDirectory = dirname(fileURLToPath(import.meta.url));
const root = resolve(testDirectory, '../..');
const temporaryRoot = await realpath(resolve(root, 'supabase/.temp'));
const runtime = resolve(temporaryRoot, 'catalog_pg_runtime');
const require = createRequire(resolve(runtime, 'package.json'));
const { Client } = require('pg');
const nativeBin = resolve(runtime, 'node_modules/@embedded-postgres/windows-x64/native/bin');
const migrationName = '20261109155043_expose_order_snapshot_product_images.sql';
const migrationDirectory = resolve(root, 'supabase/migrations');
const data = await realpath(await mkdtemp(join(temporaryRoot, 'orders_snapshot_images_pg_data_')));
assert.equal(dirname(data).toLowerCase(), temporaryRoot.toLowerCase(), 'Cluster must remain in workspace .temp');
assert.match(basename(data), /^orders_snapshot_images_pg_data_[a-z0-9]+$/i);
const database = 'orders_snapshot_image_fixture';
const quote = (value) => `"${value.replaceAll('"', '""')}"`;
const ids = {
  customerA: 'a1000000-0000-4000-8000-000000000001',
  customerB: 'a1000000-0000-4000-8000-000000000002',
  manager: 'a1000000-0000-4000-8000-000000000003',
  shipper: 'a1000000-0000-4000-8000-000000000004',
  category: 'a2000000-0000-4000-8000-000000000001',
  products: [1, 2, 3].map((n) => `a3000000-0000-4000-8000-00000000000${n}`),
  variants: [1, 2, 3].map((n) => `a4000000-0000-4000-8000-00000000000${n}`),
  orderA: 'a5000000-0000-4000-8000-000000000001',
  orderB: 'a5000000-0000-4000-8000-000000000002',
  items: [1, 2, 3, 4].map((n) => `a6000000-0000-4000-8000-00000000000${n}`),
};
const originalImage = 'https://images.example.invalid/hanoi-fc-blue-snapshot.jpg';
const changedCatalogImage = 'https://images.example.invalid/catalog-changed-after-order.jpg';
const originalAttributes = { color: 'Xanh', size: 'L' };
const legacyAttributes = { color: 'Đen', size: 'M', image_path: 'demo/legacy-image.png' };
let server;
let admin;
let client;
let stdout;
let stderr;
let options;

async function freePort() {
  const socket = createServer();
  await new Promise((resolvePort, reject) => {
    socket.once('error', reject);
    socket.listen(0, '127.0.0.1', resolvePort);
  });
  const port = socket.address().port;
  await new Promise((resolveClose, reject) => socket.close((error) => error ? reject(error) : resolveClose()));
  return port;
}

async function asActor(userId, action, role = 'authenticated') {
  assert(['authenticated', 'anon', 'service_role'].includes(role));
  const actor = new Client({ ...options, database });
  await actor.connect();
  try {
    await actor.query('BEGIN');
    await actor.query(`SET LOCAL ROLE ${quote(role)}`);
    await actor.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claims',$2,true)",
      [userId ?? '', JSON.stringify(userId ? { sub: userId, role } : { role })]);
    return await action(actor);
  } finally {
    await actor.query('ROLLBACK');
    await actor.end();
  }
}

async function detail(actor, orderId) {
  return (await actor.query('select public.get_order_details($1::uuid) as value', [orderId])).rows[0].value;
}

async function items(actor, orderId) {
  return (await actor.query('select private.orders_read_items($1::uuid) as value', [orderId])).rows[0].value;
}

async function summary(actor, scope, orderId) {
  const fn = scope === 'customer' ? 'get_customer_orders' : 'get_manager_orders';
  const response = (await actor.query(`select public.${fn}($1::text) as value`, [orderId])).rows[0].value;
  assert.equal(response.ok, true);
  assert.equal(response.data.items.length, 1);
  return response.data.items[0];
}

async function businessHash() {
  const tables = (await client.query(`select n.nspname,c.relname from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname in ('public','private') and c.relkind in ('r','p')
    order by n.nspname,c.relname`)).rows;
  const hash = createHash('sha256');
  for (const table of tables) {
    const rows = (await client.query(`select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]'::jsonb) as value
      from ${quote(table.nspname)}.${quote(table.relname)} t`)).rows[0].value;
    hash.update(JSON.stringify([table, rows]));
  }
  return hash.digest('hex');
}

async function securitySnapshot() {
  const helpers = (await client.query(`select p.proname,p.oid,p.proowner,p.proacl::text,p.prosecdef,
    p.provolatile,p.proconfig,p.proparallel,p.prorettype,p.proargtypes::text,p.prosrc,
    l.lanname from pg_proc p join pg_language l on l.oid=p.prolang
    where p.oid in ('private.orders_read_items(uuid)'::regprocedure,
      'private.checkout_items_json(uuid)'::regprocedure) order by p.proname`)).rows;
  const policies = (await client.query(`select n.nspname,c.relname,to_jsonb(p) as policy
    from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace
    where n.nspname in ('public','private') order by n.nspname,c.relname,p.polname`)).rows;
  const relations = (await client.query(`select n.nspname,c.relname,c.relowner,c.relacl::text,
    c.relrowsecurity,c.relforcerowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname in ('public','private') order by n.nspname,c.relname`)).rows;
  return { helpers, policies, relations };
}

function withoutImage(list) {
  return list.map(({ product_image_url, ...item }) => item);
}

try {
  const initialized = spawnSync(resolve(nativeBin, 'initdb.exe'), ['-D', data, '-U', 'postgres', '-A', 'trust', '--encoding=UTF8', '--locale=C'],
    { windowsHide: true, encoding: 'utf8', timeout: 60_000 });
  assert.equal(initialized.status, 0, initialized.stderr || initialized.stdout);
  const port = await freePort();
  stdout = await open(resolve(root, 'build/orders_snapshot_image_pg_stdout.log'), 'w');
  stderr = await open(resolve(root, 'build/orders_snapshot_image_pg_stderr.log'), 'w');
  server = spawn(resolve(nativeBin, 'postgres.exe'), ['-D', data, '-p', String(port), '-h', '127.0.0.1',
    '-c', 'shared_buffers=16MB', '-c', 'max_connections=10', '-c', 'work_mem=1MB', '-c', 'maintenance_work_mem=16MB'],
    { windowsHide: true, stdio: ['ignore', stdout.fd, stderr.fd] });
  options = { host: '127.0.0.1', port, user: 'postgres', database: 'postgres', connectionTimeoutMillis: 500 };
  for (let attempt = 0; attempt < 50; attempt++) {
    admin = new Client(options);
    try { await admin.connect(); break; }
    catch {
      await admin.end().catch(() => {});
      admin = null;
      if (server.exitCode !== null) break;
      await new Promise((resolveDelay) => setTimeout(resolveDelay, 200));
    }
  }
  assert(admin, 'PostgreSQL did not start');
  assert.match((await admin.query('SHOW server_version')).rows[0].server_version, /^17\./);
  assert.equal((await realpath((await admin.query('SHOW data_directory')).rows[0].data_directory)).toLowerCase(), data.toLowerCase());
  await admin.query(`CREATE DATABASE ${quote(database)}`);
  await admin.end();
  admin = null;
  client = new Client({ ...options, database });
  await client.connect();
  await client.query("SET sports_store.fixture_mode='p011_isolated'");
  await client.query(await readFile(resolve(testDirectory, 'fixtures/p011_auth_storage.sql.fixture'), 'utf8'));
  const priorMigrations = (await readdir(migrationDirectory)).filter((name) => name.endsWith('.sql') && name < migrationName).sort();
  for (const name of priorMigrations) {
    try { await client.query(await readFile(resolve(migrationDirectory, name), 'utf8')); }
    catch (error) { throw new Error(`Prerequisite migration ${name}: ${error.message}`, { cause: error }); }
  }
  console.log(`Fixture: native PostgreSQL 17; fresh ${basename(data)}; ${priorMigrations.length} prior migrations; local Auth/Storage SQL stubs only.`);
  for (const [index, userId] of [ids.customerA, ids.customerB, ids.manager, ids.shipper].entries()) {
    await client.query('insert into auth.users(id,email) values($1,$2)', [userId, `snapshot-image-${index}@example.invalid`]);
  }
  await client.query("update public.profiles set role='manager' where id=$1", [ids.manager]);
  await client.query("update public.profiles set role='shipper' where id=$1", [ids.shipper]);
  await client.query("insert into public.categories(id,code,name) values($1,'image-snapshot-fixture','Image fixture')", [ids.category]);
  for (let index = 0; index < 3; index++) {
    await client.query('insert into public.products(id,category_id,name,image_path) values($1,$2,$3,$4)',
      [ids.products[index], ids.category, `Snapshot fixture ${index}`, index === 0 ? originalImage : null]);
    await client.query(`insert into public.product_variants(id,product_id,sku,label,attributes,price_vnd,on_hand,reserved,damaged)
      values($1,$2,$3,$4,$5,120000,10,0,0)`,
      [ids.variants[index], ids.products[index], `ORDER-IMAGE-${index}`, 'Fixture variant', JSON.stringify(originalAttributes)]);
  }
  for (const [index, orderId] of [ids.orderA, ids.orderB].entries()) {
    await client.query(`insert into public.orders(id,customer_id,request_id,recipient_name,recipient_phone,address_detail,
      latitude,longitude,subtotal_vnd,placed_at)
      values($1,$2,$3,'Fixture recipient','0900000000','Fixture Ha Noi',21.0285,105.8542,$4,'2026-11-09T07:00:00Z')`,
      [orderId, index === 0 ? ids.customerA : ids.customerB, orderId, index === 0 ? 360000 : 120000]);
  }
  for (let index = 0; index < 3; index++) {
    await client.query(`insert into public.order_items(id,order_id,product_id,variant_id,product_name,variant_label,attributes,
      unit_price_vnd,quantity,created_at) values($1,$2,$3,$4,$5,'Snapshot variant',$6,120000,1,'2026-11-09T07:00:01Z')`,
      [ids.items[index], ids.orderA, ids.products[index], ids.variants[index], `Frozen product ${index}`,
        JSON.stringify(index === 1 ? legacyAttributes : originalAttributes)]);
  }
  await client.query(`insert into public.order_items(id,order_id,product_id,variant_id,product_name,variant_label,attributes,
    unit_price_vnd,quantity) values($1,$2,$3,$4,'Other customer item','Snapshot variant',$5,120000,1)`,
    [ids.items[3], ids.orderB, ids.products[0], ids.variants[0], JSON.stringify(originalAttributes)]);
  const storedImage = (await client.query('select product_image_url from public.order_items where id=$1', [ids.items[0]])).rows[0].product_image_url;
  assert.equal(storedImage, originalImage, 'Existing snapshot trigger fixture failed');
  const oldDetail = await asActor(ids.customerA, (actor) => detail(actor, ids.orderA));
  assert.equal(oldDetail.ok, true);
  assert.equal(Object.hasOwn(oldDetail.data.items[0], 'product_image_url'), false, 'Baseline unexpectedly already exposes the image');
  const oldSummary = await asActor(ids.customerA, (actor) => summary(actor, 'customer', ids.orderA));
  await client.query('update public.products set image_path=$1 where id=$2', [changedCatalogImage, ids.products[0]]);
  const beforeHash = await businessHash();
  const beforeSecurity = await securitySnapshot();
  const migration = await readFile(resolve(migrationDirectory, migrationName), 'utf8');
  await client.query(migration);
  const afterSecurity = await securitySnapshot();
  assert.equal(beforeSecurity.helpers.length, 2);
  for (let index = 0; index < beforeSecurity.helpers.length; index++) {
    const { prosrc: oldSource, ...oldMetadata } = beforeSecurity.helpers[index];
    const { prosrc: newSource, ...newMetadata } = afterSecurity.helpers[index];
    assert.deepEqual(newMetadata, oldMetadata, 'Helper identity, owner, ACL, signature, volatility or safety settings changed');
    assert.equal(newSource.replace(/'product_image_url',\s*i\.product_image_url,/g, '').replace(/\s/g, ''), oldSource.replace(/\s/g, ''), 'Unexpected helper body delta');
  }
  assert.deepEqual(afterSecurity.policies, beforeSecurity.policies, 'RLS policies changed');
  assert.deepEqual(afterSecurity.relations, beforeSecurity.relations, 'Relation grants/owners/RLS changed');
  console.log('PASS: both helper owner/ACL/OID/signature/STABLE/SECURITY INVOKER and each original search_path/timezone/order are unchanged; no relation grant/RLS changes.');

  for (const userId of [ids.customerA, ids.manager]) {
    await asActor(userId, async (actor) => {
      const result = await detail(actor, ids.orderA);
      assert.equal(result.ok, true);
      assert.deepEqual(withoutImage(result.data.items), oldDetail.data.items);
      assert.deepEqual(result.data.items.map((item) => item.id), ids.items.slice(0, 3));
      assert.equal(result.data.items[0].product_image_url, originalImage);
      assert.deepEqual(result.data.items[0].attributes, originalAttributes);
      assert.equal(result.data.items[1].product_image_url, null);
      assert.deepEqual(result.data.items[1].attributes, legacyAttributes);
      assert.equal(result.data.items[2].product_image_url, null);
      assert.deepEqual(result.data.items[2].attributes, originalAttributes);
      const preview = await summary(actor, userId === ids.manager ? 'manager' : 'customer', ids.orderA);
      assert.deepEqual(withoutImage(preview.item_preview), oldSummary.item_preview);
      assert.equal(preview.item_preview[0].product_image_url, originalImage);
      assert.equal(preview.item_preview[1].product_image_url, null);
      assert.deepEqual(await items(actor, ids.orderA), result.data.items);
    });
  }
  console.log('PASS: owner customer and manager list/detail/helper receive the existing image snapshot, unchanged attributes/order, and explicit null for legacy/missing snapshots.');

  await asActor(ids.customerB, async (actor) => {
    const denied = await detail(actor, ids.orderA);
    assert.equal(denied.ok, false);
    assert.equal(denied.error.code, 'forbidden_or_unavailable');
    assert.deepEqual(await items(actor, ids.orderA), []);
    const crossPage = (await actor.query('select public.get_customer_orders($1::text) as value', [ids.orderA])).rows[0].value;
    assert.equal(crossPage.ok, true);
    assert.deepEqual(crossPage.data.items, []);
    const own = await detail(actor, ids.orderB);
    assert.equal(own.ok, true);
    assert.equal(own.data.items[0].product_image_url, originalImage);
  });
  await asActor(ids.shipper, async (actor) => {
    const denied = await detail(actor, ids.orderA);
    assert.equal(denied.ok, false);
    assert.equal(denied.error.code, 'forbidden_or_unavailable');
    assert.deepEqual(await items(actor, ids.orderA), []);
    const page = (await actor.query('select public.get_customer_orders() as value')).rows[0].value;
    assert.equal(page.ok, false);
  });
  await asActor(null, async (actor) => {
    const denied = await detail(actor, ids.orderA);
    assert.equal(denied.ok, false);
    assert.equal(denied.error.code, 'unauthenticated');
    assert.deepEqual(await items(actor, ids.orderA), []);
  });
  for (const sql of ['select public.get_order_details($1)', 'select public.get_customer_orders($1::text)',
    'select private.orders_read_items($1)', 'select private.checkout_items_json($1)']) {
    await assert.rejects(asActor(null, (actor) => actor.query(sql, [ids.orderA]), 'anon'), (error) => error.code === '42501');
  }
  console.log('PASS: other-customer image access denied; shipper and missing identity see no item rows; anonymous RPC/helper execution denied.');

  for (const userId of [ids.customerA, ids.customerB, ids.manager, ids.shipper]) {
    await assert.rejects(asActor(userId, (actor) => actor.query('select private.checkout_items_json($1)', [ids.orderA])),
      (error) => error.code === '42501');
  }
  await assert.rejects(asActor(null, (actor) => actor.query('select private.checkout_items_json($1)', [ids.orderA]), 'service_role'),
    (error) => error.code === '42501');
  await asActor(ids.customerA, async (actor) => {
    const requestId = 'a7000000-0000-4000-8000-000000000001';
    const parameters = [requestId, JSON.stringify([{ variant_id: ids.variants[0], quantity: 1 }]),
      'Fixture recipient', '0901234567', 'Fixture Trang Tien, Ha Noi', '21.0285', '105.8542'];
    const place = async () => (await actor.query(`select public.place_order(
      $1::uuid,$2::jsonb,$3::text,$4::text,$5::text,$6::numeric,$7::numeric) as value`, parameters)).rows[0].value;
    const placed = await place();
    assert.equal(placed.ok, true, `Placement rejected: ${JSON.stringify(placed.error)}`);
    assert.equal(placed.data.replayed, false);
    assert.equal(placed.data.items[0].product_image_url, changedCatalogImage);
    assert.deepEqual(placed.data.items[0].attributes, originalAttributes);
    const lookup = (await actor.query('select public.get_placement_result($1::uuid) as value', [requestId])).rows[0].value;
    assert.equal(lookup.ok, true);
    assert.equal(lookup.data.state, 'committed');
    assert.deepEqual(lookup.data.items, placed.data.items);
    const replay = await place();
    assert.equal(replay.ok, true);
    assert.equal(replay.data.replayed, true);
    assert.deepEqual(replay.data.items, placed.data.items);
    const orderRead = await detail(actor, placed.data.order.id);
    assert.equal(orderRead.ok, true);
    // Checkout intentionally inherits caller timezone; Orders pins UTC.
    // Compare timestamp instants without changing either existing contract.
    const normalizeInstants = (list) => list.map((item) => ({
      ...item, created_at: new Date(item.created_at).toISOString(),
    }));
    assert.deepEqual(normalizeInstants(orderRead.data.items), normalizeInstants(placed.data.items));
    // asActor always rolls back, including this genuine placement and replay.
  });
  console.log('PASS: real place_order, get_placement_result, replay and subsequent order detail expose the same newly captured HTTPS snapshot without image attributes; checkout helper remains postgres-only.');

  await client.query(migration);
  assert.deepEqual(await securitySnapshot(), afterSecurity, 'Reapplying migration changed function security metadata');
  assert.equal(await businessHash(), beforeHash, 'Read projection migration changed business rows');
  assert.equal((await client.query('select product_image_url from public.order_items where id=$1', [ids.items[0]])).rows[0].product_image_url, originalImage);
  assert.equal((await client.query('select image_path from public.products where id=$1', [ids.products[0]])).rows[0].image_path, changedCatalogImage);
  console.log(`PASS: catalog changes never alter the order image snapshot; idempotent migration; all public/private business rows unchanged (SHA256 ${beforeHash}).`);
  console.log('ALL ORDER SNAPSHOT IMAGE FIXTURE CHECKS PASSED');
} finally {
  if (client) await client.end().catch(() => {});
  if (admin) await admin.end().catch(() => {});
  if (server && server.exitCode === null) {
    // Stop only the newly created, verified workspace cluster. Preserve files.
    assert.equal(dirname(await realpath(data)).toLowerCase(), temporaryRoot.toLowerCase());
    spawnSync(resolve(nativeBin, 'pg_ctl.exe'), ['-D', data, '-m', 'fast', 'stop'], { windowsHide: true, stdio: 'ignore', timeout: 20_000 });
  }
  await stdout?.close();
  await stderr?.close();
}
