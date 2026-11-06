// P08.1 real multi-connection races.  The caller owns the isolated native
// PG17 database; this module only creates committed, uniquely-prefixed fixture
// rows and removes them in finally.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';

const ids = {
  customer: '08250000-0000-0000-0000-000000000001',
  manager: '08250000-0000-0000-0000-000000000002',
  shipperA: '08250000-0000-0000-0000-000000000003',
  shipperB: '08250000-0000-0000-0000-000000000004',
  shipperC: '08250000-0000-0000-0000-000000000005',
  category: '08250000-0000-0000-0000-000000000100',
  product: '08250000-0000-0000-0000-000000000101',
  variant: '08250000-0000-0000-0000-000000000111',
  order: '08250000-0000-0000-0000-000000000010',
  orderItem: '08250000-0000-0000-0000-000000000201',
  request: '08250000-0000-0000-0000-000000000210',
  requestKey: '08250000-0000-0000-0000-000000000410',
  assignKeyB: '08250000-0000-0000-0000-000000000411',
  assignKeyC: '08250000-0000-0000-0000-000000000412',
  collectKey: '08250000-0000-0000-0000-000000000510',
  failKey: '08250000-0000-0000-0000-000000000511',
  returnItem: '08250000-0000-0000-0000-000000000301',
};

const uuidArray = Object.values(ids).filter(value => /^[0-9a-f-]{36}$/i.test(value));

function claimSql(userId) {
  return {
    text: `select set_config('request.jwt.claim.sub', $1, true),
                  set_config('request.jwt.claims', $2, true)`,
    values: [userId, JSON.stringify({
      sub: userId,
      role: 'authenticated',
      aud: 'authenticated',
    })],
  };
}

async function invoke(client, userId, text, values) {
  await client.query('begin');
  try {
    await client.query('set local role authenticated');
    await client.query(claimSql(userId));
    const result = await client.query(text, values);
    await client.query('commit');
    return result.rows[0];
  } catch (error) {
    await client.query('rollback');
    throw error;
  }
}

function errorCode(error) {
  return `${error.code || ''}/${error.message || ''}`;
}

async function seed(admin) {
  await admin.query('begin');
  try {
    await admin.query(`
      insert into auth.users (id, email) values
        ($1, 'p081-race-customer@example.invalid'),
        ($2, 'p081-race-manager@example.invalid'),
        ($3, 'p081-race-shipper-a@example.invalid'),
        ($4, 'p081-race-shipper-b@example.invalid'),
        ($5, 'p081-race-shipper-c@example.invalid')
    `, [ids.customer, ids.manager, ids.shipperA, ids.shipperB, ids.shipperC]);
    await admin.query(`
      update public.profiles set role = case
        when id = $1 then 'manager'::public.user_role
        when id in ($2, $3, $4) then 'shipper'::public.user_role
        else 'customer'::public.user_role end
      where id in ($5, $1, $2, $3, $4)
    `, [ids.manager, ids.shipperA, ids.shipperB, ids.shipperC, ids.customer]);
    await admin.query(`
      insert into public.categories (id, code, name)
      values ($1, 'P081RACE', 'P08.1 race')
    `, [ids.category]);
    await admin.query(`
      insert into public.products (id, category_id, name)
      values ($1, $2, 'P08.1 race product')
    `, [ids.product, ids.category]);
    await admin.query(`
      insert into public.product_variants
        (id, product_id, sku, label, price_vnd, on_hand, reserved, damaged)
      values ($1, $2, 'P081-RACE-01', 'P08.1 race variant', 100000, 10, 0, 0)
    `, [ids.variant, ids.product]);
    await admin.query(`
      insert into public.orders (
        id, customer_id, request_id, status, recipient_name, recipient_phone,
        address_detail, latitude, longitude, subtotal_vnd, delivery_attempt_count,
        delivered_at
      ) values (
        $1, $2, $1, 'delivered', 'P081 race recipient', '0908200001',
        'P081 race address', 21.0285, 105.8542, 100000, 0,
        clock_timestamp() - interval '1 day'
      )
    `, [ids.order, ids.customer]);
    await admin.query(`
      insert into public.order_items (
        id, order_id, product_id, variant_id, product_name, variant_label,
        unit_price_vnd, quantity
      ) values ($1, $2, $3, $4, 'P08.1 race product', 'P08.1 race variant', 100000, 1)
    `, [ids.orderItem, ids.order, ids.product, ids.variant]);
    await admin.query(`
      insert into public.return_requests (
        id, order_id, customer_id, request_id, status, reason, description,
        video_object_path, decision_reason, decision_at, decided_by
      ) values (
        $1, $2, $3, $4, 'awaiting_return_pickup', 'defective',
        'P08.1 committed race fixture', '082/customer/race.mp4',
        'approved return pickup fixture', clock_timestamp() - interval '5 minutes', $5
      )
    `, [ids.request, ids.order, ids.customer, ids.request, ids.manager]);
    await admin.query(`
      insert into public.return_items (
        id, return_request_id, order_id, order_item_id, actual_item_name,
        quantity_to_collect, quantity_collected
      ) values ($1, $2, $3, $4, 'P08.1 race item', 1, 0)
    `, [ids.returnItem, ids.request, ids.order, ids.orderItem]);
    await admin.query(`
      insert into public.cod_collections (order_id, status, expected_amount_vnd)
      select id, 'uncollected'::public.cod_status, total_cod_vnd
      from public.orders where id = $1
    `, [ids.order]);
    await admin.query('commit');
  } catch (error) {
    await admin.query('rollback');
    throw error;
  }
}

async function cleanup(admin) {
  await admin.query('begin');
  try {
    // Return-pickup ledgers are intentionally private and append-only.  The
    // user triggers are disabled only for this uniquely-prefixed cleanup; the
    // production database and its triggers are never changed by the runner.
    const privateTables = (await admin.query(`
      select c.relname,
             exists(select 1 from information_schema.columns
                    where table_schema='private' and table_name=c.relname
                      and column_name='order_id') as has_order,
             exists(select 1 from information_schema.columns
                    where table_schema='private' and table_name=c.relname
                      and column_name='task_id') as has_task,
             exists(select 1 from information_schema.columns
                    where table_schema='private' and table_name=c.relname
                      and column_name='return_request_id') as has_request
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'private' and c.relkind = 'r'
        and (c.relname ilike '%return%pickup%'
             or c.relname ilike '%pickup%return%')
    `)).rows;
    const taskRows = (await admin.query(
      'select id from public.delivery_tasks where return_request_id = $1',
      [ids.request],
    )).rows.map(row => row.id);
    for (const row of privateTables) {
      const name = row.relname.replaceAll('"', '""');
      await admin.query(`alter table private."${name}" disable trigger user`);
      try {
        if (row.has_request) {
          await admin.query(`delete from private."${name}" where return_request_id = $1`, [ids.request]);
        } else if (row.has_task && taskRows.length) {
          await admin.query(`delete from private."${name}" where task_id = any($1::uuid[])`, [taskRows]);
        } else if (row.has_order) {
          await admin.query(`delete from private."${name}" where order_id = $1`, [ids.order]);
        }
      } finally {
        await admin.query(`alter table private."${name}" enable trigger user`);
      }
    }
    await admin.query('delete from public.notifications where subject_id = $1', [ids.request]);
    if (taskRows.length) {
      await admin.query('delete from public.notifications where subject_id = any($1::uuid[])', [taskRows]);
      await admin.query('delete from public.business_events where task_id = any($1::uuid[])', [taskRows]);
      await admin.query('delete from public.delivery_attempts where task_id = any($1::uuid[])', [taskRows]);
    }
    await admin.query('delete from public.business_events where subject_id = $1', [ids.request]);
    await admin.query('delete from public.delivery_tasks where return_request_id = $1', [ids.request]);
    await admin.query('delete from public.inventory_movements where return_request_id = $1', [ids.request]);
    await admin.query('delete from public.return_items where return_request_id = $1', [ids.request]);
    await admin.query('delete from public.cod_collections where order_id = $1', [ids.order]);
    await admin.query('delete from public.return_requests where id = $1', [ids.request]);
    await admin.query('delete from public.order_items where order_id = $1', [ids.order]);
    await admin.query('delete from public.orders where id = $1', [ids.order]);
    await admin.query('delete from public.product_variants where id = $1', [ids.variant]);
    await admin.query('delete from public.products where id = $1', [ids.product]);
    await admin.query('delete from public.categories where id = $1', [ids.category]);
    await admin.query('delete from auth.users where id = any($1::uuid[])', [
      [ids.customer, ids.manager, ids.shipperA, ids.shipperB, ids.shipperC],
    ]);
    await admin.query('commit');
  } catch (error) {
    await admin.query('rollback');
    throw error;
  }
}

export async function testReturnPickupProductionConcurrency(Client, options, admin) {
  const connected = [
    new Client({ ...options }),
    new Client({ ...options }),
  ];
  await Promise.all(connected.map(client => client.connect()));
  try {
    await seed(admin);

    const assignmentSql = `select public.assign_return_pickup_task(
      $1::uuid, $2::uuid, $3::uuid, $4::uuid, $5::uuid
    ) as response`;
    // A privileged future approval writer must not append an unapproved item
    // while assignment's snapshot is still uncommitted. The trigger must wait
    // on the request before inspecting the now-committed snapshot.
    await connected[0].query('begin');
    await connected[0].query('set local role authenticated');
    await connected[0].query(claimSql(ids.manager));
    await connected[0].query(assignmentSql,
      [ids.request, ids.shipperA, ids.requestKey, null, null]);
    const inserted = connected[1].query(`
      insert into public.return_items
        (return_request_id,order_id,actual_item_name,quantity_to_collect)
      values($1,$2,'Unapproved concurrent item',1)
    `, [ids.request, ids.order]).then(() => null, error => error);
    let waiting = false;
    for (let i = 0; i < 100 && !waiting; i++) {
      waiting = (await admin.query(`select exists(select 1 from pg_stat_activity
        where pid=$1 and wait_event_type='Lock') waiting`,
      [connected[1].processID])).rows[0].waiting;
      if (!waiting) await new Promise(resolve => setTimeout(resolve, 10));
    }
    // Always release the assignment transaction before checking the waiter.
    await connected[0].query('commit');
    const insertError = await inserted;
    assert.equal(waiting, true, 'plan insert did not serialize with assignment');
    assert.equal(insertError?.code, 'PT409');
    assert.equal(insertError?.message, 'PLAN_IMMUTABLE');
    const assignmentRace = await Promise.allSettled(connected.map(client => invoke(
      client,
      ids.manager,
      assignmentSql,
      [ids.request, ids.shipperA, ids.requestKey, null, null],
    )));
    assert.equal(assignmentRace.filter(result => result.status === 'fulfilled').length, 2,
      `same-key assignment race: ${assignmentRace.map(result => result.status === 'rejected' ? errorCode(result.reason) : 'ok').join(', ')}`);
    const assignmentResponses = assignmentRace.map(result => result.value.response);
    assert.deepEqual(assignmentResponses[0], assignmentResponses[1], 'same-key assignment responses differ');
    const taskId = assignmentResponses[0].task_id;
    assert.match(taskId, /^[0-9a-f-]{36}$/i);

    const taskState = (await admin.query(
      'select status, assigned_shipper_id from public.delivery_tasks where id = $1',
      [taskId],
    )).rows[0];
    assert.equal(taskState.status, 'assigned');
    assert.equal(taskState.assigned_shipper_id, ids.shipperA);

    // Both manager calls use the same expected (old) shipper.  Exactly one
    // CAS reassignment may win; the stale writer must not change it again.
    const reassignmentRace = await Promise.allSettled([
      invoke(connected[0], ids.manager, assignmentSql,
        [ids.request, ids.shipperB, ids.assignKeyB, taskId, ids.shipperA]),
      invoke(connected[1], ids.manager, assignmentSql,
        [ids.request, ids.shipperC, ids.assignKeyC, taskId, ids.shipperA]),
    ]);
    assert.equal(reassignmentRace.filter(result => result.status === 'fulfilled').length, 1,
      `CAS reassignment race did not have one winner: ${reassignmentRace.map(result => result.status === 'rejected' ? errorCode(result.reason) : 'ok').join(', ')}`);
    assert.equal(reassignmentRace.filter(result => result.status === 'rejected').length, 1);
    const currentShipper = (await admin.query(
      'select assigned_shipper_id from public.delivery_tasks where id = $1', [taskId],
    )).rows[0].assigned_shipper_id;
    assert.ok([ids.shipperB, ids.shipperC].includes(currentShipper));

    const collectSql = `select public.collect_return_items(
      $1::uuid, $2::uuid, $3::jsonb
    ) as response`;
    const failSql = `select public.fail_return_pickup_task(
      $1::uuid, $2::uuid, $3::text, $4::text
    ) as response`;
    const racePayload = JSON.stringify([{ return_item_id: ids.returnItem, quantity: 1 }]);
    const collectAndFail = await Promise.allSettled([
      invoke(connected[0], currentShipper, collectSql, [taskId, ids.collectKey, racePayload]),
      invoke(connected[1], currentShipper, failSql, [taskId, ids.failKey, 'unreachable', 'P081 race']),
    ]);
    assert.equal(collectAndFail.filter(result => result.status === 'fulfilled').length, 1,
      `collect/fail race had unexpected outcomes: ${collectAndFail.map(result => result.status === 'rejected' ? errorCode(result.reason) : 'ok').join(', ')}`);
    assert.equal(collectAndFail.filter(result => result.status === 'rejected').length, 1);
    const finalState = (await admin.query(`
      select t.status task_status, r.status return_status,
             t.accepted_at, t.started_at, o.delivery_attempt_count,
             (select count(*) from public.delivery_attempts a where a.task_id=t.id) attempts
      from public.delivery_tasks t
      join public.return_requests r on r.id=t.return_request_id
      join public.orders o on o.id=t.order_id
      where t.id=$1
    `, [taskId])).rows[0];
    assert.ok(['failed', 'in_transit'].includes(finalState.task_status));
    if (finalState.task_status === 'in_transit') {
      assert.equal(finalState.return_status, 'returning_to_store');
      assert.ok(finalState.accepted_at);
      assert.ok(finalState.started_at);
      assert.equal(finalState.accepted_at.getTime(), finalState.started_at.getTime());
    } else {
      assert.equal(finalState.return_status, 'awaiting_return_pickup');
      assert.equal(finalState.accepted_at, null);
      assert.equal(finalState.started_at, null);
    }
    assert.equal(Number(finalState.delivery_attempt_count), 0);
    assert.equal(Number(finalState.attempts), 0);
    let handoverTask = taskId;
    if (finalState.task_status === 'failed') {
      const next = await invoke(connected[0],ids.manager,assignmentSql,
        [ids.request,currentShipper,randomUUID(),taskId,currentShipper]);
      handoverTask=next.response.task_id;
      await invoke(connected[0],currentShipper,collectSql,[handoverTask,randomUUID(),racePayload]);
    }
    const handoverSql='select public.report_return_pickup_handover($1::uuid,$2::uuid,$3::jsonb) response';
    const handoverKey=randomUUID();
    const reports=await Promise.all(connected.map(client=>invoke(client,currentShipper,
      handoverSql,[handoverTask,handoverKey,racePayload])));
    assert.deepEqual(reports[0].response,reports[1].response,'handover replay race differs');
    const evidence=(await admin.query(`select
      (select count(*) from private.return_pickup_handover_reports where task_id=$1) reports,
      (select count(*) from public.business_events where task_id=$1 and reason='return_pickup_handover_reported') events,
      (select count(*) from public.notifications where event_id=$2) notifications,
      (select status from public.delivery_tasks where id=$1) task_status,
      (select status from public.return_requests where id=$3) return_status`,
      [handoverTask,reports[0].response.event_id,ids.request])).rows[0];
    assert.equal(Number(evidence.reports),1); assert.equal(Number(evidence.events),1);
    assert.equal(Number(evidence.notifications),1);
    assert.equal(evidence.task_status,'in_transit');
    assert.equal(evidence.return_status,'returning_to_store');
    console.log('return_pickup_production_concurrency: PASS (assignment, CAS, collect/fail, exactly-once handover race)');
  } finally {
    await Promise.allSettled(connected.map(client => client.end()));
    await cleanup(admin);
  }
}

