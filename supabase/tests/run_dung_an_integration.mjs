// Isolated PostgreSQL engine tests. Auth/Storage SQL stubs are fixtures;
// this does not claim to test hosted Supabase Auth, Storage or Realtime.
// npm install --prefix build/dung_an_db_test --no-save --package-lock=false @electric-sql/pglite@0.3.14
// node supabase/tests/run_dung_an_integration.mjs
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
const root = new URL('../../', import.meta.url);
const { PGlite } = await import(new URL('build/dung_an_db_test/node_modules/@electric-sql/pglite/dist/index.js', root));
const db = new PGlite();
const manual = process.argv.includes('--manual');
let assertions = 0;
const ok = (value, message) => { assert.ok(value, message); assertions++; };
const one = async (sql, args = []) => (await db.query(sql, args)).rows[0];
const denied = async (sql, args, code) => {
  await assert.rejects(db.query(sql, args), e => e.code === code);
  assertions++;
};
const actor = async (id, role = 'authenticated') => {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [id ?? '']);
  await db.exec(`set role ${role}`);
};
const saveSql = 'select public.save_managed_product($1::uuid,$2::uuid,$3::timestamptz,$4,$5::uuid,$6,$7,$8,$9::jsonb) as id';
try {
  await db.exec("set sports_store.fixture_mode = 'p011_isolated'");
  await db.exec(await readFile(new URL('supabase/tests/fixtures/p011_auth_storage.sql.fixture', root), 'utf8'));
  const dir = new URL('supabase/migrations/', root);
  for (const name of (await readdir(dir)).filter(n => n.endsWith('.sql')).sort()) {
    const source = manual && name === '20261029041230_dung_an_management_integration.sql'
      ? new URL('supabase/manual/dung_an_management.sql', root) : new URL(name, dir);
    await db.exec(await readFile(source, 'utf8'));
  }
  if (manual) {
    const verification = await db.exec(await readFile(new URL('supabase/manual/verify_dung_an_management.sql', root), 'utf8'));
    ok(verification[0].rows.length === 5 && verification[0].rows.every(r => r.installed && r.authenticated_can_execute && !r.anon_can_execute), 'manual export installs all five protected RPCs');
    ok(verification[1].rows.length === 8 && verification[1].rows.every(r => r.installed && r.rls_enabled), 'manual export preserves RLS');
    ok(verification[2].rows.length === 2 && verification[2].rows.every(r => r.installed && r.enabled), 'manual export installs both chat triggers');
  }
  console.log('All migrations applied to isolated PostgreSQL engine.');
  const manager = randomUUID(), customer = randomUUID(), other = randomUUID(), shipper = randomUUID();
  for (const [id, role] of [[manager,'manager'],[customer,'customer'],[other,'customer'],[shipper,'shipper']]) {
    await db.query('insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)',
      [id, `${id}@example.test`, JSON.stringify({full_name:'Fixture User',phone:'0901234567',role:'manager'})]);
    const profile = await one('select * from public.profiles where id=$1', [id]);
    ok(profile.role === 'customer' && profile.phone === '0901234567', 'signup forces customer and persists contact');
    await db.query('update public.profiles set role=$1 where id=$2', [role,id]);
  }
  const category = (await one('select id from public.categories limit 1')).id;
  const command = [randomUUID(),null,null,'Test product',category,'Description',null,true,JSON.stringify([
    {id:null,sku:'FIXTURE-S',label:'S',price_vnd:100000,on_hand:10,is_active:true,attributes:{size:'S'}},
    {id:null,sku:'FIXTURE-M',label:'M',price_vnd:120000,on_hand:20,is_active:true,attributes:{size:'M'}},
  ])];
  await actor(customer);
  await denied(saveSql,command,'42501');
  await denied('update public.profiles set role=\'manager\' where id=$1',[customer],'42501');
  await actor(manager);
  const product = (await one(saveSql,command)).id;
  ok((await one(saveSql,command)).id === product,'save retry returns original receipt');
  ok((await one('select count(*)::int as n from public.products where id=$1',[product])).n === 1,'one product after retry');
  ok((await one('select count(*)::int as n from public.inventory_movements')).n === 2,'stock ledger once per variant');
  const changed = [...command]; changed[3] = 'Changed retry';
  await denied(saveSql,changed,'22023');
  const snapshot = await one('select updated_at::text from public.products where id=$1',[product]);
  let variants = (await db.query('select id,sku,label,price_vnd,on_hand,is_active,attributes from public.product_variants where product_id=$1 order by sku',[product])).rows;
  variants = variants.map(v => ({...v,price_vnd:Number(v.price_vnd),on_hand:Number(v.on_hand),expected_on_hand:Number(v.on_hand)}));
  await db.exec('reset role');
  await db.query('update public.product_variants set reserved=5 where id=$1',[variants[0].id]);
  await actor(manager);
  const invalid = variants.map(v=>({...v})); invalid[0].on_hand=4;
  await denied(saveSql,[randomUUID(),product,snapshot.updated_at,'Must rollback',category,'',null,true,JSON.stringify(invalid)],'23514');
  ok((await one('select name from public.products where id=$1',[product])).name === 'Test product','stock rejection rolls back entire product edit');
  const edited = variants.map(v=>({...v})); edited[0].on_hand=12;
  await one(saveSql,[randomUUID(),product,snapshot.updated_at,'Edited product',category,'',null,false,JSON.stringify(edited)]);
  ok((await one('select reserved::int,on_hand::int from public.product_variants where id=$1',[variants[0].id])).reserved === 5,'edit preserves reserved stock');
  await denied(saveSql,[randomUUID(),product,snapshot.updated_at,'Stale product',category,'',null,true,JSON.stringify(edited)],'40001');
  await actor(customer);
  ok(!(await one('select id from public.products where id=$1',[product])),'customer cannot see archived product');
  const conversation = (await one('select public.ensure_customer_conversation() as data')).data.id;
  ok((await one('select public.ensure_customer_conversation() as data')).data.id === conversation,'one conversation per customer');
  const clientId = randomUUID();
  const send = 'select public.send_chat_message($1,$2,$3) as data';
  const message = (await one(send,[conversation,clientId,'Xin chào'])).data;
  ok((await one(send,[conversation,clientId,'Xin chào'])).data.id === message.id,'message retry is idempotent');
  await denied(send,[conversation,clientId,'Different body'],'23505');
  await actor(other);
  await denied('select public.get_chat_messages($1)',[conversation],'42501');
  await denied(send,[conversation,randomUUID(),'Unauthorized'],'42501');
  ok((await one('select public.list_chat_conversations() as data')).data.length === 0,'customer cannot list others conversations');
  await actor(shipper);
  await denied('select public.list_chat_conversations()',[],'42501');
  await actor(manager);
  const inbox = (await one('select public.list_chat_conversations() as data')).data;
  ok(inbox.length === 1 && inbox[0].unread_count === 1,'manager inbox has real unread count');
  const thread = (await one('select public.get_chat_messages($1) as data',[conversation])).data;
  ok(thread.messages.length === 1,'manager reads authorized messages');
  ok((await one('select public.list_chat_conversations() as data')).data[0].unread_count === 0,'read marker persisted');
  await one(send,[conversation,randomUUID(),'Chào bạn']);
  await actor(customer);
  ok((await one('select public.list_chat_conversations() as data')).data[0].unread_count === 1,'customer sees manager reply unread');
  // A forged object cannot replace the other participant marker or use a future time.
  const oldMarker = (await one('select read_at_by_user from public.conversations where id=$1',[conversation])).read_at_by_user[manager];
  await db.query('update public.conversations set read_at_by_user=$1::jsonb where id=$2',
    [JSON.stringify({[manager]:'2099-01-01T00:00:00Z',[customer]:'2099-01-01T00:00:00Z'}),conversation]);
  const markers = (await one('select read_at_by_user from public.conversations where id=$1',[conversation])).read_at_by_user;
  ok(markers[manager] === oldMarker && new Date(markers[customer]).getFullYear() < 2099,'read marker preserves other user and clamps future');
  // The newest 100 messages are shown first; older history is keyset-paged.
  await actor(null, 'postgres');
  await db.query('update public.profiles set full_name=null where id=$1', [customer]);
  await actor(manager);
  ok((await one('select public.list_chat_conversations() as data')).data[0].customer_name === 'Khách hàng', 'legacy unnamed customer cannot break inbox');
  for (let i=0;i<102;i++) await one(send,[conversation,randomUUID(),`History ${i}`]);
  const firstPage = (await one('select public.get_chat_messages($1) as data',[conversation])).data;
  const olderPage = (await one('select public.get_chat_messages($1,$2) as data',[conversation,firstPage.messages[0].id])).data;
  ok(firstPage.messages.length === 100 && firstPage.has_more && olderPage.messages.length === 4 && !olderPage.has_more,'history cursor returns complete non-overlapping pages');
  const ids = new Set([...firstPage.messages,...olderPage.messages].map(m=>m.id));
  ok(ids.size === 104,'history pagination never duplicates a message');
  const readBeforeInsert = (await one('select read_at_by_user from public.conversations where id=$1',[conversation])).read_at_by_user[manager];
  await actor(null, 'postgres');
  const backdated = await one("insert into public.messages(conversation_id,sender_id,client_message_id,body,created_at) values($1,$2,$3,'Late insert','2000-01-01') returning created_at", [conversation,customer,randomUUID()]);
  ok(new Date(backdated.created_at) > new Date(readBeforeInsert),'all message inserts receive server time after the conversation read lock');
  await actor(manager);
  ok((await one('select public.list_chat_conversations() as data')).data[0].unread_count === 1,'an inserted message cannot hide behind the previous read watermark');
  await actor(null,'anon');
  await denied('select public.list_chat_conversations()',[],'42501');
  await denied(saveSql,command,'42501');
  console.log(`PASS: ${assertions} database checks (roles, Auth trigger, atomic stock, stale writes, idempotency, chat privacy/read markers).`);
} catch (error) {
  console.error(`Database test failed: ${error.code ?? error.name}: ${error.message}`);
  process.exitCode = 1;
} finally {
  await db.close();
}
