import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';

export async function testRedeliveryConcurrency(Client,options,admin,fixtureSql) {
 await admin.query('begin');
 await admin.query(fixtureSql);
 const x=(await admin.query("select p083_fixture.seed_redelivery_case_fixture('race','complete') as x")).rows[0].x;
 const rid=x.return_request_id, oid=x.order_id;
 const claim=async(client,id)=>{
   await client.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claims',$2,true)",
     [id,JSON.stringify({sub:id,role:'authenticated'})]);
 };
 let task;
 try {
  await admin.query(`update public.return_requests set status='pending_review',decision_at=null,decided_by=null,
   inspected_at=null,inspected_by=null,inspection_started_at=null where id=$1`,[rid]);
  await admin.query('update public.return_items set quantity_collected=0 where return_request_id=$1',[rid]);
  const plan=(await admin.query(`select jsonb_agg(jsonb_build_object('return_item_id',id,'quantity',quantity_to_collect) order by id) as p
    from public.return_items where return_request_id=$1`,[rid])).rows[0].p;
  const rpc=async(name,args)=> (await admin.query(`select public.${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) as ack`,args)).rows[0].ack;
  await claim(admin,x.manager_id);
  await rpc('approve_return_pickup_plan',[rid,randomUUID(),JSON.stringify(plan)]);
  const pickup=(await rpc('assign_return_pickup_task',[rid,x.shipper_id,randomUUID()])).task_id;
  await claim(admin,x.shipper_id);
  await rpc('collect_return_items',[pickup,randomUUID(),JSON.stringify(plan)]);
  await rpc('report_return_pickup_handover',[pickup,randomUUID(),JSON.stringify(plan)]);
  await claim(admin,x.manager_id);
  await rpc('receive_customer_return',[pickup,randomUUID(),JSON.stringify(plan)]);
  await rpc('reject_return_after_inspection',[rid,randomUUID(),'Inspected and rejected']);
  task=(await rpc('assign_redelivery_task',[rid,x.shipper_id,randomUUID()])).task_id;
  await claim(admin,x.shipper_id);
  await rpc('accept_redelivery_task',[task,randomUUID(),JSON.stringify(plan)]);
  await rpc('start_redelivery_task',[task,randomUUID()]);
  const before=(await admin.query('select to_jsonb(c) as c from public.cod_collections c where order_id=$1',[oid])).rows[0].c;
  await admin.query('commit');
  const a=new Client(options),b=new Client(options); await a.connect();await b.connect();
  try {
   for(const connection of [a,b]) {await connection.query('begin');await claim(connection,x.shipper_id);}
   const key=randomUUID();
   const first=(await a.query('select public.complete_redelivery($1,$2,true) as ack',[task,key])).rows[0].ack;
   const waiting=b.query('select public.fail_redelivery_task($1,$2,$3,null) as ack',[task,randomUUID(),'unreachable'])
     .then(()=>({success:true}),e=>({code:e.code}));
   await a.query('commit');
   assert.equal((await waiting).code,'PT409');await b.query('rollback');
   await b.query('begin');await claim(b,x.shipper_id);
   assert.deepEqual((await b.query('select public.complete_redelivery($1,$2,true) as ack',[task,key])).rows[0].ack,first);
   await b.query('commit');
   assert.deepEqual((await admin.query('select to_jsonb(c) as c from public.cod_collections c where order_id=$1',[oid])).rows[0].c,before);
   assert.equal((await admin.query('select count(*)::int as n from private.redelivery_outcomes where task_id=$1',[task])).rows[0].n,1);
   console.log('Redelivery concurrency PASS: completion vs failure serialized; identical retry and entire COD preserved');
  } finally {await a.end();await b.end();}
 } finally {
  await admin.query('rollback');
  // This database is a new native-only test DB, never Supabase. Keep its
  // schema/data for diagnosis rather than invoking production cleanup grants.
 }
}
