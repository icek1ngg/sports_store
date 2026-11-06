// Native isolated fixture only. Invoked after the guarded runner creates a new DB.
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';

export async function testAssignmentConcurrency(Client, options, admin) {
  const id = (n) => `03300000-0000-0000-0000-${String(n).padStart(12, '0')}`;
  const customer = id(1), managerA = id(2), managerB = id(3);
  const shipperA = id(4), shipperB = id(5), shipperC = id(6);
  const users = [customer, managerA, managerB, shipperA, shipperB, shipperC];
  const orders = [id(10), id(11), id(12)];
  const a = new Client(options), b = new Client(options);
  await a.connect();
  await b.connect();
  async function begin(client, actor) {
    await client.query('BEGIN');
    await client.query('SET LOCAL ROLE authenticated');
    await client.query("select set_config('request.jwt.claim.sub', $1, true), set_config('request.jwt.claims', $2, true)",
      [actor, JSON.stringify({ sub: actor, role: 'authenticated' })]);
  }
  const assign = (client, order, shipper, request, task = null, previous = null) =>
    client.query('select public.assign_delivery_task($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::uuid) as result',
      [order, shipper, request, task, previous]).then(r => r.rows[0].result);
  async function blockedRace(firstActor, secondActor, firstCall, secondCall) {
    await begin(a, firstActor);
    await begin(b, secondActor);
    const first = await firstCall(a);
    const pid = (await b.query('select pg_backend_pid() as pid')).rows[0].pid;
    // Attach rejection immediately so an expected SQL exception is handled.
    const pending = secondCall(b).then(value => ({ value }), error => ({ error }));
    let blocked = false;
    for (let i = 0; i < 100; i++) {
      const r = await admin.query('select cardinality(pg_blocking_pids($1)) > 0 as blocked', [pid]);
      if (r.rows[0].blocked) { blocked = true; break; }
      await delay(20);
    }
    assert.ok(blocked, 'second connection must actually wait for a transaction lock');
    await a.query('COMMIT');
    const second = await pending;
    await b.query(second.error ? 'ROLLBACK' : 'COMMIT');
    return { first, second };
  }
  try {
    await admin.query('insert into auth.users(id,email) select x, x::text || $2 from unnest($1::uuid[]) x', [users, '@concurrency.invalid']);
    await admin.query("update public.profiles set role = case when id = any($1::uuid[]) then 'manager'::public.user_role when id = any($2::uuid[]) then 'shipper'::public.user_role else 'customer'::public.user_role end where id = any($3::uuid[])",
      [[managerA, managerB], [shipperA, shipperB, shipperC], users]);
    await admin.query(`insert into public.orders(id, customer_id, request_id, status, recipient_name,
      recipient_phone,address_detail,latitude,longitude,subtotal_vnd)
      select x,$2,x,'preparing','Concurrency fixture','0900000000','Hanoi fixture',21.0285,105.8542,100000
      from unnest($1::uuid[]) x`, [orders, customer]);

    const initial = await blockedRace(managerA, managerB,
      c => assign(c, orders[0], shipperA, id(20)), c => assign(c, orders[0], shipperB, id(21)));
    assert.equal(initial.second.error?.code, 'PT409');
    assert.equal(initial.second.error?.message, 'TASK_CONFLICT');

    const replay = await blockedRace(managerA, managerA,
      c => assign(c, orders[1], shipperA, id(22)), c => assign(c, orders[1], shipperA, id(22)));
    assert.ifError(replay.second.error);
    assert.deepEqual(replay.first, replay.second.value);

    const reassign = await blockedRace(managerA, managerB,
      c => assign(c, orders[0], shipperB, id(23), initial.first.task_id, shipperA),
      c => assign(c, orders[0], shipperC, id(24), initial.first.task_id, shipperA));
    assert.equal(reassign.second.error?.code, 'PT409');
    assert.equal(reassign.second.error?.message, 'STALE_ASSIGNMENT');
    const rows = (await admin.query(`select t.order_id, count(*)::int as tasks,
      bool_and(t.amount_to_collect_vnd=o.total_cod_vnd and c.expected_amount_vnd=o.total_cod_vnd
        and c.shipper_id=t.assigned_shipper_id) as equal
      from public.delivery_tasks t join public.orders o on o.id=t.order_id
      join public.cod_collections c on c.order_id=o.id where o.id=any($1::uuid[])
      group by t.order_id`, [orders])).rows;
    assert.equal(rows.length, 2);
    assert.ok(rows.every(r => r.tasks === 1 && r.equal));
    const counts = (await admin.query(`select
      (select count(*)::int from private.delivery_assignment_requests where order_id=any($1::uuid[])) requests,
      (select count(*)::int from private.delivery_assignment_audits where order_id=any($1::uuid[])) audits`, [orders])).rows[0];
    assert.deepEqual(counts, { requests: 3, audits: 3 }, 'only winners create one request/audit; replay and losers create none');
    console.log('outbound_assignment_concurrency: PASS (two real connections; duplicate create, replay, CAS reassignment, COD equality)');
  } finally {
    await Promise.allSettled([a.query('ROLLBACK'), b.query('ROLLBACK')]);
    await Promise.allSettled([a.end(), b.end()]);
    // Specific fixture IDs only in the newly created isolated database.
    // Fixture admin disables triggers inside this cleanup transaction because
    // the production append-only guards intentionally forbid ledger deletion.
    await admin.query('BEGIN');
    try {
      await admin.query("SET LOCAL session_replication_role = 'replica'");
      await admin.query('delete from private.delivery_assignment_requests where order_id=any($1::uuid[])', [orders]);
      await admin.query('delete from private.delivery_assignment_audits where order_id=any($1::uuid[])', [orders]);
      await admin.query('delete from public.cod_collections where order_id=any($1::uuid[])', [orders]);
      await admin.query('delete from public.delivery_tasks where order_id=any($1::uuid[])', [orders]);
      await admin.query('delete from public.orders where id=any($1::uuid[])', [orders]);
      await admin.query('delete from public.profiles where id=any($1::uuid[])', [users]);
      await admin.query('delete from auth.users where id=any($1::uuid[])', [users]);
      await admin.query('COMMIT');
    } catch (error) {
      await admin.query('ROLLBACK');
      throw error;
    }
  }
}
