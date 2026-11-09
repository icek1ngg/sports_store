// Real multi-connection PostgreSQL races, never hosted Supabase.
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';
const require = createRequire(resolve('supabase/.temp/b2_runtime/package.json'));
const { Client } = require('pg');
const database = process.argv[2];
if (!/^orders_b2_\d+$/.test(database ?? '')) throw Error('Dedicated B2 disposable database name required');
const options = {host:'127.0.0.1',port:55448,user:'postgres',database};
const admin = new Client(options), first = new Client(options), second = new Client(options), lookup = new Client(options);
const clients = [admin,first,second,lookup];
const A='a2222222-2222-4222-8222-222222222222', B='b2222222-2222-4222-8222-222222222222';
async function identity(c, uid) {
 await c.query('reset role');
 await c.query("select set_config('request.jwt.claim.sub',$1,false)",[uid]);
 await c.query('set role authenticated');
}
async function call(c,name,id,key,reason) {
 assert(['confirm_order','reject_order','cancel_customer_order','get_order_operation_result'].includes(name));
 const args=name==='get_order_operation_result'?[key,id,reason]:reason===undefined?[id,key]:[id,key,reason];
 const placeholders=args.map((_,i)=>`$${i+1}`).join(',');
 return (await c.query(`select public.${name}(${placeholders}) as result`,args)).rows[0].result;
}
async function race(id, firstUser, secondUser, firstOp, secondOp, key1, key2, reason1, reason2) {
 await identity(first,firstUser); await identity(second,secondUser);
 await first.query('begin');
 const winner=await call(first,firstOp,id,key1,reason1);
 assert.equal(winner.ok,true);
 const pid=(await second.query('select pg_backend_pid() as pid')).rows[0].pid;
 const contender=call(second,secondOp,id,key2,reason2);
 let blocked=false;
 for(let n=0;n<30;n++) {
  const row=(await admin.query("select wait_event_type from pg_stat_activity where pid=$1",[pid])).rows[0];
  if(row?.wait_event_type==='Lock'){blocked=true;break;}
  await new Promise(r=>setTimeout(r,20));
 }
 assert(blocked,'second independent connection must actually wait on the transaction/advisory lock');
 await first.query('commit');
 return [winner,await contender];
}
try {
 await Promise.all(clients.map(c=>c.connect()));
 const dir=(await admin.query('show data_directory')).rows[0].data_directory;
 assert.equal(resolve(dir).toLowerCase(),resolve('supabase/.temp/b2_runtime/native_data').toLowerCase());
 await admin.query('revoke usage on schema auth from sports_store_orders_writer');
 const sql=await readFile('supabase/tests/orders_transactional_mutations.sql','utf8');
 await admin.query("set sports_store.qa_local_disposable='YES'");
 await admin.query(sql.slice(0,sql.indexOf('grant select,update on b2_orders')));
 await admin.query('commit');
 const orders=Object.fromEntries((await admin.query('select * from b2_orders')).rows.map(r=>[r.label,r]));
 let [w,l]=await race(orders.confirm.id,B,A,'confirm_order','cancel_customer_order',randomUUID(),randomUUID());
 assert.equal(l.error.code,'cancellation_not_allowed');
 console.log('RACE confirm wins/customer cancel loses: PASS');
 [w,l]=await race(orders.cancel.id,A,B,'cancel_customer_order','confirm_order',randomUUID(),randomUUID());
 assert.equal(l.error.code,'state_changed');
 console.log('RACE customer cancel wins/confirm loses: PASS');
 const key=randomUUID();
 [w,l]=await race(orders.reject.id,B,B,'reject_order','reject_order',key,key,'QA reject','QA reject');
 assert.equal(l.data.replayed,true); assert.equal(l.data.event_id,w.data.event_id);
 assert.equal(l.data.committed_at,w.data.committed_at);
 console.log('RACE duplicate same key returns stable receipt/event: PASS');
 const changedKey=randomUUID();
 [w,l]=await race(orders.corrupt.id,B,B,'reject_order','reject_order',changedKey,changedKey,'Reason one','Reason two');
 assert.equal(l.error.code,'idempotency_conflict');
 console.log('RACE same key changed fingerprint: PASS');
 await identity(first,B); await identity(lookup,B);
 const unknownKey=randomUUID(), id=orders.manager_cancel.id;
 await first.query('begin');
 const hidden=await call(first,'confirm_order',id,unknownKey);
 assert.equal((await call(lookup,'get_order_operation_result',id,unknownKey,'confirm')).data.state,'not_found');
 await first.query('commit');
 const recovered=await call(lookup,'get_order_operation_result',id,unknownKey,'confirm');
 assert.equal(recovered.data.state,'committed');
 assert.equal(recovered.data.receipt.event_id,hidden.data.event_id);
 console.log('RECOVERY uncommitted not_found then lost ACK committed lookup: PASS');
 const effects=(await admin.query(`select
  (select reserved from public.product_variants where sku='B2-LOCAL') as reserved,
  (select count(*) from public.inventory_movements where kind='release' and order_id=any($1::uuid[])) as releases,
  (select count(*) from private.business_event_contracts where subject_id=any($1::uuid[])) as events,
  (select count(*) from public.notifications where event_id in(select event_id from private.business_event_contracts where subject_id=any($1::uuid[]))) as notifications`,[Object.values(orders).map(o=>o.id)])).rows[0];
 assert.equal(Number(effects.reserved),3); assert.equal(Number(effects.releases),3);
 assert.equal(Number(effects.events),5); assert.equal(Number(effects.notifications),5);
 console.log('INVARIANTS one release/event/notification per committed operation: PASS');
 console.log('LOCAL B2 NATIVE CONCURRENCY: 6/6 PASS; fixture records retained only in disposable local database');
} finally {
 await Promise.allSettled(clients.map(async c=>{try{await c.query('rollback');}finally{await c.end();}}));
}
