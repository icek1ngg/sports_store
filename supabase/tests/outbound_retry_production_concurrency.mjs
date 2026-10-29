// P07.2 production concurrency tests. The runner owns an isolated database;
// this module owns only its prefixed rows and removes them in one cleanup
// transaction with USER triggers disabled (never session_replication_role).
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';

export async function testOutboundRetryProductionConcurrency(Client, options, admin) {
  const id = n => `07260000-0000-0000-0000-${String(n).padStart(12, '0')}`;
  const customer = id(1), managerA = id(2), managerB = id(3);
  const shipperA = id(4), shipperB = id(5);
  const category = id(100), product = id(101), variant = id(111);
  const orders = [id(10), id(11), id(12)];
  const items = [id(201), id(202), id(203)];
  const reserveEvents = [id(301), id(302), id(303)];
  const users = [customer, managerA, managerB, shipperA, shipperB];
  const connected = [new Client(options), new Client(options)];
  const [a, b] = connected;

  const setup = (sql, params = []) => admin.query(sql, params);
  const begin = async (client, actor) => {
    await client.query('begin');
    await client.query('set local role authenticated');
    await client.query("select set_config('request.jwt.claim.sub',$1,true), set_config('request.jwt.claims',$2,true)", [
      actor, JSON.stringify({ sub: actor, role: 'authenticated', aud: 'authenticated' }),
    ]);
  };
  const finish = async (client, error) => client.query(error ? 'rollback' : 'commit');
  const call = (client, name, params) => client.query(
    `select public.${name}(${params.map(() => '$1').length ? params.map((_, i) => `$${i + 1}::uuid`).join(',') : ''}) as result`,
    params,
  ).then(r => r.rows[0].result);
  const assign = (client, order, request, shipper = shipperA) => call(
    client, 'assign_delivery_task', [order, shipper, request, null, null]);
  const accept = (client, task, request) => call(client, 'accept_delivery_task', [task, request]);
  const start = (client, task, request) => call(client, 'start_delivery_task', [task, request]);
  const fail = (client, task, request) => client.query(
    'select public.fail_delivery_task($1::uuid,$2::uuid,$3::text,null) as result',
    [task, request, 'bad_address'],
  ).then(r => r.rows[0].result);
  const decide = (client, order, request, decision, failedTask, retryTask = null) =>
    client.query(
      'select public.decide_outbound_retry($1::uuid,$2::uuid,$3::text,$4::uuid,$5::uuid) as result',
      [order, request, decision, failedTask, retryTask],
    ).then(r => r.rows[0].result);

  // Execute one complete RPC transaction and return its ACK. Calls are kept
  // in explicit transactions so the race helper can hold the order lock after
  // the first RPC returns but before it commits.
  const one = async (client, actor, fn) => {
    await begin(client, actor);
    try {
      const value = await fn();
      await finish(client, false);
      return value;
    } catch (error) {
      await finish(client, true);
      throw error;
    }
  };

  async function prepareFailed(order, base) {
    const assigned = await one(a, managerA, () => assign(a, order, id(base), shipperA));
    const task = assigned.task_id;
    await one(a, shipperA, () => accept(a, task, id(base + 1)));
    await one(a, shipperA, () => start(a, task, id(base + 2)));
    await one(a, shipperA, () => fail(a, task, id(base + 3)));
    return task;
  }

  async function createRetryAccepted(order, base) {
    const failedTask = await prepareFailed(order, base);
    const retryAck = await one(a, managerA, () => decide(
      a, order, id(base + 4), 'retry', failedTask, null,
    ));
    const task2 = (await setup(
      'select id from public.delivery_tasks where order_id=$1 and attempt_number=2', [order],
    )).rows[0]?.id;
    assert.ok(task2, 'retry must create an attempt 2 task');
    assert.equal(retryAck.task_id ?? retryAck.retry_task_id ?? task2, task2);
    await one(a, shipperA, () => accept(a, task2, id(base + 5)));
    return { failedTask, task2 };
  }

  // Hold the first successful transaction open after the RPC returns. The
  // second call must block on the same order/request serialization lock.
  async function heldRace(firstActor, firstCall, secondActor, secondCall) {
    await begin(a, firstActor);
    const first = await firstCall(a).then(value => ({ value }), error => ({ error }));
    if (first.error) {
      await a.query('rollback');
      throw first.error;
    }
    await begin(b, secondActor);
    const pid = (await b.query('select pg_backend_pid() as pid')).rows[0].pid;
    const pending = secondCall(b).then(value => ({ value }), error => ({ error }));
    let blocked = false;
    for (let i = 0; i < 120; i += 1) {
      if ((await setup('select cardinality(pg_blocking_pids($1)) > 0 as blocked', [pid])).rows[0].blocked) {
        blocked = true;
        break;
      }
      await delay(10);
    }
    assert.equal(blocked, true, 'second P07.2 decision must wait on the order lock');
    await a.query('commit');
    const second = await pending;
    await b.query(second.error ? 'rollback' : 'commit');
    return { first, second };
  }

  try {
    await Promise.all(connected.map(client => client.connect()));
    await Promise.all(connected.map(client => client.query("set statement_timeout='8s'; set lock_timeout='5s'")));
    await setup(
      'insert into auth.users(id,email) select x, x::text || $2 from unnest($1::uuid[]) x',
      [users, '@p0726.invalid'],
    );
    await setup(
      "update public.profiles set role=case when id=any($1::uuid[]) then 'manager'::public.user_role when id=any($2::uuid[]) then 'shipper'::public.user_role else 'customer'::public.user_role end where id=any($3::uuid[])",
      [[managerA, managerB], [shipperA, shipperB], users],
    );
    await setup("insert into public.categories(id,code,name) values($1,'P0726','P07.2 concurrency')", [category]);
    await setup("insert into public.products(id,category_id,name) values($1,$2,'P07.2 concurrency product')", [product, category]);
    await setup(
      "insert into public.product_variants(id,product_id,sku,label,price_vnd,on_hand,reserved) values($1,$2,'P0726-01','P07.2 concurrency variant',520000,3,3)",
      [variant, product],
    );
    for (let i = 0; i < orders.length; i += 1) {
      await setup(
        "insert into public.orders(id,customer_id,request_id,status,recipient_name,recipient_phone,address_detail,latitude,longitude,subtotal_vnd,delivery_attempt_count) values($1,$2,$1,'preparing','P07.2 concurrency recipient','0907260001','P07.2 Hanoi address',21.0285,105.8542,520000,0)",
        [orders[i], customer],
      );
      await setup(
        "insert into public.order_items(id,order_id,product_id,variant_id,product_name,variant_label,unit_price_vnd,quantity) values($1,$2,$3,$4,'P07.2 concurrency product','P07.2 concurrency variant',520000,1)",
        [items[i], orders[i], product, variant],
      );
      await setup(
        "insert into public.inventory_movements(variant_id,order_id,event_id,kind,reserved_delta,actor_id,reason) values($1,$2,$3,'reserve',1,$4,'p0726 reserve')",
        [variant, orders[i], reserveEvents[i], managerA],
      );
    }

    // Two managers decide the same failed order concurrently. Exactly one
    // creates task 2; the loser observes the committed CAS conflict.
    const failedRaceTask = await prepareFailed(orders[0], 400);
    const cas = await heldRace(
      managerA,
      c => decide(c, orders[0], id(410), 'retry', failedRaceTask, null),
      managerB,
      c => decide(c, orders[0], id(411), 'return_to_store', failedRaceTask, null),
    );
    assert.ifError(cas.first.error);
    assert.equal(cas.second.error?.code, 'PT409');
    assert.ok(['TASK_CONFLICT', 'STALE_ASSIGNMENT', 'STATE_CONFLICT', 'IDEMPOTENCY_CONFLICT'].includes(cas.second.error?.message));
    const raceTaskCount = (await setup(
      'select count(*)::int count from public.delivery_tasks where order_id=$1', [orders[0]],
    )).rows[0].count;
    assert.equal(raceTaskCount, 2, 'CAS loser must not create another retry task');

    await begin(a, managerA);
    const replayed = await decide(a, orders[0], id(410), 'retry', failedRaceTask, null);
    await a.query('commit');
    assert.deepEqual(replayed, cas.first.value, 'same manager/key must replay the exact result');

    // Generic direct UPDATE cannot cancel accepted task 1. P07.2 trusted
    // decision permission is the only route for a pre-start accepted task 2.
    const acceptedCancel = await createRetryAccepted(orders[1], 500);
    const directCancel = await setup(
      "update public.delivery_tasks set status='cancelled' where id=$1", [acceptedCancel.task2],
    ).then(() => ({ ok: true }), error => ({ error }));
    assert.equal(directCancel.error?.code, 'PT409');
    assert.equal(directCancel.error?.message, 'CUSTODY_UNRESOLVED');

    // Cancel-first ordering: manager holds the order lock, shipper start waits
    // and is rejected. Custody/history are retained by the decision.
    const cancelFirst = await heldRace(
      managerA,
      c => decide(c, orders[1], id(520), 'return_to_store', acceptedCancel.failedTask, acceptedCancel.task2),
      shipperA,
      c => start(c, acceptedCancel.task2, id(521)),
    );
    assert.ifError(cancelFirst.first.error);
    assert.equal(cancelFirst.second.error?.code, 'PT409');
    assert.ok(['STATE_CONFLICT', 'CUSTODY_UNRESOLVED'].includes(cancelFirst.second.error?.message));
    const cancelledState = (await setup(
      "select t.status, t.accepted_at, t.started_at, o.status order_status, o.delivery_attempt_count, (select count(*) from private.outbound_custody_acceptances c where c.task_id=t.id)::int custody from public.delivery_tasks t join public.orders o on o.id=t.order_id where t.id=$1",
      [acceptedCancel.task2],
    )).rows[0];
    assert.equal(cancelledState.status, 'cancelled');
    assert.ok(cancelledState.accepted_at);
    assert.equal(cancelledState.started_at, null);
    assert.equal(cancelledState.order_status, 'awaiting_store_return');
    assert.equal(Number(cancelledState.delivery_attempt_count), 1);
    assert.equal(Number(cancelledState.custody), 1);

    // Start-first ordering on an independent accepted task: start wins and a
    // manager switch after start is rejected; the order count is two.
    const acceptedStart = await createRetryAccepted(orders[2], 600);
    const startFirst = await heldRace(
      shipperA,
      c => start(c, acceptedStart.task2, id(620)),
      managerA,
      c => decide(c, orders[2], id(621), 'return_to_store', acceptedStart.failedTask, acceptedStart.task2),
    );
    assert.ifError(startFirst.first.error);
    assert.equal(startFirst.second.error?.code, 'PT409');
    assert.ok(['STATE_CONFLICT', 'CUSTODY_UNRESOLVED', 'ATTEMPT_LIMIT'].includes(startFirst.second.error?.message));
    const startedState = (await setup(
      'select t.status,o.status order_status,o.delivery_attempt_count from public.delivery_tasks t join public.orders o on o.id=t.order_id where t.id=$1',
      [acceptedStart.task2],
    )).rows[0];
    assert.equal(startedState.status, 'in_transit');
    assert.equal(startedState.order_status, 'delivering');
    assert.equal(Number(startedState.delivery_attempt_count), 2);

    console.log('outbound_retry_production_concurrency: PASS (manager CAS, accepted-cancel/start lock races, trusted cancel permit, custody/history retention)');
  } finally {
    await Promise.allSettled(connected.map(client => client.query('rollback')));
    await Promise.allSettled(connected.map(client => client.end()));
    await setup('begin');
    try {
      // Private append-only ledgers are cleaned only after their USER triggers
      // are disabled. This deliberately does not disable ALL triggers.
      const privateRows = (await setup(`
        select c.relname,
               exists(select 1 from information_schema.columns x where x.table_schema='private' and x.table_name=c.relname and x.column_name='order_id') has_order,
               exists(select 1 from information_schema.columns x where x.table_schema='private' and x.table_name=c.relname and x.column_name='task_id') has_task
        from pg_class c join pg_namespace n on n.oid=c.relnamespace
        where n.nspname='private' and c.relkind='r'
          and (c.relname like '%retry%' or c.relname like '%decision%' or c.relname in ('delivery_assignment_requests','delivery_assignment_audits','outbound_command_requests','outbound_dispatches','outbound_custody_acceptances','outbound_failure_requests','outbound_failure_results'))
        order by case when c.relname='outbound_dispatches' then 2 else 1 end
      `)).rows;
      for (const row of privateRows) {
        await setup(`alter table private."${row.relname.replaceAll('"', '""')}" disable trigger user`);
        if (row.has_order) await setup(`delete from private."${row.relname.replaceAll('"', '""')}" where order_id=any($1::uuid[])`, [orders]);
        else if (row.has_task) {
          const taskRows = (await setup('select id from public.delivery_tasks where order_id=any($1::uuid[])', [orders])).rows.map(x => x.id);
          if (taskRows.length) await setup(`delete from private."${row.relname.replaceAll('"', '""')}" where task_id=any($1::uuid[])`, [taskRows]);
        }
        await setup(`alter table private."${row.relname.replaceAll('"', '""')}" enable trigger user`);
      }
      await setup('delete from public.notifications where subject_id=any($1::uuid[])', [orders]);
      const taskRows = (await setup('select id from public.delivery_tasks where order_id=any($1::uuid[])', [orders])).rows.map(x => x.id);
      if (taskRows.length) {
        await setup('delete from public.notifications where subject_id=any($1::uuid[])', [taskRows]);
        await setup('delete from public.delivery_attempts where task_id=any($1::uuid[])', [taskRows]);
        await setup('delete from public.business_events where subject_id=any($1::uuid[]) or task_id=any($1::uuid[])', [taskRows]);
      }
      await setup('delete from public.business_events where subject_id=any($1::uuid[])', [orders]);
      await setup('delete from public.delivery_tasks where order_id=any($1::uuid[])', [orders]);
      await setup('delete from public.inventory_movements where order_id=any($1::uuid[])', [orders]);
      await setup('delete from public.order_items where order_id=any($1::uuid[])', [orders]);
      await setup('delete from public.cod_collections where order_id=any($1::uuid[])', [orders]);
      await setup('delete from public.orders where id=any($1::uuid[])', [orders]);
      await setup('delete from public.product_variants where id=$1', [variant]);
      await setup('delete from public.products where id=$1', [product]);
      await setup('delete from public.categories where id=$1', [category]);
      await setup('delete from auth.users where id=any($1::uuid[])', [users]);
      const leaked = (await setup(`
        select (select count(*) from public.orders where id=any($1::uuid[])) orders,
               (select count(*) from public.delivery_tasks where order_id=any($1::uuid[])) tasks,
               (select count(*) from public.delivery_attempts where order_id=any($1::uuid[])) attempts,
               (select count(*) from public.inventory_movements where order_id=any($1::uuid[])) movements,
               (select count(*) from public.notifications where subject_id=any($1::uuid[])) notifications
      `, [orders])).rows[0];
      for (const [key, value] of Object.entries(leaked)) assert.equal(Number(value), 0, `P07.2 cleanup leaked ${key}`);
      await setup('commit');
    } catch (error) {
      await setup('rollback');
      throw error;
    }
  }
}
