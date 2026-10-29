// P10.1: real production RPCs crossing the delivery/COD transaction boundary.
// No cloud endpoint. Checkout reservation is explicitly a privileged TEST SEED.
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';

export async function testDeliveryCodConcurrency(Client, options, admin) {
  assert.equal(options.host, '127.0.0.1');
  assert.equal(options.port, 55439);
  assert.match(options.database, /^p011_/);
  assert.equal((await admin.query("select current_setting('sports_store.fixture_mode') m")).rows[0].m, 'p011_isolated');
  const id = n => `10110000-0000-0000-0000-${String(n).padStart(12,'0')}`;
  const customer=id(1), managerA=id(2), managerB=id(3), shipper=id(4);
  const users=[customer,managerA,managerB,shipper];
  const orders=[id(10),id(11),id(12)];
  const tasks=[];
  const a=new Client(options), b=new Client(options);
  const begin=async(c,actor)=>{
    await c.query('begin');
    await c.query('set local role authenticated');
    await c.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claims',$2,true)",
      [actor,JSON.stringify({sub:actor,role:'authenticated'})]);
  };
  const rpc=async(c,name,args)=>{
    // Names come only from the static test calls below.
    const params=args.map((_,i)=>`$${i+1}`).join(',');
    return (await c.query(`select public.${name}(${params}) result`,args)).rows[0].result;
  };
  const completion=(c,i,key)=>rpc(c,'complete_outbound_delivery',[tasks[i],key,true,550000]);
  const receipt=(c,i,key,amount=550000)=>rpc(c,'confirm_cod_received',[orders[i],amount,key]);
  const expectConflict=error=>{assert.equal(error?.code,'PT409');assert.equal(error?.message,'STATE_CONFLICT');};
  async function race(firstActor,secondActor,firstCall,secondCall,commit=true) {
    await begin(a,firstActor); await begin(b,secondActor);
    const first=await firstCall(a);
    const pid=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
    const pending=secondCall(b).then(value=>({value}),error=>({error}));
    let blocked=false;
    for(let n=0;n<100;n++) {
      blocked=(await admin.query('select cardinality(pg_blocking_pids($1))>0 blocked',[pid])).rows[0].blocked;
      if(blocked) break;
      await delay(15);
    }
    assert.ok(blocked,'COD/delivery contender must actually wait for a transaction lock');
    await a.query(commit?'commit':'rollback');
    const second=await pending;
    await b.query(second.error?'rollback':'commit');
    return {first,second};
  }
  async function snapshot(i) {
    return (await admin.query(`select o.status::text order_status,t.status::text task_status,
      o.total_cod_vnd::int total,c.expected_amount_vnd::int expected,
      c.collected_amount_vnd::int collected,c.received_amount_vnd::int received,c.status::text cod_status,
      o.delivery_attempt_count::int attempts,
      (select count(*)::int from public.delivery_attempts where order_id=o.id) results,
      (select count(*)::int from private.outbound_dispatches where order_id=o.id) dispatches,
      (select count(*)::int from public.inventory_movements where order_id=o.id and kind='dispatch') movements,
      (select count(*)::int from private.outbound_completion_results where task_id=t.id) completion_results,
      (select count(*)::int from private.cod_receipt_requests where order_id=o.id) receipts,
      (select count(*)::int from public.business_events e where e.id in
        (select event_id from private.outbound_completion_results where task_id=t.id)) completion_events,
      (select count(*)::int from public.notifications n where n.event_id in
        (select event_id from private.outbound_completion_results where task_id=t.id)) completion_notifications,
      (select count(*)::int from public.business_events e where e.id in
        (select (response->>'event_id')::uuid from private.cod_receipt_requests where order_id=o.id)) receipt_events,
      (select count(*)::int from public.notifications n where n.event_id in
        (select (response->>'event_id')::uuid from private.cod_receipt_requests where order_id=o.id)) receipt_notifications
      from public.orders o join public.delivery_tasks t on t.order_id=o.id
      join public.cod_collections c on c.order_id=o.id where o.id=$1`,[orders[i]])).rows[0];
  }
  await Promise.all([a.connect(),b.connect()]);
  try {
    for(const c of [a,b]) await c.query("set statement_timeout='8s';set lock_timeout='5s'");
    await admin.query('insert into auth.users(id,email) select x,x::text||$2 from unnest($1::uuid[]) x',[users,'@p101.invalid']);
    await admin.query(`update public.profiles set role=case when id=any($1::uuid[]) then 'manager'::public.user_role
      when id=$2 then 'shipper'::public.user_role else 'customer'::public.user_role end where id=any($3::uuid[])`,[[managerA,managerB],shipper,users]);
    await admin.query("insert into public.categories(id,code,name) values($1,'P101','P10.1 isolated fixture')",[id(100)]);
    await admin.query("insert into public.products(id,category_id,name) values($1,$2,'P10.1 isolated fixture')",[id(101),id(100)]);
    await admin.query("insert into public.product_variants(id,product_id,sku,label,price_vnd,on_hand,reserved) values($1,$2,'P101','P101',260000,20,6)",[id(102),id(101)]);
    for(let i=0;i<orders.length;i++) {
      await admin.query(`insert into public.orders(id,customer_id,request_id,status,recipient_name,recipient_phone,address_detail,latitude,longitude,subtotal_vnd)
        values($1,$2,$1,'preparing','TEST ONLY','0900000000','TEST Hanoi',21.0285,105.8542,520000)`,[orders[i],customer]);
      await admin.query(`insert into public.order_items(id,order_id,product_id,variant_id,product_name,variant_label,unit_price_vnd,quantity)
        values($1,$2,$3,$4,'TEST ONLY','TEST ONLY',260000,2)`,[id(200+i),orders[i],id(101),id(102)]);
      await admin.query(`insert into public.inventory_movements(variant_id,order_id,event_id,kind,reserved_delta,actor_id,reason)
        values($1,$2,$3,'reserve',2,$4,'P10.1 TEST-ONLY checkout reservation seed')`,[id(102),orders[i],id(300+i),managerA]);
      await begin(a,managerA);
      tasks.push((await rpc(a,'assign_delivery_task',[orders[i],shipper,id(400+i)])).task_id);
      await a.query('commit');
      await begin(a,shipper);
      await rpc(a,'accept_delivery_task',[tasks[i],id(500+i)]);
      await rpc(a,'start_delivery_task',[tasks[i],id(600+i)]);
      await a.query('commit');
    }
    // A receipt waits for a real completion commit and sees its atomic COD.
    const first=await race(shipper,managerA,c=>completion(c,0,id(700)),c=>receipt(c,0,id(700)));
    assert.ifError(first.second.error);
    const expected={order_status:'delivered',task_status:'delivered',total:550000,expected:550000,
      collected:550000,received:550000,cod_status:'received',attempts:1,results:1,dispatches:1,movements:1,
      completion_results:1,receipts:1,completion_events:1,completion_notifications:3,receipt_events:1,receipt_notifications:1};
    assert.deepEqual(await snapshot(0),expected);
    // Identical request UUID may be used in different actor/operation ledgers;
    // neither operation can replay the other's acknowledgement or create money.
    await begin(a,shipper); assert.deepEqual(await completion(a,0,id(700)),first.first); await a.query('commit');
    await begin(a,managerA); assert.deepEqual(await receipt(a,0,id(700)),first.second.value); await a.query('commit');
    assert.deepEqual(await snapshot(0),expected);

    // If completion rolls back, the blocked receipt must not consume staged COD.
    const rolled=await race(shipper,managerA,c=>completion(c,1,id(701)),c=>receipt(c,1,id(702)),false);
    expectConflict(rolled.second.error);
    const pending=await snapshot(1);
    assert.deepEqual(pending,{...expected,order_status:'delivering',task_status:'in_transit',collected:0,received:0,
      cod_status:'uncollected',results:0,completion_results:0,receipts:0,completion_events:0,
      completion_notifications:0,receipt_events:0,receipt_notifications:0});
    await begin(a,shipper); await completion(a,1,id(701)); await a.query('commit');
    // Two managers reconcile after real completion, not an artificial collected seed.
    const managers=await race(managerA,managerB,c=>receipt(c,1,id(703)),c=>receipt(c,1,id(704)));
    expectConflict(managers.second.error);
    assert.deepEqual(await snapshot(1),expected);

    // A failed transaction can reuse its key with corrected payload; it did not
    // reserve that key, collect partial money or write a result/event.
    await begin(a,shipper);
    await assert.rejects(rpc(a,'complete_outbound_delivery',[tasks[2],id(705),true,520000]),e=>e.code==='PT409'&&e.message==='AMOUNT_MISMATCH');
    await a.query('rollback');
    assert.deepEqual(await snapshot(2),pending);
    await begin(a,shipper); await completion(a,2,id(705)); await a.query('commit');
    await begin(a,managerA);
    await assert.rejects(receipt(a,2,id(706),520000),e=>e.code==='PT409'&&e.message==='AMOUNT_MISMATCH');
    await a.query('rollback');
    assert.equal((await snapshot(2)).receipts,0);
    await begin(a,managerA); await receipt(a,2,id(706)); await a.query('commit');
    assert.deepEqual(await snapshot(2),expected);
    console.log('p101_delivery_cod_concurrency: PASS (real completion/receipt commit+rollback waiters, two managers, actor/operation key isolation, 550000 exact once, real blocking locks)');
  } finally {
    await Promise.allSettled([a.query('rollback'),b.query('rollback')]);
    await Promise.allSettled([a.end(),b.end()]);
    // Isolated, guarded NEW database only. Scoped fixture UUIDs; never change
    // runtime grants/RLS. Replica mode is transaction-local cleanup of immutable
    // test rows, not part of any application operation or assertion.
    await admin.query('begin');
    try {
      await admin.query("set local session_replication_role='replica'");
      for(const table of ['cod_receipt_requests','outbound_completion_results','outbound_completion_requests',
        'outbound_command_requests','outbound_custody_acceptances','outbound_dispatches',
        'delivery_assignment_requests','delivery_assignment_audits']) {
        await admin.query(`delete from private.${table} where order_id=any($1::uuid[])`,[orders]);
      }
      await admin.query('delete from public.notifications where event_id in (select id from public.business_events where task_id=any($1::uuid[]) or subject_id=any($2::uuid[]))',[tasks,orders]);
      await admin.query('delete from public.business_events where task_id=any($1::uuid[]) or subject_id=any($2::uuid[])',[tasks,orders]);
      for(const table of ['inventory_movements','delivery_attempts','cod_collections','delivery_tasks','order_items']) {
        await admin.query(`delete from public.${table} where order_id=any($1::uuid[])`,[orders]);
      }
      await admin.query('delete from public.orders where id=any($1::uuid[])',[orders]);
      await admin.query('delete from public.product_variants where id=$1',[id(102)]);
      await admin.query('delete from public.products where id=$1',[id(101)]);
      await admin.query('delete from public.categories where id=$1',[id(100)]);
      await admin.query('delete from public.profiles where id=any($1::uuid[])',[users]);
      await admin.query('delete from auth.users where id=any($1::uuid[])',[users]);
      await admin.query('commit');
    } catch(error) {await admin.query('rollback');throw error;}
  }
}
