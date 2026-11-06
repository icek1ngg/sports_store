// Run only after run_checkout_fixture.mjs creates a new isolated checkout_ database.
// Example: node supabase/tests/catalog_checkout_concurrency.mjs checkout_lock_fixture_01
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { randomUUID } from 'node:crypto';
const require = createRequire(resolve('supabase/.temp/catalog_pg_runtime/package.json'));
const { Client } = require('pg');
const database = process.argv[2];
if (!database || !/^checkout_[a-z0-9_]+$/.test(database)) throw Error('A fresh checkout_ fixture database is required.');
const options={host:'127.0.0.1',port:55441,user:'postgres',database};
const admin=new Client(options), buyer=new Client(options), manager=new Client(options), observer=new Client(options);
const clients=[admin,buyer,manager,observer];
const ids={customer:randomUUID(),manager:randomUUID(),category:randomUUID(),p1:randomUUID(),p2:randomUUID(),request:randomUUID(),save:randomUUID()};
const variants=['91000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000001'];
let pendingManager;
try {
 await Promise.all(clients.map(c=>c.connect()));
 const dir=(await admin.query('show data_directory')).rows[0].data_directory;
 if(resolve(dir).toLowerCase()!==resolve('supabase/.temp/catalog_pg_data').toLowerCase())throw Error('Unexpected fixture path');
 await admin.query('begin');
 await admin.query('insert into auth.users(id,email) values($1,$2),($3,$4)',[ids.customer,'lock-customer-'+ids.customer+'@example.invalid',ids.manager,'lock-manager-'+ids.manager+'@example.invalid']);
 await admin.query("update public.profiles set role='manager' where id=$1",[ids.manager]);
 await admin.query('insert into public.categories(id,code,name) values($1,$2,$3)',[ids.category,'lock-'+ids.category,'Lock review']);
 await admin.query("insert into public.products(id,category_id,name) values($1,$2,'Before manager'),($3,$2,'Second product')",[ids.p1,ids.category,ids.p2]);
 for(let i=0;i<3;i++) await admin.query('insert into public.product_variants(id,product_id,sku,label,price_vnd,on_hand) values($1,$2,$3,$4,100000,10)',[variants[i],i===1?ids.p2:ids.p1,'LOCK-'+variants[i],'Variant '+i]);
 await admin.query('commit');
 const timestamp=(await admin.query('select updated_at::text as updated_at from public.products where id=$1',[ids.p1])).rows[0].updated_at;
 const rows=(await admin.query('select id,sku,label,attributes,price_vnd,on_hand,is_active from public.product_variants where product_id=$1 order by id',[ids.p1])).rows;
 const payload=rows.map(v=>({...v,price_vnd:Number(v.price_vnd),on_hand:Number(v.on_hand),expected_on_hand:Number(v.on_hand)}));
 await buyer.query('begin');
 await buyer.query("set local statement_timeout='4s'");
 await buyer.query('select id from public.product_variants where id=$1 for update',[variants[0]]);
 await buyer.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claims',$2,true)",[ids.customer,JSON.stringify({sub:ids.customer,role:'authenticated'})]);
 await buyer.query('set local role authenticated');
 await manager.query('begin');
 await manager.query("set local statement_timeout='6s'");
 await manager.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claims',$2,true)",[ids.manager,JSON.stringify({sub:ids.manager,role:'authenticated'})]);
 await manager.query('set local role authenticated');
 const managerPid=(await manager.query('select pg_backend_pid() as pid')).rows[0].pid;
 pendingManager=manager.query('select public.save_managed_product($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb) as id',[ids.save,ids.p1,timestamp,'After manager',ids.category,'',null,true,JSON.stringify(payload)]).then(r=>({ok:true,id:r.rows[0].id}),error=>({ok:false,code:error.code,message:error.message}));
 let blocked=false;
 for(let i=0;i<50;i++){if((await observer.query('select cardinality(pg_blocking_pids($1))>0 as blocked',[managerPid])).rows[0].blocked){blocked=true;break;}await new Promise(resolve=>setTimeout(resolve,20));}
 if(!blocked)throw Error('Manager did not wait on checkout variant');
 await observer.query('begin');
 await observer.query('select id from public.products where id=$1 for share nowait',[ids.p1]);
 await observer.query('rollback');
 console.log('PASS: manager waits on variants without holding the product row.');
 const items=variants.map(variant_id=>({variant_id,quantity:1}));
 const placement=(await buyer.query('select public.place_order($1,$2::jsonb,$3,$4,$5,$6,$7) as result',[ids.request,JSON.stringify(items),'Fixture customer','0901234567','Số 1 Tràng Tiền, Hà Nội',21.0285,105.8542])).rows[0].result;
 if(placement.ok!==true)throw Error('Checkout failed: '+JSON.stringify(placement));
 await buyer.query('commit');
 const save=await pendingManager;
 if(!save.ok)throw Error('Manager failed: '+JSON.stringify(save));
 await manager.query('commit');
 const stock=(await admin.query('select reserved,on_hand from public.product_variants where id=any($1::uuid[]) order by id',[variants])).rows;
 if(stock.length!==3||stock.some(v=>v.reserved!=='1'||v.on_hand!=='10'))throw Error('Incorrect reservation: '+JSON.stringify(stock));
 const snapshots=placement.data.items.filter(v=>v.product_id===ids.p1);
 if(snapshots.length!==2||snapshots.some(v=>v.product_name!=='Before manager'))throw Error('Checkout snapshot changed');
 const product=(await admin.query('select name from public.products where id=$1',[ids.p1])).rows[0];
 if(product.name!=='After manager')throw Error('Manager update missing');
 console.log('PASS: actual place_order with three interleaved variants across two products completes concurrently with actual save_managed_product.');
 console.log('PASS: no deadlock; each reservation exactly once; stock unchanged; order snapshots preserve the old catalog name.');
} catch(error){console.error(error);process.exitCode=1;}
finally {
 for(const c of clients){try{await c.query('rollback');}catch{}}
 if(pendingManager)await pendingManager.catch(()=>{});
 await Promise.all(clients.map(c=>c.end().catch(()=>{})));
}