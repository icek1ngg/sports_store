// P06.3 native isolated-fixture test.  This exercises the real PostgreSQL RPC
// on two authenticated connections; it is not a cloud/Supabase deployment
// test and must never be run against a production database.
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';

export async function testCodReceiptConcurrency(Client, options, admin) {
  const id = n => `06300000-0000-0000-0000-${String(n).padStart(12, '0')}`;
  const customer = id(1);
  const managerA = id(2);
  const managerB = id(3);
  const shipper = id(4);
  const users = [customer, managerA, managerB, shipper];
  const orders = [10, 11, 12, 13, 14, 15, 16, 17].map(id);
  const sameIdOrder = orders[0];
  const raceOrder = orders[1];
  const partialOrder = orders[2];
  const deniedOrder = orders[3];
  const rollbackOrder = orders[4];
  const uncollectedOrder = orders[5];
  const forcedRollbackOrder = orders[6];
  const identicalOrder = orders[7];
  const sameRequest = id(100);
  const raceRequestA = id(101);
  const raceRequestB = id(102);
  const partialRequest = id(103);
  const deniedRequest = id(104);
  const rollbackRequest = id(105);
  const uncollectedRequest = id(106);
  const rollbackWaiterRequest = id(107);
  const forcedRollbackRequest = id(108);
  const identicalRequest = id(109);
  const a = new Client(options);
  const b = new Client(options);

  const connect = async client => {
    await client.connect();
    // A hung contender is a test failure, not an indefinitely running fixture.
    await client.query("SET statement_timeout = '8s'");
    await client.query("SET lock_timeout = '5s'");
  };

  async function begin(client, actor) {
    await client.query('BEGIN');
    await client.query('SET LOCAL ROLE authenticated');
    await client.query(
      "select set_config('request.jwt.claim.sub', $1, true), set_config('request.jwt.claims', $2, true)",
      [actor, JSON.stringify({ sub: actor, role: 'authenticated', aud: 'authenticated' })],
    );
  }

  const confirm = (client, orderId, amount, requestId) => client.query(
    'select public.confirm_cod_received($1::uuid, $2::bigint, $3::uuid) as result',
    [orderId, amount, requestId],
  ).then(result => result.rows[0].result);

  async function blockedRace(firstActor, secondActor, firstCall, secondCall) {
    await begin(a, firstActor);
    await begin(b, secondActor);
    const first = await firstCall(a);
    const pid = (await b.query('select pg_backend_pid() as pid')).rows[0].pid;
    // Attach rejection immediately.  A rejected SQL promise must not become an
    // unhandled rejection while the first transaction is deliberately held.
    const pending = secondCall(b).then(value => ({ value }), error => ({ error }));
    let blocked = false;
    for (let i = 0; i < 150; i++) {
      const row = (await admin.query(
        'select cardinality(pg_blocking_pids($1)) > 0 as blocked', [pid],
      )).rows[0];
      if (row.blocked) {
        blocked = true;
        break;
      }
      await delay(20);
    }
    assert.ok(blocked, 'second confirm must actually wait on a PostgreSQL transaction lock');
    await a.query('COMMIT');
    const second = await pending;
    await b.query(second.error ? 'ROLLBACK' : 'COMMIT');
    return { first, second };
  }

  function assertBusinessError(outcome, messages) {
    assert.ok(outcome?.error, `expected business error ${messages.join(' / ')}`);
    assert.equal(outcome.error.code, 'PT409', 'business conflict HTTP/SQL contract');
    assert.ok(messages.includes(outcome.error.message),
      `unexpected business error ${outcome.error.message}`);
  }

  async function snapshot(orderId) {
    const { rows } = await admin.query(`
      select c.status::text,
             c.expected_amount_vnd::bigint,
             c.collected_amount_vnd::bigint,
             c.received_amount_vnd::bigint,
             c.received_by::text,
             c.received_at,
             c.handed_over_at,
             (select count(*)::int from private.cod_receipt_requests r
               where r.order_id = $1) as receipt_ledger_rows,
             (select count(*)::int from public.business_events e
               where e.subject_id = $1) as event_rows,
             (select count(*)::int from public.notifications n
               join public.business_events e on e.id = n.event_id
               where e.subject_id = $1) as notification_rows
        from public.cod_collections c
       where c.order_id = $1`, [orderId]);
    assert.equal(rows.length, 1);
    return rows[0];
  }

  async function sideEffects(orderId) {
    const { rows } = await admin.query(`
      select e.id::text as event_id, n.id::text as notification_id,
             n.recipient_id::text as notification_recipient
        from public.business_events e
        left join public.notifications n on n.event_id = e.id
       where e.subject_id = $1`, [orderId]);
    return rows;
  }

  async function installRollbackTrigger() {
    await admin.query(`
      create or replace function public.p063_fail_cod_notification()
      returns trigger
      language plpgsql
      security definer
      set search_path = pg_catalog
      as $$
      begin
        raise exception using errcode = 'P0001', message = 'P063_FORCED_ROLLBACK';
      end
      $$;
      drop trigger if exists p063_fail_cod_notification on public.notifications;
      create trigger p063_fail_cod_notification
      before insert on public.notifications
      for each row execute function public.p063_fail_cod_notification();
    `);
  }

  async function removeRollbackTrigger() {
    await admin.query('drop trigger if exists p063_fail_cod_notification on public.notifications');
    await admin.query('drop function if exists public.p063_fail_cod_notification()');
  }

  async function installDeferredRollbackTrigger() {
    await admin.query(`
      create or replace function public.p063_fail_cod_commit()
      returns trigger
      language plpgsql
      security definer
      set search_path = pg_catalog
      as $$
      begin
        if coalesce(current_setting('p063.fail_cod_commit', true), 'off') = 'on' then
          raise exception using errcode = 'P0001', message = 'P063_DEFERRED_ROLLBACK';
        end if;
        return null;
      end
      $$;
      drop trigger if exists p063_fail_cod_commit on public.notifications;
      create constraint trigger p063_fail_cod_commit
      after insert on public.notifications
      deferrable initially deferred
      for each row execute function public.p063_fail_cod_commit();
    `);
  }

  async function removeDeferredRollbackTrigger() {
    await admin.query('drop trigger if exists p063_fail_cod_commit on public.notifications');
    await admin.query('drop function if exists public.p063_fail_cod_commit()');
  }

  // The first transaction has a deferred constraint failure. It therefore
  // holds the order lock until COMMIT, where it rolls back; the waiter then
  // acquires the same lock and is allowed to create the sole receipt.
  async function rollbackWinnerWaiterRace() {
    await begin(a, managerA);
    await begin(b, managerB);
    await a.query("select set_config('p063.fail_cod_commit', 'on', true)");
    const first = await confirm(a, rollbackOrder, 550000, rollbackRequest);
    const pid = (await b.query('select pg_backend_pid() as pid')).rows[0].pid;
    const pending = confirm(b, rollbackOrder, 550000, rollbackWaiterRequest)
      .then(value => ({ value }), error => ({ error }));
    let blocked = false;
    for (let i = 0; i < 150; i++) {
      const row = (await admin.query(
        'select cardinality(pg_blocking_pids($1)) > 0 as blocked', [pid],
      )).rows[0];
      if (row.blocked) {
        blocked = true;
        break;
      }
      await delay(20);
    }
    assert.ok(blocked, 'rollback winner waiter must actually wait on the order lock');
    let commitError;
    try {
      await a.query('COMMIT');
    } catch (error) {
      commitError = error;
      await a.query('ROLLBACK').catch(() => {});
    }
    assert.ok(commitError, 'deferred rollback winner must fail at commit');
    const second = await pending;
    await b.query(second.error ? 'ROLLBACK' : 'COMMIT');
    return { first, commitError, second };
  }

  try {
    await Promise.all([connect(a), connect(b)]);

    await admin.query(
      'insert into auth.users(id,email) select x, x::text || $2 from unnest($1::uuid[]) x',
      [users, '@p063.invalid'],
    );
    await admin.query(`
      update public.profiles
         set role = case
           when id = any($1::uuid[]) then 'manager'::public.user_role
           when id = any($2::uuid[]) then 'shipper'::public.user_role
           else 'customer'::public.user_role
         end
       where id = any($3::uuid[])`, [[managerA, managerB], [shipper], users]);

    await admin.query(`
      insert into public.orders(
        id, customer_id, request_id, status, recipient_name, recipient_phone,
        address_detail, latitude, longitude, subtotal_vnd, delivery_fee_vnd
      )
      select x, $2, x, 'delivered'::public.order_status,
             'P063 COD recipient', '0900000063', 'P063 fixture address',
             21.0285, 105.8542, 520000, 30000
        from unnest($1::uuid[]) x`, [orders, customer]);
    await admin.query(`
      insert into public.cod_collections(
        order_id, shipper_id, status, expected_amount_vnd, collected_amount_vnd,
        received_amount_vnd, collected_at, collected_by, created_at, updated_at
      )
       select x, $2::uuid, case when x = $3::uuid then 'uncollected'::public.cod_status
                         else 'collected'::public.cod_status end,
             550000,
             case when x = $3::uuid then 0 else 550000 end,
             0,
             case when x = $3::uuid then null else now() - interval '1 minute' end,
             case when x = $3::uuid then null else $2::uuid end,
             now(), now()
        from unnest($1::uuid[]) x`, [orders, shipper, uncollectedOrder]);

    // Two managers race on the same COD row.  The first transaction owns the
    // order->COD lock; the second is observed blocked, then receives a state
    // conflict after the first commits.
    const race = await blockedRace(
      managerA,
      managerB,
      client => confirm(client, raceOrder, 550000, raceRequestA),
      client => confirm(client, raceOrder, 550000, raceRequestB),
    );
    assert.equal(race.first.order_id, raceOrder);
    assert.equal(race.first.status, 'received');
    assert.equal(Number(race.first.received_amount_vnd), 550000);
    assert.equal(race.first.received_by, managerA);
    assert.ok(race.first.received_at);
    assert.equal(race.first.handed_over_at, race.first.received_at);
    assert.match(race.first.event_id, /^[0-9a-f-]{36}$/i);
    assert.match(race.first.notification_id, /^[0-9a-f-]{36}$/i);
    assertBusinessError(race.second, ['STATE_CONFLICT', 'COD_ALREADY_RECEIVED']);
    const raceSnapshot = await snapshot(raceOrder);
    assert.ok(raceSnapshot.received_at);
    assert.ok(raceSnapshot.handed_over_at);
    assert.equal(raceSnapshot.received_at.getTime(), raceSnapshot.handed_over_at.getTime());
    assert.deepEqual({
      status: raceSnapshot.status,
      expected: Number(raceSnapshot.expected_amount_vnd),
      collected: Number(raceSnapshot.collected_amount_vnd),
      received: Number(raceSnapshot.received_amount_vnd),
      receivedBy: raceSnapshot.received_by,
      ledger: raceSnapshot.receipt_ledger_rows,
      events: raceSnapshot.event_rows,
      notifications: raceSnapshot.notification_rows,
    }, {
      status: 'received', expected: 550000, collected: 550000, received: 550000,
      receivedBy: managerA, ledger: 1, events: 1, notifications: 1,
    });
    assert.deepEqual(await sideEffects(raceOrder), [{
      event_id: race.first.event_id,
      notification_id: race.first.notification_id,
      notification_recipient: shipper,
    }]);

    const identical = await blockedRace(
      managerA, managerA,
      client => confirm(client, identicalOrder, 550000, identicalRequest),
      client => confirm(client, identicalOrder, 550000, identicalRequest),
    );
    assert.ifError(identical.second.error);
    assert.deepEqual(identical.second.value, identical.first,
      'concurrent same-ID/same-payload must replay the identical committed result');
    const identicalSnapshot = await snapshot(identicalOrder);
    assert.equal(identicalSnapshot.receipt_ledger_rows, 1);
    assert.equal(identicalSnapshot.event_rows, 1);
    assert.equal(identicalSnapshot.notification_rows, 1);

    // Same actor/request ID is serialized by the request ledger.  A second
    // identical call must replay the exact result, while a payload mismatch
    // waiting on that same key must fail rather than create another receipt.
    const sameId = await blockedRace(
      managerA,
      managerA,
      client => confirm(client, sameIdOrder, 550000, sameRequest),
      client => confirm(client, sameIdOrder, 549999, sameRequest),
    );
    assert.equal(sameId.first.status, 'received');
    assertBusinessError(sameId.second, ['IDEMPOTENCY_CONFLICT']);
    const replayClient = new Client(options);
    await replayClient.connect();
    try {
      await begin(replayClient, managerA);
      const replay = await confirm(replayClient, sameIdOrder, 550000, sameRequest);
      assert.deepEqual(replay, sameId.first, 'same request/payload must return the prior JSON result');
      await replayClient.query('COMMIT');
    } finally {
      await Promise.allSettled([replayClient.query('ROLLBACK'), replayClient.end()]);
    }
    const sameSnapshot = await snapshot(sameIdOrder);
    assert.equal(sameSnapshot.receipt_ledger_rows, 1);
    assert.equal(sameSnapshot.event_rows, 1);
    assert.equal(sameSnapshot.notification_rows, 1);

    // A partial amount is rejected before any state or ledger mutation.
    await begin(a, managerA);
    const partial = confirm(a, partialOrder, 549999, partialRequest)
      .then(value => ({ value }), error => ({ error }));
    const partialOutcome = await partial;
    assertBusinessError(partialOutcome, ['AMOUNT_MISMATCH']);
    await a.query('ROLLBACK');
    const partialSnapshot = await snapshot(partialOrder);
    assert.equal(partialSnapshot.status, 'collected');
    assert.equal(partialSnapshot.received_amount_vnd, '0');
    assert.equal(partialSnapshot.receipt_ledger_rows, 0);
    assert.equal(partialSnapshot.event_rows, 0);
    assert.equal(partialSnapshot.notification_rows, 0);

    // A shipper cannot confirm by calling the function directly, even when the
    // amount and collection state are otherwise valid.
    await begin(a, shipper);
    const denied = await confirm(a, deniedOrder, 550000, deniedRequest)
      .then(value => ({ value }), error => ({ error }));
    assert.ok(denied.error);
    assert.equal(denied.error.code, '42501');
    await a.query('ROLLBACK');
    const deniedSnapshot = await snapshot(deniedOrder);
    assert.equal(deniedSnapshot.status, 'collected');
    assert.equal(deniedSnapshot.receipt_ledger_rows, 0);

    // An uncollected obligation is not a receivable and cannot be confirmed.
    await begin(a, managerA);
    const uncollected = await confirm(a, uncollectedOrder, 550000, uncollectedRequest)
      .then(value => ({ value }), error => ({ error }));
    assertBusinessError(uncollected, ['STATE_CONFLICT', 'COD_NOT_COLLECTED']);
    await a.query('ROLLBACK');
    const uncollectedSnapshot = await snapshot(uncollectedOrder);
    assert.equal(uncollectedSnapshot.status, 'uncollected');
    assert.equal(uncollectedSnapshot.collected_amount_vnd, '0');
    assert.equal(uncollectedSnapshot.receipt_ledger_rows, 0);

    // The first transaction reaches a deferred constraint failure at COMMIT,
    // while a second manager waits on the order lock.  After the failed commit
    // rolls back, the waiter must win and create the only receipt.
    await installDeferredRollbackTrigger();
    try {
      const rollbackRace = await rollbackWinnerWaiterRace();
      assert.equal(rollbackRace.first.status, 'received');
      assert.equal(rollbackRace.commitError.code, 'P0001');
      assert.equal(rollbackRace.commitError.message, 'P063_DEFERRED_ROLLBACK');
      assert.ifError(rollbackRace.second.error);
      assert.equal(rollbackRace.second.value.status, 'received');
      assert.equal(rollbackRace.second.value.received_by, managerB);
    } finally {
      await removeDeferredRollbackTrigger();
    }
    const rollbackSnapshot = await snapshot(rollbackOrder);
    assert.deepEqual({
      status: rollbackSnapshot.status,
      received: Number(rollbackSnapshot.received_amount_vnd),
      receivedBy: rollbackSnapshot.received_by,
      ledger: rollbackSnapshot.receipt_ledger_rows,
      events: rollbackSnapshot.event_rows,
      notifications: rollbackSnapshot.notification_rows,
    }, {
      status: 'received', received: 550000, receivedBy: managerB,
      ledger: 1, events: 1, notifications: 1,
    });

    // Also exercise an immediate side-effect failure.  This proves the
    // database transaction rolls back COD, event, notification and ledger,
    // independently of the deferred-winner race above.
    await installRollbackTrigger();
    try {
      await begin(a, managerA);
      const failed = await confirm(a, forcedRollbackOrder, 550000, forcedRollbackRequest)
        .then(value => ({ value }), error => ({ error }));
      assert.ok(failed.error);
      assert.equal(failed.error.code, 'P0001');
      assert.equal(failed.error.message, 'P063_FORCED_ROLLBACK');
      await a.query('ROLLBACK');
    } finally {
      await removeRollbackTrigger();
    }
    const forcedRollbackSnapshot = await snapshot(forcedRollbackOrder);
    assert.deepEqual({
      status: forcedRollbackSnapshot.status,
      received: Number(forcedRollbackSnapshot.received_amount_vnd),
      receivedBy: forcedRollbackSnapshot.received_by,
      ledger: forcedRollbackSnapshot.receipt_ledger_rows,
      events: forcedRollbackSnapshot.event_rows,
      notifications: forcedRollbackSnapshot.notification_rows,
    }, {
      status: 'collected', received: 0, receivedBy: null,
      ledger: 0, events: 0, notifications: 0,
    });

    console.log('cod_receipt_concurrency: PASS (manager authorization, exact COD, order/COD locking, idempotent replay/mismatch, rollback)');
  } finally {
    await removeRollbackTrigger().catch(() => {});
    await removeDeferredRollbackTrigger().catch(() => {});
    await Promise.allSettled([a.query('ROLLBACK'), b.query('ROLLBACK')]);
    await Promise.allSettled([a.end(), b.end()]);

    // IDs above are unique to a newly created p011 fixture database.  Disable
    // append-only guards only for this precise cleanup transaction; no broad
    // database reset or cloud cleanup is permitted.
    await admin.query('BEGIN');
    try {
      await admin.query("SET LOCAL session_replication_role = 'replica'");
      await admin.query('delete from public.notifications n using public.business_events e where n.event_id=e.id and e.subject_id=any($1::uuid[])', [orders]);
      await admin.query('delete from public.business_events where subject_id=any($1::uuid[])', [orders]);
      await admin.query('delete from private.cod_receipt_requests where order_id=any($1::uuid[])', [orders]);
      await admin.query('delete from public.cod_collections where order_id=any($1::uuid[])', [orders]);
      await admin.query('delete from public.orders where id=any($1::uuid[])', [orders]);
      await admin.query('delete from public.profiles where id=any($1::uuid[])', [users]);
      await admin.query('delete from auth.users where id=any($1::uuid[])', [users]);
      await admin.query('COMMIT');
    } catch (error) {
      await admin.query('ROLLBACK');
      throw error;
    }
  }
}
