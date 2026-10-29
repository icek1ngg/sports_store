// Real RPCs / real PostgreSQL locks. Native fixture only, invoked by guarded runner.
// Checkout reservation and manager cancellation writes are privileged TEST SEEDS;
// cancellation below tests the order-row/trigger boundary, not Bảo's absent RPC.
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';

export async function testAcceptStartConcurrency(Client, options, admin) {
  const id = n => `04140000-0000-0000-0000-${String(n).padStart(12, '0')}`;
  const customer = id(1), manager = id(2), shipper = id(3), nextShipper = id(4);
  const users = [customer, manager, shipper, nextShipper];
  const orders = Array.from({ length: 9 }, (_, i) => id(10 + i));
  const tasks = [];
  const a = new Client(options), b = new Client(options);
  await Promise.all([a.connect(), b.connect()]);
  const call = (c, operation, task, request) => c.query(
    `select public.${operation}_delivery_task($1::uuid,$2::uuid) as result`,
    [task, request],
  ).then(r => r.rows[0].result);
  async function begin(c, actor) {
    await c.query('BEGIN');
    if (actor) {
      await c.query('SET LOCAL ROLE authenticated');
      await c.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claims',$2,true)",
        [actor, JSON.stringify({ sub: actor, role: 'authenticated' })]);
    }
  }
  async function race(actorA, actorB, firstCall, secondCall, commitFirst = true) {
    await begin(a, actorA);
    await begin(b, actorB);
    const first = await firstCall(a);
    const pid = (await b.query('select pg_backend_pid() pid')).rows[0].pid;
    const pending = secondCall(b).then(value => ({ value }), error => ({ error }));
    let blocked = false;
    for (let i = 0; i < 100; i++) {
      const { rows } = await admin.query('select cardinality(pg_blocking_pids($1)) > 0 blocked', [pid]);
      if (rows[0].blocked) { blocked = true; break; }
      await delay(20);
    }
    assert.ok(blocked, 'second connection must really wait for transaction locks');
    await a.query(commitFirst ? 'COMMIT' : 'ROLLBACK');
    const second = await pending;
    await b.query(second.error ? 'ROLLBACK' : 'COMMIT');
    return { first, second };
  }
  async function snapshot(order) {
    const { rows } = await admin.query(`select o.delivery_attempt_count::int attempts,
      (select count(*)::int from private.outbound_dispatches d where d.order_id=o.id) dispatches,
      (select count(*)::int from public.inventory_movements m where m.order_id=o.id and m.kind='dispatch') movements,
      (select count(*)::int from public.delivery_attempts t where t.order_id=o.id) results
      from public.orders o where o.id=$1`, [order]);
    return rows[0];
  }
  const conflict = result => {
    assert.equal(result.second.error?.code, 'PT409');
    assert.equal(result.second.error?.message, 'STATE_CONFLICT');
  };
  try {
    await admin.query('insert into auth.users(id,email) select x,x::text||$2 from unnest($1::uuid[]) x', [users, '@p041-prod.invalid']);
    await admin.query(`update public.profiles set role=case when id=$1 then 'manager'::public.user_role
      when id=any($2::uuid[]) then 'shipper'::public.user_role else 'customer'::public.user_role end
      where id=any($3::uuid[])`, [manager, [shipper, nextShipper], users]);
    await admin.query('insert into public.categories(id,code,name) values($1,$2,$2)', [id(30), 'P041-PROD-RACE']);
    await admin.query('insert into public.products(id,category_id,name) values($1,$2,$3)', [id(31), id(30), 'P041 production race fixture']);
    await admin.query(`insert into public.product_variants(id,product_id,sku,label,price_vnd,on_hand,reserved)
      values($1,$2,$3,$3,260000,100,$4)`, [id(32), id(31), 'P041-PROD-RACE', orders.length * 2]);
    for (let i = 0; i < orders.length; i++) {
      const order = orders[i];
      await admin.query(`insert into public.orders(id,customer_id,request_id,status,recipient_name,recipient_phone,
        address_detail,latitude,longitude,subtotal_vnd) values($1,$2,$1,'preparing','Fixture','0900000000','Hanoi',21.0285,105.8542,520000)`, [order, customer]);
      await admin.query(`insert into public.order_items(id,order_id,product_id,variant_id,product_name,variant_label,unit_price_vnd,quantity)
        values($1,$2,$3,$4,'Fixture','Fixture',260000,2)`, [id(40 + i), order, id(31), id(32)]);
      await admin.query(`insert into public.inventory_movements(variant_id,order_id,event_id,kind,reserved_delta,actor_id,reason)
        values($1,$2,$3,'reserve',2,$4,'TEST-ONLY checkout reservation seed')`, [id(32), order, id(60 + i), manager]);
      await begin(a, manager);
      const assignment = await a.query('select public.assign_delivery_task($1,$2,$3) result', [order, shipper, id(80 + i)]);
      tasks.push(assignment.rows[0].result.task_id);
      await a.query('COMMIT');
    }

    const replay = await race(shipper, shipper,
      c => call(c, 'accept', tasks[0], id(100)), c => call(c, 'accept', tasks[0], id(100)));
    assert.ifError(replay.second.error);
    assert.deepEqual(replay.first, replay.second.value);
    assert.deepEqual(await snapshot(orders[0]), { attempts: 0, dispatches: 1, movements: 1, results: 0 });

    conflict(await race(shipper, shipper,
      c => call(c, 'accept', tasks[1], id(101)), c => call(c, 'accept', tasks[1], id(102))));
    assert.deepEqual(await snapshot(orders[1]), { attempts: 0, dispatches: 1, movements: 1, results: 0 });

    const startReplay = await race(shipper, shipper,
      c => call(c, 'start', tasks[0], id(103)), c => call(c, 'start', tasks[0], id(103)));
    assert.ifError(startReplay.second.error);
    assert.deepEqual(startReplay.first, startReplay.second.value);
    conflict(await race(shipper, shipper,
      c => call(c, 'start', tasks[1], id(104)), c => call(c, 'start', tasks[1], id(105))));
    for (const order of orders.slice(0, 2)) {
      assert.deepEqual(await snapshot(order), { attempts: 1, dispatches: 1, movements: 1, results: 0 });
    }

    // The trusted order mutation intentionally has no reservation-release or
    // task-cancellation workflow: this verifies only the common locking guard.
    const cancelWins = await race(null, shipper,
      c => c.query("update public.orders set status='cancelled' where id=$1", [orders[2]]),
      c => call(c, 'accept', tasks[2], id(106)));
    conflict(cancelWins);
    assert.deepEqual(await snapshot(orders[2]), { attempts: 0, dispatches: 0, movements: 0, results: 0 });
    const acceptWins = await race(shipper, null,
      c => call(c, 'accept', tasks[3], id(107)),
      c => c.query("update public.orders set status='cancelled' where id=$1", [orders[3]]));
    assert.equal(acceptWins.second.error?.code, 'PT409');
    assert.equal(acceptWins.second.error?.message, 'CUSTODY_UNRESOLVED');
    assert.deepEqual(await snapshot(orders[3]), { attempts: 0, dispatches: 1, movements: 1, results: 0 });

    const rollback = await race(shipper, shipper,
      c => call(c, 'accept', tasks[4], id(108)), c => call(c, 'accept', tasks[4], id(108)), false);
    assert.ifError(rollback.second.error);
    assert.deepEqual(await snapshot(orders[4]), { attempts: 0, dispatches: 1, movements: 1, results: 0 });

    const reassign = c => c.query('select public.assign_delivery_task($1,$2,$3,$4,$5) result',
      [orders[5], nextShipper, id(109), tasks[5], shipper]);
    const reassignmentWins = await race(manager, shipper, reassign,
      c => call(c, 'accept', tasks[5], id(110)));
    assert.equal(reassignmentWins.second.error?.code, '42501');
    assert.deepEqual(await snapshot(orders[5]), { attempts: 0, dispatches: 0, movements: 0, results: 0 });
    const custodyWins = await race(shipper, manager,
      c => call(c, 'accept', tasks[6], id(111)),
      c => c.query('select public.assign_delivery_task($1,$2,$3,$4,$5) result',
        [orders[6], nextShipper, id(112), tasks[6], shipper]));
    assert.equal(custodyWins.second.error?.message, 'CUSTODY_UNRESOLVED');
    assert.deepEqual(await snapshot(orders[6]), { attempts: 0, dispatches: 1, movements: 1, results: 0 });
    console.log('outbound_accept_start_concurrency: PASS (real accept/start replay, distinct keys, rollback waiter, cancel guard both directions, assignment/custody races; no cancel RPC claimed)');
  } finally {
    await Promise.allSettled([a.query('ROLLBACK'), b.query('ROLLBACK')]);
    await Promise.allSettled([a.end(), b.end()]);
    await admin.query('BEGIN');
    try {
      // Specific fixture IDs in a NEW isolated DB only. Never a production path.
      await admin.query("SET LOCAL session_replication_role='replica'");
      for (const table of ['outbound_command_requests', 'outbound_custody_acceptances', 'outbound_dispatches', 'delivery_assignment_requests', 'delivery_assignment_audits']) {
        await admin.query(`delete from private.${table} where order_id=any($1::uuid[])`, [orders]);
      }
      await admin.query(`delete from public.notifications where event_id in
        (select id from public.business_events where task_id=any($1::uuid[])
          or (subject_type='order' and subject_id=any($2::uuid[])))`, [tasks, orders]);
      await admin.query(`delete from public.business_events where task_id=any($1::uuid[])
        or (subject_type='order' and subject_id=any($2::uuid[]))`, [tasks, orders]);
      for (const table of ['inventory_movements', 'delivery_attempts', 'cod_collections', 'delivery_tasks', 'order_items']) {
        await admin.query(`delete from public.${table} where order_id=any($1::uuid[])`, [orders]);
      }
      await admin.query('delete from public.orders where id=any($1::uuid[])', [orders]);
      await admin.query('delete from public.product_variants where id=$1', [id(32)]);
      await admin.query('delete from public.products where id=$1', [id(31)]);
      await admin.query('delete from public.categories where id=$1', [id(30)]);
      await admin.query('delete from public.profiles where id=any($1::uuid[])', [users]);
      await admin.query('delete from auth.users where id=any($1::uuid[])', [users]);
      await admin.query('COMMIT');
    } catch (error) {
      await admin.query('ROLLBACK');
      throw error;
    }
  }
}
