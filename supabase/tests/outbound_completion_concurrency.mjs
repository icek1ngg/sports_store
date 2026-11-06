// P05.1 CONTRACT FIXTURE ONLY. Never imported by Flutter or deployed to Supabase.
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';

export async function testOutboundCompletionConcurrency(Client, options, admin, fixture) {
  const id = n => `05190000-0000-0000-0000-${String(n).padStart(12, '0')}`;
  const customer = id(1), manager = id(2), shipper = id(3);
  const orders = [10, 11, 12, 13, 14].map(id);
  const tasks = [20, 21, 22, 23, 24].map(id);
  const a = new Client(options), b = new Client(options), connected = [];
  let installed = false;
  const complete = (client, task, request, amount = 550000) => client.query(
    'select p051_fixture.complete_outbound_delivery($1::uuid,$2::uuid,true,$3::bigint) result',
    [task, request, amount]).then(r => r.rows[0].result);
  async function begin(client) {
    await client.query('BEGIN');
    await client.query("select set_config('request.jwt.claim.sub',$1,true), set_config('request.jwt.claims',$2,true)",
      [shipper, JSON.stringify({ sub: shipper, role: 'authenticated' })]);
  }
  async function race(firstCall, secondCall) {
    await begin(a);
    await begin(b);
    const first = await firstCall(a);
    const pid = (await b.query('select pg_backend_pid() pid')).rows[0].pid;
    const pending = secondCall(b).then(value => ({ value }), error => ({ error }));
    let blocked = false;
    for (let i = 0; i < 100; i++) {
      if ((await admin.query('select cardinality(pg_blocking_pids($1)) > 0 blocked', [pid])).rows[0].blocked) {
        blocked = true; break;
      }
      await delay(20);
    }
    assert.ok(blocked, 'completion contender must actually wait on a PostgreSQL transaction lock');
    await a.query('COMMIT');
    const second = await pending;
    await b.query(second.error ? 'ROLLBACK' : 'COMMIT');
    return { first, second };
  }
  async function snapshot(index) {
    return (await admin.query(`select t.status task_status,o.status order_status,
      o.total_cod_vnd::int,c.status cod_status,c.collected_amount_vnd::int,
      (select count(*)::int from p051_fixture.attempts x where x.task_id=t.id) attempts,
      (select count(*)::int from p051_fixture.events e where e.task_id=t.id) events,
      (select count(*)::int from p051_fixture.notifications n join p051_fixture.events e on e.id=n.event_id where e.task_id=t.id) notifications
      from p051_fixture.tasks t join p051_fixture.orders o on o.id=t.order_id
      join p051_fixture.cod c on c.order_id=o.id where t.id=$1`, [tasks[index]])).rows[0];
  }
  try {
    for (const client of [a, b]) {
      await client.connect(); connected.push(client);
      await client.query("SET statement_timeout='8s'");
      await client.query("SET lock_timeout='5s'");
    }
    assert.equal((await admin.query("select to_regnamespace('p051_fixture') is null clean")).rows[0].clean, true);
    await admin.query('BEGIN');
    await admin.query("SET LOCAL sports_store.fixture_mode='disabled'");
    await assert.rejects(admin.query(fixture), error => error.code === 'P0001');
    await admin.query('ROLLBACK');
    assert.equal((await admin.query("select to_regnamespace('p051_fixture') is null clean")).rows[0].clean, true);
    await admin.query('BEGIN');
    await admin.query(fixture);
    await admin.query('COMMIT');
    installed = true;
    await admin.query("insert into p051_fixture.actors values($1,'customer'),($2,'manager'),($3,'shipper')", [customer, manager, shipper]);
    for (let i = 0; i < tasks.length; i++) {
      await admin.query(`insert into p051_fixture.orders(id,customer_id,subtotal_vnd,delivery_fee_vnd,status,attempt_count)
        values($1,$2,520000,30000,'delivering',1)`, [orders[i], customer]);
      await admin.query(`insert into p051_fixture.tasks(id,order_id,shipper_id,kind,status,attempt_number,amount_to_collect_vnd,accepted_at,started_at)
        values($1,$2,$3,'outbound','in_transit',1,550000,now(),now())`, [tasks[i], orders[i], shipper]);
      await admin.query(`insert into p051_fixture.cod(order_id,shipper_id,status,expected_amount_vnd,collected_amount_vnd)
        values($1,$2,'uncollected',550000,0)`, [orders[i], shipper]);
      await admin.query('insert into p051_fixture.custody(task_id,holder_id,dispatch_proof) values($1,$2,true)', [tasks[i], shipper]);
      // Explicit fixture recipients, not a stakeholder-approved notification policy.
      await admin.query('insert into p051_fixture.recipients(order_id,recipient_id) values($1,$2),($1,$3)', [orders[i], customer, manager]);
    }
    for (const client of connected) {
      // A result-slot contender only: NOT the future failed-delivery RPC or workflow.
      await client.query(`create function pg_temp.claim_failed_result_for_test(p_task uuid) returns void
        language plpgsql security invoker set search_path='' as $$
        declare t p051_fixture.tasks%rowtype; oid uuid; os text;
        begin
          select order_id into oid from p051_fixture.tasks where id=p_task;
          select status into os from p051_fixture.orders where id=oid for update;
          select * into t from p051_fixture.tasks where id=p_task for update;
          if t.shipper_id is distinct from auth.uid() then raise exception using errcode='42501',message='FORBIDDEN'; end if;
          if os<>'delivering' or t.status<>'in_transit' or exists(select 1 from p051_fixture.attempts where task_id=p_task) then
            raise exception using errcode='P0001',message='STATE_CONFLICT'; end if;
          insert into p051_fixture.attempts(task_id,order_id,attempt_number,result,shipper_id)
            values(t.id,t.order_id,t.attempt_number,'failed',t.shipper_id);
          update p051_fixture.tasks set status='failed' where id=p_task;
        end $$`);
    }
    const failedClaim = (client, task) => client.query('select pg_temp.claim_failed_result_for_test($1::uuid)', [task]);

    const replay = await race(c => complete(c, tasks[0], id(100)), c => complete(c, tasks[0], id(100)));
    assert.ifError(replay.second.error);
    assert.deepEqual(replay.first, replay.second.value);
    const duplicate = await race(c => complete(c, tasks[1], id(101)), c => complete(c, tasks[1], id(102)));
    assert.equal(duplicate.second.error?.code, 'P0001');
    assert.equal(duplicate.second.error?.message, 'STATE_CONFLICT');
    const successWins = await race(c => complete(c, tasks[2], id(103)), c => failedClaim(c, tasks[2]));
    assert.equal(successWins.second.error?.code, 'P0001');
    assert.equal(successWins.second.error?.message, 'STATE_CONFLICT');
    const failureWins = await race(c => failedClaim(c, tasks[3]), c => complete(c, tasks[3], id(104)));
    assert.equal(failureWins.second.error?.code, 'P0001');
    assert.equal(failureWins.second.error?.message, 'STATE_CONFLICT');
    const mismatch = await race(c => complete(c, tasks[4], id(105)), c => complete(c, tasks[4], id(105), 520000));
    assert.equal(mismatch.second.error?.code, 'P0001');
    assert.equal(mismatch.second.error?.message, 'IDEMPOTENCY_CONFLICT');
    for (const i of [0, 1, 2, 4]) {
      assert.deepEqual(await snapshot(i), { task_status: 'delivered', order_status: 'delivered', total_cod_vnd: 550000,
        cod_status: 'collected', collected_amount_vnd: 550000, attempts: 1, events: 1, notifications: 2 });
    }
    assert.deepEqual(await snapshot(3), { task_status: 'failed', order_status: 'delivering', total_cod_vnd: 550000,
      cod_status: 'uncollected', collected_amount_vnd: 0, attempts: 1, events: 0, notifications: 0 });
    assert.equal((await admin.query('select count(*)::int n from p051_fixture.requests')).rows[0].n, 4);
    console.log(`P05.1 FIXTURE complete: ${JSON.stringify(await snapshot(0))}`);
    console.log('outbound_completion_concurrency: PASS (FIXTURE ONLY: 5 real lock races; failure contender is only a result-slot test stub)');
  } finally {
    await Promise.allSettled(connected.map(client => client.query('ROLLBACK')));
    await Promise.allSettled(connected.map(client => client.end()));
    await admin.query('ROLLBACK');
    if (installed) {
      await admin.query('DROP SCHEMA p051_fixture CASCADE');
      assert.equal((await admin.query("select to_regnamespace('p051_fixture') is null clean")).rows[0].clean, true);
    }
  }
}
