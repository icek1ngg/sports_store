-- P08.3 isolated redelivery contract tests.
--
-- NOT production/auth/RLS acceptance.  The companion fixture is a
-- transaction-only candidate interface because Sơn has not supplied the
-- production receive_customer_return/inspection immutable proof.  This suite
-- runs after a runner-created BEGIN, exercises p083_fixture.* only, prints the
-- required marker, and ends with ROLLBACK.  It must never be applied to a
-- shared database or Supabase cloud.

create or replace function pg_temp.set_p083_claims(p_user_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
  perform set_config(
    'request.jwt.claims',
    case when p_user_id is null then '' else jsonb_build_object(
      'sub', p_user_id::text,
      'role', 'authenticated',
      'aud', 'authenticated'
    )::text end,
    true
  );
end;
$$;

create or replace function pg_temp.assert_p083(
  p_label text,
  p_ok boolean
)
returns void
language plpgsql
as $$
begin
  if coalesce(p_ok, false) is not true then
    raise exception 'P08.3 redelivery fixture test failed: %', p_label;
  end if;
end;
$$;

create or replace function pg_temp.assert_p083_error(
  p_label text,
  p_sql text,
  p_state text,
  p_message text default null
)
returns void
language plpgsql
as $$
declare
  l_state text;
  l_message text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics
      l_state = returned_sqlstate,
      l_message = message_text;
  end;
  if l_state is distinct from p_state then
    raise exception
      'P08.3 redelivery error % expected SQLSTATE %, got %: %',
      p_label, p_state, coalesce(l_state, 'success'), coalesce(l_message, '');
  end if;
  if p_message is not null and l_message is distinct from p_message then
    raise exception
      'P08.3 redelivery error % expected message %, got %',
      p_label, p_message, coalesce(l_message, '');
  end if;
end;
$$;

create temp table p083_cases (
  case_code text primary key,
  data jsonb not null,
  task_id uuid
) on commit drop;

-- Seed independent cases and exercise the manager create boundary.  The
-- default request is awaiting_redelivery with complete immutable proof.
do $$
declare
  l_valid jsonb;
  l_missing jsonb;
  l_wrong_quantity jsonb;
  l_false jsonb;
  l_failure jsonb;
  l_rollback jsonb;
  l_result jsonb;
  l_create_key uuid := '08350000-0000-0000-0000-000000000101';
begin
  l_valid := p083_fixture.seed_redelivery_case_fixture('valid');
  l_missing := p083_fixture.seed_redelivery_case_fixture('missing-proof', 'missing');
  l_wrong_quantity := p083_fixture.seed_redelivery_case_fixture('wrong-quantity', 'wrong_quantity');
  l_false := p083_fixture.seed_redelivery_case_fixture('complete-false');
  l_failure := p083_fixture.seed_redelivery_case_fixture('failure');
  l_rollback := p083_fixture.seed_redelivery_case_fixture('rollback');

  insert into p083_cases(case_code, data)
  values
    ('valid', l_valid),
    ('missing-proof', l_missing),
    ('wrong-quantity', l_wrong_quantity),
    ('complete-false', l_false),
    ('failure', l_failure),
    ('rollback', l_rollback);

  perform pg_temp.set_p083_claims((l_valid->>'manager_id')::uuid);
  l_result := p083_fixture.create_redelivery_task_fixture(
    (l_valid->>'order_id')::uuid,
    (l_valid->>'return_request_id')::uuid,
    (l_valid->>'shipper_id')::uuid,
    l_create_key
  );
  update p083_cases
  set task_id = (l_result->>'task_id')::uuid
  where case_code = 'valid';
  perform pg_temp.assert_p083('manager creates assigned redelivery task',
    l_result->>'task_status' = 'assigned'
    and l_result->>'return_status' = 'awaiting_redelivery'
    and (l_result->>'attempt_number')::int = 1
    and (l_result->>'amount_to_collect_vnd')::bigint = 0
    and (l_result->>'task_id') is not null);
  perform pg_temp.assert_p083('created task is free and related',
    (select t.kind = 'redelivery'
       and t.status = 'assigned'
       and t.order_id = (l_valid->>'order_id')::uuid
       and t.return_request_id = (l_valid->>'return_request_id')::uuid
       and t.assigned_shipper_id = (l_valid->>'shipper_id')::uuid
       and t.amount_to_collect_vnd = 0
       and t.attempt_number = 1
     from public.delivery_tasks t
     where t.id = (l_result->>'task_id')::uuid));

  -- Same actor/key/payload is a pure ACK replay; it cannot create another task.
  perform pg_temp.assert_p083('create same-key replay',
    p083_fixture.create_redelivery_task_fixture(
      (l_valid->>'order_id')::uuid,
      (l_valid->>'return_request_id')::uuid,
      (l_valid->>'shipper_id')::uuid,
      l_create_key
    ) = l_result);
  perform pg_temp.assert_p083_error('create same-key payload mismatch',
    format($sql$select p083_fixture.create_redelivery_task_fixture(%L::uuid,%L::uuid,%L::uuid,%L::uuid)$sql$,
      l_valid->>'order_id', l_valid->>'return_request_id',
      l_valid->>'alternate_shipper_id', l_create_key),
    'P0001', 'IDEMPOTENCY_CONFLICT');

  perform pg_temp.set_p083_claims((l_valid->>'customer_id')::uuid);
  perform pg_temp.assert_p083_error('customer cannot create redelivery',
    format($sql$select p083_fixture.create_redelivery_task_fixture(%L::uuid,%L::uuid,%L::uuid,%L::uuid)$sql$,
      l_valid->>'order_id', l_valid->>'return_request_id',
      l_valid->>'shipper_id', '08350000-0000-0000-0000-000000000102'),
    '42501', 'PERMISSION_DENIED');

  perform pg_temp.set_p083_claims((l_valid->>'manager_id')::uuid);
  perform pg_temp.assert_p083_error('manager cannot choose customer as shipper',
    format($sql$select p083_fixture.create_redelivery_task_fixture(%L::uuid,%L::uuid,%L::uuid,%L::uuid)$sql$,
      l_valid->>'order_id', l_valid->>'return_request_id',
      l_valid->>'customer_id', '08350000-0000-0000-0000-000000000103'),
    'P0001', 'INVALID_SHIPPER');
  perform pg_temp.assert_p083_error('wrong order/request relation is hidden',
    format($sql$select p083_fixture.create_redelivery_task_fixture(%L::uuid,%L::uuid,%L::uuid,%L::uuid)$sql$,
      l_missing->>'order_id', l_valid->>'return_request_id',
      l_valid->>'shipper_id', '08350000-0000-0000-0000-000000000104'),
    '42501', 'NOT_FOUND_OR_FORBIDDEN');
  perform pg_temp.assert_p083_error('missing immutable receipt proof blocks create',
    format($sql$select p083_fixture.create_redelivery_task_fixture(%L::uuid,%L::uuid,%L::uuid,%L::uuid)$sql$,
      l_missing->>'order_id', l_missing->>'return_request_id',
      l_missing->>'shipper_id', '08350000-0000-0000-0000-000000000105'),
    'P0001', 'PROOF_MISSING_OR_INVALID');
  perform pg_temp.assert_p083_error('incomplete inspection release blocks create',
    format($sql$select p083_fixture.create_redelivery_task_fixture(%L::uuid,%L::uuid,%L::uuid,%L::uuid)$sql$,
      l_wrong_quantity->>'order_id', l_wrong_quantity->>'return_request_id',
      l_wrong_quantity->>'shipper_id', '08350000-0000-0000-0000-000000000106'),
    'P0001', 'PROOF_MISSING_OR_INVALID');
  perform pg_temp.assert_p083_error('second active redelivery task is rejected',
    format($sql$select p083_fixture.create_redelivery_task_fixture(%L::uuid,%L::uuid,%L::uuid,%L::uuid)$sql$,
      l_valid->>'order_id', l_valid->>'return_request_id',
      l_valid->>'shipper_id', '08350000-0000-0000-0000-000000000107'),
    'P0001', 'TASK_CONFLICT');
end;
$$;

-- Seed explicit physical custody, then test shipper/assignment/state/order
-- guards.  This helper is intentionally separate from production accept/start.
do $$
declare
  l_valid jsonb;
  l_false jsonb;
  l_result jsonb;
  l_task uuid;
  l_key uuid := '08350000-0000-0000-0000-000000000201';
begin
  select data into l_valid from p083_cases where case_code = 'valid';
  select data into l_false from p083_cases where case_code = 'complete-false';
  l_task := (select task_id from p083_cases where case_code = 'valid');

  perform pg_temp.set_p083_claims((l_valid->>'alternate_shipper_id')::uuid);
  perform pg_temp.assert_p083_error('other shipper cannot seed custody',
    format($sql$select p083_fixture.seed_redelivery_physical_custody_fixture(%L::uuid,%L::uuid,%L::uuid,%L::uuid)$sql$,
      l_valid->>'order_id', l_valid->>'return_request_id', l_task, l_key),
    '42501', 'NOT_FOUND_OR_FORBIDDEN');

  perform pg_temp.set_p083_claims((l_valid->>'shipper_id')::uuid);
  perform pg_temp.assert_p083_error('wrong order cannot seed custody',
    format($sql$select p083_fixture.seed_redelivery_physical_custody_fixture(%L::uuid,%L::uuid,%L::uuid,%L::uuid)$sql$,
      l_false->>'order_id', l_valid->>'return_request_id', l_task,
      '08350000-0000-0000-0000-000000000202'),
    '42501', 'NOT_FOUND_OR_FORBIDDEN');
  l_result := p083_fixture.seed_redelivery_physical_custody_fixture(
    (l_valid->>'order_id')::uuid,
    (l_valid->>'return_request_id')::uuid,
    l_task,
    l_key
  );
  perform pg_temp.assert_p083('fixture custody moves task to transit',
    l_result->>'task_status' = 'in_transit'
    and l_result->>'return_status' = 'awaiting_redelivery');
  perform pg_temp.assert_p083('custody has exact immutable item receipts',
    (select c.accepted_at = c.started_at
       and c.shipper_id = (l_valid->>'shipper_id')::uuid
       and jsonb_array_length(c.item_receipts) = 2
     from p083_fixture.redelivery_custody c where c.task_id = l_task));
  perform pg_temp.assert_p083('seed same-key replay',
    p083_fixture.seed_redelivery_physical_custody_fixture(
      (l_valid->>'order_id')::uuid,
      (l_valid->>'return_request_id')::uuid,
      l_task,
      l_key
    ) = l_result);
  perform pg_temp.assert_p083_error('seed replay payload mismatch',
    format($sql$select p083_fixture.seed_redelivery_physical_custody_fixture(%L::uuid,%L::uuid,%L::uuid,%L::uuid)$sql$,
      l_valid->>'order_id', l_valid->>'return_request_id', l_task,
      '08350000-0000-0000-0000-000000000203'),
    'P0001', 'STATE_CONFLICT');

  -- complete(false) is rejected without a result ledger or state mutation.
  perform pg_temp.assert_p083_error('complete false is not success',
    format($sql$select p083_fixture.complete_redelivery_fixture(%L::uuid,%L::uuid,%L::uuid,%L::uuid,false)$sql$,
      l_valid->>'order_id', l_valid->>'return_request_id', l_task,
      '08350000-0000-0000-0000-000000000204'),
    'P0001', 'ITEMS_MISMATCH');
  perform pg_temp.assert_p083('complete false leaves transit task open',
    (select t.status = 'in_transit' and r.status = 'awaiting_redelivery'
       and t.completed_at is null and r.closed_at is null
     from public.delivery_tasks t
     join public.return_requests r on r.id = t.return_request_id
     where t.id = l_task));
  perform pg_temp.assert_p083_error('complete wrong order is hidden',
    format($sql$select p083_fixture.complete_redelivery_fixture(%L::uuid,%L::uuid,%L::uuid,%L::uuid,true)$sql$,
      l_false->>'order_id', l_valid->>'return_request_id', l_task,
      '08350000-0000-0000-0000-000000000205'),
    '42501', 'NOT_FOUND_OR_FORBIDDEN');
  perform pg_temp.assert_p083_error('transit task cannot be seeded twice',
    format($sql$select p083_fixture.seed_redelivery_physical_custody_fixture(%L::uuid,%L::uuid,%L::uuid,%L::uuid)$sql$,
      l_valid->>'order_id', l_valid->>'return_request_id', l_task,
      '08350000-0000-0000-0000-000000000206'),
    'P0001', 'STATE_CONFLICT');
  perform pg_temp.assert_p083_error('proof update is immutable',
    format($sql$update p083_fixture.redelivery_item_proofs set quantity_released=0 where return_request_id=%L::uuid$sql$,
      l_valid->>'return_request_id'),
    'P0001', 'IMMUTABLE_FIXTURE_PROOF');
  perform pg_temp.assert_p083_error('custody delete is immutable',
    format($sql$delete from p083_fixture.redelivery_custody where task_id=%L::uuid$sql$,
      l_task),
    'P0001', 'IMMUTABLE_FIXTURE_PROOF');
end;
$$;

-- A plan quantity drift after custody is not silently accepted.  This is a
-- savepoint-only corruption used to exercise the immutable per-item guard.
savepoint p083_item_quantity;
update public.return_items
set quantity_to_collect = 2
where id = (
  select (data->>'item_b_id')::uuid from p083_cases where case_code = 'valid'
);
select pg_temp.assert_p083_error(
  'item quantity drift is rejected',
  format($sql$select p083_fixture.complete_redelivery_fixture(%L::uuid,%L::uuid,%L::uuid,%L::uuid,true)$sql$,
    (select data->>'order_id' from p083_cases where case_code = 'valid'),
    (select data->>'return_request_id' from p083_cases where case_code = 'valid'),
    (select task_id from p083_cases where case_code = 'valid'),
    '08350000-0000-0000-0000-000000000207'),
  'P0001', 'ITEMS_MISMATCH'
);
rollback to savepoint p083_item_quantity;

-- Successful D9 outcome: only task delivered and request closed as
-- rejected_after_inspection.  The order, COD obligation, inventory and
-- outbound-attempt history are snapshots and must remain unchanged.
create temp table p083_valid_before as
select
  o.status as order_status,
  o.delivery_attempt_count,
  to_jsonb(c) as cod_snapshot,
  va.on_hand as variant_a_on_hand,
  va.reserved as variant_a_reserved,
  va.damaged as variant_a_damaged,
  vb.on_hand as variant_b_on_hand,
  vb.reserved as variant_b_reserved,
  vb.damaged as variant_b_damaged,
  (select count(*) from public.delivery_attempts da where da.order_id = o.id)
    as outbound_attempts
from p083_cases x
join public.orders o on o.id = (x.data->>'order_id')::uuid
join public.cod_collections c on c.order_id = o.id
join public.product_variants va on va.id = (x.data->>'variant_a_id')::uuid
join public.product_variants vb on vb.id = (x.data->>'variant_b_id')::uuid
where x.case_code = 'valid';

do $$
declare
  l_case jsonb;
  l_task uuid;
  l_key uuid := '08350000-0000-0000-0000-000000000301';
  l_result jsonb;
begin
  select data, task_id into l_case, l_task from p083_cases where case_code = 'valid';
  perform pg_temp.set_p083_claims((l_case->>'shipper_id')::uuid);
  l_result := p083_fixture.complete_redelivery_fixture(
    (l_case->>'order_id')::uuid, (l_case->>'return_request_id')::uuid,
    l_task, l_key, true);
  perform pg_temp.assert_p083('valid completion maps D9 states',
    l_result->>'task_status' = 'delivered'
    and l_result->>'return_status' = 'rejected_after_inspection'
    and (l_result->>'amount_to_collect_vnd')::bigint = 0);
  perform pg_temp.assert_p083('completion closes request and task only',
    (select t.status = 'delivered' and t.completed_at is not null
       and r.status = 'rejected_after_inspection' and r.closed_at is not null
       and o.status = 'delivered' and o.delivery_attempt_count = 1
     from public.delivery_tasks t
     join public.return_requests r on r.id = t.return_request_id
     join public.orders o on o.id = t.order_id
     where t.id = l_task));
  perform pg_temp.assert_p083('completion has no COD/inventory/outbound mutation',
    (select b.order_status = o.status
       and b.delivery_attempt_count = o.delivery_attempt_count
        and b.cod_snapshot = to_jsonb(c)
       and b.variant_a_on_hand = va.on_hand
       and b.variant_a_reserved = va.reserved
       and b.variant_a_damaged = va.damaged
       and b.variant_b_on_hand = vb.on_hand
       and b.variant_b_reserved = vb.reserved
       and b.variant_b_damaged = vb.damaged
       and b.outbound_attempts = (select count(*) from public.delivery_attempts da
                                  where da.order_id = o.id)
     from p083_valid_before b
     join public.orders o on o.id = (l_case->>'order_id')::uuid
     join public.cod_collections c on c.order_id = o.id
     join public.product_variants va on va.id = (l_case->>'variant_a_id')::uuid
     join public.product_variants vb on vb.id = (l_case->>'variant_b_id')::uuid));
  perform pg_temp.assert_p083('complete same-key replay',
    p083_fixture.complete_redelivery_fixture(
      (l_case->>'order_id')::uuid, (l_case->>'return_request_id')::uuid,
      l_task, l_key, true) = l_result);
  perform pg_temp.assert_p083_error('complete replay payload mismatch',
    format($sql$select p083_fixture.complete_redelivery_fixture(%L::uuid,%L::uuid,%L::uuid,%L::uuid,false)$sql$,
      l_case->>'order_id', l_case->>'return_request_id', l_task, l_key),
    'P0001', 'IDEMPOTENCY_CONFLICT');
  perform pg_temp.assert_p083_error('opposite failure after success is rejected',
    format($sql$select p083_fixture.fail_redelivery_fixture(%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L)$sql$,
      l_case->>'order_id', l_case->>'return_request_id', l_task,
      '08350000-0000-0000-0000-000000000302', 'unreachable'),
    'P0001', 'STATE_CONFLICT');
end;
$$;

-- Failure mapping: both task and request require manager action, custody and
-- the open timestamps remain intact, and no outbound/COD/inventory write is
-- introduced.  A different key cannot subsequently complete the task.
create temp table p083_failure_before as
select
  o.status as order_status,
  o.delivery_attempt_count,
  to_jsonb(c) as cod_snapshot,
  va.on_hand as variant_a_on_hand,
  va.reserved as variant_a_reserved,
  va.damaged as variant_a_damaged,
  vb.on_hand as variant_b_on_hand,
  vb.reserved as variant_b_reserved,
  vb.damaged as variant_b_damaged,
  (select count(*) from public.delivery_attempts da where da.order_id = o.id)
    as outbound_attempts
from p083_cases x
join public.orders o on o.id = (x.data->>'order_id')::uuid
join public.cod_collections c on c.order_id = o.id
join public.product_variants va on va.id = (x.data->>'variant_a_id')::uuid
join public.product_variants vb on vb.id = (x.data->>'variant_b_id')::uuid
where x.case_code = 'failure';

do $$
declare
  l_case jsonb;
  l_create jsonb;
  l_seed jsonb;
  l_fail jsonb;
  l_task uuid;
  l_create_key uuid := '08350000-0000-0000-0000-000000000401';
  l_seed_key uuid := '08350000-0000-0000-0000-000000000402';
  l_fail_key uuid := '08350000-0000-0000-0000-000000000403';
begin
  select data into l_case from p083_cases where case_code = 'failure';
  perform pg_temp.set_p083_claims((l_case->>'manager_id')::uuid);
  l_create := p083_fixture.create_redelivery_task_fixture(
    (l_case->>'order_id')::uuid, (l_case->>'return_request_id')::uuid,
    (l_case->>'shipper_id')::uuid, l_create_key);
  l_task := (l_create->>'task_id')::uuid;
  update p083_cases set task_id = l_task where case_code = 'failure';
  perform pg_temp.set_p083_claims((l_case->>'shipper_id')::uuid);
  l_seed := p083_fixture.seed_redelivery_physical_custody_fixture(
    (l_case->>'order_id')::uuid, (l_case->>'return_request_id')::uuid,
    l_task, l_seed_key);
  perform pg_temp.assert_p083_error('unknown failure reason is rejected',
    format($sql$select p083_fixture.fail_redelivery_fixture(%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L)$sql$,
      l_case->>'order_id', l_case->>'return_request_id', l_task,
      '08350000-0000-0000-0000-000000000406', 'not-a-reason'),
    '22023', 'INVALID_ARGUMENT');
  perform pg_temp.assert_p083_error('other failure requires description',
    format($sql$select p083_fixture.fail_redelivery_fixture(%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L)$sql$,
      l_case->>'order_id', l_case->>'return_request_id', l_task,
      '08350000-0000-0000-0000-000000000407', 'other'),
    '22023', 'INVALID_ARGUMENT');
  l_fail := p083_fixture.fail_redelivery_fixture(
    (l_case->>'order_id')::uuid, (l_case->>'return_request_id')::uuid,
    l_task, l_fail_key, 'other', 'customer unavailable');
  perform pg_temp.assert_p083('failure maps both states to manager action',
    l_fail->>'task_status' = 'manager_action_required'
    and l_fail->>'return_status' = 'manager_action_required'
    and (l_fail->>'custody_open')::boolean
    and (l_fail->>'amount_to_collect_vnd')::bigint = 0);
  perform pg_temp.assert_p083('failure retains open custody and timestamps',
    (select t.status = 'manager_action_required'
       and t.completed_at is null and r.status = 'manager_action_required'
       and r.closed_at is null and c.task_id = t.id
       and c.shipper_id = (l_case->>'shipper_id')::uuid
     from public.delivery_tasks t
     join public.return_requests r on r.id = t.return_request_id
     join p083_fixture.redelivery_custody c on c.task_id = t.id
     where t.id = l_task));
  perform pg_temp.assert_p083('failure has no COD/inventory/outbound mutation',
    (select b.order_status = o.status
       and b.delivery_attempt_count = o.delivery_attempt_count
       and b.cod_snapshot = to_jsonb(c)
       and b.variant_a_on_hand = va.on_hand
       and b.variant_a_reserved = va.reserved
       and b.variant_a_damaged = va.damaged
       and b.variant_b_on_hand = vb.on_hand
       and b.variant_b_reserved = vb.reserved
       and b.variant_b_damaged = vb.damaged
       and b.outbound_attempts = (select count(*) from public.delivery_attempts da
                                  where da.order_id = o.id)
     from p083_failure_before b
     join public.orders o on o.id = (l_case->>'order_id')::uuid
     join public.cod_collections c on c.order_id = o.id
     join public.product_variants va on va.id = (l_case->>'variant_a_id')::uuid
     join public.product_variants vb on vb.id = (l_case->>'variant_b_id')::uuid));
  perform pg_temp.assert_p083('failure same-key replay',
    p083_fixture.fail_redelivery_fixture(
      (l_case->>'order_id')::uuid, (l_case->>'return_request_id')::uuid,
      l_task, l_fail_key, 'other', 'customer unavailable') = l_fail);
  perform pg_temp.assert_p083_error('failure replay payload mismatch',
    format($sql$select p083_fixture.fail_redelivery_fixture(%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L,%L)$sql$,
      l_case->>'order_id', l_case->>'return_request_id', l_task, l_fail_key,
      'other', 'different reason'),
    'P0001', 'IDEMPOTENCY_CONFLICT');
  perform pg_temp.assert_p083_error('complete after failure is rejected',
    format($sql$select p083_fixture.complete_redelivery_fixture(%L::uuid,%L::uuid,%L::uuid,%L::uuid,true)$sql$,
      l_case->>'order_id', l_case->>'return_request_id', l_task,
      '08350000-0000-0000-0000-000000000404'),
    'P0001', 'STATE_CONFLICT');
  perform pg_temp.set_p083_claims((l_case->>'manager_id')::uuid);
  perform pg_temp.assert_p083_error('manager cannot create over open failed custody',
    format($sql$select p083_fixture.create_redelivery_task_fixture(%L::uuid,%L::uuid,%L::uuid,%L::uuid)$sql$,
      l_case->>'order_id', l_case->>'return_request_id', l_case->>'shipper_id',
      '08350000-0000-0000-0000-000000000405'),
    'P0001', 'STATE_CONFLICT');
end;
$$;

-- Inject a test-only AFTER UPDATE fault to prove a late failure rolls back the
-- task/request changes and does not write an outcome ledger.  The trigger is
-- created and removed in this transaction; it is not part of the fixture API.
create or replace function pg_temp.p083_fault_after_task_update()
returns trigger
language plpgsql
as $$
begin
  raise exception using errcode = 'P0001', message = 'P083_TEST_FAULT';
end;
$$;

do $$
declare
  l_case jsonb;
  l_create jsonb;
  l_task uuid;
begin
  select data into l_case from p083_cases where case_code = 'rollback';
  perform pg_temp.set_p083_claims((l_case->>'manager_id')::uuid);
  l_create := p083_fixture.create_redelivery_task_fixture(
    (l_case->>'order_id')::uuid, (l_case->>'return_request_id')::uuid,
    (l_case->>'shipper_id')::uuid,
    '08350000-0000-0000-0000-000000000501');
  l_task := (l_create->>'task_id')::uuid;
  update p083_cases set task_id = l_task where case_code = 'rollback';
  perform pg_temp.set_p083_claims((l_case->>'shipper_id')::uuid);
  perform p083_fixture.seed_redelivery_physical_custody_fixture(
    (l_case->>'order_id')::uuid, (l_case->>'return_request_id')::uuid,
    l_task, '08350000-0000-0000-0000-000000000502');
  execute format(
    'create trigger p083_test_fault after update of status '
    'on public.delivery_tasks for each row when (new.id = %L::uuid) '
    'execute function pg_temp.p083_fault_after_task_update()', l_task);
end;
$$;

savepoint p083_late_fault;
select pg_temp.assert_p083_error(
  'late task write rolls back all redelivery state',
  format($sql$select p083_fixture.fail_redelivery_fixture(%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L,%L)$sql$,
    (select data->>'order_id' from p083_cases where case_code = 'rollback'),
    (select data->>'return_request_id' from p083_cases where case_code = 'rollback'),
    (select task_id from p083_cases where case_code = 'rollback'),
    '08350000-0000-0000-0000-000000000503', 'other', 'late fault'),
  'P0001', 'P083_TEST_FAULT'
);
select pg_temp.assert_p083(
  'late fault leaves task/request/custody and no ledger mutation',
  (select t.status = 'in_transit' and r.status = 'awaiting_redelivery'
      and t.completed_at is null and r.closed_at is null
      and exists (select 1 from p083_fixture.redelivery_custody c where c.task_id = t.id)
      and not exists (select 1 from p083_fixture.request_ledger l
                      where l.request_id = '08350000-0000-0000-0000-000000000503'::uuid)
    from public.delivery_tasks t
    join public.return_requests r on r.id = t.return_request_id
    where t.id = (select task_id from p083_cases where case_code = 'rollback'))
);
rollback to savepoint p083_late_fault;
drop trigger p083_test_fault on public.delivery_tasks;

-- The same rollback case succeeds after the injected error is removed.
do $$
declare
  l_case jsonb;
  l_task uuid;
  l_result jsonb;
begin
  select data, task_id into l_case, l_task from p083_cases where case_code = 'rollback';
  perform pg_temp.set_p083_claims((l_case->>'shipper_id')::uuid);
  l_result := p083_fixture.fail_redelivery_fixture(
    (l_case->>'order_id')::uuid, (l_case->>'return_request_id')::uuid,
    l_task, '08350000-0000-0000-0000-000000000503', 'other', 'late fault');
  perform pg_temp.assert_p083('retry after rollback commits D9 failure',
    l_result->>'task_status' = 'manager_action_required'
    and l_result->>'return_status' = 'manager_action_required');
end;
$$;

select pg_temp.assert_p083(
  'no public P08.3 RPC was added',
  to_regprocedure('public.assign_redelivery_task(uuid,uuid,uuid)') is null
  and to_regprocedure('public.complete_redelivery(uuid,uuid,boolean)') is null
  and to_regprocedure('public.fail_redelivery_task(uuid,uuid,text,text)') is null
);

select 'redelivery_contract_fixture.sql: PASS' as test_marker;
rollback;
