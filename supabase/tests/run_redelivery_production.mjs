// Local PG17 production-function tests; no cloud deployment or Auth simulation claims.
import {readFile,readdir} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';
import {testRedeliveryConcurrency} from './redelivery_production_concurrency.mjs';
const root=resolve(import.meta.dirname,'..');
const require=createRequire(resolve(root,'.temp/p011_pg_runtime/package.json'));
const {Client}=require('pg');
const database=process.argv[2]??`p011_p083_prod_${Date.now()}`;
assert.match(database,/^p011_p083_[a-z0-9_]+$/);
const options={host:'127.0.0.1',port:55439,user:'postgres',database:'postgres'};
const admin=new Client(options); await admin.connect();
try {
 const v=(await admin.query('show server_version')).rows[0].server_version;
 const d=(await admin.query('show data_directory')).rows[0].data_directory;
 assert.ok(v.startsWith('17.'));
 assert.equal(resolve(d).toLowerCase(),resolve(root,'.temp/p011_native_data').toLowerCase());
 await admin.query(`create database "${database}"`);
} finally {await admin.end();}
const c=new Client({...options,database}); await c.connect();
try {
 await c.query("set sports_store.fixture_mode='p011_isolated'");
 await c.query(await readFile(resolve(root,'tests/fixtures/p011_auth_storage.sql.fixture'),'utf8'));
 const files=(await readdir(resolve(root,'migrations'))).filter(x=>x.endsWith('.sql')).sort();
 for(const file of files) await c.query(await readFile(resolve(root,'migrations',file),'utf8'));
 await c.query('begin');
 await c.query(await readFile(resolve(root,'tests/fixtures/p083_redelivery.sql.fixture'),'utf8'));
 const results=await c.query(await readFile(resolve(root,'tests/redelivery_production.sql'),'utf8'));
 assert.equal(results.at(-1).command,'ROLLBACK');
 assert.ok(results.some(x=>x.rows?.some(r=>r.result==='redelivery_production.sql: PASS')));
 console.log(`Production redelivery PASS: ${files.length} migrations, real functions, rollback (${database})`);
 await testRedeliveryConcurrency(Client,{...options,database},c,
   await readFile(resolve(root,'tests/fixtures/p083_redelivery.sql.fixture'),'utf8'));
} finally {await c.query('rollback').catch(()=>{});await c.end();}
