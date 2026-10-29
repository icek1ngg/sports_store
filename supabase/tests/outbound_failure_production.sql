-- P07.1 production failure contract on the real schema.
--
-- This suite is deliberately self-contained and rolls back at the end.  The
-- second outbound attempt is fixture-seeded here because manager retry and
-- custody transfer belong to P07.2; this file tests only the failure write
-- primitive once the task/custody proof already exists.
begin;
set constraints all deferred;

-- Catalog checks complement role/assignment behavioral tests below.
do $$
declare l_table regclass;
begin
  if not exists (
    select 1 from pg_roles r
    where r.rolname = 'sports_store_outbound_failure_writer'
      and not r.rolcanlogin and not r.rolsuper and not r.rolbypassrls
      and not r.rolinherit and not r.rolcreaterole and not r.rolcreatedb
      and not r.rolreplication
  ) or exists (
    select 1 from pg_auth_members m
    join pg_roles granted on granted.oid=m.roleid
    join pg_roles member on member.oid=m.member
    where granted.rolname='sports_store_outbound_failure_writer'
      and member.rolname <> 'postgres'
  ) then raise exception 'Unsafe P07.1 writer role'; end if;
  if not exists (
    select 1 from pg_proc p
    where p.oid='public.fail_delivery_task(uuid,uuid,text,text)'::regprocedure
      and p.prosecdef and p.proconfig @> array['search_path=""']
      and pg_get_userbyid(p.proowner)='sports_store_outbound_failure_writer'
  ) or not has_function_privilege('authenticated',
      'public.fail_delivery_task(uuid,uuid,text,text)','EXECUTE')
    or has_function_privilege('anon',
      'public.fail_delivery_task(uuid,uuid,text,text)','EXECUTE')
    or has_function_privilege('service_role',
      'public.fail_delivery_task(uuid,uuid,text,text)','EXECUTE')
  then raise exception 'Unsafe P07.1 RPC configuration'; end if;
  foreach l_table in array array[
    'private.outbound_failure_requests'::regclass,
    'private.outbound_failure_results'::regclass
  ] loop
    if not exists (select 1 from pg_class c where c.oid=l_table
      and c.relrowsecurity and c.relforcerowsecurity)
      or has_table_privilege('authenticated',l_table,'SELECT,INSERT,UPDATE,DELETE')
      or has_table_privilege('anon',l_table,'SELECT,INSERT,UPDATE,DELETE')
      or has_table_privilege('service_role',l_table,'SELECT,INSERT,UPDATE,DELETE')
    then raise exception 'Unsafe P07.1 ledger configuration'; end if;
  end loop;
end;
$$;

create or replace function pg_temp.set_failure_claims(p_user_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
  perform set_config(
    'request.jwt.claims',
    case when p_user_id is null then '' else
      jsonb_build_object(
        'sub', p_user_id::text,
        'role', 'authenticated',
        'aud', 'authenticated'
      )::text
    end,
    true
  );
end;
$$;

create or replace function pg_temp.assert_failure(
  p_label text,
  p_ok boolean
)
returns void
language plpgsql
as $$
begin
  if coalesce(p_ok, false) is not true then
    raise exception 'P07.1 failure test failed: %', p_label;
  end if;
end;
$$;

create or replace function pg_temp.assert_failure_error(
  p_label text,
  p_sql text,
  p_state text,
  p_message text
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
  if l_state is distinct from p_state or l_message is distinct from p_message then
    raise exception
      'P07.1 failure error % expected %/% got %/%',
      p_label, p_state, p_message, coalesce(l_state, 'success'),
      coalesce(l_message, '');
  end if;
end;
$$;

create or replace function pg_temp.assert_failure_state(
  p_label text,
  p_sql text,
  p_state text
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
      'P07.1 failure state % expected % got %/%',
      p_label, p_state, coalesce(l_state, 'success'), coalesce(l_message, '');
  end if;
end;
$$;

-- A late notification failure must roll back the attempt, state transitions,
-- event, notifications and both private ledgers together.
create or replace function public.p071_test_fail_after_failure_notification()
returns trigger
language plpgsql
as $$
begin
  if current_setting('p071.test_fault', true) = 'after_notification' then
    raise exception using errcode = 'P0711', message = 'P07_TEST_LATE_FAULT';
  end if;
  return new;
end;
$$;
create trigger p071_test_fail_after_failure_notification
after insert on public.notifications
for each row execute function public.p071_test_fail_after_failure_notification();

insert into auth.users (id, email) values
  ('07150000-0000-0000-0000-000000000001', 'p071-customer@example.invalid'),
  ('07150000-0000-0000-0000-000000000002', 'p071-manager@example.invalid'),
  ('07150000-0000-0000-0000-000000000003', 'p071-shipper@example.invalid'),
  ('07150000-0000-0000-0000-000000000004', 'p071-other-shipper@example.invalid'),
  ('07150000-0000-0000-0000-000000000005', 'p071-manager-two@example.invalid');
update public.profiles
set role = case
  when id in (
    '07150000-0000-0000-0000-000000000002',
    '07150000-0000-0000-0000-000000000005'
  ) then 'manager'::public.user_role
  when id in (
    '07150000-0000-0000-0000-000000000003',
    '07150000-0000-0000-0000-000000000004'
  ) then 'shipper'::public.user_role
  else 'customer'::public.user_role
end
where id in (
  '07150000-0000-0000-0000-000000000001',
  '07150000-0000-0000-0000-000000000002',
  '07150000-0000-0000-0000-000000000003',
  '07150000-0000-0000-0000-000000000004',
  '07150000-0000-0000-0000-000000000005'
);

insert into public.categories (id, code, name)
values ('07150000-0000-0000-0000-000000000100', 'P071', 'P07.1 failure');
insert into public.products (id, category_id, name)
values (
  '07150000-0000-0000-0000-000000000101',
  '07150000-0000-0000-0000-000000000100',
  'P07.1 product'
);
insert into public.product_variants (
  id, product_id, sku, label, price_vnd, on_hand, reserved
) values (
  '07150000-0000-0000-0000-000000000111',
  '07150000-0000-0000-0000-000000000101',
  'P071-01', 'P07.1 variant', 520000, 0, 0
);

-- First-attempt fixture: this is the real P07.1 success path.
insert into public.orders (
  id, customer_id, request_id, status, recipient_name, recipient_phone,
  address_detail, latitude, longitude, subtotal_vnd, delivery_attempt_count
) values (
  '07150000-0000-0000-0000-000000000010',
  '07150000-0000-0000-0000-000000000001',
  '07150000-0000-0000-0000-000000000010',
  'delivering', 'P07.1 recipient one', '0907100001',
  'P07.1 Hanoi address one', 21.0285, 105.8542, 520000, 1
);
insert into public.order_items (
  id, order_id, product_id, variant_id, product_name, variant_label,
  unit_price_vnd, quantity
) values (
  '07150000-0000-0000-0000-000000000201',
  '07150000-0000-0000-0000-000000000010',
  '07150000-0000-0000-0000-000000000101',
  '07150000-0000-0000-0000-000000000111',
  'P07.1 product', 'P07.1 variant', 520000, 1
);
insert into public.inventory_movements (
  variant_id, order_id, event_id, kind, reserved_delta, actor_id, reason
) values (
  '07150000-0000-0000-0000-000000000111',
  '07150000-0000-0000-0000-000000000010',
  '07150000-0000-0000-0000-000000000301',
  'reserve', 1, '07150000-0000-0000-0000-000000000002', 'p071 reserve one'
);
insert into public.delivery_tasks (
  id, order_id, kind, assigned_shipper_id, assigned_by, status, attempt_number,
  destination_name, destination_phone, destination_address,
  destination_latitude, destination_longitude, amount_to_collect_vnd,
  assigned_at, accepted_at, started_at
) values (
  '07150000-0000-0000-0000-000000000020',
  '07150000-0000-0000-0000-000000000010',
  'outbound', '07150000-0000-0000-0000-000000000003',
  '07150000-0000-0000-0000-000000000002', 'in_transit', 1,
  'P07.1 recipient one', '0907100001', 'P07.1 Hanoi address one',
  21.0285, 105.8542, 550000,
  clock_timestamp() - interval '90 seconds',
  clock_timestamp() - interval '60 seconds',
  clock_timestamp() - interval '30 seconds'
);
insert into public.cod_collections (order_id, shipper_id, status, expected_amount_vnd)
values (
  '07150000-0000-0000-0000-000000000010',
  '07150000-0000-0000-0000-000000000003', 'uncollected', 550000
);
insert into public.business_events (
  id, actor_id, subject_type, subject_id, from_state, to_state, reason,
  task_id, request_id
) values (
  '07150000-0000-0000-0000-000000000302',
  '07150000-0000-0000-0000-000000000003', 'delivery_task',
  '07150000-0000-0000-0000-000000000020', 'accepted', 'in_transit',
  'fixture dispatch one', '07150000-0000-0000-0000-000000000020',
  '07150000-0000-0000-0000-000000000302'
);
insert into public.inventory_movements (
  variant_id, order_id, event_id, kind, on_hand_delta, reserved_delta,
  actor_id, reason
) values (
  '07150000-0000-0000-0000-000000000111',
  '07150000-0000-0000-0000-000000000010',
  '07150000-0000-0000-0000-000000000302',
  'dispatch', -1, -1, '07150000-0000-0000-0000-000000000003',
  'outbound_dispatch'
);
insert into private.outbound_dispatches (
  order_id, initial_task_id, holder_id, event_id, items_snapshot, dispatched_at
) values (
  '07150000-0000-0000-0000-000000000010',
  '07150000-0000-0000-0000-000000000020',
  '07150000-0000-0000-0000-000000000003',
  '07150000-0000-0000-0000-000000000302',
  private.outbound_items_snapshot('07150000-0000-0000-0000-000000000010'),
  clock_timestamp() - interval '20 seconds'
);
insert into private.outbound_custody_acceptances (
  task_id, order_id, holder_id, dispatch_event_id, accepted_at, attempt_number
) values (
  '07150000-0000-0000-0000-000000000020',
  '07150000-0000-0000-0000-000000000010',
  '07150000-0000-0000-0000-000000000003',
  '07150000-0000-0000-0000-000000000302',
  (select accepted_at from public.delivery_tasks
    where id = '07150000-0000-0000-0000-000000000020'), 1
);

-- Second-attempt fixture: P07.2 would create/reassign this task.  P07.1
-- consumes the already-seeded retry/custody proof and must not create task 2.
insert into public.orders (
  id, customer_id, request_id, status, recipient_name, recipient_phone,
  address_detail, latitude, longitude, subtotal_vnd, delivery_attempt_count
) values (
  '07150000-0000-0000-0000-000000000011',
  '07150000-0000-0000-0000-000000000001',
  '07150000-0000-0000-0000-000000000011',
  'delivering', 'P07.1 recipient two', '0907100002',
  'P07.1 Hanoi address two', 21.0285, 105.8542, 520000, 2
);
insert into public.order_items (
  id, order_id, product_id, variant_id, product_name, variant_label,
  unit_price_vnd, quantity
) values (
  '07150000-0000-0000-0000-000000000211',
  '07150000-0000-0000-0000-000000000011',
  '07150000-0000-0000-0000-000000000101',
  '07150000-0000-0000-0000-000000000111',
  'P07.1 product', 'P07.1 variant', 520000, 1
);
insert into public.inventory_movements (
  variant_id, order_id, event_id, kind, reserved_delta, actor_id, reason
) values (
  '07150000-0000-0000-0000-000000000111',
  '07150000-0000-0000-0000-000000000011',
  '07150000-0000-0000-0000-000000000311',
  'reserve', 1, '07150000-0000-0000-0000-000000000002', 'p071 reserve two'
);
insert into public.delivery_tasks (
  id, order_id, kind, assigned_shipper_id, assigned_by, status, attempt_number,
  destination_name, destination_phone, destination_address,
  destination_latitude, destination_longitude, amount_to_collect_vnd,
  assigned_at, accepted_at, started_at, completed_at, failure_reason
) values (
  '07150000-0000-0000-0000-000000000021',
  '07150000-0000-0000-0000-000000000011',
  'outbound', '07150000-0000-0000-0000-000000000003',
  '07150000-0000-0000-0000-000000000002', 'failed', 1,
  'P07.1 recipient two', '0907100002', 'P07.1 Hanoi address two',
  21.0285, 105.8542, 550000,
  clock_timestamp() - interval '8 minutes',
  clock_timestamp() - interval '7 minutes',
  clock_timestamp() - interval '6 minutes',
  clock_timestamp() - interval '5 minutes',
  'fixture first failure'
), (
  '07150000-0000-0000-0000-000000000022',
  '07150000-0000-0000-0000-000000000011',
  'outbound', '07150000-0000-0000-0000-000000000003',
  '07150000-0000-0000-0000-000000000002', 'in_transit', 2,
  'P07.1 recipient two', '0907100002', 'P07.1 Hanoi address two',
  21.0285, 105.8542, 550000,
  clock_timestamp() - interval '90 seconds',
  clock_timestamp() - interval '60 seconds',
  clock_timestamp() - interval '30 seconds',
  null, null
);
insert into public.delivery_attempts (
  id, task_id, order_id, attempt_number, task_kind, result, reason,
  occurred_at, shipper_id
) values (
  '07150000-0000-0000-0000-000000000221',
  '07150000-0000-0000-0000-000000000021',
  '07150000-0000-0000-0000-000000000011', 1, 'outbound', 'failed',
  'fixture first failure', clock_timestamp() - interval '5 minutes',
  '07150000-0000-0000-0000-000000000003'
);
insert into public.cod_collections (order_id, shipper_id, status, expected_amount_vnd)
values (
  '07150000-0000-0000-0000-000000000011',
  '07150000-0000-0000-0000-000000000003', 'uncollected', 550000
);
insert into public.business_events (
  id, actor_id, subject_type, subject_id, from_state, to_state, reason,
  task_id, request_id
) values (
  '07150000-0000-0000-0000-000000000312',
  '07150000-0000-0000-0000-000000000003', 'delivery_task',
  '07150000-0000-0000-0000-000000000021', 'accepted', 'in_transit',
  'fixture dispatch two', '07150000-0000-0000-0000-000000000021',
  '07150000-0000-0000-0000-000000000312'
);
insert into public.inventory_movements (
  variant_id, order_id, event_id, kind, on_hand_delta, reserved_delta,
  actor_id, reason
) values (
  '07150000-0000-0000-0000-000000000111',
  '07150000-0000-0000-0000-000000000011',
  '07150000-0000-0000-0000-000000000312',
  'dispatch', -1, -1, '07150000-0000-0000-0000-000000000003',
  'outbound_dispatch'
);
insert into private.outbound_dispatches (
  order_id, initial_task_id, holder_id, event_id, items_snapshot, dispatched_at
) values (
  '07150000-0000-0000-0000-000000000011',
  '07150000-0000-0000-0000-000000000021',
  '07150000-0000-0000-0000-000000000003',
  '07150000-0000-0000-0000-000000000312',
  private.outbound_items_snapshot('07150000-0000-0000-0000-000000000011'),
  clock_timestamp() - interval '20 seconds'
);
insert into private.outbound_custody_acceptances (
  task_id, order_id, holder_id, dispatch_event_id, accepted_at, attempt_number
) values
  (
    '07150000-0000-0000-0000-000000000021',
    '07150000-0000-0000-0000-000000000011',
    '07150000-0000-0000-0000-000000000003',
    '07150000-0000-0000-0000-000000000312',
    (select accepted_at from public.delivery_tasks
      where id = '07150000-0000-0000-0000-000000000021'), 1
  ),
  (
    '07150000-0000-0000-0000-000000000022',
    '07150000-0000-0000-0000-000000000011',
    '07150000-0000-0000-0000-000000000003',
    '07150000-0000-0000-0000-000000000312',
    (select accepted_at from public.delivery_tasks
      where id = '07150000-0000-0000-0000-000000000022'), 2
  );

-- Anonymous and malformed calls fail before any business lookup/write.
select pg_temp.set_failure_claims(null);
set local role authenticated;
select pg_temp.assert_failure_error(
  'anonymous failure requires auth',
  $$select public.fail_delivery_task(
    '07150000-0000-0000-0000-000000000020',
    '07150000-0000-0000-0000-000000000401', 'bad_address', null
  )$$,
  '42501', 'AUTH_REQUIRED'
);
select pg_temp.set_failure_claims('07150000-0000-0000-0000-000000000003');
select pg_temp.assert_failure_error(
  'null task rejected',
  $$select public.fail_delivery_task(
    null, '07150000-0000-0000-0000-000000000402', 'bad_address', null
  )$$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_failure_error(
  'null request rejected',
  $$select public.fail_delivery_task(
    '07150000-0000-0000-0000-000000000020', null, 'bad_address', null
  )$$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_failure_error(
  'null reason rejected',
  $$select public.fail_delivery_task(
    '07150000-0000-0000-0000-000000000020',
    '07150000-0000-0000-0000-000000000403', null, null
  )$$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_failure_error(
  'unknown reason rejected',
  $$select public.fail_delivery_task(
    '07150000-0000-0000-0000-000000000020',
    '07150000-0000-0000-0000-000000000404', 'customer_changed_mind', 'x'
  )$$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_failure_error(
  'other without description rejected',
  $$select public.fail_delivery_task(
    '07150000-0000-0000-0000-000000000020',
    '07150000-0000-0000-0000-000000000405', 'other', null
  )$$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_failure_error(
  'other with blank description rejected',
  $$select public.fail_delivery_task(
    '07150000-0000-0000-0000-000000000020',
    '07150000-0000-0000-0000-000000000406', 'other', E'\t\n'
  )$$,
  '22023', 'INVALID_ARGUMENT'
);

-- Direct table access is not a substitute for the transaction RPC.
select pg_temp.assert_failure_state(
  'authenticated cannot read failure result ledger',
  $$select count(*) from private.outbound_failure_results$$,
  '42501'
);
select pg_temp.assert_failure_state(
  'authenticated cannot write delivery task directly',
  $$update public.delivery_tasks set failure_reason = 'bypass'
      where id = '07150000-0000-0000-0000-000000000020'$$,
  '42501'
);

-- All five approved reason codes validate.  Savepoints discard their writes;
-- the later bad_address call is the one durable failure in this transaction.
select pg_temp.set_failure_claims('07150000-0000-0000-0000-000000000003');
savepoint p071_reason_unreachable;
select pg_temp.assert_failure(
  'unreachable accepted',
  (select (public.fail_delivery_task(
    '07150000-0000-0000-0000-000000000020',
    '07150000-0000-0000-0000-000000000407', 'unreachable', null
  )->>'task_status') = 'failed'
   and (public.fail_delivery_task(
    '07150000-0000-0000-0000-000000000020',
    '07150000-0000-0000-0000-000000000407', 'unreachable', null
  )->>'failure_reason_description') is null)
);
rollback to savepoint p071_reason_unreachable;
savepoint p071_reason_reschedule;
select pg_temp.assert_failure(
  'reschedule accepted',
  (select (public.fail_delivery_task(
    '07150000-0000-0000-0000-000000000020',
    '07150000-0000-0000-0000-000000000408', 'reschedule', '   '
  )->>'task_status') = 'failed')
);
rollback to savepoint p071_reason_reschedule;
savepoint p071_reason_bad_address;
select pg_temp.assert_failure(
  'bad_address accepted',
  (select (public.fail_delivery_task(
    '07150000-0000-0000-0000-000000000020',
    '07150000-0000-0000-0000-000000000409', 'bad_address', ''
  )->>'task_status') = 'failed')
);
rollback to savepoint p071_reason_bad_address;
savepoint p071_reason_refusal;
select pg_temp.assert_failure(
  'refusal accepted',
  (select (public.fail_delivery_task(
    '07150000-0000-0000-0000-000000000020',
    '07150000-0000-0000-0000-000000000410', 'refusal', null
  )->>'task_status') = 'failed')
);
rollback to savepoint p071_reason_refusal;
savepoint p071_reason_other;
select pg_temp.assert_failure(
  'other accepted with description',
  (select (public.fail_delivery_task(
    '07150000-0000-0000-0000-000000000020',
    '07150000-0000-0000-0000-000000000411', 'other', '  recipient unavailable  '
  )->>'task_status') = 'failed')
);
rollback to savepoint p071_reason_other;

-- Wrong shipper covers reassignment/current-task ownership.  A manager is not
-- allowed to report on behalf of a shipper, even when the task is visible.
select pg_temp.set_failure_claims('07150000-0000-0000-0000-000000000004');
select pg_temp.assert_failure_error(
  'reassigned/non-current shipper denied',
  $$select public.fail_delivery_task(
    '07150000-0000-0000-0000-000000000020',
    '07150000-0000-0000-0000-000000000412', 'bad_address', 'address issue'
  )$$,
  '42501', 'NOT_FOUND_OR_FORBIDDEN'
);
select pg_temp.set_failure_claims('07150000-0000-0000-0000-000000000002');
select pg_temp.assert_failure_error(
  'manager denied',
  $$select public.fail_delivery_task(
    '07150000-0000-0000-0000-000000000413',
    '07150000-0000-0000-0000-000000000413', 'bad_address', 'address issue'
  )$$,
  '42501', 'PERMISSION_DENIED'
);
reset role;
update public.profiles
set role = 'customer'::public.user_role
where id = '07150000-0000-0000-0000-000000000003';
select pg_temp.set_failure_claims('07150000-0000-0000-0000-000000000003');
set local role authenticated;
select pg_temp.assert_failure_error(
  'lost shipper role denied',
  $$select public.fail_delivery_task(
    '07150000-0000-0000-0000-000000000020',
    '07150000-0000-0000-0000-000000000414', 'bad_address', 'address issue'
  )$$,
  '42501', 'PERMISSION_DENIED'
);
reset role;
update public.profiles
set role = 'shipper'::public.user_role
where id = '07150000-0000-0000-0000-000000000003';

-- Wrong task state is rejected without writing a failure result.
update public.delivery_tasks
set status = 'accepted'::public.delivery_task_status
where id = '07150000-0000-0000-0000-000000000020';
select pg_temp.set_failure_claims('07150000-0000-0000-0000-000000000003');
set local role authenticated;
select pg_temp.assert_failure_state(
  'accepted task rejected',
  $$select public.fail_delivery_task(
    '07150000-0000-0000-0000-000000000020',
    '07150000-0000-0000-0000-000000000415', 'bad_address', 'address issue'
  )$$,
  'PT409'
);
reset role;
update public.delivery_tasks
set status = 'in_transit'::public.delivery_task_status
where id = '07150000-0000-0000-0000-000000000020';

-- A collected/dirty COD row cannot be failed and is restored by savepoint.
savepoint p071_amount_mismatch;
update public.delivery_tasks set amount_to_collect_vnd = 520000
where id = '07150000-0000-0000-0000-000000000020';
set local role authenticated;
select pg_temp.assert_failure_error(
  'task/order COD mismatch rejected',
  $$select public.fail_delivery_task(
    '07150000-0000-0000-0000-000000000020',
    '07150000-0000-0000-0000-000000000420', 'unreachable', null
  )$$,
  'PT409', 'AMOUNT_MISMATCH'
);
reset role;
rollback to savepoint p071_amount_mismatch;

savepoint p071_dirty_cod;
update public.cod_collections
set status = 'collected'::public.cod_status,
    collected_amount_vnd = expected_amount_vnd,
    collected_by = '07150000-0000-0000-0000-000000000003',
    collected_at = clock_timestamp()
where order_id = '07150000-0000-0000-0000-000000000010';
select pg_temp.set_failure_claims('07150000-0000-0000-0000-000000000003');
set local role authenticated;
select pg_temp.assert_failure_state(
  'dirty COD rejected',
  $$select public.fail_delivery_task(
    '07150000-0000-0000-0000-000000000020',
    '07150000-0000-0000-0000-000000000416', 'bad_address', 'address issue'
  )$$,
  'PT409'
);
reset role;
rollback to savepoint p071_dirty_cod;

-- Missing custody proof is fail-closed and leaves all state untouched.
savepoint p071_missing_custody;
alter table private.outbound_custody_acceptances
  disable trigger outbound_custody_append_only;
delete from private.outbound_custody_acceptances
where task_id = '07150000-0000-0000-0000-000000000020';
alter table private.outbound_custody_acceptances
  enable trigger outbound_custody_append_only;
select pg_temp.set_failure_claims('07150000-0000-0000-0000-000000000003');
set local role authenticated;
select pg_temp.assert_failure_error(
  'missing custody rejected',
  $$select public.fail_delivery_task(
    '07150000-0000-0000-0000-000000000020',
    '07150000-0000-0000-0000-000000000417', 'bad_address', 'address issue'
  )$$,
  'PT409', 'CUSTODY_UNRESOLVED'
);
reset role;
rollback to savepoint p071_missing_custody;

-- Inject a failure after the first manager notification.  The exception must
-- roll back all writes rather than leave a task/result half-applied.
select pg_temp.set_failure_claims('07150000-0000-0000-0000-000000000003');
set local role authenticated;
select set_config('p071.test_fault', 'after_notification', true);
select pg_temp.assert_failure_error(
  'late failure fault rolls back',
  $$select public.fail_delivery_task(
    '07150000-0000-0000-0000-000000000020',
    '07150000-0000-0000-0000-000000000418', 'bad_address', 'address issue'
  )$$,
  'P0711', 'P07_TEST_LATE_FAULT'
);
select set_config('p071.test_fault', '', true);
reset role;
select pg_temp.assert_failure(
  'late fault leaves first fixture untouched',
  (select status = 'in_transit' and completed_at is null
     from public.delivery_tasks
    where id = '07150000-0000-0000-0000-000000000020')
  and (select status = 'delivering' and delivery_attempt_count = 1
     from public.orders
    where id = '07150000-0000-0000-0000-000000000010')
  and (select status = 'uncollected' and collected_amount_vnd = 0
             and received_amount_vnd = 0 and collected_by is null
     from public.cod_collections
    where order_id = '07150000-0000-0000-0000-000000000010')
  and not exists (select 1 from public.delivery_attempts
                   where task_id = '07150000-0000-0000-0000-000000000020')
  and not exists (select 1 from public.notifications
                   where subject_id = '07150000-0000-0000-0000-000000000020')
  and not exists (select 1 from public.business_events
                   where request_id = '07150000-0000-0000-0000-000000000418')
  and not exists (select 1 from private.outbound_failure_requests
                   where task_id = '07150000-0000-0000-0000-000000000020')
  and not exists (select 1 from private.outbound_failure_results
                   where task_id = '07150000-0000-0000-0000-000000000020')
);

-- Durable first failure: count remains 1, COD and inventory stay untouched,
-- one failed attempt/result/event is recorded, and only managers are notified.
select pg_temp.set_failure_claims('07150000-0000-0000-0000-000000000003');
set local role authenticated;
select pg_temp.assert_failure(
  'first failure response',
  (select (public.fail_delivery_task(
    '07150000-0000-0000-0000-000000000020',
    '07150000-0000-0000-0000-000000000401', 'bad_address', '  address issue  '
  )->>'task_status') = 'failed')
);
reset role;
select pg_temp.assert_failure(
  'first failure state and unchanged counters',
  (select status = 'failed' and completed_at is not null
      and failure_reason is not null and btrim(failure_reason) <> ''
     from public.delivery_tasks
    where id = '07150000-0000-0000-0000-000000000020')
  and (select status = 'awaiting_redelivery' and delivery_attempt_count = 1
     from public.orders
    where id = '07150000-0000-0000-0000-000000000010')
  and (select status = 'uncollected' and collected_amount_vnd = 0
             and received_amount_vnd = 0 and collected_by is null
     from public.cod_collections
    where order_id = '07150000-0000-0000-0000-000000000010')
  and (select count(*) = 1 and bool_and(
      result = 'failed'::public.delivery_attempt_result
      and failure_reason_code = 'bad_address'
      and failure_reason_description = 'address issue'
      and reason = 'bad_address: address issue'
    )
     from public.delivery_attempts
    where task_id = '07150000-0000-0000-0000-000000000020')
  and (select count(*) = 0
     from public.inventory_movements
    where order_id = '07150000-0000-0000-0000-000000000010'
      and kind not in ('reserve'::public.inventory_movement_kind,
                       'dispatch'::public.inventory_movement_kind))
  and (select on_hand = 0 and reserved = 0
     from public.product_variants
    where id = '07150000-0000-0000-0000-000000000111')
);
select pg_temp.assert_failure(
  'failure event and manager-only recipients',
  (select count(*) = 1 and bool_and(
      reason = 'delivery_failed'
      and subject_type = 'delivery_task'
      and subject_id = task_id
      and task_id = '07150000-0000-0000-0000-000000000020'
      and request_id = id
    )
     from public.business_events
    where task_id = '07150000-0000-0000-0000-000000000020'
      and reason = 'delivery_failed')
  and (select count(*) = (select count(*) from public.profiles where role = 'manager')
          and bool_and(
            p.role = 'manager'::public.user_role
            and n.title = 'Giao hàng thất bại'
            and n.body = 'Một nhiệm vụ giao hàng thất bại cần được xử lý.'
            and position('address issue' in n.body) = 0
          )
     from public.notifications n
     join public.profiles p on p.id = n.recipient_id
    where n.subject_id = '07150000-0000-0000-0000-000000000020')
  and not exists (
    select 1 from public.notifications n
    where n.subject_id = '07150000-0000-0000-0000-000000000020'
      and n.recipient_id = '07150000-0000-0000-0000-000000000001'
  )
);
select pg_temp.assert_failure(
  'separate failure request/result ledgers each have one row',
  (select count(*) = 1 from private.outbound_failure_requests
    where task_id = '07150000-0000-0000-0000-000000000020'
      and reason_code = 'bad_address'
      and description = 'address issue')
  and (select count(*) = 1 from private.outbound_failure_results
    where task_id = '07150000-0000-0000-0000-000000000020'
      and reason_code = 'bad_address'
      and description = 'address issue')
);

-- Same actor/key/payload replays exactly, but a changed payload or a new key
-- after the result is rejected.  A completion call with the same key also
-- cannot turn a failed task into a successful/COD-collected one.
select pg_temp.set_failure_claims('07150000-0000-0000-0000-000000000003');
set local role authenticated;
select pg_temp.assert_failure(
  'same failure request replays response',
  (public.fail_delivery_task(
    '07150000-0000-0000-0000-000000000020',
    '07150000-0000-0000-0000-000000000401', 'bad_address', 'address issue'
  ) ->> 'task_status') = 'failed'
  and (public.fail_delivery_task(
    '07150000-0000-0000-0000-000000000020',
    '07150000-0000-0000-0000-000000000401', 'bad_address', 'address issue'
  ) ->> 'failure_reason_description') = 'address issue'
);
select pg_temp.assert_failure_error(
  'mismatched failure replay rejected',
  $$select public.fail_delivery_task(
    '07150000-0000-0000-0000-000000000020',
    '07150000-0000-0000-0000-000000000401', 'other', 'changed payload'
  )$$,
  'PT409', 'IDEMPOTENCY_CONFLICT'
);
select pg_temp.assert_failure_state(
  'new failure key after result rejected',
  $$select public.fail_delivery_task(
    '07150000-0000-0000-0000-000000000020',
    '07150000-0000-0000-0000-000000000419', 'bad_address', 'address issue'
  )$$,
  'PT409'
);
select pg_temp.assert_failure_error(
  'completion cannot reuse failed request key',
  $$select public.complete_outbound_delivery(
    '07150000-0000-0000-0000-000000000020',
    '07150000-0000-0000-0000-000000000401', true, 550000
  )$$,
  'PT409', 'IDEMPOTENCY_CONFLICT'
);
reset role;
select pg_temp.assert_failure(
  'replay and conflicts do not duplicate side effects',
  (select count(*) = 1 from public.delivery_attempts
    where task_id = '07150000-0000-0000-0000-000000000020')
  and (select count(*) = (select count(*) from public.profiles where role = 'manager')
    from public.notifications
    where subject_id = '07150000-0000-0000-0000-000000000020')
  and (select status = 'uncollected' and collected_amount_vnd = 0
    from public.cod_collections
    where order_id = '07150000-0000-0000-0000-000000000010')
);

-- Durable second failure uses the explicitly seeded attempt-2 task and moves
-- the order to store return without changing the attempt count.
select pg_temp.set_failure_claims('07150000-0000-0000-0000-000000000003');
set local role authenticated;
select pg_temp.assert_failure(
  'second failure response',
  (select (public.fail_delivery_task(
    '07150000-0000-0000-0000-000000000022',
    '07150000-0000-0000-0000-000000000421', 'refusal', 'recipient refused'
  )->>'task_status') = 'failed')
);
reset role;
select pg_temp.assert_failure(
  'second failure reaches store return without incrementing count',
  (select status = 'failed' and completed_at is not null
     from public.delivery_tasks
    where id = '07150000-0000-0000-0000-000000000022')
  and (select status = 'awaiting_store_return' and delivery_attempt_count = 2
     from public.orders
    where id = '07150000-0000-0000-0000-000000000011')
  and (select count(*) = 2 and bool_and(result = 'failed'::public.delivery_attempt_result)
     from public.delivery_attempts
    where order_id = '07150000-0000-0000-0000-000000000011')
  and (select status = 'uncollected' and collected_amount_vnd = 0
     from public.cod_collections
    where order_id = '07150000-0000-0000-0000-000000000011')
  and (select count(*) = (select count(*) from public.profiles where role = 'manager')
     from public.notifications
    where subject_id = '07150000-0000-0000-0000-000000000022')
);
select pg_temp.assert_failure(
  'failure does not create a retry task',
  (select count(*) = 2 from public.delivery_tasks
    where order_id = '07150000-0000-0000-0000-000000000011')
);

select 'outbound_failure_production.sql: PASS' as result;
rollback;
