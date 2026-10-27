-- P05.1 production completion contract on the real schema.
-- All fixture rows are rolled back by the runner.
begin;
set constraints all deferred;

create or replace function pg_temp.set_completion_claims(p_user_id uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
  perform set_config('request.jwt.claims',
    case when p_user_id is null then '' else
      jsonb_build_object('sub', p_user_id::text, 'role', 'authenticated', 'aud', 'authenticated')::text
    end, true);
end;
$$;

create or replace function pg_temp.assert_completion(p_label text, p_ok boolean)
returns void language plpgsql as $$
begin
  if coalesce(p_ok, false) is not true then
    raise exception 'P05.1 completion test failed: %', p_label;
  end if;
end;
$$;

create or replace function pg_temp.assert_completion_error(
  p_label text, p_sql text, p_state text, p_message text
) returns void language plpgsql as $$
declare l_state text; l_message text;
begin
  begin execute p_sql;
  exception when others then
    get stacked diagnostics l_state = returned_sqlstate, l_message = message_text;
  end;
  if l_state is distinct from p_state or l_message is distinct from p_message then
    raise exception 'P05.1 error % expected %/% got %/%', p_label, p_state,
      p_message, coalesce(l_state, 'success'), coalesce(l_message, '');
  end if;
end;
$$;

-- Test-only late-fault trigger.  It fires after the completion RPC has
-- written the attempt, task/order/COD state, event, and the first notification
-- row.  The trigger is created inside this transaction and disappears with
-- the rollback at the end of the suite; it is not a production contract.
create or replace function public.p05_test_fail_after_completion_notification()
returns trigger language plpgsql as $$
begin
  if current_setting('p05.test_fault', true) = 'after_notification' then
    raise exception using errcode = 'P0501', message = 'P05_TEST_LATE_FAULT';
  end if;
  return new;
end;
$$;
create trigger p05_test_fail_after_completion_notification
after insert on public.notifications
for each row execute function public.p05_test_fail_after_completion_notification();

insert into auth.users (id, email) values
  ('05150000-0000-0000-0000-000000000001', 'p051-customer@example.invalid'),
  ('05150000-0000-0000-0000-000000000002', 'p051-manager@example.invalid'),
  ('05150000-0000-0000-0000-000000000003', 'p051-shipper@example.invalid'),
  ('05150000-0000-0000-0000-000000000004', 'p051-other@example.invalid'),
  ('05150000-0000-0000-0000-000000000005', 'p051-manager-two@example.invalid');
update public.profiles set role = case
  when id = '05150000-0000-0000-0000-000000000002' then 'manager'::public.user_role
  when id in ('05150000-0000-0000-0000-000000000002', '05150000-0000-0000-0000-000000000005') then 'manager'::public.user_role
  when id in ('05150000-0000-0000-0000-000000000003', '05150000-0000-0000-0000-000000000004') then 'shipper'::public.user_role
  else 'customer'::public.user_role end
where id in ('05150000-0000-0000-0000-000000000001', '05150000-0000-0000-0000-000000000002', '05150000-0000-0000-0000-000000000003', '05150000-0000-0000-0000-000000000004', '05150000-0000-0000-0000-000000000005');

insert into public.categories (id, code, name)
values ('05150000-0000-0000-0000-000000000100', 'P051', 'P05.1 completion');
insert into public.products (id, category_id, name)
values ('05150000-0000-0000-0000-000000000101', '05150000-0000-0000-0000-000000000100', 'P05.1 product');
insert into public.product_variants (id, product_id, sku, label, price_vnd, on_hand, reserved)
values ('05150000-0000-0000-0000-000000000111', '05150000-0000-0000-0000-000000000101', 'P051-01', 'P05.1 variant', 520000, 0, 0);

insert into public.orders (
  id, customer_id, request_id, status, recipient_name, recipient_phone,
  address_detail, latitude, longitude, subtotal_vnd, delivery_attempt_count
) values (
  '05150000-0000-0000-0000-000000000010', '05150000-0000-0000-0000-000000000001',
  '05150000-0000-0000-0000-000000000010', 'delivering', 'P05.1 recipient',
  '0905000001', 'P05.1 Hanoi address', 21.0285, 105.8542, 520000, 1
);
insert into public.order_items (
  id, order_id, product_id, variant_id, product_name, variant_label,
  unit_price_vnd, quantity
) values (
  '05150000-0000-0000-0000-000000000201', '05150000-0000-0000-0000-000000000010',
  '05150000-0000-0000-0000-000000000101', '05150000-0000-0000-0000-000000000111',
  'P05.1 product', 'P05.1 variant', 520000, 1
);
insert into public.inventory_movements (
  variant_id, order_id, event_id, kind, reserved_delta, actor_id, reason
) values (
  '05150000-0000-0000-0000-000000000111', '05150000-0000-0000-0000-000000000010',
  '05150000-0000-0000-0000-000000000301', 'reserve', 1,
  '05150000-0000-0000-0000-000000000002', 'p051 fixture reserve'
);
insert into public.delivery_tasks (
  id, order_id, kind, assigned_shipper_id, assigned_by, status, attempt_number,
  destination_name, destination_phone, destination_address,
  destination_latitude, destination_longitude, amount_to_collect_vnd,
  assigned_at, accepted_at, started_at
) values (
  '05150000-0000-0000-0000-000000000020', '05150000-0000-0000-0000-000000000010',
  'outbound', '05150000-0000-0000-0000-000000000003', '05150000-0000-0000-0000-000000000002',
  'in_transit', 1, 'P05.1 recipient', '0905000001', 'P05.1 Hanoi address',
  21.0285, 105.8542, 550000, clock_timestamp() - interval '90 seconds',
  clock_timestamp() - interval '60 seconds', clock_timestamp() - interval '30 seconds'
);
insert into public.cod_collections (order_id, shipper_id, status, expected_amount_vnd)
values ('05150000-0000-0000-0000-000000000010', '05150000-0000-0000-0000-000000000003', 'uncollected', 550000);

-- Internal dispatch/custody proof seeded by postgres for the production RPC.
insert into public.business_events (
  id, actor_id, subject_type, subject_id, from_state, to_state, reason,
  task_id, request_id
) values (
  '05150000-0000-0000-0000-000000000301', '05150000-0000-0000-0000-000000000003',
  'delivery_task', '05150000-0000-0000-0000-000000000020',
  'awaiting_pickup', 'accepted', 'fixture dispatch',
  '05150000-0000-0000-0000-000000000020', '05150000-0000-0000-0000-000000000301'
);
insert into public.business_events (
  id, actor_id, subject_type, subject_id, from_state, to_state, reason,
  task_id, request_id
) values (
  '05150000-0000-0000-0000-000000000302', '05150000-0000-0000-0000-000000000003',
  'delivery_task', '05150000-0000-0000-0000-000000000020',
  'accepted', 'in_transit', 'fixture dispatch',
  '05150000-0000-0000-0000-000000000020', '05150000-0000-0000-0000-000000000302'
);
insert into public.inventory_movements (
  variant_id, order_id, event_id, kind, on_hand_delta, reserved_delta,
  actor_id, reason
) values (
  '05150000-0000-0000-0000-000000000111', '05150000-0000-0000-0000-000000000010',
  '05150000-0000-0000-0000-000000000302', 'dispatch', -1, -1,
  '05150000-0000-0000-0000-000000000003', 'outbound_dispatch'
);
insert into private.outbound_dispatches (
  order_id, initial_task_id, holder_id, event_id, items_snapshot, dispatched_at
) values (
  '05150000-0000-0000-0000-000000000010', '05150000-0000-0000-0000-000000000020',
  '05150000-0000-0000-0000-000000000003', '05150000-0000-0000-0000-000000000302',
  private.outbound_items_snapshot('05150000-0000-0000-0000-000000000010'), clock_timestamp() - interval '20 seconds'
);
insert into private.outbound_custody_acceptances (
  task_id, order_id, holder_id, dispatch_event_id, accepted_at, attempt_number
) values (
  '05150000-0000-0000-0000-000000000020', '05150000-0000-0000-0000-000000000010',
  '05150000-0000-0000-0000-000000000003', '05150000-0000-0000-0000-000000000302',
  clock_timestamp() - interval '60 seconds', 1
);

select pg_temp.set_completion_claims('05150000-0000-0000-0000-000000000003');
set local role authenticated;

select pg_temp.assert_completion_error('partial cash rejected before completion', $$
  select public.complete_outbound_delivery(
    '05150000-0000-0000-0000-000000000020', '05150000-0000-0000-0000-000000000402', true, 520000
  )
$$, 'PT409', 'AMOUNT_MISMATCH');
select pg_temp.assert_completion_error('false all-items attestation rejected', $$
  select public.complete_outbound_delivery(
    '05150000-0000-0000-0000-000000000020', '05150000-0000-0000-0000-000000000404', false, 550000
  )
$$, '22023', 'INVALID_ARGUMENT');
select pg_temp.assert_completion_error('null all-items attestation rejected', $$
  select public.complete_outbound_delivery(
    '05150000-0000-0000-0000-000000000020', '05150000-0000-0000-0000-000000000405', null, 550000
  )
$$, '22023', 'INVALID_ARGUMENT');

reset role;
update public.delivery_tasks
set status = 'accepted'::public.delivery_task_status
where id = '05150000-0000-0000-0000-000000000020';
set local role authenticated;
select pg_temp.assert_completion_error('wrong task state rejected', $$
  select public.complete_outbound_delivery(
    '05150000-0000-0000-0000-000000000020', '05150000-0000-0000-0000-000000000406', true, 550000
  )
$$, 'PT409', 'STATE_CONFLICT');
reset role;
update public.delivery_tasks
set status = 'in_transit'::public.delivery_task_status
where id = '05150000-0000-0000-0000-000000000020';
update public.inventory_movements
set reserved_delta = 0
where event_id = '05150000-0000-0000-0000-000000000302'
  and kind = 'dispatch'::public.inventory_movement_kind;
set local role authenticated;
select pg_temp.assert_completion_error('tampered dispatch proof rejected', $$
  select public.complete_outbound_delivery(
    '05150000-0000-0000-0000-000000000020', '05150000-0000-0000-0000-000000000407', true, 550000
  )
$$, 'PT409', 'ITEMS_MISMATCH');
reset role;
update public.inventory_movements
set reserved_delta = -1
where event_id = '05150000-0000-0000-0000-000000000302'
  and kind = 'dispatch'::public.inventory_movement_kind;
set local role authenticated;

-- Damage/loss reported after start invalidates custody before completion.  The
-- completion RPC must fail closed and leave no attempt, money, event,
-- notification, or private idempotency/result ledger row behind.
reset role;
savepoint p051_poststart_damage;
insert into public.business_events (
  actor_id, subject_type, subject_id, task_id, incident_kind, request_id, reason
) values (
  '05150000-0000-0000-0000-000000000003', 'delivery_task',
  '05150000-0000-0000-0000-000000000020',
  '05150000-0000-0000-0000-000000000020', 'damaged',
  '05150000-0000-0000-0000-000000000410', 'P05.1 test-only post-start damage'
);
set local role authenticated;
select pg_temp.set_completion_claims('05150000-0000-0000-0000-000000000003');
select pg_temp.assert_completion_error('post-start damage blocks completion', $$
  select public.complete_outbound_delivery(
    '05150000-0000-0000-0000-000000000020',
    '05150000-0000-0000-0000-000000000410', true, 550000
  )
$$, 'PT409', 'CUSTODY_UNRESOLVED');
reset role;
select pg_temp.assert_completion('damage rejection writes nothing',
  (select status = 'in_transit' and completed_at is null
     from public.delivery_tasks
    where id = '05150000-0000-0000-0000-000000000020')
  and (select status = 'delivering' and delivered_at is null
     from public.orders
    where id = '05150000-0000-0000-0000-000000000010')
  and (select status = 'uncollected' and collected_amount_vnd = 0
             and received_amount_vnd = 0 and collected_by is null
             and collected_at is null
     from public.cod_collections
    where order_id = '05150000-0000-0000-0000-000000000010')
  and not exists (select 1 from public.delivery_attempts
                   where task_id = '05150000-0000-0000-0000-000000000020')
  and not exists (select 1 from public.notifications
                   where subject_id = '05150000-0000-0000-0000-000000000020')
  and not exists (select 1 from private.outbound_completion_results
                   where task_id = '05150000-0000-0000-0000-000000000020')
  and not exists (select 1 from private.outbound_completion_requests
                   where task_id = '05150000-0000-0000-0000-000000000020')
  and (select count(*) = 1 and bool_and(incident_kind = 'damaged'::public.delivery_incident_kind)
         from public.business_events
        where request_id = '05150000-0000-0000-0000-000000000410'));
rollback to savepoint p051_poststart_damage;
release savepoint p051_poststart_damage;

reset role;
savepoint p051_poststart_loss;
insert into public.business_events (
  actor_id, subject_type, subject_id, task_id, incident_kind, request_id, reason
) values (
  '05150000-0000-0000-0000-000000000003', 'delivery_task',
  '05150000-0000-0000-0000-000000000020',
  '05150000-0000-0000-0000-000000000020', 'lost',
  '05150000-0000-0000-0000-000000000411', 'P05.1 test-only post-start loss'
);
set local role authenticated;
select pg_temp.set_completion_claims('05150000-0000-0000-0000-000000000003');
select pg_temp.assert_completion_error('post-start loss blocks completion', $$
  select public.complete_outbound_delivery(
    '05150000-0000-0000-0000-000000000020',
    '05150000-0000-0000-0000-000000000411', true, 550000
  )
$$, 'PT409', 'CUSTODY_UNRESOLVED');
reset role;
select pg_temp.assert_completion('loss rejection writes nothing',
  (select status = 'in_transit' and completed_at is null
     from public.delivery_tasks
    where id = '05150000-0000-0000-0000-000000000020')
  and (select status = 'delivering' and delivered_at is null
     from public.orders
    where id = '05150000-0000-0000-0000-000000000010')
  and (select status = 'uncollected' and collected_amount_vnd = 0
             and received_amount_vnd = 0 and collected_by is null
             and collected_at is null
     from public.cod_collections
    where order_id = '05150000-0000-0000-0000-000000000010')
  and not exists (select 1 from public.delivery_attempts
                   where task_id = '05150000-0000-0000-0000-000000000020')
  and not exists (select 1 from public.notifications
                   where subject_id = '05150000-0000-0000-0000-000000000020')
  and not exists (select 1 from private.outbound_completion_results
                   where task_id = '05150000-0000-0000-0000-000000000020')
  and not exists (select 1 from private.outbound_completion_requests
                   where task_id = '05150000-0000-0000-0000-000000000020')
  and (select count(*) = 1 and bool_and(incident_kind = 'lost'::public.delivery_incident_kind)
         from public.business_events
        where request_id = '05150000-0000-0000-0000-000000000411'));
rollback to savepoint p051_poststart_loss;
release savepoint p051_poststart_loss;

-- Raise after the first notification insert, when all business writes above
-- are already staged.  A function exception must roll back every affected
-- table and both private ledgers, not merely suppress the notification.
set local role authenticated;
select pg_temp.set_completion_claims('05150000-0000-0000-0000-000000000003');
select set_config('p05.test_fault', 'after_notification', true);
select pg_temp.assert_completion_error('late injected fault rolls back atomically', $$
  select public.complete_outbound_delivery(
    '05150000-0000-0000-0000-000000000020',
    '05150000-0000-0000-0000-000000000409', true, 550000
  )
$$, 'P0501', 'P05_TEST_LATE_FAULT');
select set_config('p05.test_fault', '', true);
reset role;
select pg_temp.assert_completion('late fault rolls back all writes',
  (select status = 'in_transit' and completed_at is null
     from public.delivery_tasks
    where id = '05150000-0000-0000-0000-000000000020')
  and (select status = 'delivering' and delivered_at is null
     from public.orders
    where id = '05150000-0000-0000-0000-000000000010')
  and (select status = 'uncollected' and collected_amount_vnd = 0
             and received_amount_vnd = 0 and collected_by is null
             and collected_at is null
     from public.cod_collections
    where order_id = '05150000-0000-0000-0000-000000000010')
  and not exists (select 1 from public.delivery_attempts
                   where task_id = '05150000-0000-0000-0000-000000000020')
  and not exists (select 1 from public.notifications
                   where subject_id = '05150000-0000-0000-0000-000000000020')
  and not exists (select 1 from public.business_events
                   where request_id = '05150000-0000-0000-0000-000000000409')
  and not exists (select 1 from private.outbound_completion_results
                   where task_id = '05150000-0000-0000-0000-000000000020')
  and not exists (select 1 from private.outbound_completion_requests
                   where task_id = '05150000-0000-0000-0000-000000000020'));

select pg_temp.assert_completion('success response',
  (public.complete_outbound_delivery(
    '05150000-0000-0000-0000-000000000020', '05150000-0000-0000-0000-000000000401', true, 550000
  )->>'task_status') = 'delivered');
reset role;
select pg_temp.assert_completion('server full COD',
  (select collected_amount_vnd = 550000 and status = 'collected'::public.cod_status from public.cod_collections where order_id = '05150000-0000-0000-0000-000000000010'));
select pg_temp.assert_completion('one success attempt',
  (select count(*) = 1 and bool_and(result = 'success'::public.delivery_attempt_result) from public.delivery_attempts where task_id = '05150000-0000-0000-0000-000000000020'));
select pg_temp.assert_completion('customer and manager notification',
  (select count(*) = (select count(*) + 1 from public.profiles where role = 'manager')
   from public.notifications where subject_id = '05150000-0000-0000-0000-000000000020'));
reset role;
select pg_temp.assert_completion('event marker and UUID-only linkage',
  (select reason = 'delivery_completed' and subject_type = 'delivery_task'
      and subject_id = task_id and request_id = '05150000-0000-0000-0000-000000000401'
   from public.business_events
   where task_id = '05150000-0000-0000-0000-000000000020'
     and reason = 'delivery_completed'));
select pg_temp.assert_completion('exact notification recipients and safe payload',
  (select count(*) = (select count(*) + 1 from public.profiles where role = 'manager')
      and bool_and(subject_type = 'delivery_task'
                   and subject_id = '05150000-0000-0000-0000-000000000020'
                   and title = 'Giao hàng thành công'
                   and body = 'Đơn hàng đã được giao thành công và thu đủ COD.'
                   and position('0905' in body) = 0)
   from public.notifications
   where event_id = (select id from public.business_events where request_id = '05150000-0000-0000-0000-000000000401')));
select pg_temp.assert_completion('recipient set is customer plus current managers',
  (select array_agg(recipient_id order by recipient_id) =
      (select array_agg(id order by id) from public.profiles
       where role = 'manager' or id = '05150000-0000-0000-0000-000000000001'::uuid)
   from public.notifications
   where event_id = (select id from public.business_events where request_id = '05150000-0000-0000-0000-000000000401')));
set local role authenticated;
set local role authenticated;
select pg_temp.assert_completion('same request replay',
  (public.complete_outbound_delivery(
    '05150000-0000-0000-0000-000000000020', '05150000-0000-0000-0000-000000000401', true, 550000
  )->>'task_status') = 'delivered');
reset role;
select pg_temp.assert_completion('replay does not duplicate',
  (select (select count(*) from public.delivery_attempts where task_id = '05150000-0000-0000-0000-000000000020') = 1
    and (select count(*) from public.notifications where subject_id = '05150000-0000-0000-0000-000000000020') =
      (select count(*) + 1 from public.profiles where role = 'manager')));

select pg_temp.assert_completion_error('mismatched replay', $$
  select public.complete_outbound_delivery(
    '05150000-0000-0000-0000-000000000020', '05150000-0000-0000-0000-000000000401', true, 520000
  )
$$, 'PT409', 'IDEMPOTENCY_CONFLICT');
select pg_temp.assert_completion_error('invalid amount on completed task', $$
  select public.complete_outbound_delivery(
    '05150000-0000-0000-0000-000000000020', '05150000-0000-0000-0000-000000000402', true, 520000
  )
$$, 'PT409', 'STATE_CONFLICT');

reset role;
select pg_temp.set_completion_claims('05150000-0000-0000-0000-000000000004');
set local role authenticated;
select pg_temp.assert_completion_error('wrong shipper denied', $$
  select public.complete_outbound_delivery(
    '05150000-0000-0000-0000-000000000020', '05150000-0000-0000-0000-000000000403', true, 550000
  )
$$, '42501', 'NOT_FOUND_OR_FORBIDDEN');
reset role;
select pg_temp.set_completion_claims('05150000-0000-0000-0000-000000000002');
set local role authenticated;
select pg_temp.assert_completion_error('manager denied', $$
  select public.complete_outbound_delivery(
    '05150000-0000-0000-0000-000000000020', '05150000-0000-0000-0000-000000000408', true, 550000
  )
$$, '42501', 'PERMISSION_DENIED');

select 'outbound_completion_production.sql: PASS' as result;
rollback;
