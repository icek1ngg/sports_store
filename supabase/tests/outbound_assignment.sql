-- P03.3 outbound assignment contract.
-- TEST FIXTURE ONLY. The runner executes this file in one transaction and
-- rolls every fixture row back. It intentionally exercises the public RPC as
-- authenticated users; only the fixture setup/inspection uses postgres.

begin;
set constraints all deferred;

create or replace function pg_temp.set_assignment_claims(
  p_user_id uuid,
  p_claimed_role text default 'authenticated'
) returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', p_user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', p_user_id::text,
      'role', p_claimed_role,
      'aud', p_claimed_role
    )::text,
    true
  );
end;
$$;

create or replace function pg_temp.clear_assignment_claims()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
end;
$$;

create or replace function pg_temp.assert_assignment(
  p_label text,
  p_condition boolean
) returns void
language plpgsql
as $$
begin
  if coalesce(p_condition, false) is not true then
    raise exception 'outbound assignment test failed: %', p_label;
  end if;
end;
$$;

create or replace function pg_temp.assert_assignment_error(
  p_label text,
  p_sql text,
  p_state text,
  p_message text default null
) returns void
language plpgsql
as $$
declare
  l_state text;
  l_message text;
begin
  begin
    execute p_sql;
  exception
    when others then
      get stacked diagnostics
        l_state = returned_sqlstate,
        l_message = message_text;
  end;
  if l_state is distinct from p_state then
    raise exception
      'outbound assignment test failed: % (expected SQLSTATE %, got %: %)',
      p_label, p_state, coalesce(l_state, 'success'), coalesce(l_message, '');
  end if;
  if p_message is not null and l_message is distinct from p_message then
    raise exception
      'outbound assignment test failed: % (expected message %, got %)',
      p_label, p_message, coalesce(l_message, '');
  end if;
end;
$$;

-- Server-managed fixture identities. The claim role is deliberately always
-- authenticated in the normal calls; profile.role is the authorization input.
insert into auth.users (id, email)
values
  ('03310000-0000-0000-0000-000000000001'::uuid, 'assignment-customer@example.invalid'),
  ('03310000-0000-0000-0000-000000000002'::uuid, 'assignment-manager@example.invalid'),
  ('03310000-0000-0000-0000-000000000003'::uuid, 'assignment-other-manager@example.invalid'),
  ('03310000-0000-0000-0000-000000000004'::uuid, 'assignment-shipper-a@example.invalid'),
  ('03310000-0000-0000-0000-000000000005'::uuid, 'assignment-shipper-b@example.invalid'),
  ('03310000-0000-0000-0000-000000000006'::uuid, 'assignment-shipper-c@example.invalid');

update public.profiles
set role = case
  when id in (
    '03310000-0000-0000-0000-000000000002'::uuid,
    '03310000-0000-0000-0000-000000000003'::uuid
  ) then 'manager'::public.user_role
  when id in (
    '03310000-0000-0000-0000-000000000004'::uuid,
    '03310000-0000-0000-0000-000000000005'::uuid,
    '03310000-0000-0000-0000-000000000006'::uuid
  ) then 'shipper'::public.user_role
  else 'customer'::public.user_role
end
where id in (
  '03310000-0000-0000-0000-000000000001'::uuid,
  '03310000-0000-0000-0000-000000000002'::uuid,
  '03310000-0000-0000-0000-000000000003'::uuid,
  '03310000-0000-0000-0000-000000000004'::uuid,
  '03310000-0000-0000-0000-000000000005'::uuid,
  '03310000-0000-0000-0000-000000000006'::uuid
);

insert into public.orders (
  id, customer_id, request_id, status, recipient_name, recipient_phone,
  address_detail, latitude, longitude, subtotal_vnd
)
select x, '03310000-0000-0000-0000-000000000001'::uuid, x,
  case when x = '03310000-0000-0000-0000-000000000013'::uuid
    then 'delivered'::public.order_status
    else 'preparing'::public.order_status end,
  'Assignment Recipient', '0900000000', 'Ha Noi assignment fixture',
  21.0285, 105.8542, 100000
from unnest(array[
  '03310000-0000-0000-0000-000000000010'::uuid,
  '03310000-0000-0000-0000-000000000011'::uuid,
  '03310000-0000-0000-0000-000000000012'::uuid,
  '03310000-0000-0000-0000-000000000013'::uuid,
  '03310000-0000-0000-0000-000000000014'::uuid,
  '03310000-0000-0000-0000-000000000015'::uuid,
  '03310000-0000-0000-0000-000000000016'::uuid,
  '03310000-0000-0000-0000-000000000017'::uuid,
  '03310000-0000-0000-0000-000000000018'::uuid,
  '03310000-0000-0000-0000-000000000019'::uuid,
  '03310000-0000-0000-0000-000000000020'::uuid,
  '03310000-0000-0000-0000-000000000021'::uuid,
  '03310000-0000-0000-0000-000000000022'::uuid,
  '03310000-0000-0000-0000-000000000023'::uuid,
  '03310000-0000-0000-0000-000000000024'::uuid,
  '03310000-0000-0000-0000-000000000025'::uuid,
  '03310000-0000-0000-0000-000000000026'::uuid
]::uuid[]) as ids(x);

update public.orders
set status = 'awaiting_pickup'::public.order_status
where id = '03310000-0000-0000-0000-000000000024'::uuid;
update public.orders
set status = 'awaiting_pickup'::public.order_status
where id = '03310000-0000-0000-0000-000000000025'::uuid;

update public.orders
set delivery_attempt_count = 1
where id = '03310000-0000-0000-0000-000000000016'::uuid;

-- A clean uncollected row with a stale expected amount is reconciled to the
-- generated order total (130000 VND), without any caller-supplied amount.
insert into public.cod_collections (
  order_id, shipper_id, status, expected_amount_vnd
) values (
  '03310000-0000-0000-0000-000000000014'::uuid,
  '03310000-0000-0000-0000-000000000004'::uuid,
  'uncollected', 1
);

-- A collected row is historical custody and must never be repaired.
insert into public.cod_collections (
  order_id, shipper_id, status, expected_amount_vnd, collected_amount_vnd,
  collected_by
) values (
  '03310000-0000-0000-0000-000000000015'::uuid,
  '03310000-0000-0000-0000-000000000004'::uuid,
  'collected', 130000, 130000,
  '03310000-0000-0000-0000-000000000004'::uuid
);

-- Existing pending assignment is manager-ready but has not been physically
-- accepted. The expected shipper is NULL for this state.
insert into public.delivery_tasks (
  id, order_id, kind, status, attempt_number, destination_name,
  destination_phone, destination_address, destination_latitude,
  destination_longitude, amount_to_collect_vnd
) values (
  '03310000-0000-0000-0000-000000000101'::uuid,
  '03310000-0000-0000-0000-000000000018'::uuid,
  'outbound', 'pending_assignment', 1, 'Assignment Recipient', '0900000000',
  'Ha Noi assignment fixture', 21.0285, 105.8542, 130000
);

-- This task has custody evidence and is not eligible for reassignment.
insert into public.delivery_tasks (
  id, order_id, kind, assigned_shipper_id, status, attempt_number,
  destination_name, destination_phone, destination_address,
  destination_latitude, destination_longitude, amount_to_collect_vnd,
  assigned_at, accepted_at
) values (
  '03310000-0000-0000-0000-000000000102'::uuid,
  '03310000-0000-0000-0000-000000000019'::uuid,
  'outbound', '03310000-0000-0000-0000-000000000004'::uuid, 'assigned', 1,
  'Assignment Recipient', '0900000000', 'Ha Noi assignment fixture',
  21.0285, 105.8542, 130000, now() - interval '2 minutes', now()
);

-- A delivery_attempt row blocks assignment even when the order counter has
-- not yet been repaired; the RPC never resets or writes that history.
insert into public.delivery_tasks (
  id, order_id, kind, assigned_shipper_id, status, attempt_number,
  destination_name, destination_phone, destination_address,
  destination_latitude, destination_longitude, amount_to_collect_vnd,
  assigned_at
) values (
  '03310000-0000-0000-0000-000000000103'::uuid,
  '03310000-0000-0000-0000-000000000017'::uuid,
  'outbound', '03310000-0000-0000-0000-000000000004'::uuid, 'assigned', 1,
  'Assignment Recipient', '0900000000', 'Ha Noi assignment fixture',
  21.0285, 105.8542, 130000, now()
);
insert into public.delivery_attempts (
  task_id, order_id, attempt_number, task_kind, result, reason, shipper_id
) values (
  '03310000-0000-0000-0000-000000000103'::uuid,
  '03310000-0000-0000-0000-000000000017'::uuid,
  1, 'outbound', 'failed', 'Fixture failed attempt',
  '03310000-0000-0000-0000-000000000004'::uuid
);

-- Terminal/custody evidence on an otherwise active row cannot be reused or
-- overwritten, regardless of its status label.
insert into public.delivery_tasks (
  id, order_id, kind, assigned_shipper_id, status, attempt_number,
  destination_name, destination_phone, destination_address,
  destination_latitude, destination_longitude, amount_to_collect_vnd,
  assigned_at, completed_at
) values (
  '03310000-0000-0000-0000-000000000104'::uuid,
  '03310000-0000-0000-0000-000000000020'::uuid,
  'outbound', '03310000-0000-0000-0000-000000000004'::uuid, 'assigned', 1,
  'Assignment Recipient', '0900000000', 'Ha Noi assignment fixture',
  21.0285, 105.8542, 130000, now(), now()
), (
  '03310000-0000-0000-0000-000000000105'::uuid,
  '03310000-0000-0000-0000-000000000021'::uuid,
  'outbound', '03310000-0000-0000-0000-000000000004'::uuid, 'assigned', 1,
  'Assignment Recipient', '0900000000', 'Ha Noi assignment fixture',
  21.0285, 105.8542, 130000, now(), null
), (
  '03310000-0000-0000-0000-000000000106'::uuid,
  '03310000-0000-0000-0000-000000000022'::uuid, 'outbound',
  '03310000-0000-0000-0000-000000000004'::uuid, 'assigned', 1,
  'Assignment Recipient', '0900000000', 'Ha Noi assignment fixture',
  21.0285, 105.8542, 130000, now(), null
);
update public.delivery_tasks
set failure_reason = 'Fixture failure'
where id = '03310000-0000-0000-0000-000000000105'::uuid;
update public.delivery_tasks
set cancel_reason = 'Fixture cancellation'
where id = '03310000-0000-0000-0000-000000000106'::uuid;

-- Existing active snapshots are immutable: amount mismatch maps to a COD
-- conflict, while destination mismatch maps to a state conflict.
insert into public.delivery_tasks (
  id, order_id, kind, status, attempt_number, destination_name,
  destination_phone, destination_address, destination_latitude,
  destination_longitude, amount_to_collect_vnd
) values (
  '03310000-0000-0000-0000-000000000107'::uuid,
  '03310000-0000-0000-0000-000000000023'::uuid,
  'outbound', 'pending_assignment', 1, 'Assignment Recipient', '0900000000',
  'Ha Noi assignment fixture', 21.0285, 105.8542, 1
), (
  '03310000-0000-0000-0000-000000000108'::uuid,
  '03310000-0000-0000-0000-000000000024'::uuid,
  'outbound', 'assigned', 1, 'Different Recipient', '0900000000',
  'Ha Noi assignment fixture', 21.0285, 105.8542, 130000
);

-- Pending assignment is valid only while its order remains preparing and its
-- shipper is still NULL. These rows exercise both guards explicitly.
insert into public.delivery_tasks (
  id, order_id, kind, status, attempt_number, destination_name,
  destination_phone, destination_address, destination_latitude,
  destination_longitude, amount_to_collect_vnd, assigned_shipper_id
) values (
  '03310000-0000-0000-0000-000000000109'::uuid,
  '03310000-0000-0000-0000-000000000025'::uuid,
  'outbound', 'pending_assignment', 1, 'Assignment Recipient', '0900000000',
  'Ha Noi assignment fixture', 21.0285, 105.8542, 130000, null
), (
  '03310000-0000-0000-0000-000000000110'::uuid,
  '03310000-0000-0000-0000-000000000026'::uuid,
  'outbound', 'pending_assignment', 1, 'Assignment Recipient', '0900000000',
  'Ha Noi assignment fixture', 21.0285, 105.8542, 130000,
  '03310000-0000-0000-0000-000000000004'::uuid
);

-- Function/role/ACL contract: only authenticated can execute the RPC, while
-- the owner itself remains a locked-down NOLOGIN/NOBYPASSRLS writer.
do $$
declare
  l_function oid := 'public.assign_delivery_task(uuid,uuid,uuid,uuid,uuid)'::regprocedure;
  l_writer oid := 'sports_store_delivery_writer'::regrole;
  l_owner text;
begin
  select p.proowner::regrole::text into l_owner from pg_proc p where p.oid = l_function;
  perform pg_temp.assert_assignment('function owner is dedicated writer',
    l_owner = 'sports_store_delivery_writer');
  perform pg_temp.assert_assignment('function is SECURITY DEFINER and fixed search_path',
    (select p.prosecdef and p.proconfig = array['search_path=""']
       from pg_proc p where p.oid = l_function));
  perform pg_temp.assert_assignment('authenticated is sole API execute grant',
    has_function_privilege('authenticated', l_function, 'EXECUTE')
    and not has_function_privilege('anon', l_function, 'EXECUTE')
    and not has_function_privilege('service_role', l_function, 'EXECUTE'));
  perform pg_temp.assert_assignment('writer role is locked down',
    (select not r.rolcanlogin and not r.rolinherit and not r.rolbypassrls
       and not r.rolsuper and not r.rolcreaterole and not r.rolcreatedb
       and not r.rolreplication from pg_roles r where r.oid = l_writer));
  perform pg_temp.assert_assignment('writer membership is postgres-only',
    not exists (
      select 1 from pg_auth_members m
      where m.roleid = l_writer and m.member <> 'postgres'::regrole
    ));
  perform pg_temp.assert_assignment('writer has no public schema CREATE',
    not has_schema_privilege('sports_store_delivery_writer', 'public', 'CREATE'));
  perform pg_temp.assert_assignment('writer column grants are minimal',
    has_column_privilege('sports_store_delivery_writer', 'public.profiles', 'id', 'SELECT')
    and has_column_privilege('sports_store_delivery_writer', 'public.profiles', 'role', 'SELECT')
    and has_column_privilege('sports_store_delivery_writer', 'public.profiles', 'id', 'UPDATE')
    and not has_column_privilege('sports_store_delivery_writer', 'public.profiles', 'role', 'UPDATE'));
  perform pg_temp.assert_assignment('authenticated cannot write task table',
    not has_table_privilege('authenticated', 'public.delivery_tasks', 'INSERT')
    and not has_table_privilege('authenticated', 'public.delivery_tasks', 'UPDATE'));
end;
$$;

-- Anonymous, customer, and shipper callers are rejected before any business
-- rows are visible or changed. Forged JWT role claims do not grant manager.
set local role anon;
select pg_temp.clear_assignment_claims();
select pg_temp.assert_assignment_error(
  'anonymous caller denied',
  $sql$select public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000010'::uuid,
    '03310000-0000-0000-0000-000000000004'::uuid,
    '03310000-0000-0000-0000-000000000201'::uuid)$sql$,
  '42501'
);
set local role authenticated;
select pg_temp.set_assignment_claims(
  '03310000-0000-0000-0000-000000000001'::uuid, 'manager'
);
select pg_temp.assert_assignment_error(
  'customer with forged manager claim denied',
  $sql$select public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000010'::uuid,
    '03310000-0000-0000-0000-000000000004'::uuid,
    '03310000-0000-0000-0000-000000000202'::uuid)$sql$,
  '42501', 'PERMISSION_DENIED'
);
select pg_temp.set_assignment_claims(
  '03310000-0000-0000-0000-000000000004'::uuid
);
select pg_temp.assert_assignment_error(
  'shipper caller denied',
  $sql$select public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000010'::uuid,
    '03310000-0000-0000-0000-000000000004'::uuid,
    '03310000-0000-0000-0000-000000000203'::uuid)$sql$,
  '42501', 'PERMISSION_DENIED'
);

-- Manager first assignment is the only path that moves preparing to
-- awaiting_pickup. Snapshot and COD values are all server-derived.
select pg_temp.set_assignment_claims(
  '03310000-0000-0000-0000-000000000002'::uuid
);
do $$
declare
  l_result jsonb;
begin
  l_result := public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000010'::uuid,
    '03310000-0000-0000-0000-000000000004'::uuid,
    '03310000-0000-0000-0000-000000000210'::uuid
  );
  perform pg_temp.assert_assignment('first assignment returns server total',
    l_result ->> 'amount_to_collect_vnd' = '130000'
    and l_result ->> 'expected_amount_vnd' = '130000'
    and l_result ->> 'total_cod_vnd' = '130000'
    and l_result ->> 'task_status' = 'assigned'
    and l_result ->> 'order_status' = 'awaiting_pickup'
    and l_result ->> 'attempt_number' = '1');
end;
$$;
reset role;
select pg_temp.assert_assignment('first assignment transitions order',
  (select status = 'awaiting_pickup' from public.orders
    where id = '03310000-0000-0000-0000-000000000010'::uuid));
select pg_temp.assert_assignment('first assignment snapshots recipient and COD',
  (select t.destination_name = o.recipient_name
      and t.destination_phone = o.recipient_phone
      and t.destination_address = o.address_detail
      and t.destination_latitude = o.latitude
      and t.destination_longitude = o.longitude
      and t.amount_to_collect_vnd = o.total_cod_vnd
      and c.expected_amount_vnd = o.total_cod_vnd
      and c.shipper_id = t.assigned_shipper_id
      and c.status = 'uncollected'
   from public.delivery_tasks t
   join public.orders o on o.id = t.order_id
   join public.cod_collections c on c.order_id = o.id
   where t.order_id = '03310000-0000-0000-0000-000000000010'::uuid
     and t.kind = 'outbound'));
select pg_temp.assert_assignment('first assignment writes one audit and request',
  (select count(*) = 1 from private.delivery_assignment_audits
    where order_id = '03310000-0000-0000-0000-000000000010'::uuid)
  and (select count(*) = 1 from private.delivery_assignment_requests
    where order_id = '03310000-0000-0000-0000-000000000010'::uuid));

-- A second request cannot silently overwrite an active task, while the exact
-- same request replays the stored JSON result without a second audit.
set local role authenticated;
select pg_temp.set_assignment_claims('03310000-0000-0000-0000-000000000002'::uuid);
select pg_temp.assert_assignment_error(
  'active task requires expected id',
  $sql$select public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000010'::uuid,
    '03310000-0000-0000-0000-000000000005'::uuid,
    '03310000-0000-0000-0000-000000000211'::uuid)$sql$,
  'PT409', 'TASK_CONFLICT'
);
do $$
declare
  l_first jsonb;
  l_replay jsonb;
begin
  l_first := public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000011'::uuid,
    '03310000-0000-0000-0000-000000000004'::uuid,
    '03310000-0000-0000-0000-000000000220'::uuid
  );
  l_replay := public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000011'::uuid,
    '03310000-0000-0000-0000-000000000004'::uuid,
    '03310000-0000-0000-0000-000000000220'::uuid
  );
  perform pg_temp.assert_assignment('idempotent replay is byte-equivalent JSON',
    l_first = l_replay);
end;
$$;
select pg_temp.assert_assignment_error(
  'same request with different payload denied',
  $sql$select public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000011'::uuid,
    '03310000-0000-0000-0000-000000000005'::uuid,
    '03310000-0000-0000-0000-000000000220'::uuid)$sql$,
  'PT409', 'IDEMPOTENCY_CONFLICT'
);

-- CAS reassignment changes the shipper only before physical acceptance. A
-- matching same-target request is a no-op and does not append another audit.
do $$
declare
  l_task uuid;
  l_before timestamptz;
  l_after timestamptz;
  l_result jsonb;
begin
  select id, assigned_at into l_task, l_before
  from public.delivery_tasks
  where order_id = '03310000-0000-0000-0000-000000000010'::uuid
    and kind = 'outbound';
  l_result := public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000010'::uuid,
    '03310000-0000-0000-0000-000000000005'::uuid,
    '03310000-0000-0000-0000-000000000230'::uuid,
    l_task,
    '03310000-0000-0000-0000-000000000004'::uuid
  );
  select assigned_at into l_after from public.delivery_tasks where id = l_task;
  perform pg_temp.assert_assignment('reassignment keeps task id',
    l_result ->> 'task_id' = l_task::text);
  perform pg_temp.assert_assignment('reassignment changes shipper',
    (select assigned_shipper_id = '03310000-0000-0000-0000-000000000005'::uuid
         from public.delivery_tasks where id = l_task));
  l_before := l_after;
  l_result := public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000010'::uuid,
    '03310000-0000-0000-0000-000000000005'::uuid,
    '03310000-0000-0000-0000-000000000231'::uuid,
    l_task,
    '03310000-0000-0000-0000-000000000005'::uuid
  );
  select assigned_at into l_after from public.delivery_tasks where id = l_task;
  perform pg_temp.assert_assignment('same-target reassignment is a no-op',
    l_before is not null and l_before = l_after
      and (l_result ->> 'assigned_at')::timestamptz = l_before);
end;
$$;
reset role;
select pg_temp.assert_assignment('reassignment appends exactly one audit',
  (select count(*) = 2 from private.delivery_assignment_audits
    where order_id = '03310000-0000-0000-0000-000000000010'::uuid));
select pg_temp.assert_assignment('audit records manager and old/new shipper',
  (select old_shipper_id is null
      and new_shipper_id = '03310000-0000-0000-0000-000000000004'::uuid
      and action = 'assigned'
      and actor_id = '03310000-0000-0000-0000-000000000002'::uuid
    from private.delivery_assignment_audits
    where request_id = '03310000-0000-0000-0000-000000000210'::uuid)
  and (select old_shipper_id = '03310000-0000-0000-0000-000000000004'::uuid
      and new_shipper_id = '03310000-0000-0000-0000-000000000005'::uuid
      and action = 'reassigned'
      and actor_id = '03310000-0000-0000-0000-000000000002'::uuid
    from private.delivery_assignment_audits
    where request_id = '03310000-0000-0000-0000-000000000230'::uuid));
set local role authenticated;
select pg_temp.set_assignment_claims('03310000-0000-0000-0000-000000000002'::uuid);
select pg_temp.assert_assignment_error(
  'stale previous shipper cannot win CAS',
  $sql$select public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000010'::uuid,
    '03310000-0000-0000-0000-000000000006'::uuid,
    '03310000-0000-0000-0000-000000000232'::uuid,
    (select id from public.delivery_tasks where order_id='03310000-0000-0000-0000-000000000010'::uuid),
    '03310000-0000-0000-0000-000000000004'::uuid)$sql$,
  'PT409', 'STALE_ASSIGNMENT'
);

-- Pending assignment from preparing accepts a NULL expected shipper and then
-- becomes an assigned task. The clean COD mismatch is atomically reconciled.
do $$
declare l_result jsonb;
begin
  l_result := public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000018'::uuid,
    '03310000-0000-0000-0000-000000000006'::uuid,
    '03310000-0000-0000-0000-000000000240'::uuid,
    '03310000-0000-0000-0000-000000000101'::uuid,
    null
  );
  perform pg_temp.assert_assignment('pending task assignment succeeds',
    l_result ->> 'task_id' = '03310000-0000-0000-0000-000000000101'
    and (select status = 'assigned' and assigned_shipper_id =
      '03310000-0000-0000-0000-000000000006'::uuid
      from public.delivery_tasks where id='03310000-0000-0000-0000-000000000101'::uuid));
end;
$$;
do $$
declare l_result jsonb;
begin
  l_result := public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000014'::uuid,
    '03310000-0000-0000-0000-000000000004'::uuid,
    '03310000-0000-0000-0000-000000000241'::uuid
  );
  perform pg_temp.assert_assignment('clean COD mismatch reconciles',
    l_result ->> 'total_cod_vnd' = '130000'
    and (select expected_amount_vnd = 130000 and shipper_id =
      '03310000-0000-0000-0000-000000000004'::uuid
      from public.cod_collections where order_id='03310000-0000-0000-0000-000000000014'::uuid));
end;
$$;

-- State/attempt/custody/COD conflicts leave no new task or ledger history.
select pg_temp.assert_assignment_error(
  'invalid shipper role',
  $sql$select public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000012'::uuid,
    '03310000-0000-0000-0000-000000000001'::uuid,
    '03310000-0000-0000-0000-000000000250'::uuid)$sql$,
  'PT409', 'INVALID_SHIPPER'
);
select pg_temp.assert_assignment_error(
  'delivered order cannot be assigned',
  $sql$select public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000013'::uuid,
    '03310000-0000-0000-0000-000000000004'::uuid,
    '03310000-0000-0000-0000-000000000251'::uuid)$sql$,
  'PT409', 'STATE_CONFLICT'
);
select pg_temp.assert_assignment_error(
  'attempt count blocks second outbound task',
  $sql$select public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000016'::uuid,
    '03310000-0000-0000-0000-000000000004'::uuid,
    '03310000-0000-0000-0000-000000000252'::uuid)$sql$,
  'PT409', 'ATTEMPT_LIMIT'
);
select pg_temp.assert_assignment_error(
  'accepted task cannot be reassigned',
  $sql$select public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000019'::uuid,
    '03310000-0000-0000-0000-000000000005'::uuid,
    '03310000-0000-0000-0000-000000000253'::uuid,
    '03310000-0000-0000-0000-000000000102'::uuid,
    '03310000-0000-0000-0000-000000000004'::uuid)$sql$,
  'PT409', 'CUSTODY_UNRESOLVED'
);
select pg_temp.assert_assignment_error(
  'collected COD cannot be repaired',
  $sql$select public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000015'::uuid,
    '03310000-0000-0000-0000-000000000004'::uuid,
    '03310000-0000-0000-0000-000000000254'::uuid)$sql$,
  'PT409', 'COD_CONFLICT'
);
select pg_temp.assert_assignment_error(
  'delivery attempt history blocks assignment',
  $sql$select public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000017'::uuid,
    '03310000-0000-0000-0000-000000000005'::uuid,
    '03310000-0000-0000-0000-000000000255'::uuid)$sql$,
  'PT409', 'ATTEMPT_LIMIT'
);
select pg_temp.assert_assignment_error(
  'completed evidence on active label is blocked',
  $sql$select public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000020'::uuid,
    '03310000-0000-0000-0000-000000000005'::uuid,
    '03310000-0000-0000-0000-000000000256'::uuid,
    '03310000-0000-0000-0000-000000000104'::uuid,
    '03310000-0000-0000-0000-000000000004'::uuid)$sql$,
  'PT409', 'CUSTODY_UNRESOLVED'
);
select pg_temp.assert_assignment_error(
  'failure evidence on active label is blocked',
  $sql$select public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000021'::uuid,
    '03310000-0000-0000-0000-000000000005'::uuid,
    '03310000-0000-0000-0000-000000000257'::uuid,
    '03310000-0000-0000-0000-000000000105'::uuid,
    '03310000-0000-0000-0000-000000000004'::uuid)$sql$,
  'PT409', 'CUSTODY_UNRESOLVED'
);
select pg_temp.assert_assignment_error(
  'cancel evidence on active label is blocked',
  $sql$select public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000022'::uuid,
    '03310000-0000-0000-0000-000000000005'::uuid,
    '03310000-0000-0000-0000-000000000258'::uuid,
    '03310000-0000-0000-0000-000000000106'::uuid,
    '03310000-0000-0000-0000-000000000004'::uuid)$sql$,
  'PT409', 'CUSTODY_UNRESOLVED'
);
select pg_temp.assert_assignment_error(
  'active amount mismatch is blocked',
  $sql$select public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000023'::uuid,
    '03310000-0000-0000-0000-000000000005'::uuid,
    '03310000-0000-0000-0000-000000000259'::uuid,
    '03310000-0000-0000-0000-000000000107'::uuid,
    null::uuid)$sql$,
  'PT409', 'COD_CONFLICT'
);
select pg_temp.assert_assignment_error(
  'active destination mismatch is blocked',
  $sql$select public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000024'::uuid,
    '03310000-0000-0000-0000-000000000005'::uuid,
    '03310000-0000-0000-0000-000000000260'::uuid,
    '03310000-0000-0000-0000-000000000108'::uuid,
    '03310000-0000-0000-0000-000000000004'::uuid)$sql$,
  'PT409', 'STATE_CONFLICT'
);
select pg_temp.assert_assignment_error(
  'pending task on awaiting_pickup is invalid',
  $sql$select public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000025'::uuid,
    '03310000-0000-0000-0000-000000000005'::uuid,
    '03310000-0000-0000-0000-000000000261'::uuid,
    '03310000-0000-0000-0000-000000000109'::uuid,
    null::uuid)$sql$,
  'PT409', 'STATE_CONFLICT'
);
select pg_temp.assert_assignment_error(
  'pending task with a shipper is invalid',
  $sql$select public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000026'::uuid,
    '03310000-0000-0000-0000-000000000005'::uuid,
    '03310000-0000-0000-0000-000000000262'::uuid,
    '03310000-0000-0000-0000-000000000110'::uuid,
    '03310000-0000-0000-0000-000000000004'::uuid)$sql$,
  'PT409', 'STALE_ASSIGNMENT'
);
select pg_temp.assert_assignment_error(
  'null request id is invalid',
  $sql$select public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000012'::uuid,
    '03310000-0000-0000-0000-000000000004'::uuid,
    null::uuid)$sql$,
  '22023', 'INVALID_ARGUMENT'
);

reset role;
select pg_temp.assert_assignment('failed state rolls back task/audit/ledger',
  (select count(*) = 0 from public.delivery_tasks
    where order_id in (
      '03310000-0000-0000-0000-000000000012'::uuid,
      '03310000-0000-0000-0000-000000000013'::uuid,
      '03310000-0000-0000-0000-000000000015'::uuid,
      '03310000-0000-0000-0000-000000000016'::uuid
    ))
  and (select count(*) = 0 from private.delivery_assignment_requests
    where request_id in (
      '03310000-0000-0000-0000-000000000250'::uuid,
      '03310000-0000-0000-0000-000000000251'::uuid,
      '03310000-0000-0000-0000-000000000252'::uuid,
      '03310000-0000-0000-0000-000000000253'::uuid,
      '03310000-0000-0000-0000-000000000254'::uuid
    )));
select pg_temp.assert_assignment('failed state writes no audit',
  (select count(*) = 0 from private.delivery_assignment_audits
    where request_id in (
      '03310000-0000-0000-0000-000000000250'::uuid,
      '03310000-0000-0000-0000-000000000251'::uuid,
      '03310000-0000-0000-0000-000000000252'::uuid,
      '03310000-0000-0000-0000-000000000253'::uuid,
      '03310000-0000-0000-0000-000000000254'::uuid,
      '03310000-0000-0000-0000-000000000255'::uuid,
      '03310000-0000-0000-0000-000000000256'::uuid,
      '03310000-0000-0000-0000-000000000257'::uuid,
      '03310000-0000-0000-0000-000000000258'::uuid,
      '03310000-0000-0000-0000-000000000259'::uuid,
      '03310000-0000-0000-0000-000000000260'::uuid,
      '03310000-0000-0000-0000-000000000261'::uuid,
      '03310000-0000-0000-0000-000000000262'::uuid
    )));
select pg_temp.assert_assignment('custody task remains unchanged after rejection',
  (select count(*) = 1 and bool_and(status = 'assigned'
      and accepted_at is not null and assigned_shipper_id =
        '03310000-0000-0000-0000-000000000004'::uuid)
    from public.delivery_tasks
    where id = '03310000-0000-0000-0000-000000000102'::uuid));

-- Private ledgers have no client entitlement; the function is the only write
-- path and no generic retry/workflow table is exposed.
update public.delivery_tasks set assigned_at = null
where order_id = '03310000-0000-0000-0000-000000000010'::uuid;
set local role authenticated;
select pg_temp.set_assignment_claims('03310000-0000-0000-0000-000000000002'::uuid);
select pg_temp.assert_assignment_error(
  'assigned task without assignment timestamp is invalid even for no-op',
  $sql$select public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000010'::uuid,
    '03310000-0000-0000-0000-000000000005'::uuid,
    '03310000-0000-0000-0000-000000000263'::uuid,
    (select id from public.delivery_tasks where order_id = '03310000-0000-0000-0000-000000000010'::uuid),
    '03310000-0000-0000-0000-000000000005'::uuid)$sql$,
  'PT409', 'STATE_CONFLICT'
);
reset role;
select pg_temp.assert_assignment('invalid timestamp leaves no command or audit',
  not exists (select 1 from private.delivery_assignment_requests
    where request_id = '03310000-0000-0000-0000-000000000263'::uuid)
  and not exists (select 1 from private.delivery_assignment_audits
    where request_id = '03310000-0000-0000-0000-000000000263'::uuid));
set local role authenticated;
select pg_temp.set_assignment_claims('03310000-0000-0000-0000-000000000002'::uuid);
select pg_temp.assert_assignment_error(
  'authenticated cannot read private request ledger',
  $sql$select count(*) from private.delivery_assignment_requests$sql$,
  '42501'
);
select pg_temp.assert_assignment_error(
  'authenticated cannot mutate profile through lock privilege',
  $sql$update public.profiles set id = id
    where id = '03310000-0000-0000-0000-000000000002'::uuid$sql$,
  '42501'
);
reset role;

-- P07.2 regression of the EXISTING initial-assignment API, not a retry API.
-- Privileged seed deliberately has count=2 even without result rows: a caller
-- cannot exploit missing history or a new manager/shipper/request to reset it.
update public.orders set delivery_attempt_count = 2
where id = '03310000-0000-0000-0000-000000000016'::uuid;
create temp table p072_assignment_before as
select
  (select jsonb_agg(to_jsonb(x) order by x.id) from public.orders x) as orders,
  (select jsonb_agg(to_jsonb(x) order by x.id) from public.delivery_tasks x) as tasks,
  (select jsonb_agg(to_jsonb(x) order by x.id) from public.delivery_attempts x) as attempts,
  (select jsonb_agg(to_jsonb(x) order by x.id) from public.inventory_movements x) as movements,
  (select jsonb_agg(to_jsonb(x) order by x.actor_id, x.request_id)
     from private.delivery_assignment_requests x) as requests;
set local role authenticated;
select pg_temp.set_assignment_claims('03310000-0000-0000-0000-000000000002'::uuid);
select pg_temp.assert_assignment_error(
  'P07.2 direct assignment cannot open third attempt',
  $sql$select public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000016'::uuid,
    '03310000-0000-0000-0000-000000000005'::uuid,
    '03310000-0000-0000-0000-000000000272'::uuid)$sql$,
  'PT409', 'ATTEMPT_LIMIT'
);
select pg_temp.set_assignment_claims('03310000-0000-0000-0000-000000000003'::uuid);
select pg_temp.assert_assignment_error(
  'P07.2 different manager shipper and request cannot open third attempt',
  $sql$select public.assign_delivery_task(
    '03310000-0000-0000-0000-000000000016'::uuid,
    '03310000-0000-0000-0000-000000000006'::uuid,
    '03310000-0000-0000-0000-000000000273'::uuid)$sql$,
  'PT409', 'ATTEMPT_LIMIT'
);
reset role;
select pg_temp.assert_assignment('P07.2 rejected third calls preserve history and counters',
  (select jsonb_agg(to_jsonb(x) order by x.id) from public.orders x)
    is not distinct from (select orders from p072_assignment_before)
  and (select jsonb_agg(to_jsonb(x) order by x.id) from public.delivery_tasks x)
    is not distinct from (select tasks from p072_assignment_before)
  and (select jsonb_agg(to_jsonb(x) order by x.id) from public.delivery_attempts x)
    is not distinct from (select attempts from p072_assignment_before)
  and (select jsonb_agg(to_jsonb(x) order by x.id) from public.inventory_movements x)
    is not distinct from (select movements from p072_assignment_before)
  and (select jsonb_agg(to_jsonb(x) order by x.actor_id, x.request_id)
    from private.delivery_assignment_requests x)
    is not distinct from (select requests from p072_assignment_before));

select 'outbound_assignment.sql: PASS' as result,
       'fixtures rolled back by final statement' as fixture_scope;
rollback;
