// P04.1 SIMULATION ONLY. Called exclusively by the guarded opt-in runner.
// All business writes are restricted to a new p041_demo schema, never public.
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';

export async function testOutboundCommandsDemo(Client, options, admin, fixture) {
  const id = n => `04190000-0000-0000-0000-${String(n).padStart(12, '0')}`;
  const manager = id(1), shipper = id(2);
  const orders = [10, 11, 12, 13].map(id);
  const tasks = [20, 21, 22, 23].map(id);
  const variants = [30, 31, 32, 33].map(id);
  const a = new Client(options), b = new Client(options);
  const connected = [];
  let installed = false;
  async function begin(client, actor) {
    await client.query('BEGIN');
    // Auth stub + actors table are a demo identity model, NOT Supabase JWT/RLS.
    await client.query("select set_config('request.jwt.claim.sub',$1,true), set_config('request.jwt.claims',$2,true)",
      [actor, JSON.stringify({ sub: actor, role: 'authenticated' })]);
  }
  const call = (client, operation, task, request) => client.query(
    'select p041_demo.command($1,$2::uuid,$3::uuid) result', [operation, task, request]
  ).then(r => r.rows[0].result);
  async function race(actorA, actorB, firstCall, secondCall) {
    await begin(a, actorA);
    await begin(b, actorB);
    const first = await firstCall(a);
    const pid = (await b.query('select pg_backend_pid() pid')).rows[0].pid;
    const pending = secondCall(b).then(value => ({ value }), error => ({ error }));
    let blocked = false;
    for (let i = 0; i < 100; i++) {
      const r = await admin.query('select cardinality(pg_blocking_pids($1)) > 0 blocked', [pid]);
      if (r.rows[0].blocked) { blocked = true; break; }
      await delay(20);
    }
    assert.ok(blocked, 'demo second connection must wait for a real PostgreSQL lock');
    await a.query('COMMIT');
    const second = await pending;
    await b.query(second.error ? 'ROLLBACK' : 'COMMIT');
    return { first, second };
  }
  async function state(index) {
    return (await admin.query(`select t.status task_status,o.status order_status,
      o.attempt_count,v.on_hand::int,v.reserved::int,
      (select count(*)::int from p041_demo.dispatches d where d.order_id=o.id) dispatches,
      (select count(*)::int from p041_demo.tasks x where x.order_id=o.id and x.result is not null) results
      from p041_demo.tasks t join p041_demo.orders o on o.id=t.order_id
      join p041_demo.items i on i.order_id=o.id join p041_demo.variants v on v.id=i.variant_id
      where t.id=$1`, [tasks[index]])).rows[0];
  }
  try {
    await a.connect();
    connected.push(a);
    await b.connect();
    connected.push(b);
    assert.equal((await admin.query("select to_regnamespace('p041_demo') is null clean")).rows[0].clean, true);
    await admin.query('BEGIN');
    await admin.query("SET LOCAL sports_store.fixture_mode = 'not_enabled'");
    await assert.rejects(admin.query(fixture), error =>
      error.code === 'P0001' && error.message === 'P04.1 demo requires guarded p011_ isolated fixture');
    await admin.query('ROLLBACK');
    assert.equal((await admin.query("select to_regnamespace('p041_demo') is null clean")).rows[0].clean, true);
    await admin.query('BEGIN');
    await admin.query(fixture);
    await admin.query('COMMIT');
    installed = true;
    for (const client of [a, b]) {
      await client.query("SET statement_timeout = '8s'");
      await client.query("SET lock_timeout = '5s'");
    }
    await admin.query("insert into p041_demo.actors values($1,'manager'),($2,'shipper')", [manager, shipper]);
    for (let i = 0; i < orders.length; i++) {
      await admin.query("insert into p041_demo.orders values($1,'awaiting_pickup',0)", [orders[i]]);
      await admin.query('insert into p041_demo.variants values($1,10,2)', [variants[i]]);
      await admin.query('insert into p041_demo.items values($1,$2,2)', [orders[i], variants[i]]);
      await admin.query("insert into p041_demo.tasks(id,order_id,shipper_id,status,attempt_number) values($1,$2,$3,'assigned',1)",
        [tasks[i], orders[i], shipper]);
    }

    const cancelWins = await race(manager, shipper,
      c => call(c, 'cancel', tasks[0], id(100)), c => call(c, 'accept', tasks[0], id(101)));
    assert.equal(cancelWins.second.error?.code, '42501');
    assert.equal(cancelWins.second.error?.message, 'FORBIDDEN');
    assert.deepEqual(await state(0), { task_status: 'cancelled', order_status: 'cancelled', attempt_count: 0,
      on_hand: 10, reserved: 0, dispatches: 0, results: 0 });
    console.log(`DEMO RACE cancel wins: ${JSON.stringify(await state(0))}; accept denied after lock wait`);

    const acceptWins = await race(shipper, manager,
      c => call(c, 'accept', tasks[1], id(102)), c => call(c, 'cancel', tasks[1], id(103)));
    assert.equal(acceptWins.second.error?.code, 'P0001');
    assert.equal(acceptWins.second.error?.message, 'CUSTODY_UNRESOLVED');
    assert.deepEqual(await state(1), { task_status: 'accepted', order_status: 'awaiting_pickup', attempt_count: 0,
      on_hand: 8, reserved: 0, dispatches: 1, results: 0 });
    console.log(`DEMO RACE accept wins: ${JSON.stringify(await state(1))}; cancel denied after lock wait`);

    const replayStart = await race(shipper, shipper,
      c => call(c, 'start', tasks[1], id(104)), c => call(c, 'start', tasks[1], id(104)));
    assert.ifError(replayStart.second.error);
    assert.deepEqual(replayStart.first, replayStart.second.value);
    assert.equal((await state(1)).attempt_count, 1);
    console.log(`DEMO RACE same-request start replay: ${JSON.stringify(await state(1))}`);

    const doubleAccept = await race(shipper, shipper,
      c => call(c, 'accept', tasks[2], id(105)), c => call(c, 'accept', tasks[2], id(106)));
    assert.equal(doubleAccept.second.error?.code, 'P0001');
    assert.equal(doubleAccept.second.error?.message, 'STATE_CONFLICT');
    assert.equal((await state(2)).dispatches, 1);
    assert.equal((await state(2)).on_hand, 8);

    await begin(a, shipper);
    await call(a, 'accept', tasks[3], id(107));
    await a.query('COMMIT');
    const doubleStart = await race(shipper, shipper,
      c => call(c, 'start', tasks[3], id(108)), c => call(c, 'start', tasks[3], id(109)));
    assert.equal(doubleStart.second.error?.code, 'P0001');
    assert.equal(doubleStart.second.error?.message, 'CUSTODY_UNRESOLVED');
    assert.equal((await state(3)).attempt_count, 1);
    assert.equal((await state(3)).dispatches, 1);
    assert.equal((await state(3)).results, 0);
    assert.equal((await admin.query('select count(*)::int n from p041_demo.requests')).rows[0].n, 6);
    console.log('outbound_commands_demo_concurrency: PASS (SIMULATION: 5 real lock races; counters/dispatch once; no attempt results)');
  } finally {
    await Promise.allSettled(connected.map(client => client.query('ROLLBACK')));
    await Promise.allSettled(connected.map(client => client.end()));
    await admin.query('ROLLBACK');
    if (installed) {
      // Only the exact schema created above in a verified new fixture database.
      await admin.query('DROP SCHEMA p041_demo CASCADE');
      assert.equal((await admin.query("select to_regnamespace('p041_demo') is null clean")).rows[0].clean, true);
    }
  }
}
