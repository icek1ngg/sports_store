// P07.4 production report concurrency tests.  The runner owns an isolated
// local PostgreSQL database; this module never contacts Supabase/cloud.
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';

export async function testDeliveryReportingProductionConcurrency(Client, options, admin) {
  const id = n => `07460000-0000-0000-0000-${String(n).padStart(12, '0')}`;
  const customer = id(1);
  const manager = id(2);
  const shipperA = id(3);
  const shipperB = id(4);
  const category = id(100);
  const product = id(101);
  const variant = id(111);
  const orders = Array.from({ length: 6 }, (_, i) => id(10 + i));
  const itemIds = Array.from({ length: 6 }, (_, i) => id(200 + i));
  const reserveEvents = Array.from({ length: 6 }, (_, i) => id(300 + i));
  const tasks = [];
  const requestKeys = {
    handover: id(401),
    handoverConflict: id(402),
    incident: id(403),
    sameActorA: id(404),
    sameActorB: id(405),
    incidentFirst: id(406),
    completionFirst: id(407),
  };
  const connected = [];
  const setup = async (sql, params = []) => admin.query(sql, params);

  async function withUser(actor, operation) {
    const client = new Client(options);
    await client.connect();
    try {
      await client.query('begin');
      await client.query('set local role authenticated');
      await client.query("select set_config('request.jwt.claim.sub',$1,true)", [actor]);
      await client.query("select set_config('request.jwt.claims',$1,true)", [
        JSON.stringify({ sub: actor, role: 'authenticated', aud: 'authenticated' }),
      ]);
      const value = await operation(client);
      await client.query('commit');
      return value;
    } catch (error) {
      await client.query('rollback').catch(() => {});
      throw error;
    } finally {
      await client.end();
    }
  }

  async function callRpc(actor, sql, params) {
    return withUser(actor, async client => (await client.query(sql, params)).rows[0].result);
  }

  const assign = (actor, order, shipper, request) => callRpc(
    actor,
    'select public.assign_delivery_task($1::uuid,$2::uuid,$3::uuid) result',
    [order, shipper, request],
  );
  const accept = (actor, task, request) => callRpc(
    actor,
    'select public.accept_delivery_task($1::uuid,$2::uuid) result',
    [task, request],
  );
  const start = (actor, task, request) => callRpc(
    actor,
    'select public.start_delivery_task($1::uuid,$2::uuid) result',
    [task, request],
  );
  const fail = (actor, task, request) => callRpc(
    actor,
    'select public.fail_delivery_task($1::uuid,$2::uuid,$3::text,$4::text) result',
    [task, request, 'bad_address', null],
  );
  const returnToStore = (order, task, request, retryTask = null) => callRpc(
    manager,
    'select public.decide_outbound_retry($1::uuid,$2::uuid,$3::text,$4::uuid,$5::uuid) result',
    [order, request, 'return_to_store', task, retryTask],
  );
  const incident = (actor, task, request, kind = 'damaged', reason = 'P07.4 concurrency incident') => callRpc(
    actor,
    'select public.report_delivery_incident($1::uuid,$2::uuid,$3::public.delivery_incident_kind,$4::text) result',
    [task, request, kind, reason],
  );
  const handover = (actor, task, request, itemId, quantity = 1) => callRpc(
    actor,
    'select public.report_store_handover($1::uuid,$2::uuid,$3::jsonb) result',
    [task, request, JSON.stringify([{ order_item_id: itemId, quantity }])],
  );
  const complete = (actor, task, request) => callRpc(
    actor,
    'select public.complete_outbound_delivery($1::uuid,$2::uuid,true,130000) result',
    [task, request],
  );

  async function begin(client, actor) {
    await client.query('begin');
    await client.query('set local role authenticated');
    await client.query("select set_config('request.jwt.claim.sub',$1,true)", [actor]);
    await client.query("select set_config('request.jwt.claims',$1,true)", [
      JSON.stringify({ sub: actor, role: 'authenticated', aud: 'authenticated' }),
    ]);
  }

  async function race(first, firstActor, second, secondActor, requireBlocked = true, commitFirst = true) {
    const a = new Client(options);
    const b = new Client(options);
    await Promise.all([a.connect(), b.connect()]);
    connected.push(a, b);
    await Promise.all([begin(a, firstActor), begin(b, secondActor)]);
    try {
      const firstResult = await first(a);
      const pid = (await b.query('select pg_backend_pid() pid')).rows[0].pid;
      const pending = second(b).then(value => ({ value }), error => ({ error }));
      let blocked = false;
      for (let i = 0; i < 120; i += 1) {
        if ((await setup('select cardinality(pg_blocking_pids($1)) > 0 blocked', [pid])).rows[0].blocked) {
          blocked = true;
          break;
        }
        await delay(10);
      }
      if (requireBlocked) assert.equal(blocked, true, 'P07.4 contender must wait on a business lock');
      await a.query(commitFirst ? 'commit' : 'rollback');
      const secondResult = await pending;
      await b.query(secondResult.error ? 'rollback' : 'commit');
      return { firstResult, secondResult };
    } catch (error) {
      await Promise.allSettled([a.query('rollback'), b.query('rollback')]);
      throw error;
    }
  }

  try {
    await setup(
      "insert into auth.users (id,email) values ($1,'p0746-customer@example.invalid'),($2,'p0746-manager@example.invalid'),($3,'p0746-shipper-a@example.invalid'),($4,'p0746-shipper-b@example.invalid')",
      [customer, manager, shipperA, shipperB],
    );
    await setup(
      "update public.profiles set role = case when id=$1 then 'manager'::public.user_role when id in ($2,$3) then 'shipper'::public.user_role else 'customer'::public.user_role end where id in ($1,$2,$3,$4)",
      [manager, shipperA, shipperB, customer],
    );
    await setup("insert into public.categories(id,code,name) values ($1,'P0746','P07.4 concurrency')", [category]);
    await setup("insert into public.products(id,category_id,name) values ($1,$2,'P07.4 concurrency product')", [product, category]);
    await setup(
      "insert into public.product_variants(id,product_id,sku,label,price_vnd,on_hand,reserved) values ($1,$2,'P0746-01','P07.4 concurrency variant',100000,30,6)",
      [variant, product],
    );
    for (let i = 0; i < orders.length; i += 1) {
      const order = orders[i];
      await setup(
        "insert into public.orders(id,customer_id,request_id,status,recipient_name,recipient_phone,address_detail,latitude,longitude,subtotal_vnd,delivery_attempt_count) values($1,$2,$1,'preparing','P07.4 concurrency recipient','0907460001','P07.4 Hanoi address',21.0285,105.8542,100000,0)",
        [order, customer],
      );
      await setup(
        "insert into public.order_items(id,order_id,product_id,variant_id,product_name,variant_label,unit_price_vnd,quantity) values($1,$2,$3,$4,'P07.4 concurrency product','P07.4 concurrency variant',100000,1)",
        [itemIds[i], order, product, variant],
      );
      await setup(
        "insert into public.inventory_movements(variant_id,order_id,event_id,kind,reserved_delta,actor_id,reason) values($1,$2,$3,'reserve',1,$4,'P07.4 concurrency reservation')",
        [variant, order, reserveEvents[i], manager],
      );
      await setup(
        "insert into public.cod_collections(order_id,shipper_id,status,expected_amount_vnd) values($1,$2,'uncollected',130000)",
        [order, i === 5 ? shipperB : shipperA],
      );
    }

    // Real assignment/accept/start/fail/manager-return chain for task 0,
    // which is the handover duplicate/key-conflict fixture.
    const assigned0 = await assign(manager, orders[0], shipperA, id(500));
    const task0 = assigned0.task_id;
    tasks.push(task0);
    await accept(shipperA, task0, id(501));
    await start(shipperA, task0, id(502));
    await fail(shipperA, task0, id(503));
    await returnToStore(orders[0], task0, id(504));

    // Accepted task for incident replay; two in-transit tasks for the
    // incident/completion races; two accepted tasks for same-client-key actor
    // isolation.
    for (const [i, shipper] of [[1, shipperA], [2, shipperA], [3, shipperA], [4, shipperA], [5, shipperB]]) {
      const assigned = await assign(manager, orders[i], shipper, id(510 + i));
      const task = assigned.task_id;
      tasks.push(task);
      await accept(shipper, task, id(520 + i));
      if (i === 2 || i === 3) await start(shipper, task, id(530 + i));
    }

    const duplicateHandover = await race(
      c => c.query(
        'select public.report_store_handover($1::uuid,$2::uuid,$3::jsonb) result',
        [task0, requestKeys.handover, JSON.stringify([{ order_item_id: itemIds[0], quantity: 1 }])],
      ).then(r => r.rows[0].result),
      shipperA,
      c => c.query(
        'select public.report_store_handover($1::uuid,$2::uuid,$3::jsonb) result',
        [task0, requestKeys.handover, JSON.stringify([{ order_item_id: itemIds[0], quantity: 1 }])],
      ).then(r => r.rows[0].result),
      shipperA,
    );
    assert.ifError(duplicateHandover.secondResult.error);
    assert.deepEqual(duplicateHandover.firstResult, duplicateHandover.secondResult.value,
      'same actor/request/payload handover must replay exactly');
    let handoverConflictError;
    try {
      await withUser(shipperA, client => client.query(
        'select public.report_store_handover($1::uuid,$2::uuid,$3::jsonb) result',
        [task0, requestKeys.handoverConflict, JSON.stringify([{ order_item_id: itemIds[0], quantity: 1 }])],
      ));
    } catch (error) {
      handoverConflictError = error;
    }
    assert.equal(handoverConflictError?.code, 'PT409', 'new handover key must conflict');
    assert.equal(handoverConflictError?.message, 'STATE_CONFLICT');

    const duplicateIncident = await race(
      c => c.query(
        'select public.report_delivery_incident($1::uuid,$2::uuid,$3::public.delivery_incident_kind,$4::text) result',
        [tasks[1], requestKeys.incident, 'damaged', 'P07.4 duplicate incident'],
      ).then(r => r.rows[0].result),
      shipperA,
      c => c.query(
        'select public.report_delivery_incident($1::uuid,$2::uuid,$3::public.delivery_incident_kind,$4::text) result',
        [tasks[1], requestKeys.incident, 'damaged', 'P07.4 duplicate incident'],
      ).then(r => r.rows[0].result),
      shipperA,
    );
    assert.ifError(duplicateIncident.secondResult.error);
    assert.deepEqual(duplicateIncident.firstResult, duplicateIncident.secondResult.value,
      'same actor/request/payload incident must replay exactly');

    // A client UUID is actor-scoped: two current holders can report separate
    // tasks with the same key, and each receives a distinct event.
    const sameKeyA = await withUser(shipperA, client => client.query(
      'select public.report_delivery_incident($1::uuid,$2::uuid,$3::public.delivery_incident_kind,$4::text) result',
      [tasks[4], requestKeys.sameActorA, 'damaged', 'same UUID actor A'],
    ).then(r => r.rows[0].result));
    const sameKeyB = await withUser(shipperB, client => client.query(
      'select public.report_delivery_incident($1::uuid,$2::uuid,$3::public.delivery_incident_kind,$4::text) result',
      [tasks[5], requestKeys.sameActorA, 'damaged', 'same UUID actor B'],
    ).then(r => r.rows[0].result));
    assert.notEqual(sameKeyA.event_id, sameKeyB.event_id,
      'same client UUID by two actors must create two distinct report events');

    // Existing completion proof rejects a historical damage incident.  The
    // report and completion paths still serialize on the order in both
    // directions: incident first blocks completion; completion first leaves a
    // delivered task that cannot accept a new incident.
    const incidentFirst = await race(
      c => c.query(
        'select public.report_delivery_incident($1::uuid,$2::uuid,$3::public.delivery_incident_kind,$4::text) result',
        [tasks[2], requestKeys.incidentFirst, 'damaged', 'incident wins'],
      ).then(r => r.rows[0].result),
      shipperA,
      c => c.query(
        'select public.complete_outbound_delivery($1::uuid,$2::uuid,true,130000) result',
        [tasks[2], id(550)],
      ).then(r => r.rows[0].result),
      shipperA,
    );
    assert.equal(incidentFirst.secondResult.error?.code, 'PT409');
    assert.equal(incidentFirst.secondResult.error?.message, 'CUSTODY_UNRESOLVED');

    const completionFirst = await race(
      c => c.query(
        'select public.complete_outbound_delivery($1::uuid,$2::uuid,true,130000) result',
        [tasks[3], requestKeys.completionFirst],
      ).then(r => r.rows[0].result),
      shipperA,
      c => c.query(
        'select public.report_delivery_incident($1::uuid,$2::uuid,$3::public.delivery_incident_kind,$4::text) result',
        [tasks[3], id(551), 'damaged', 'completion wins'],
      ).then(r => r.rows[0].result),
      shipperA,
    );
    assert.equal(completionFirst.firstResult.task_status, 'delivered');
    assert.equal(completionFirst.secondResult.error?.code, 'PT409');
    assert.equal(completionFirst.secondResult.error?.message, 'STATE_CONFLICT');

    const state = (await setup(`
      select
        (select status='awaiting_store_return'::public.order_status from public.orders where id=$1) as handover_order,
        (select status='failed'::public.delivery_task_status from public.delivery_tasks where id=$2) as handover_task,
        (select count(*)=0 from public.delivery_attempts where task_id=$3) as incident_first_no_result,
        (select status='delivered'::public.order_status from public.orders where id=$4) as completion_order,
        (select status='collected'::public.cod_status and collected_amount_vnd=130000 from public.cod_collections where order_id=$5) as completion_cod,
        (select count(*)=1 from public.delivery_attempts where task_id=$6 and result='success'::public.delivery_attempt_result) as completion_result
    `, [orders[0], task0, tasks[2], orders[3], orders[3], tasks[3]])).rows[0];
    for (const [label, value] of Object.entries(state)) assert.equal(value, true, `serialized report outcome: ${label}`);

    console.log('delivery_reporting_production_concurrency: PASS (handover replay/key race, incident replay, actor-scoped UUID, incident/completion both orderings)');
  } finally {
    await Promise.allSettled(connected.map(client => client.query('rollback')));
    await Promise.allSettled(connected.map(client => client.end()));
    await setup('begin');
    try {
      const eventRows = await setup(`
        select id from public.business_events
        where task_id=any($1::uuid[])
           or (subject_type='order' and subject_id=any($2::uuid[]))
      `, [tasks, orders]);
      const eventIds = eventRows.rows.map(row => row.id);

      // Remove private request/result rows first.  Only USER triggers are
      // disabled; FK ordering and the transaction remain real.  The dynamic
      // catalog query keeps this test independent of the private ledger's
      // internal table split.
      const privateTables = await setup(`
        select c.relname,
          array_agg(a.attname order by a.attnum) filter (where a.attname is not null) as columns
        from pg_class c
        join pg_namespace n on n.oid=c.relnamespace
        left join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped
        where n.nspname='private' and c.relkind='r'
        group by c.relname
        having bool_or(a.attname in ('task_id','order_id','event_id'))
        order by case when c.relname='outbound_dispatches' then 2 else 1 end
      `);
      for (const row of privateTables.rows) {
        const columns = Array.isArray(row.columns) ? row.columns : String(row.columns).replace(/[{}]/g,'').split(',');
        const predicates = [];
        const params = [];
        if (columns.includes('task_id')) { params.push(tasks); predicates.push(`task_id=any($${params.length}::uuid[])`); }
        if (columns.includes('order_id')) { params.push(orders); predicates.push(`order_id=any($${params.length}::uuid[])`); }
        if (columns.includes('event_id') && eventIds.length > 0) { params.push(eventIds); predicates.push(`event_id=any($${params.length}::uuid[])`); }
        if (predicates.length === 0) continue;
        const table = `private."${row.relname.replaceAll('"', '""')}"`;
        await setup(`alter table ${table} disable trigger user`);
        await setup(`delete from ${table} where ${predicates.join(' or ')}`, params);
        await setup(`alter table ${table} enable trigger user`);
      }
      if (eventIds.length > 0) {
        await setup('delete from public.notifications where event_id=any($1::uuid[])', [eventIds]);
      }
      await setup(`delete from public.business_events where task_id=any($1::uuid[])
        or (subject_type='order' and subject_id=any($2::uuid[]))`, [tasks, orders]);
      await setup('delete from public.delivery_attempts where order_id=any($1::uuid[])', [orders]);
      await setup('delete from public.cod_collections where order_id=any($1::uuid[])', [orders]);
      await setup('delete from public.inventory_movements where order_id=any($1::uuid[])', [orders]);
      await setup('delete from public.delivery_tasks where order_id=any($1::uuid[])', [orders]);
      await setup('delete from public.order_items where order_id=any($1::uuid[])', [orders]);
      await setup('delete from public.orders where id=any($1::uuid[])', [orders]);
      await setup('delete from public.product_variants where id=$1', [variant]);
      await setup('delete from public.products where id=$1', [product]);
      await setup('delete from public.categories where id=$1', [category]);
      await setup('delete from auth.users where id=any($1::uuid[])', [[customer, manager, shipperA, shipperB]]);
      const leaked = (await setup(`
        select
          (select count(*) from public.orders where id=any($1::uuid[])) orders,
          (select count(*) from public.delivery_tasks where id=any($2::uuid[])) tasks,
          (select count(*) from public.business_events where task_id=any($2::uuid[])) events,
          (select count(*) from public.notifications where event_id=any($3::uuid[])) notifications
      `, [orders, tasks, eventIds])).rows[0];
      for (const [label, value] of Object.entries(leaked)) assert.equal(Number(value), 0, `P07.4 cleanup leaked ${label}`);
      await setup('commit');
    } catch (cleanupError) {
      await setup('rollback');
      throw cleanupError;
    }
  }
}
