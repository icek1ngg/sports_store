// Isolated PostgreSQL fixture runner for MH16 checkout placement.
//
// This runner uses only the native PostgreSQL instance under
// supabase/.temp/catalog_pg_data.  It never connects to Supabase cloud, never
// resets an existing database, and uses the Auth/Storage SQL stubs solely for
// the isolated RLS fixture.
import { readFile, readdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const testDir = dirname(fileURLToPath(import.meta.url));
const runtime = resolve(testDir, '../.temp/catalog_pg_runtime');
const require = createRequire(resolve(runtime, 'package.json'));
const { Client } = require('pg');

const database = process.argv[2] || 'checkout_placement_fixture';
if (!/^checkout_[a-z0-9_]+$/.test(database)) {
  throw new Error('Use a new checkout_ prefixed isolated test database name.');
}

const options = {
  host: '127.0.0.1',
  port: 55441,
  user: 'postgres',
  database: 'postgres',
};

const admin = new Client(options);
await admin.connect();
try {
  const { rows } = await admin.query('SHOW server_version');
  if (!rows[0].server_version.startsWith('17.')) {
    throw new Error('Requires PostgreSQL 17');
  }
  const directory = await admin.query('SHOW data_directory');
  const expectedDirectory = resolve(testDir, '../.temp/catalog_pg_data');
  if (
    resolve(directory.rows[0].data_directory).toLowerCase() !==
    expectedDirectory.toLowerCase()
  ) {
    throw new Error('Refusing PostgreSQL outside this workspace fixture directory.');
  }
  // Deliberately fail if the database exists: never reset or drop existing data.
  await admin.query(`CREATE DATABASE "${database}"`);
  console.log(
    `Fixture environment: PostgreSQL ${rows[0].server_version}; local Auth/Storage SQL stubs only.`,
  );
} finally {
  await admin.end();
}

const client = new Client({ ...options, database });
await client.connect();

const concurrencyIds = {
  customerA: '11000000-0000-0000-0000-000000000001',
  customerB: '11000000-0000-0000-0000-000000000002',
  manager: '11000000-0000-0000-0000-000000000003',
  category: '12000000-0000-0000-0000-000000000001',
  product: '13000000-0000-0000-0000-000000000001',
  variant: '14000000-0000-0000-0000-000000000001',
  requestA: '15000000-0000-0000-0000-000000000001',
  // Deliberately shared across two customer principals: source-operation
  // uniqueness must be scoped by customer, not by request UUID alone.
  requestB: '15000000-0000-0000-0000-000000000001',
};

const serviceArea = {
  type: 'Polygon',
  coordinates: [
    [
      [105, 20],
      [106, 20],
      [106, 21],
      [105, 21],
      [105, 20],
    ],
  ],
};

let priorStoreSettings = null;
let concurrencySeeded = false;

async function seedConcurrencyFixture() {
  const existing = await client.query(
    `select name, address, latitude, longitude, approved_service_area_geojson
       from public.store_settings where id = true`,
  );
  priorStoreSettings = existing.rows[0] ?? null;

  await client.query('BEGIN');
  try {
    await client.query(
      `insert into auth.users (id, email) values
         ($1::uuid, 'checkout-concurrency-a@example.invalid'),
         ($2::uuid, 'checkout-concurrency-b@example.invalid'),
         ($3::uuid, 'checkout-concurrency-manager@example.invalid')`,
      [concurrencyIds.customerA, concurrencyIds.customerB, concurrencyIds.manager],
    );
    await client.query(
      `update public.profiles set role = 'manager'
       where id = $1::uuid`,
      [concurrencyIds.manager],
    );
    await client.query(
      `insert into public.categories (id, code, name, is_active)
       values ($1::uuid, 'checkout-concurrency', 'Checkout concurrency', true)`,
      [concurrencyIds.category],
    );
    await client.query(
      `insert into public.products (id, category_id, name, description, is_active)
       values ($1::uuid, $2::uuid, 'Concurrency fixture', 'Isolated fixture', true)`,
      [concurrencyIds.product, concurrencyIds.category],
    );
    await client.query(
      `insert into public.product_variants
         (id, product_id, sku, label, attributes, price_vnd, is_active,
          on_hand, reserved, damaged)
       values ($1::uuid, $2::uuid, 'CHECKOUT-CONCURRENCY-001', 'One unit',
          '{}'::jsonb, 100000, true, 1, 0, 0)`,
      [concurrencyIds.variant, concurrencyIds.product],
    );
    await client.query(
      `insert into public.store_settings
         (id, name, address, latitude, longitude, approved_service_area_geojson)
       values (true, 'Concurrency fixture store', 'Synthetic Hanoi', 20.5, 105.5, $1::jsonb)
       on conflict (id) do update set
         name = excluded.name,
         address = excluded.address,
         latitude = excluded.latitude,
         longitude = excluded.longitude,
         approved_service_area_geojson = excluded.approved_service_area_geojson`,
      [JSON.stringify(serviceArea)],
    );
    await client.query('COMMIT');
    concurrencySeeded = true;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  }
}

async function callPlacement(userId, requestId) {
  const connection = new Client({ ...options, database });
  await connection.connect();
  try {
    await connection.query('set role authenticated');
    await connection.query(
      `select set_config('request.jwt.claim.sub', $1, false),
              set_config('request.jwt.claims', $2, false)`,
      [
        userId,
        JSON.stringify({ sub: userId, role: 'authenticated', aud: 'authenticated' }),
      ],
    );
    const result = await connection.query(
      `select public.place_order(
         $1::uuid,
         $2::jsonb,
         $3::text,
         $4::text,
         $5::text,
         $6::numeric,
         $7::numeric
       ) as result`,
      [
        requestId,
        JSON.stringify([{ variant_id: concurrencyIds.variant, quantity: 1 }]),
        'Concurrent fixture customer',
        '0900000011',
        'Synthetic Hanoi concurrency address',
        '20.25',
        '105.25',
      ],
    );
    return result.rows[0].result;
  } finally {
    await connection.end();
  }
}

async function runConcurrentReservationCheck() {
  await seedConcurrencyFixture();
  const results = await Promise.all([
    callPlacement(concurrencyIds.customerA, concurrencyIds.requestA),
    callPlacement(concurrencyIds.customerB, concurrencyIds.requestB),
  ]);
  const successes = results.filter((result) => result.ok === true);
  const insufficient = results.filter(
    (result) => result.ok === false && result.error?.code === 'insufficient_stock',
  );
  if (successes.length !== 1 || insufficient.length !== 1) {
    throw new Error(`Concurrent placement did not produce one success/one stock failure: ${JSON.stringify(results)}`);
  }

  const stock = await client.query(
    `select on_hand, reserved, available_quantity
       from public.product_variants where id = $1::uuid`,
    [concurrencyIds.variant],
  );
  if (
    stock.rows.length !== 1 ||
    stock.rows[0].on_hand !== '1' ||
    stock.rows[0].reserved !== '1' ||
    stock.rows[0].available_quantity !== '0'
  ) {
    throw new Error(`Concurrent stock invariant failed: ${JSON.stringify(stock.rows)}`);
  }
  const effects = await client.query(
    `select
       (select count(*) from public.orders where request_id in ($1::uuid, $2::uuid)) as orders,
       (select count(*) from public.inventory_movements where variant_id = $3::uuid) as movements,
       (select count(*) from public.notifications where subject_id in
          (select id from public.orders where request_id in ($1::uuid, $2::uuid))) as notifications`,
    [concurrencyIds.requestA, concurrencyIds.requestB, concurrencyIds.variant],
  );
  const counts = effects.rows[0];
  if (counts.orders !== '1' || counts.movements !== '1' || counts.notifications !== '1') {
    throw new Error(`Concurrent side-effect invariant failed: ${JSON.stringify(counts)}`);
  }
  console.log('PASS: concurrent final-stock placement = one committed order, one insufficient_stock, one reservation.');
}

async function cleanupConcurrencyFixture() {
  if (!concurrencySeeded) return;
  await client.query('BEGIN');
  try {
    await client.query(
      `delete from private.checkout_placements
       where request_id in ($1::uuid, $2::uuid)`,
      [concurrencyIds.requestA, concurrencyIds.requestB],
    );
    await client.query(
      `delete from public.notifications
       where subject_id in (select id from public.orders
         where request_id in ($1::uuid, $2::uuid))`,
      [concurrencyIds.requestA, concurrencyIds.requestB],
    );
    await client.query(
      `delete from public.inventory_movements
       where order_id in (select id from public.orders
         where request_id in ($1::uuid, $2::uuid))`,
      [concurrencyIds.requestA, concurrencyIds.requestB],
    );
    await client.query(
      `delete from public.order_items
       where order_id in (select id from public.orders
         where request_id in ($1::uuid, $2::uuid))`,
      [concurrencyIds.requestA, concurrencyIds.requestB],
    );
    await client.query(
      `delete from public.business_events
       where subject_id in (select id from public.orders
         where request_id in ($1::uuid, $2::uuid))`,
      [concurrencyIds.requestA, concurrencyIds.requestB],
    );
    await client.query(
      `delete from public.orders where request_id in ($1::uuid, $2::uuid)`,
      [concurrencyIds.requestA, concurrencyIds.requestB],
    );
    await client.query(
      `delete from public.product_variants where id = $1::uuid`,
      [concurrencyIds.variant],
    );
    await client.query(
      `delete from public.products where id = $1::uuid`,
      [concurrencyIds.product],
    );
    await client.query(
      `delete from public.categories where id = $1::uuid`,
      [concurrencyIds.category],
    );
    await client.query(
      `delete from auth.users where id in ($1::uuid, $2::uuid, $3::uuid)`,
      [concurrencyIds.customerA, concurrencyIds.customerB, concurrencyIds.manager],
    );
    if (priorStoreSettings) {
      await client.query(
        `update public.store_settings set
           name = $1, address = $2, latitude = $3, longitude = $4,
           approved_service_area_geojson = $5::jsonb
         where id = true`,
        [
          priorStoreSettings.name,
          priorStoreSettings.address,
          priorStoreSettings.latitude,
          priorStoreSettings.longitude,
          JSON.stringify(priorStoreSettings.approved_service_area_geojson),
        ],
      );
    } else {
      await client.query('delete from public.store_settings where id = true');
    }
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    concurrencySeeded = false;
  }
}

try {
  await client.query("set sports_store.fixture_mode = 'p011_isolated'");
  await client.query(
    await readFile(resolve(testDir, 'fixtures/p011_auth_storage.sql.fixture'), 'utf8'),
  );

  const migrationDir = resolve(testDir, '../migrations');
  const migrations = (await readdir(migrationDir))
    .filter((name) => name.endsWith('.sql'))
    .sort();
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

  // The root configuration migration supplies the approved Hanoi polygon.
  // Exercise the real 4k+ vertex shape once before the synthetic hole/boundary
  // tests in checkout_placement.sql.  The helper is pure PostgreSQL and must
  // reject representative Hue, Ho Chi Minh City and Bac Ninh coordinates.
  const geography = await client.query(`
    select
      private.checkout_geojson_contains(
        s.approved_service_area_geojson, 21.0285, 105.8542
      ) as hanoi,
      private.checkout_geojson_contains(
        s.approved_service_area_geojson, 16.4637, 107.5909
      ) as hue,
      private.checkout_geojson_contains(
        s.approved_service_area_geojson, 10.8231, 106.6297
      ) as ho_chi_minh,
      private.checkout_geojson_contains(
        s.approved_service_area_geojson, 21.1861, 106.0763
      ) as bac_ninh
    from public.store_settings as s
    where s.id = true
  `);
  if (
    geography.rows.length !== 1 ||
    geography.rows[0].hanoi !== true ||
    geography.rows[0].hue !== false ||
    geography.rows[0].ho_chi_minh !== false ||
    geography.rows[0].bac_ninh !== false
  ) {
    throw new Error(`Hanoi geometry validation failed: ${JSON.stringify(geography.rows)}`);
  }
  console.log('PASS: approved Hanoi geometry accepts Hanoi center and rejects neighboring-city samples.');

  await runConcurrentReservationCheck();
  await cleanupConcurrencyFixture();

  const results = await client.query(
    await readFile(resolve(testDir, 'checkout_placement.sql'), 'utf8'),
  );
  const hasPass = results.some((result) =>
    result.rows?.some((row) => Object.values(row).includes('checkout_placement.sql: PASS')),
  );
  if (!hasPass || results.at(-1)?.command !== 'ROLLBACK') {
    throw new Error('checkout_placement.sql did not finish all assertions with PASS + ROLLBACK');
  }
  console.log('checkout_placement.sql: PASS (SQL fixture, rolled back)');

  const remaining = await client.query(`
    select
      (select count(*) from auth.users) as users,
      (select count(*) from public.orders) as orders,
      (select count(*) from public.delivery_tasks) as tasks,
      (select count(*) from public.notifications) as notifications,
      (select count(*) from private.checkout_placements) as placements,
      (select count(*) from storage.objects) as objects
  `);
  if (Object.values(remaining.rows[0]).some((value) => value !== '0')) {
    throw new Error(`Fixture rows survived rollback/cleanup: ${JSON.stringify(remaining.rows[0])}`);
  }
  console.log('PASS: checkout fixture rolled back; no Auth/order/task/notification/placement/Storage rows remain.');
} finally {
  try {
    await cleanupConcurrencyFixture();
  } finally {
    await client.end();
  }
}
