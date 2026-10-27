// Explicit opt-in live test. Secrets stay in process memory/environment only.
// Creates uniquely scoped test accounts/data, exercises real JWT/UI, then cleans up.
import { execSync, spawn } from 'node:child_process';
import { readFile, writeFile, mkdir, unlink } from 'node:fs/promises';
import { randomUUID, randomBytes } from 'node:crypto';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';

assert.ok(process.argv.includes('--live'), 'Requires explicit --live');
const complete = process.argv.includes('--complete');
const root = resolve(import.meta.dirname, '../..');
const config = JSON.parse(await readFile(resolve(root, 'config/supabase.json'), 'utf8'));
const project = new URL(config.SUPABASE_URL).hostname.split('.')[0];
assert.equal(project, 'bqoyfytmrtvjwrpshuhh', 'Unexpected live project');
function cli(args) {
  try { return execSync(`npx --yes supabase@2.122.0 ${args}`, { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 5e6 }); }
  catch { throw new Error('Supabase CLI operation failed; credential-bearing output suppressed'); }
}
const keyResult = JSON.parse(cli(`projects api-keys --project-ref ${project} --reveal --output json`));
const keys = Array.isArray(keyResult) ? keyResult : keyResult.api_keys ?? keyResult.keys;
const secret = keys?.find(k => k.name === 'service_role')?.api_key;
assert.ok(secret, 'Server-only Auth Admin credential unavailable');
const run = randomUUID();
const ids = Object.fromEntries(['order','category','product','variant','item','reserve'].map(k => [k,randomUUID()]));
const users = [];
const sqlDir = resolve(root, 'supabase/.temp');
await mkdir(sqlDir, { recursive: true });
const sqlFile = resolve(sqlDir, `live-${run}.sql`);
async function query(sql) {
  await writeFile(sqlFile, sql);
  return JSON.parse(cli(`db query --linked --file "${sqlFile}"`)).rows;
}
async function admin(path, method, body) {
  const r = await fetch(`${config.SUPABASE_URL}/auth/v1/admin/${path}`, {
    method, headers:{ apikey:secret, Authorization:`Bearer ${secret}`, 'Content-Type':'application/json' },
    body:body ? JSON.stringify(body):undefined, signal:AbortSignal.timeout(20000),
  });
  assert.ok(r.ok, `Auth Admin ${method} failed (${r.status}); response suppressed`);
  return r.status === 204 ? null : r.json();
}
async function login(user) {
  const r = await fetch(`${config.SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method:'POST', headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,'Content-Type':'application/json'},
    body:JSON.stringify({email:user.email,password:user.password}),signal:AbortSignal.timeout(20000),
  });
  assert.ok(r.ok, `Real password login failed (${r.status})`);
  return (await r.json()).access_token;
}
async function rpc(token, name, body, denied=false) {
  const r = await fetch(`${config.SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method:'POST',headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,Authorization:`Bearer ${token}`,'Content-Type':'application/json'},
    body:JSON.stringify(body), signal:AbortSignal.timeout(20000),
  });
  const data = await r.json();
  if (denied) { assert.ok(!r.ok, `${name} unexpectedly authorized`); return; }
  assert.ok(r.ok, `${name} failed HTTP ${r.status} / ${data.code ?? 'unknown'}`);
  return data;
}
let seeded=false;
try {
  for (const role of ['customer','manager','shipper','shipper']) {
    const email=`live-${run}-${users.length}@example.invalid`;
    const password=`Aa1!${randomBytes(24).toString('hex')}`;
    const result=await admin('users','POST',{email,password,email_confirm:true});
    users.push({id:result.id ?? result.user?.id,email,password,role});
  }
  const [customer,manager,shipper,other]=users;
  assert.ok(users.every(u=>/^[0-9a-f-]{36}$/.test(u.id)));
  await query(`begin;
    ${users.map(u=>`update public.profiles set role='${u.role}' where id='${u.id}';`).join('\n')}
    insert into public.categories(id,code,name) values('${ids.category}','LIVE-${run}','Live isolated verification');
    insert into public.products(id,category_id,name) values('${ids.product}','${ids.category}','Live test product');
    insert into public.product_variants(id,product_id,sku,label,attributes,price_vnd,on_hand,reserved)
      values('${ids.variant}','${ids.product}','LIVE-${run}','Live variant','{}',520000,5,1);
    insert into public.orders(id,customer_id,request_id,status,recipient_name,recipient_phone,address_detail,latitude,longitude,subtotal_vnd)
      values('${ids.order}','${customer.id}','${ids.order}','preparing','Live test recipient','0900000000','Live test Hanoi',21.0285,105.8542,520000);
    insert into public.order_items(id,order_id,product_id,variant_id,product_name,variant_label,attributes,unit_price_vnd,quantity)
      values('${ids.item}','${ids.order}','${ids.product}','${ids.variant}','Live test product','Live variant','{}',520000,1);
    insert into public.inventory_movements(id,variant_id,order_id,event_id,kind,on_hand_delta,reserved_delta,damaged_delta,actor_id,reason)
      values('${ids.reserve}','${ids.variant}','${ids.order}','${ids.reserve}','reserve',0,1,0,'${customer.id}','Explicit live verification fixture');
    commit;`);
  seeded=true;
  const managerToken=await login(manager);
  const assignment=await rpc(managerToken,'assign_delivery_task',{p_order_id:ids.order,p_shipper_id:shipper.id,p_request_id:randomUUID()});
  const taskId=assignment.task_id;
  const otherToken=await login(other);
  await rpc(otherToken,'get_my_delivery_task',{p_task_id:taskId},true);
  await rpc(otherToken,'accept_delivery_task',{p_task_id:taskId,p_request_id:randomUUID()},true);
  await rpc(managerToken,'accept_delivery_task',{p_task_id:taskId,p_request_id:randomUUID()},true);
  console.log('LIVE: real Auth login, manager assignment, unauthorized detail/accept denied PASS');
  // Flutter receives only ephemeral test-user credentials, never Admin secret.
  const env={...process.env,LIVE_OUTBOUND_UI:'1',LIVE_SUPABASE_URL:config.SUPABASE_URL,
    LIVE_PUBLISHABLE_KEY:config.SUPABASE_PUBLISHABLE_KEY,LIVE_TEST_EMAIL:shipper.email,
    LIVE_TEST_PASSWORD:shipper.password,LIVE_TASK_ID:taskId,LIVE_COMPLETE:complete?'1':'0'};
  const exit=await new Promise((ok,reject)=>{
    const child=spawn('flutter',['test','--no-pub','test/live/live_outbound_ui_test.dart'],{cwd:root,env,shell:process.platform==='win32',stdio:['ignore','pipe','pipe']});
    const redact=s=>s.toString().replaceAll(shipper.password,'[redacted]');
    child.stdout.on('data',d=>process.stdout.write(redact(d)));
    child.stderr.on('data',d=>process.stderr.write(redact(d)));
    child.on('error',reject); child.on('close',ok);
  });
  assert.equal(exit,0,'Live Flutter UI test failed');
  const rows=await query(`select o.status::text, o.delivery_attempt_count,
    v.on_hand,v.reserved,(select count(*) from public.delivery_attempts a where a.order_id=o.id) attempts,
    c.status::text cod_status,c.expected_amount_vnd,c.collected_amount_vnd
    from public.orders o join public.product_variants v on v.id='${ids.variant}'
    join public.cod_collections c on c.order_id=o.id where o.id='${ids.order}';`);
  const row=rows[0];
  assert.equal(row.status,complete?'delivered':'delivering');
  assert.equal(Number(row.delivery_attempt_count),1);
  assert.equal(Number(row.on_hand),4); assert.equal(Number(row.reserved),0);
  assert.equal(Number(row.attempts),complete?1:0);
  assert.equal(row.cod_status,complete?'collected':'uncollected');
  assert.equal(Number(row.expected_amount_vnd),550000);
  assert.equal(Number(row.collected_amount_vnd),complete?550000:0);
  if (complete) {
    const [receipt]=await query(`select request_id,event_id from private.outbound_completion_results where task_id='${taskId}';`);
    const shipperToken=await login(shipper);
    await rpc(shipperToken,'complete_outbound_delivery',{p_task_id:taskId,p_request_id:receipt.request_id,p_received_all_items:true,p_collected_amount_vnd:550000});
    await rpc(otherToken,'complete_outbound_delivery',{p_task_id:taskId,p_request_id:randomUUID(),p_received_all_items:true,p_collected_amount_vnd:550000},true);
    const otherCod=await rpc(otherToken,'list_cod_collections',{});
    assert.equal(Number(otherCod.outstanding_vnd),0);
    const [proof]=await query(`select
      (select count(*) from public.delivery_attempts where task_id='${taskId}') attempts,
      (select count(*) from public.business_events where task_id='${taskId}' and reason='delivery_completed') events,
      (select count(*) from public.notifications where event_id='${receipt.event_id}') notifications,
      (select count(*)+1 from public.profiles where role='manager') expected_notifications,
      (select bool_and(body='Đơn hàng đã được giao thành công và thu đủ COD.' and subject_type='delivery_task' and subject_id='${taskId}') from public.notifications where event_id='${receipt.event_id}') safe_notifications;`);
    assert.equal(Number(proof.attempts),1);assert.equal(Number(proof.events),1);
    assert.equal(Number(proof.notifications),Number(proof.expected_notifications));
    assert.equal(proof.safe_notifications,true);
    console.log('LIVE completion replay, wrong-shipper denial, COD isolation, one result/event and safe recipient notifications PASS');
  }
  console.log(`LIVE ${complete?'P04→P05':'P04.2'} PASS: real UI/repository/JWT, exactly-once dispatch/counters, authoritative COD verified`);
} finally {
  // Maintenance cleanup only: scoped UUIDs, transaction, restore append-only
  // triggers before commit. Never disables RLS, FK constraints or runtime auth.
  if (seeded) {
    await query(`begin;
      do $$ declare t text; begin
        foreach t in array array['outbound_completion_results','outbound_completion_requests','outbound_command_requests','outbound_custody_acceptances','outbound_dispatches','delivery_assignment_audits','delivery_assignment_requests'] loop
          if to_regclass('private.'||t) is not null then
            execute format('alter table private.%I disable trigger user',t);
            execute format('delete from private.%I where order_id=%L::uuid',t,'${ids.order}');
            execute format('alter table private.%I enable trigger user',t);
          end if;
        end loop;
      end $$;
      delete from public.notifications where event_id in(select id from public.business_events where subject_id='${ids.order}' or subject_id in(select id from public.delivery_tasks where order_id='${ids.order}'));
      delete from public.delivery_attempts where order_id='${ids.order}';
      delete from public.inventory_movements where order_id='${ids.order}';
      delete from public.business_events where subject_id='${ids.order}' or subject_id in(select id from public.delivery_tasks where order_id='${ids.order}');
      delete from public.cod_collections where order_id='${ids.order}';
      delete from public.delivery_tasks where order_id='${ids.order}';
      delete from public.order_items where order_id='${ids.order}';
      delete from public.orders where id='${ids.order}';
      delete from public.product_variants where id='${ids.variant}';
      delete from public.products where id='${ids.product}';
      delete from public.categories where id='${ids.category}';
      commit;`);
  }
  for (const user of users.reverse()) await admin(`users/${user.id}`,'DELETE');
  await unlink(sqlFile).catch(()=>{});
  console.log('LIVE cleanup: scoped test rows/accounts removed; existing data retained');
}
