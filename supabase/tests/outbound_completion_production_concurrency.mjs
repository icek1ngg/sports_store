// P05.1 production concurrency test. The losing outcome is a test-only
// competitor that models a future failure RPC; it is not a production API.
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';

export async function testOutboundCompletionProductionConcurrency(Client, options, admin) {
  const id = n => `05160000-0000-0000-0000-${String(n).padStart(12, '0')}`;
  const customer = id(1), manager = id(2), shipper = id(3);
  const orders = [id(10), id(11), id(12), id(13)];
  const tasks = [id(20), id(21), id(22), id(23)];
  const dispatchEvents = [id(30), id(31), id(32), id(33)];
  const reserveEvents = [id(40), id(41), id(42), id(43)];
  const requests = [id(50), id(51), id(52), id(53)];
  const connected = [];
  const setup = async (sql, params = []) => admin.query(sql, params);

  await setup("insert into auth.users (id,email) values ($1,'p0516-customer@example.invalid'),($2,'p0516-manager@example.invalid'),($3,'p0516-shipper@example.invalid')", [customer, manager, shipper]);
  await setup("update public.profiles set role = case when id=$1 then 'manager'::public.user_role when id=$2 then 'shipper'::public.user_role else 'customer'::public.user_role end where id in ($3,$1,$2)", [manager, shipper, customer]);
  await setup("insert into public.categories(id,code,name) values ($1,'P0516','P05.1 concurrency')", [id(100)]);
  await setup("insert into public.products(id,category_id,name) values ($1,$2,'P05.1 concurrency product')", [id(101), id(100)]);
  await setup("insert into public.product_variants(id,product_id,sku,label,price_vnd,on_hand,reserved) values ($1,$2,'P0516-01','P05.1 concurrency variant',520000,0,0)", [id(111), id(101)]);

  for (let i = 0; i < orders.length; i++) {
    const o = orders[i], t = tasks[i], d = dispatchEvents[i], r = reserveEvents[i], item = id(200 + i);
    await setup("insert into public.orders(id,customer_id,request_id,status,recipient_name,recipient_phone,address_detail,latitude,longitude,subtotal_vnd,delivery_attempt_count) values($1,$2,$1,'delivering','P05.1 concurrency recipient','0905160001','P05.1 Hanoi address',21.0285,105.8542,520000,1)", [o, customer]);
    await setup("insert into public.order_items(id,order_id,product_id,variant_id,product_name,variant_label,unit_price_vnd,quantity) values($1,$2,$3,$4,'P05.1 concurrency product','P05.1 concurrency variant',520000,1)", [item, o, id(101), id(111)]);
    await setup("insert into public.inventory_movements(variant_id,order_id,event_id,kind,reserved_delta,actor_id,reason) values($1,$2,$3,'reserve',1,$4,'p0516 reserve')", [id(111), o, r, manager]);
    await setup("insert into public.inventory_movements(variant_id,order_id,event_id,kind,on_hand_delta,reserved_delta,actor_id,reason) values($1,$2,$3,'dispatch',-1,-1,$4,'outbound_dispatch')", [id(111), o, d, shipper]);
    await setup("insert into public.delivery_tasks(id,order_id,kind,assigned_shipper_id,assigned_by,status,attempt_number,destination_name,destination_phone,destination_address,destination_latitude,destination_longitude,amount_to_collect_vnd,assigned_at,accepted_at,started_at) values($1,$2,'outbound',$3,$4,'in_transit',1,'P05.1 concurrency recipient','0905160001','P05.1 Hanoi address',21.0285,105.8542,550000,clock_timestamp()-interval '90 seconds',clock_timestamp()-interval '60 seconds',clock_timestamp()-interval '30 seconds')", [t, o, shipper, manager]);
    await setup("insert into public.business_events(id,actor_id,subject_type,subject_id,from_state,to_state,reason,task_id,request_id) values($1,$2,'delivery_task',$3,'accepted','in_transit','fixture dispatch',$3,$1)", [d, shipper, t]);
    await setup("insert into public.cod_collections(order_id,shipper_id,status,expected_amount_vnd) values($1,$2,'uncollected',550000)", [o, shipper]);
    await setup("insert into private.outbound_dispatches(order_id,initial_task_id,holder_id,event_id,items_snapshot,dispatched_at) values($1,$2,$3,$4,private.outbound_items_snapshot($1),clock_timestamp()-interval '20 seconds')", [o, t, shipper, d]);
    await setup("insert into private.outbound_custody_acceptances(task_id,order_id,holder_id,dispatch_event_id,accepted_at,attempt_number) values($1,$2,$3,$4,clock_timestamp()-interval '60 seconds',1)", [t, o, shipper, d]);
  }

  for (const client of [new Client(options), new Client(options)]) {
    await client.connect();
    await client.query("set statement_timeout='8s'; set lock_timeout='5s'");
    connected.push(client);
  }
  const [a, b] = connected;
  const begin = async client => {
    await client.query('begin');
    await client.query('set local role authenticated');
    await client.query("select set_config('request.jwt.claim.sub',$1,true)", [shipper]);
    await client.query("select set_config('request.jwt.claims',$1,true)", [JSON.stringify({ sub: shipper, role: 'authenticated', aud: 'authenticated' })]);
  };
  const complete = (client, task, request) => client.query(
    'select public.complete_outbound_delivery($1::uuid,$2::uuid,true,550000) result', [task, request]
  ).then(r => r.rows[0].result);
  const race = async (first, second, requireBlocked = true) => {
    await begin(a); await begin(b);
    const firstResult = await first(a);
    const pid = (await b.query('select pg_backend_pid() pid')).rows[0].pid;
    const pending = second(b).then(value => ({ value }), error => ({ error }));
    let blocked = false;
    for (let i = 0; i < 100; i++) {
      if ((await admin.query('select cardinality(pg_blocking_pids($1)) > 0 blocked', [pid])).rows[0].blocked) { blocked = true; break; }
      await delay(10);
    }
    if (requireBlocked) assert.equal(blocked, true, 'completion contender must wait on the order/request lock');
    await a.query('commit');
    const secondResult = await pending;
    await b.query(secondResult.error ? 'rollback' : 'commit');
    return { firstResult, secondResult };
  };
  try {
    const replay = await race(c => complete(c, tasks[0], requests[0]), c => complete(c, tasks[0], requests[0]));
    assert.deepEqual(replay.firstResult, replay.secondResult.value);
    const distinct = await race(c => complete(c, tasks[1], requests[1]), c => complete(c, tasks[1], id(53)));
    assert.equal(distinct.secondResult.error?.code, 'PT409');
    assert.equal(distinct.secondResult.error?.message, 'STATE_CONFLICT');

    for (const client of [a, b]) {
      await client.query(`create or replace function pg_temp.claim_failed_result_for_test(p_task uuid) returns void language plpgsql security definer set search_path='' as $$
        declare t public.delivery_tasks%rowtype; oid uuid;
        begin
          select order_id into oid from public.delivery_tasks where id=p_task;
          perform pg_advisory_xact_lock(hashtextextended('sports_store.complete_outbound_delivery:order:'||oid::text,0));
          select * into t from public.delivery_tasks where id=p_task for update;
          if t.status <> 'in_transit' then raise exception using errcode='P0001',message='STATE_CONFLICT'; end if;
          insert into public.delivery_attempts(task_id,order_id,attempt_number,task_kind,result,reason,shipper_id)
            values(t.id,t.order_id,t.attempt_number,'outbound','failed','test-only competitor',t.assigned_shipper_id);
          update public.delivery_tasks set status='failed',failure_reason='test-only competitor' where id=p_task;
        end $$`);
    }
    const conflict = await race(c => complete(c, tasks[2], requests[2]), c => c.query('select pg_temp.claim_failed_result_for_test($1::uuid)', [tasks[2]]), true);
    assert.equal(conflict.secondResult.error?.code, 'P0001');
    assert.equal(conflict.secondResult.error?.message, 'STATE_CONFLICT');

    // Reverse the ordering on an independent task: a test-only failure
    // contender obtains the order lock and commits first, then the production
    // completion is serialized behind it and must lose without any success
    // writes or COD collection.
    const failureFirst = await race(
      c => c.query('select pg_temp.claim_failed_result_for_test($1::uuid)', [tasks[3]]),
      c => complete(c, tasks[3], requests[3]),
      true,
    );
    assert.equal(failureFirst.secondResult.error?.code, 'PT409');
    assert.equal(failureFirst.secondResult.error?.message, 'STATE_CONFLICT');
    const failureFirstState = (await admin.query(`
      select
        (select status = 'failed'::public.delivery_task_status
           from public.delivery_tasks where id = $1) as task_failed,
        (select status = 'delivering'::public.order_status
           from public.orders where id = $2) as order_untouched,
        (select status = 'uncollected'::public.cod_status
             and collected_amount_vnd = 0 and collected_by is null
           from public.cod_collections where order_id = $2) as cod_untouched,
        (select count(*) = 1 and bool_and(result = 'failed'::public.delivery_attempt_result)
           from public.delivery_attempts where task_id = $1) as only_failure_attempt,
        (select count(*) = 0 from public.notifications where subject_id = $1) as no_notifications,
        (select count(*) = 0 from private.outbound_completion_results where task_id = $1) as no_result_ledger,
        (select count(*) = 0 from private.outbound_completion_requests where task_id = $1) as no_request_ledger
    `, [tasks[3], orders[3]])).rows[0];
    for (const [label, value] of Object.entries(failureFirstState)) {
      assert.equal(value, true, `failure-first completion rollback: ${label}`);
    }
    console.log('outbound_completion_production_concurrency: PASS (identical replay, distinct request conflict, completion-first and failure-first serialization)');
  } finally {
    await Promise.allSettled(connected.map(client => client.query('rollback')));
    await Promise.allSettled(connected.map(client => client.end()));
    await setup('delete from public.notifications where subject_id = any($1::uuid[])', [tasks]);
    await setup('alter table private.outbound_completion_requests disable trigger outbound_completion_requests_append_only');
    await setup('alter table private.outbound_completion_results disable trigger outbound_completion_results_append_only');
    await setup('delete from private.outbound_completion_requests where task_id = any($1::uuid[])', [tasks]);
    await setup('delete from private.outbound_completion_results where task_id = any($1::uuid[])', [tasks]);
    await setup('alter table private.outbound_completion_requests enable trigger outbound_completion_requests_append_only');
    await setup('alter table private.outbound_completion_results enable trigger outbound_completion_results_append_only');
    await setup('delete from public.delivery_attempts where task_id = any($1::uuid[])', [tasks]);
    await setup('delete from public.cod_collections where order_id = any($1::uuid[])', [orders]);
    await setup('alter table private.outbound_custody_acceptances disable trigger outbound_custody_append_only');
    await setup('alter table private.outbound_dispatches disable trigger outbound_dispatches_append_only');
    await setup('delete from private.outbound_custody_acceptances where task_id = any($1::uuid[])', [tasks]);
    await setup('delete from private.outbound_dispatches where order_id = any($1::uuid[])', [orders]);
    await setup('alter table private.outbound_custody_acceptances enable trigger outbound_custody_append_only');
    await setup('alter table private.outbound_dispatches enable trigger outbound_dispatches_append_only');
    await setup('delete from public.business_events where subject_id = any($1::uuid[])', [tasks]);
    await setup('delete from public.delivery_tasks where id = any($1::uuid[])', [tasks]);
    await setup('delete from public.inventory_movements where order_id = any($1::uuid[])', [orders]);
    await setup('delete from public.order_items where order_id = any($1::uuid[])', [orders]);
    await setup('delete from public.orders where id = any($1::uuid[])', [orders]);
    await setup('delete from public.product_variants where id=$1', [id(111)]);
    await setup('delete from public.products where id=$1', [id(101)]);
    await setup('delete from public.categories where id=$1', [id(100)]);
    await setup('delete from auth.users where id = any($1::uuid[])', [[customer, manager, shipper]]);
  }
}
