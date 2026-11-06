// P07.1 production failure concurrency tests.  The database is isolated by
// the runner; this module only owns its prefixed fixture rows.
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';

export async function testOutboundFailureProductionConcurrency(Client, options, admin) {
  const id = n => `07160000-0000-0000-0000-${String(n).padStart(12, '0')}`;
  const customer = id(1);
  const manager = id(2);
  const shipperA = id(3);
  const shipperB = id(4);
  const category = id(100);
  const product = id(101);
  const variant = id(111);
  const orders = Array.from({ length: 8 }, (_, i) => id(10 + i));
  const tasks = Array.from({ length: 8 }, (_, i) => id(20 + i));
  const dispatchEvents = Array.from({ length: 8 }, (_, i) => id(30 + i));
  const reserveEvents = Array.from({ length: 8 }, (_, i) => id(40 + i));
  const items = Array.from({ length: 8 }, (_, i) => id(200 + i));
  const requestKeys = Array.from({ length: 5 }, (_, i) => id(50 + i));
  const connected = [];
  const setup = async (sql, params = []) => admin.query(sql, params);

  await setup(
    "insert into auth.users (id,email) values ($1,'p0716-customer@example.invalid'),($2,'p0716-manager@example.invalid'),($3,'p0716-shipper-a@example.invalid'),($4,'p0716-shipper-b@example.invalid')",
    [customer, manager, shipperA, shipperB],
  );
  await setup(
    "update public.profiles set role = case when id=$1 then 'manager'::public.user_role when id in ($2,$3) then 'shipper'::public.user_role else 'customer'::public.user_role end where id in ($1,$2,$3,$4)",
    [manager, shipperA, shipperB, customer],
  );
  await setup("insert into public.categories(id,code,name) values ($1,'P0716','P07.1 concurrency')", [category]);
  await setup("insert into public.products(id,category_id,name) values ($1,$2,'P07.1 concurrency product')", [product, category]);
  await setup(
    "insert into public.product_variants(id,product_id,sku,label,price_vnd,on_hand,reserved) values ($1,$2,'P0716-01','P07.1 concurrency variant',520000,0,0)",
    [variant, product],
  );

  for (let i = 0; i < orders.length; i += 1) {
    const order = orders[i];
    const task = tasks[i];
    const dispatchEvent = dispatchEvents[i];
    const reserveEvent = reserveEvents[i];
    const shipper = i === 5 ? shipperB : shipperA;
    await setup(
      "insert into public.orders(id,customer_id,request_id,status,recipient_name,recipient_phone,address_detail,latitude,longitude,subtotal_vnd,delivery_attempt_count) values($1,$2,$1,'delivering','P07.1 concurrency recipient','0907160001','P07.1 Hanoi address',21.0285,105.8542,520000,1)",
      [order, customer],
    );
    await setup(
      "insert into public.order_items(id,order_id,product_id,variant_id,product_name,variant_label,unit_price_vnd,quantity) values($1,$2,$3,$4,'P07.1 concurrency product','P07.1 concurrency variant',520000,1)",
      [items[i], order, product, variant],
    );
    await setup(
      "insert into public.inventory_movements(variant_id,order_id,event_id,kind,reserved_delta,actor_id,reason) values($1,$2,$3,'reserve',1,$4,'p0716 reserve')",
      [variant, order, reserveEvent, manager],
    );
    await setup(
      "insert into public.delivery_tasks(id,order_id,kind,assigned_shipper_id,assigned_by,status,attempt_number,destination_name,destination_phone,destination_address,destination_latitude,destination_longitude,amount_to_collect_vnd,assigned_at,accepted_at,started_at) values($1,$2,'outbound',$3,$4,'in_transit',1,'P07.1 concurrency recipient','0907160001','P07.1 Hanoi address',21.0285,105.8542,550000,clock_timestamp()-interval '90 seconds',clock_timestamp()-interval '60 seconds',clock_timestamp()-interval '30 seconds')",
      [task, order, shipper, manager],
    );
    await setup(
      "insert into public.cod_collections(order_id,shipper_id,status,expected_amount_vnd) values($1,$2,'uncollected',550000)",
      [order, shipper],
    );
    await setup(
      "insert into public.business_events(id,actor_id,subject_type,subject_id,from_state,to_state,reason,task_id,request_id) values($1,$2,'delivery_task',$3,'accepted','in_transit','fixture dispatch',$3,$1)",
      [dispatchEvent, shipper, task],
    );
    await setup(
      "insert into public.inventory_movements(variant_id,order_id,event_id,kind,on_hand_delta,reserved_delta,actor_id,reason) values($1,$2,$3,'dispatch',-1,-1,$4,'outbound_dispatch')",
      [variant, order, dispatchEvent, shipper],
    );
    await setup(
      "insert into private.outbound_dispatches(order_id,initial_task_id,holder_id,event_id,items_snapshot,dispatched_at) values($1,$2,$3,$4,private.outbound_items_snapshot($1),clock_timestamp()-interval '20 seconds')",
      [order, task, shipper, dispatchEvent],
    );
    await setup(
      "insert into private.outbound_custody_acceptances(task_id,order_id,holder_id,dispatch_event_id,accepted_at,attempt_number) select $1,$2,$3,$4,accepted_at,1 from public.delivery_tasks where id=$1",
      [task, order, shipper, dispatchEvent],
    );
  }

  for (const client of [new Client(options), new Client(options)]) {
    await client.connect();
    await client.query("set statement_timeout='8s'; set lock_timeout='5s'");
    connected.push(client);
  }
  const [a, b] = connected;
  const begin = async (client, actor) => {
    await client.query('begin');
    await client.query('set local role authenticated');
    await client.query("select set_config('request.jwt.claim.sub',$1,true)", [actor]);
    await client.query("select set_config('request.jwt.claims',$1,true)", [JSON.stringify({ sub: actor, role: 'authenticated', aud: 'authenticated' })]);
  };
  const fail = (client, task, request, reason = 'bad_address', description = 'p0716 test failure') => client.query(
    'select public.fail_delivery_task($1::uuid,$2::uuid,$3::text,$4::text) result',
    [task, request, reason, description],
  ).then(r => r.rows[0].result);
  const complete = (client, task, request) => client.query(
    'select public.complete_outbound_delivery($1::uuid,$2::uuid,true,550000) result',
    [task, request],
  ).then(r => r.rows[0].result);
  const race = async (first, firstActor, second, secondActor, requireBlocked = true) => {
    await begin(a, firstActor);
    await begin(b, secondActor);
    const firstResult = await first(a);
    const pid = (await b.query('select pg_backend_pid() pid')).rows[0].pid;
    const pending = second(b).then(value => ({ value }), error => ({ error }));
    let blocked = false;
    for (let i = 0; i < 100; i += 1) {
      if ((await admin.query('select cardinality(pg_blocking_pids($1)) > 0 blocked', [pid])).rows[0].blocked) {
        blocked = true;
        break;
      }
      await delay(10);
    }
    if (requireBlocked) assert.equal(blocked, true, 'failure/success contender must wait on the order lock');
    await a.query('commit');
    const secondResult = await pending;
    await b.query(secondResult.error ? 'rollback' : 'commit');
    return { firstResult, secondResult };
  };

  try {
    const duplicate = await race(
      c => fail(c, tasks[0], requestKeys[0]), shipperA,
      c => fail(c, tasks[0], requestKeys[0]), shipperA,
    );
    assert.deepEqual(duplicate.firstResult, duplicate.secondResult.value, 'identical failure replay must return the same response');

    const distinct = await race(
      c => fail(c, tasks[1], requestKeys[1]), shipperA,
      c => fail(c, tasks[1], id(61)), shipperA,
    );
    assert.equal(distinct.secondResult.error?.code, 'PT409');
    assert.equal(distinct.secondResult.error?.message, 'STATE_CONFLICT');

    const failureFirst = await race(
      c => fail(c, tasks[2], requestKeys[2]), shipperA,
      c => complete(c, tasks[2], requestKeys[2]), shipperA,
    );
    assert.equal(failureFirst.secondResult.error?.code, 'PT409');
    assert.equal(failureFirst.secondResult.error?.message, 'IDEMPOTENCY_CONFLICT');

    const completionFirst = await race(
      c => complete(c, tasks[3], requestKeys[3]), shipperA,
      c => fail(c, tasks[3], requestKeys[3]), shipperA,
    );
    assert.equal(completionFirst.secondResult.error?.code, 'PT409');
    assert.equal(completionFirst.secondResult.error?.message, 'IDEMPOTENCY_CONFLICT');

    const failureWins = await race(
      c => fail(c, tasks[6], id(70)), shipperA,
      c => complete(c, tasks[6], id(71)), shipperA,
    );
    assert.equal(failureWins.secondResult.error?.code, 'PT409');
    assert.equal(failureWins.secondResult.error?.message, 'STATE_CONFLICT');
    const completionWins = await race(
      c => complete(c, tasks[7], id(72)), shipperA,
      c => fail(c, tasks[7], id(73)), shipperA,
    );
    assert.equal(completionWins.secondResult.error?.code, 'PT409');
    assert.equal(completionWins.secondResult.error?.message, 'STATE_CONFLICT');

    // The client request UUID is scoped by actor.  Two current shippers may
    // use the same UUID on independent tasks; each gets a different server
    // event/result and neither is treated as a replay of the other.
    await begin(a, shipperA);
    await begin(b, shipperB);
    const [sameKeyA, sameKeyB] = await Promise.all([
      fail(a, tasks[4], requestKeys[4]),
      fail(b, tasks[5], requestKeys[4]),
    ]);
    await a.query('commit');
    await b.query('commit');
    assert.equal(sameKeyA.task_status, 'failed');
    assert.equal(sameKeyB.task_status, 'failed');
    assert.notEqual(sameKeyA.event_id, sameKeyB.event_id, 'server event IDs must not reuse a client request UUID');
    const sameKeyEvents = (await admin.query(
      "select count(*)::int count from public.business_events where id in ($1::uuid,$2::uuid) and reason='delivery_failed'",
      [sameKeyA.event_id, sameKeyB.event_id],
    )).rows[0].count;
    assert.equal(sameKeyEvents, 2);

    const state = (await admin.query(`
      select
        (select status = 'awaiting_redelivery'::public.order_status
           from public.orders where id = $1) as failure_first_order,
        (select status = 'uncollected'::public.cod_status
              and collected_amount_vnd = 0 and collected_by is null
           from public.cod_collections where order_id = $2) as failure_first_cod,
        (select count(*) = 1 and bool_and(result = 'failed'::public.delivery_attempt_result)
           from public.delivery_attempts where task_id = $3) as failure_first_attempt,
        (select status = 'delivered'::public.order_status
           from public.orders where id = $4) as completion_first_order,
        (select status = 'collected'::public.cod_status
              and collected_amount_vnd = 550000
           from public.cod_collections where order_id = $5) as completion_first_cod,
        (select count(*) = 1 and bool_and(result = 'success'::public.delivery_attempt_result)
           from public.delivery_attempts where task_id = $6) as completion_first_attempt,
        (select count(*) = 1 from private.outbound_failure_results where task_id = $3) as failure_ledger,
        (select count(*) = 1 from private.outbound_completion_results where task_id = $6) as completion_ledger
    `, [orders[2], orders[2], tasks[2], orders[3], orders[3], tasks[3]])).rows[0];
    for (const [label, value] of Object.entries(state)) assert.equal(value, true, `serialized outcome: ${label}`);

    console.log('outbound_failure_production_concurrency: PASS (duplicate replay, distinct-key conflict, fail/complete both orderings, actor-scoped request UUID)');
  } finally {
    await Promise.allSettled(connected.map(client => client.query('rollback')));
    await Promise.allSettled(connected.map(client => client.end()));
    await setup('begin');
    try {
      await setup('delete from public.notifications where subject_id = any($1::uuid[])', [tasks]);
      await setup('alter table private.outbound_failure_requests disable trigger user');
      await setup('alter table private.outbound_failure_results disable trigger user');
      await setup('delete from private.outbound_failure_requests where task_id = any($1::uuid[])', [tasks]);
      await setup('delete from private.outbound_failure_results where task_id = any($1::uuid[])', [tasks]);
      await setup('alter table private.outbound_failure_requests enable trigger user');
      await setup('alter table private.outbound_failure_results enable trigger user');
      await setup('alter table private.outbound_completion_requests disable trigger user');
      await setup('alter table private.outbound_completion_results disable trigger user');
      await setup('delete from private.outbound_completion_requests where task_id = any($1::uuid[])', [tasks]);
      await setup('delete from private.outbound_completion_results where task_id = any($1::uuid[])', [tasks]);
      await setup('alter table private.outbound_completion_requests enable trigger user');
      await setup('alter table private.outbound_completion_results enable trigger user');
      await setup('delete from public.delivery_attempts where task_id = any($1::uuid[])', [tasks]);
      await setup('delete from public.cod_collections where order_id = any($1::uuid[])', [orders]);
      await setup('alter table private.outbound_custody_acceptances disable trigger user');
      await setup('alter table private.outbound_dispatches disable trigger user');
      await setup('delete from private.outbound_custody_acceptances where task_id = any($1::uuid[])', [tasks]);
      await setup('delete from private.outbound_dispatches where order_id = any($1::uuid[])', [orders]);
      await setup('alter table private.outbound_custody_acceptances enable trigger user');
      await setup('alter table private.outbound_dispatches enable trigger user');
      await setup('delete from public.business_events where subject_id = any($1::uuid[])', [tasks]);
      await setup('delete from public.delivery_tasks where id = any($1::uuid[])', [tasks]);
      await setup('delete from public.inventory_movements where order_id = any($1::uuid[])', [orders]);
      await setup('delete from public.order_items where order_id = any($1::uuid[])', [orders]);
      await setup('delete from public.orders where id = any($1::uuid[])', [orders]);
      await setup('delete from public.product_variants where id=$1', [variant]);
      await setup('delete from public.products where id=$1', [product]);
      await setup('delete from public.categories where id=$1', [category]);
      await setup('delete from auth.users where id = any($1::uuid[])', [[customer, manager, shipperA, shipperB]]);
      const leaked = (await setup(`
        select
          (select count(*) from public.orders where id = any($1::uuid[])) orders,
          (select count(*) from public.delivery_tasks where id = any($2::uuid[])) tasks,
          (select count(*) from public.delivery_attempts where task_id = any($2::uuid[])) attempts,
          (select count(*) from public.business_events where subject_id = any($2::uuid[])) events,
          (select count(*) from public.notifications where subject_id = any($2::uuid[])) notifications,
          (select count(*) from private.outbound_failure_requests where task_id = any($2::uuid[])) failure_requests,
          (select count(*) from private.outbound_failure_results where task_id = any($2::uuid[])) failure_results,
          (select count(*) from private.outbound_completion_requests where task_id = any($2::uuid[])) completion_requests,
          (select count(*) from private.outbound_completion_results where task_id = any($2::uuid[])) completion_results
      `, [orders, tasks])).rows[0];
      for (const [label, value] of Object.entries(leaked)) {
        assert.equal(Number(value), 0, `concurrency cleanup leaked ${label}`);
      }
      await setup('commit');
    } catch (cleanupError) {
      await setup('rollback');
      throw cleanupError;
    }
  }
}
