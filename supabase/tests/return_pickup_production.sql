-- P08.1 production return-pickup contract.
--
-- This suite is intentionally self contained and rolls back all fixture rows.
-- It calls only the three P08.1 RPCs.  Return approval and store receipt are
-- owned by returns and are not implemented in this phase, so the fixture
-- seeds an already-approved request with server-side decision metadata.  No
-- test creates a fake approval/receipt endpoint.
begin;
set constraints all deferred;

create or replace function pg_temp.set_p081_claims(p_user_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
  perform set_config(
    'request.jwt.claims',
    case when p_user_id is null then '' else jsonb_build_object(
      'sub', p_user_id::text, 'role', 'authenticated', 'aud', 'authenticated'
    )::text end,
    true
  );
end;
$$;

create or replace function pg_temp.assert_p081(p_label text, p_ok boolean)
returns void
language plpgsql
as $$
begin
  if coalesce(p_ok, false) is not true then
    raise exception 'P08.1 return-pickup test failed: %', p_label;
  end if;
end;
$$;

create or replace function pg_temp.assert_p081_error(
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
      'P08.1 return-pickup error % expected SQLSTATE %, got %: %',
      p_label, p_state, coalesce(l_state, 'success'), coalesce(l_message, '');
  end if;
  if p_message is not null and l_message is distinct from p_message then
    raise exception
      'P08.1 return-pickup error % expected message %, got %',
      p_label, p_message, coalesce(l_message, '');
  end if;
end;
$$;

create temp table p081_ids(
  name text primary key,
  id uuid not null
) on commit drop;
create temp table p081_results(
  name text primary key,
  response jsonb not null
) on commit drop;
create temp table p081_before(
  name text primary key,
  quantity bigint,
  quantity_collected bigint,
  order_status public.order_status,
  return_status public.return_request_status,
  task_status public.delivery_task_status,
  accepted_at timestamptz,
  started_at timestamptz,
  delivery_attempt_count smallint,
  cod_status public.cod_status,
  cod_collected bigint,
  cod_received bigint,
  variant_on_hand bigint,
  variant_reserved bigint,
  variant_damaged bigint,
  inspection_started_at timestamptz,
  inspected_at timestamptz,
  refund_amount_vnd bigint,
  refund_request_id uuid
) on commit drop;
grant select, insert, update on p081_ids, p081_results, p081_before to authenticated;

-- The exact five-argument signatures are part of the P08.1 API even though
-- the expected task/shipper arguments have defaults.  Keep the ACL check
-- independent of the implementation's private ledger names.
do $$
declare
  l_proc oid;
  l_name text;
begin
  foreach l_name in array array[
    'public.assign_return_pickup_task(uuid,uuid,uuid,uuid,uuid)',
    'public.collect_return_items(uuid,uuid,jsonb)',
    'public.fail_return_pickup_task(uuid,uuid,text,text)'
  ] loop
    l_proc := to_regprocedure(l_name);
    if l_proc is null then
      raise exception 'P08.1 RPC is missing: %', l_name;
    end if;
    if not has_function_privilege('authenticated', l_proc, 'EXECUTE')
       or has_function_privilege('anon', l_proc, 'EXECUTE')
       or has_function_privilege('service_role', l_proc, 'EXECUTE') then
      raise exception 'P08.1 RPC ACL is not authenticated-only: %', l_name;
    end if;
  end loop;
end;
$$;

-- Server-managed identities.  Approval metadata below is deliberately seeded
-- by the fixture setup rather than produced by a non-existent approval RPC.
insert into auth.users (id, email)
values
  ('08150000-0000-0000-0000-000000000001', 'p081-customer@example.invalid'),
  ('08150000-0000-0000-0000-000000000002', 'p081-manager@example.invalid'),
  ('08150000-0000-0000-0000-000000000003', 'p081-shipper-a@example.invalid'),
  ('08150000-0000-0000-0000-000000000004', 'p081-shipper-b@example.invalid'),
  ('08150000-0000-0000-0000-000000000005', 'p081-shipper-c@example.invalid'),
  ('08150000-0000-0000-0000-000000000006', 'p081-shipper-d@example.invalid'),
  ('08150000-0000-0000-0000-000000000007', 'p081-other-customer@example.invalid');
update public.profiles
set role = case
  when id = '08150000-0000-0000-0000-000000000002' then 'manager'::public.user_role
  when id in (
    '08150000-0000-0000-0000-000000000003',
    '08150000-0000-0000-0000-000000000004',
    '08150000-0000-0000-0000-000000000005',
    '08150000-0000-0000-0000-000000000006'
  ) then 'shipper'::public.user_role
  else 'customer'::public.user_role
end
where id in (
  '08150000-0000-0000-0000-000000000001',
  '08150000-0000-0000-0000-000000000002',
  '08150000-0000-0000-0000-000000000003',
  '08150000-0000-0000-0000-000000000004',
  '08150000-0000-0000-0000-000000000005',
  '08150000-0000-0000-0000-000000000006',
  '08150000-0000-0000-0000-000000000007'
);

insert into public.categories (id, code, name)
values ('08150000-0000-0000-0000-000000000100', 'P081', 'P08.1 return pickup');
insert into public.products (id, category_id, name)
values (
  '08150000-0000-0000-0000-000000000101',
  '08150000-0000-0000-0000-000000000100',
  'P08.1 return product'
);
insert into public.product_variants (
  id, product_id, sku, label, price_vnd, on_hand, reserved, damaged
)
values
  ('08150000-0000-0000-0000-000000000111',
   '08150000-0000-0000-0000-000000000101', 'P081-01', 'P08.1 jersey',
   100000, 40, 7, 0),
  ('08150000-0000-0000-0000-000000000112',
   '08150000-0000-0000-0000-000000000101', 'P081-02', 'P08.1 shorts',
   80000, 30, 4, 0);

-- Every order is already delivered.  Return pickup must not alter order/COD
-- state, and the order remains the aggregate that owns the return request.
insert into public.orders (
  id, customer_id, request_id, status, recipient_name, recipient_phone,
  address_detail, latitude, longitude, subtotal_vnd, delivery_attempt_count,
  delivered_at
)
select x.order_id, '08150000-0000-0000-0000-000000000001'::uuid,
  x.order_id, 'delivered'::public.order_status,
  x.recipient_name, x.recipient_phone, x.address_detail, 21.0285, 105.8542,
  x.subtotal_vnd, 0, clock_timestamp() - interval '1 day'
from (values
  ('08150000-0000-0000-0000-000000000010'::uuid, 'P081 Main Recipient', '0908100001', 'P081 main address', 180000::bigint),
  ('08150000-0000-0000-0000-000000000011'::uuid, 'P081 Partial Recipient', '0908100002', 'P081 partial address', 100000::bigint),
  ('08150000-0000-0000-0000-000000000012'::uuid, 'P081 Foreign Recipient', '0908100003', 'P081 foreign address', 100000::bigint),
  ('08150000-0000-0000-0000-000000000013'::uuid, 'P081 Failed Recipient', '0908100004', 'P081 failed address', 100000::bigint),
  ('08150000-0000-0000-0000-000000000014'::uuid, 'P081 Pending Recipient', '0908100005', 'P081 pending address', 100000::bigint),
  ('08150000-0000-0000-0000-000000000015'::uuid, 'P081 Reassign Recipient', '0908100006', 'P081 reassign address', 100000::bigint),
  ('08150000-0000-0000-0000-000000000016'::uuid, 'P081 No Items Recipient', '0908100007', 'P081 no-items address', 100000::bigint)
) x(order_id, recipient_name, recipient_phone, address_detail, subtotal_vnd);

insert into public.order_items (
  id, order_id, product_id, variant_id, product_name, variant_label,
  unit_price_vnd, quantity
)
values
  ('08150000-0000-0000-0000-000000000201', '08150000-0000-0000-0000-000000000010', '08150000-0000-0000-0000-000000000101', '08150000-0000-0000-0000-000000000111', 'P08.1 jersey', 'P08.1 jersey', 100000, 2),
  ('08150000-0000-0000-0000-000000000202', '08150000-0000-0000-0000-000000000010', '08150000-0000-0000-0000-000000000101', '08150000-0000-0000-0000-000000000112', 'P08.1 shorts', 'P08.1 shorts', 80000, 1),
  ('08150000-0000-0000-0000-000000000211', '08150000-0000-0000-0000-000000000011', '08150000-0000-0000-0000-000000000101', '08150000-0000-0000-0000-000000000111', 'P08.1 jersey', 'P08.1 jersey', 100000, 2),
  ('08150000-0000-0000-0000-000000000221', '08150000-0000-0000-0000-000000000012', '08150000-0000-0000-0000-000000000101', '08150000-0000-0000-0000-000000000111', 'P08.1 jersey', 'P08.1 jersey', 100000, 1),
  ('08150000-0000-0000-0000-000000000231', '08150000-0000-0000-0000-000000000013', '08150000-0000-0000-0000-000000000101', '08150000-0000-0000-0000-000000000111', 'P08.1 jersey', 'P08.1 jersey', 100000, 1),
  ('08150000-0000-0000-0000-000000000251', '08150000-0000-0000-0000-000000000015', '08150000-0000-0000-0000-000000000101', '08150000-0000-0000-0000-000000000111', 'P08.1 jersey', 'P08.1 jersey', 100000, 1),
  ('08150000-0000-0000-0000-000000000261', '08150000-0000-0000-0000-000000000016', '08150000-0000-0000-0000-000000000101', '08150000-0000-0000-0000-000000000111', 'P08.1 jersey', 'P08.1 jersey', 100000, 1),
  ('08150000-0000-0000-0000-000000000241', '08150000-0000-0000-0000-000000000014', '08150000-0000-0000-0000-000000000101', '08150000-0000-0000-0000-000000000111', 'P08.1 jersey', 'P08.1 jersey', 100000, 1);

-- The approval API is outside P08.1.  These rows carry the manager decision
-- metadata that the production assignment RPC must validate server-side.
insert into public.return_requests (
  id, order_id, customer_id, request_id, status, reason, description,
  video_object_path, decision_reason, decision_at, decided_by
)
values
  ('08150000-0000-0000-0000-000000000210', '08150000-0000-0000-0000-000000000010', '08150000-0000-0000-0000-000000000001', '08150000-0000-0000-0000-000000000310', 'awaiting_return_pickup', 'defective', 'P081 approved main return', '081/customer/main.mp4', 'approved return pickup fixture', clock_timestamp() - interval '5 minutes', '08150000-0000-0000-0000-000000000002'),
  ('08150000-0000-0000-0000-000000000211', '08150000-0000-0000-0000-000000000011', '08150000-0000-0000-0000-000000000001', '08150000-0000-0000-0000-000000000311', 'awaiting_return_pickup', 'missing_items', 'P081 approved partial-validation return', '081/customer/partial.mp4', 'approved return pickup fixture', clock_timestamp() - interval '5 minutes', '08150000-0000-0000-0000-000000000002'),
  ('08150000-0000-0000-0000-000000000212', '08150000-0000-0000-0000-000000000012', '08150000-0000-0000-0000-000000000001', '08150000-0000-0000-0000-000000000312', 'awaiting_return_pickup', 'wrong_item', 'P081 foreign-item return', '081/customer/foreign.mp4', 'approved return pickup fixture', clock_timestamp() - interval '5 minutes', '08150000-0000-0000-0000-000000000002'),
  ('08150000-0000-0000-0000-000000000213', '08150000-0000-0000-0000-000000000013', '08150000-0000-0000-0000-000000000001', '08150000-0000-0000-0000-000000000313', 'awaiting_return_pickup', 'defective', 'P081 repeated pickup failure return', '081/customer/fail.mp4', 'approved return pickup fixture', clock_timestamp() - interval '5 minutes', '08150000-0000-0000-0000-000000000002'),
  ('08150000-0000-0000-0000-000000000215', '08150000-0000-0000-0000-000000000015', '08150000-0000-0000-0000-000000000001', '08150000-0000-0000-0000-000000000315', 'awaiting_return_pickup', 'defective', 'P081 reassignment return', '081/customer/reassign.mp4', 'approved return pickup fixture', clock_timestamp() - interval '5 minutes', '08150000-0000-0000-0000-000000000002'),
  ('08150000-0000-0000-0000-000000000216', '08150000-0000-0000-0000-000000000016', '08150000-0000-0000-0000-000000000001', '08150000-0000-0000-0000-000000000316', 'awaiting_return_pickup', 'defective', 'P081 no-items return', '081/customer/no-items.mp4', 'approved return pickup fixture', clock_timestamp() - interval '5 minutes', '08150000-0000-0000-0000-000000000002'),
  ('08150000-0000-0000-0000-000000000214', '08150000-0000-0000-0000-000000000014', '08150000-0000-0000-0000-000000000001', '08150000-0000-0000-0000-000000000314', 'pending_review', 'defective', 'P081 not yet approved return', '081/customer/pending.mp4', null, null, null);

insert into public.return_items (
  id, return_request_id, order_id, order_item_id, actual_item_name,
  quantity_to_collect, quantity_collected
)
values
  ('08150000-0000-0000-0000-000000000301', '08150000-0000-0000-0000-000000000210', '08150000-0000-0000-0000-000000000010', '08150000-0000-0000-0000-000000000201', 'P081 jersey', 2, 0),
  ('08150000-0000-0000-0000-000000000302', '08150000-0000-0000-0000-000000000210', '08150000-0000-0000-0000-000000000010', '08150000-0000-0000-0000-000000000202', 'P081 shorts', 1, 0),
  ('08150000-0000-0000-0000-000000000311', '08150000-0000-0000-0000-000000000211', '08150000-0000-0000-0000-000000000011', '08150000-0000-0000-0000-000000000211', 'P081 jersey', 2, 0),
  ('08150000-0000-0000-0000-000000000312', '08150000-0000-0000-0000-000000000211', '08150000-0000-0000-0000-000000000011', null, 'P081 wrong item without order link', 1, 0),
  ('08150000-0000-0000-0000-000000000321', '08150000-0000-0000-0000-000000000212', '08150000-0000-0000-0000-000000000012', null, 'P081 wrong item', 1, 0),
  ('08150000-0000-0000-0000-000000000331', '08150000-0000-0000-0000-000000000213', '08150000-0000-0000-0000-000000000013', '08150000-0000-0000-0000-000000000231', 'P081 jersey', 1, 0),
  ('08150000-0000-0000-0000-000000000351', '08150000-0000-0000-0000-000000000215', '08150000-0000-0000-0000-000000000015', '08150000-0000-0000-0000-000000000251', 'P081 jersey', 1, 0),
  ('08150000-0000-0000-0000-000000000341', '08150000-0000-0000-0000-000000000214', '08150000-0000-0000-0000-000000000014', '08150000-0000-0000-0000-000000000241', 'P081 jersey', 1, 0);

insert into public.cod_collections (order_id, status, expected_amount_vnd)
select id, 'uncollected'::public.cod_status, total_cod_vnd
from public.orders
where id between '08150000-0000-0000-0000-000000000010'::uuid
           and '08150000-0000-0000-0000-000000000016'::uuid;

-- Capture immutable business state before any P08.1 action.
insert into p081_before (
  name, quantity, quantity_collected, order_status, return_status,
  delivery_attempt_count, cod_status, cod_collected, cod_received,
  variant_on_hand, variant_reserved, variant_damaged,
  inspection_started_at, inspected_at, refund_amount_vnd, refund_request_id
)
select 'main_item_1', quantity_to_collect, quantity_collected, null, null,
  null, null, null, null, null, null, null, null, null, null, null
from public.return_items where id = '08150000-0000-0000-0000-000000000301';
insert into p081_before (
  name, quantity, quantity_collected, order_status, return_status,
  delivery_attempt_count, cod_status, cod_collected, cod_received,
  variant_on_hand, variant_reserved, variant_damaged,
  inspection_started_at, inspected_at, refund_amount_vnd, refund_request_id
)
select 'main_item_2', quantity_to_collect, quantity_collected, null, null,
  null, null, null, null, null, null, null, null, null, null, null
from public.return_items where id = '08150000-0000-0000-0000-000000000302';
insert into p081_before (
  name, order_status, return_status, delivery_attempt_count,
  cod_status, cod_collected, cod_received, variant_on_hand, variant_reserved,
  variant_damaged, inspection_started_at, inspected_at, refund_amount_vnd,
  refund_request_id
)
select 'main_aggregate', o.status, r.status, o.delivery_attempt_count,
  c.status, c.collected_amount_vnd, c.received_amount_vnd,
  v.on_hand, v.reserved, v.damaged, r.inspection_started_at, r.inspected_at,
  r.refund_amount_vnd, r.refund_request_id
from public.orders o
join public.return_requests r on r.order_id = o.id
join public.cod_collections c on c.order_id = o.id
join public.product_variants v on v.id = '08150000-0000-0000-0000-000000000111'::uuid
where o.id = '08150000-0000-0000-0000-000000000010';

-- Manager-only assignment; customer and shipper identities cannot even
-- enumerate request/task existence through this write API.
set local role authenticated;
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000001'::uuid);
select pg_temp.assert_p081_error(
  'customer cannot assign',
  $sql$select public.assign_return_pickup_task(
    '08150000-0000-0000-0000-000000000210'::uuid,
    '08150000-0000-0000-0000-000000000003'::uuid,
    '08150000-0000-0000-0000-000000000401'::uuid)$sql$,
  '42501', 'PERMISSION_DENIED'
);
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000003'::uuid);
select pg_temp.assert_p081_error(
  'shipper cannot assign',
  $sql$select public.assign_return_pickup_task(
    '08150000-0000-0000-0000-000000000210'::uuid,
    '08150000-0000-0000-0000-000000000003'::uuid,
    '08150000-0000-0000-0000-000000000402'::uuid)$sql$,
  '42501', 'PERMISSION_DENIED'
);
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000002'::uuid);
select pg_temp.assert_p081_error(
  'pending request is not assignable',
  $sql$select public.assign_return_pickup_task(
    '08150000-0000-0000-0000-000000000214'::uuid,
    '08150000-0000-0000-0000-000000000003'::uuid,
    '08150000-0000-0000-0000-000000000403'::uuid)$sql$,
  'PT409', 'APPROVAL_UNRESOLVED'
);

-- Status alone is never approval.  The same approved-looking request is
-- rejected when decision metadata is absent, belongs to a customer, or is in
-- the future.  Restore the pending fixture after each provenance check.
reset role;
update public.return_requests
set status = 'awaiting_return_pickup'::public.return_request_status,
    decided_by = null,
    decision_at = null,
    decision_reason = null
where id = '08150000-0000-0000-0000-000000000214'::uuid;
set local role authenticated;
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000002'::uuid);
select pg_temp.assert_p081_error(
  'awaiting status without approval metadata is rejected',
  $sql$select public.assign_return_pickup_task(
    '08150000-0000-0000-0000-000000000214'::uuid,
    '08150000-0000-0000-0000-000000000003'::uuid,
    '08150000-0000-0000-0000-000000000406'::uuid)$sql$,
  'PT409', 'APPROVAL_UNRESOLVED'
);
reset role;
update public.return_requests
set decided_by = '08150000-0000-0000-0000-000000000001'::uuid,
    decision_at = clock_timestamp() - interval '1 minute',
    decision_reason = 'customer-forged approval fixture'
where id = '08150000-0000-0000-0000-000000000214'::uuid;
set local role authenticated;
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000002'::uuid);
select pg_temp.assert_p081_error(
  'customer decision provenance is rejected',
  $sql$select public.assign_return_pickup_task(
    '08150000-0000-0000-0000-000000000214'::uuid,
    '08150000-0000-0000-0000-000000000003'::uuid,
    '08150000-0000-0000-0000-000000000407'::uuid)$sql$,
  'PT409', 'APPROVAL_UNRESOLVED'
);
reset role;
update public.return_requests
set decided_by = '08150000-0000-0000-0000-000000000002'::uuid,
    decision_at = clock_timestamp() + interval '1 minute',
    decision_reason = 'future approval fixture'
where id = '08150000-0000-0000-0000-000000000214'::uuid;
set local role authenticated;
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000002'::uuid);
select pg_temp.assert_p081_error(
  'future manager decision is rejected',
  $sql$select public.assign_return_pickup_task(
    '08150000-0000-0000-0000-000000000214'::uuid,
    '08150000-0000-0000-0000-000000000003'::uuid,
    '08150000-0000-0000-0000-000000000408'::uuid)$sql$,
  'PT409', 'APPROVAL_UNRESOLVED'
);
reset role;
update public.return_requests
set status = 'pending_review'::public.return_request_status,
    decided_by = null,
    decision_at = null,
    decision_reason = null
where id = '08150000-0000-0000-0000-000000000214'::uuid;
set local role authenticated;
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000002'::uuid);
select pg_temp.assert_p081_error(
  'approved request with no items is not assignable',
  $sql$select public.assign_return_pickup_task(
    '08150000-0000-0000-0000-000000000216'::uuid,
    '08150000-0000-0000-0000-000000000003'::uuid,
    '08150000-0000-0000-0000-000000000404'::uuid)$sql$,
  'PT409', 'ITEMS_MISMATCH'
);
select pg_temp.assert_p081_error(
  'unknown request is non-enumerating',
  $sql$select public.assign_return_pickup_task(
    '08150000-0000-0000-0000-000000009999'::uuid,
    '08150000-0000-0000-0000-000000000003'::uuid,
    '08150000-0000-0000-0000-000000000405'::uuid)$sql$,
  '42501', 'NOT_FOUND_OR_FORBIDDEN'
);

-- First assignment creates one assigned pickup task, pins order/item snapshot
-- data, and leaves the delivered order/COD/stock/inspection aggregate alone.
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000002'::uuid);
insert into p081_results(name, response)
select 'main_assign', public.assign_return_pickup_task(
  '08150000-0000-0000-0000-000000000210'::uuid,
  '08150000-0000-0000-0000-000000000003'::uuid,
  '08150000-0000-0000-0000-000000000410'::uuid
);
insert into p081_ids(name, id)
select 'main_task', (response ->> 'task_id')::uuid
from p081_results where name = 'main_assign';
select pg_temp.assert_p081(
  'assignment returns a task id',
  (select id is not null from p081_ids where name = 'main_task')
);
reset role;
select pg_temp.assert_p081(
  'first assignment pins task snapshot and remains assigned',
  (select t.kind = 'return_pickup'
      and t.status = 'assigned'
      and t.attempt_number = 1
      and t.assigned_shipper_id = '08150000-0000-0000-0000-000000000003'::uuid
      and t.accepted_at is null and t.started_at is null
      and t.amount_to_collect_vnd = 0
      and t.destination_name = 'P081 Main Recipient'
      and t.destination_phone = '0908100001'
      and t.destination_address = 'P081 main address'
   from public.delivery_tasks t where t.id = (select id from p081_ids where name = 'main_task'))
);
select pg_temp.assert_p081(
  'assignment creates exactly one active task',
  (select count(*) = 1 from public.delivery_tasks
   where return_request_id = '08150000-0000-0000-0000-000000000210'::uuid)
);
select pg_temp.assert_p081(
  'assignment pins every approved return item snapshot',
  (select count(*) = 2
       and bool_and(actual_item_name in ('P081 jersey', 'P081 shorts'))
      and bool_and(quantity_to_collect in (1, 2))
   from private.return_pickup_task_items
   where task_id = (select id from p081_ids where name = 'main_task')
     and return_request_id = '08150000-0000-0000-0000-000000000210'::uuid)
);
set local role authenticated;
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000002'::uuid);
select pg_temp.assert_p081_error(
  'authenticated cannot read private pickup snapshot',
  $sql$select count(*) from private.return_pickup_task_items$sql$,
  '42501'
);
reset role;

-- Exact assignment replay is byte-equivalent and a changed payload conflicts.
-- A legacy/imported task without a pinned plan cannot be adopted by a new
-- mutation. Remove only this fixture's snapshot inside a rolled-back savepoint.
savepoint p081_legacy_without_snapshot;
alter table private.return_pickup_task_items disable trigger user;
delete from private.return_pickup_task_items
where task_id=(select id from p081_ids where name='main_task');
alter table private.return_pickup_task_items enable trigger user;
set local role authenticated;
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000002');
select pg_temp.assert_p081_error('unproven legacy task is not silently adopted',
  $sql$select public.assign_return_pickup_task(
    '08150000-0000-0000-0000-000000000210',
    '08150000-0000-0000-0000-000000000003',
    '08150000-0000-0000-0000-000000000419',
    (select id from p081_ids where name='main_task'),
    '08150000-0000-0000-0000-000000000003')$sql$,
  'PT409','CUSTODY_UNRESOLVED');
rollback to savepoint p081_legacy_without_snapshot;
set local role authenticated;
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000002'::uuid);
insert into p081_results(name, response)
select 'main_assign_replay', public.assign_return_pickup_task(
  '08150000-0000-0000-0000-000000000210'::uuid,
  '08150000-0000-0000-0000-000000000003'::uuid,
  '08150000-0000-0000-0000-000000000410'::uuid
);
select pg_temp.assert_p081(
  'assignment replay is exact',
  (select response from p081_results where name = 'main_assign') =
  (select response from p081_results where name = 'main_assign_replay')
);
select pg_temp.assert_p081_error(
  'assignment key payload mismatch conflicts',
  $sql$select public.assign_return_pickup_task(
    '08150000-0000-0000-0000-000000000210'::uuid,
    '08150000-0000-0000-0000-000000000004'::uuid,
    '08150000-0000-0000-0000-000000000410'::uuid)$sql$,
  'PT409', 'IDEMPOTENCY_CONFLICT'
);
select pg_temp.assert_p081_error(
  'wrong expected task cannot reassign',
  $sql$select public.assign_return_pickup_task(
    '08150000-0000-0000-0000-000000000210'::uuid,
    '08150000-0000-0000-0000-000000000004'::uuid,
    '08150000-0000-0000-0000-000000000411'::uuid,
    '08150000-0000-0000-0000-000000009999'::uuid,
    '08150000-0000-0000-0000-000000000003'::uuid)$sql$,
  'PT409'
);

-- Invalid collection payloads are rejected before accepted/custody.  These
-- cases deliberately cover missing/foreign/unknown/duplicate item IDs and
-- zero, negative, partial and excess quantities.
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000003'::uuid);
select pg_temp.assert_p081_error(
  'partial pickup is rejected',
  $sql$select public.collect_return_items(
    (select id from p081_ids where name = 'main_task'),
    '08150000-0000-0000-0000-000000000501'::uuid,
    '[{"return_item_id":"08150000-0000-0000-0000-000000000301","quantity":1},{"return_item_id":"08150000-0000-0000-0000-000000000302","quantity":1}]'::jsonb)$sql$,
  'PT409', 'ITEMS_MISMATCH'
);
select pg_temp.assert_p081_error(
  'zero quantity is rejected',
  $sql$select public.collect_return_items(
    (select id from p081_ids where name = 'main_task'),
    '08150000-0000-0000-0000-000000000502'::uuid,
    '[{"return_item_id":"08150000-0000-0000-0000-000000000301","quantity":0},{"return_item_id":"08150000-0000-0000-0000-000000000302","quantity":1}]'::jsonb)$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p081_error(
  'negative quantity is rejected',
  $sql$select public.collect_return_items(
    (select id from p081_ids where name = 'main_task'),
    '08150000-0000-0000-0000-000000000503'::uuid,
    '[{"return_item_id":"08150000-0000-0000-0000-000000000301","quantity":-1},{"return_item_id":"08150000-0000-0000-000000000302","quantity":1}]'::jsonb)$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p081_error(
  'excess quantity is rejected',
  $sql$select public.collect_return_items(
    (select id from p081_ids where name = 'main_task'),
    '08150000-0000-0000-0000-000000000504'::uuid,
    '[{"return_item_id":"08150000-0000-0000-0000-000000000301","quantity":3},{"return_item_id":"08150000-0000-0000-0000-000000000302","quantity":1}]'::jsonb)$sql$,
  'PT409', 'ITEMS_MISMATCH'
);
select pg_temp.assert_p081_error(
  'missing planned item is rejected',
  $sql$select public.collect_return_items(
    (select id from p081_ids where name = 'main_task'),
    '08150000-0000-0000-0000-000000000505'::uuid,
    '[{"return_item_id":"08150000-0000-0000-0000-000000000301","quantity":2}]'::jsonb)$sql$,
  'PT409', 'ITEMS_MISMATCH'
);
select pg_temp.assert_p081_error(
  'foreign request item is rejected',
  $sql$select public.collect_return_items(
    (select id from p081_ids where name = 'main_task'),
    '08150000-0000-0000-0000-000000000506'::uuid,
    '[{"return_item_id":"08150000-0000-0000-0000-000000000301","quantity":2},{"return_item_id":"08150000-0000-0000-0000-000000000321","quantity":1}]'::jsonb)$sql$,
  'PT409', 'ITEMS_MISMATCH'
);
select pg_temp.assert_p081_error(
  'unknown item is rejected',
  $sql$select public.collect_return_items(
    (select id from p081_ids where name = 'main_task'),
    '08150000-0000-0000-0000-000000000507'::uuid,
     '[{"return_item_id":"08150000-0000-0000-0000-000000000302","quantity":1},{"return_item_id":"08150000-0000-0000-0000-000000009999","quantity":2}]'::jsonb)$sql$,
  'PT409', 'ITEMS_MISMATCH'
);
select pg_temp.assert_p081_error(
  'duplicate item IDs are rejected',
  $sql$select public.collect_return_items(
    (select id from p081_ids where name = 'main_task'),
    '08150000-0000-0000-0000-000000000508'::uuid,
    '[{"return_item_id":"08150000-0000-0000-0000-000000000301","quantity":1},{"return_item_id":"08150000-0000-0000-0000-000000000301","quantity":1},{"return_item_id":"08150000-0000-0000-0000-000000000302","quantity":1}]'::jsonb)$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p081_error(
  'unknown task is non-enumerating',
  $sql$select public.collect_return_items(
    '08150000-0000-0000-0000-000000009999'::uuid,
    '08150000-0000-0000-0000-000000000509'::uuid,
    '[{"return_item_id":"08150000-0000-0000-0000-000000000301","quantity":2},{"return_item_id":"08150000-0000-0000-0000-000000000302","quantity":1}]'::jsonb)$sql$,
  '42501', 'NOT_FOUND_OR_FORBIDDEN'
);
reset role;
select pg_temp.assert_p081(
  'invalid collection attempts leave task assigned',
  (select status = 'assigned' and accepted_at is null and started_at is null
   from public.delivery_tasks where id = (select id from p081_ids where name = 'main_task'))
  and (select quantity_collected = 0 from public.return_items
       where id = '08150000-0000-0000-0000-000000000301'::uuid)
  and (select quantity_collected = 0 from public.return_items
       where id = '08150000-0000-0000-0000-000000000302'::uuid)
);

-- Updating source rows after assignment must not change the pinned task
-- snapshot.  A future migration may make these source rows append-only; the
-- fixture tolerates that stronger protection and still tests destination pin.
reset role;
do $$
begin
  begin
    update public.return_items
    set actual_item_name = 'P081 source row changed', quantity_to_collect = 9
    where id = '08150000-0000-0000-0000-000000000301'::uuid;
  exception when others then
    null;
  end;
  begin
    update public.orders
    set recipient_name = 'P081 Mutated Recipient',
        address_detail = 'P081 mutated address'
    where id = '08150000-0000-0000-0000-000000000010'::uuid;
  exception when others then
    null;
  end;
end;
$$;
-- Force a late event failure after the task/request/items have been updated.
-- The subtransaction must roll them all back, including the request ledger.
create function public.p081_collect_late_fault() returns trigger
language plpgsql as $$
begin
  if new.reason='return_pickup_collected' then
    raise exception using errcode='P0811',message='P081_TEST_LATE_FAULT';
  end if;
  return new;
end;
$$;
create trigger p081_collect_late_fault after insert on public.business_events
for each row execute function public.p081_collect_late_fault();
set local role authenticated;
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000003'::uuid);
select pg_temp.assert_p081_error('late collect failure rolls back all writes',
 $sql$select public.collect_return_items(
  (select id from p081_ids where name='main_task'),
  '08150000-0000-0000-0000-000000000509',
  '[{"return_item_id":"08150000-0000-0000-0000-000000000301","quantity":2},{"return_item_id":"08150000-0000-0000-0000-000000000302","quantity":1}]')$sql$,
 'P0811','P081_TEST_LATE_FAULT');
reset role;
select pg_temp.assert_p081('late fault leaves no custody/collection/ledger',
 (select status='assigned' and accepted_at is null and started_at is null
  from public.delivery_tasks where id=(select id from p081_ids where name='main_task'))
 and (select status='awaiting_return_pickup' from public.return_requests
  where id='08150000-0000-0000-0000-000000000210')
 and not exists(select 1 from public.return_items
  where return_request_id='08150000-0000-0000-0000-000000000210' and quantity_collected<>0)
 and not exists(select 1 from private.return_pickup_custody
  where task_id=(select id from p081_ids where name='main_task'))
 and not exists(select 1 from private.return_pickup_requests
  where request_id='08150000-0000-0000-0000-000000000509')
 and not exists(select 1 from public.business_events
  where task_id=(select id from p081_ids where name='main_task') and reason='return_pickup_collected'));
drop trigger p081_collect_late_fault on public.business_events;
drop function public.p081_collect_late_fault();
set local role authenticated;
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000003'::uuid);
insert into p081_results(name, response)
select 'main_collect', public.collect_return_items(
  (select id from p081_ids where name = 'main_task'),
  '08150000-0000-0000-0000-000000000510'::uuid,
  '[{"return_item_id":"08150000-0000-0000-0000-000000000301","quantity":2},{"return_item_id":"08150000-0000-0000-0000-000000000302","quantity":1}]'::jsonb
);
reset role;
select pg_temp.assert_p081(
  'full pickup atomically starts task and changes return state',
  (select status = 'in_transit' and accepted_at is not null
      and started_at is not null and accepted_at = started_at
   from public.delivery_tasks where id = (select id from p081_ids where name = 'main_task'))
  and (select status = 'returning_to_store'
       from public.return_requests
       where id = '08150000-0000-0000-0000-000000000210'::uuid)
  and (select quantity_collected = (select quantity from p081_before where name = 'main_item_1')
       from public.return_items where id = '08150000-0000-0000-0000-000000000301'::uuid)
  and (select quantity_collected = (select quantity from p081_before where name = 'main_item_2')
       from public.return_items where id = '08150000-0000-0000-0000-000000000302'::uuid)
);
select pg_temp.assert_p081(
  'pickup does not mutate order COD inventory or inspection/refund',
  (select o.status = b.order_status
      and o.delivery_attempt_count = b.delivery_attempt_count
      and c.status = b.cod_status
      and c.collected_amount_vnd = b.cod_collected
      and c.received_amount_vnd = b.cod_received
      and v.on_hand = b.variant_on_hand
      and v.reserved = b.variant_reserved
      and v.damaged = b.variant_damaged
      and r.inspection_started_at is not distinct from b.inspection_started_at
      and r.inspected_at is not distinct from b.inspected_at
      and r.refund_amount_vnd is not distinct from b.refund_amount_vnd
      and r.refund_request_id is not distinct from b.refund_request_id
   from public.orders o
   join public.return_requests r on r.order_id = o.id
   join public.cod_collections c on c.order_id = o.id
   join public.product_variants v on v.id = '08150000-0000-0000-0000-000000000111'::uuid
   cross join p081_before b
   where o.id = '08150000-0000-0000-0000-000000000010'::uuid
     and b.name = 'main_aggregate')
  and not exists (select 1 from public.delivery_attempts
                  where task_id = (select id from p081_ids where name = 'main_task'))
  and not exists (select 1 from public.inventory_movements
                  where return_request_id = '08150000-0000-0000-0000-000000000210'::uuid)
);
select pg_temp.assert_p081(
  'destination snapshot survives source order mutation',
  (select destination_name = 'P081 Main Recipient'
      and destination_address = 'P081 main address'
   from public.delivery_tasks where id = (select id from p081_ids where name = 'main_task'))
);

-- Idempotent assignment replay is checked before the now-changed business
-- preconditions.  A retry after collection must still return the original
-- ACK, not leak custody/state or item details.
set local role authenticated;
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000002'::uuid);
insert into p081_results(name, response)
select 'main_assign_after_collect', public.assign_return_pickup_task(
  '08150000-0000-0000-0000-000000000210'::uuid,
  '08150000-0000-0000-0000-000000000003'::uuid,
  '08150000-0000-0000-0000-000000000410'::uuid
);
select pg_temp.assert_p081(
  'assignment replay after collection is exact',
  (select response from p081_results where name = 'main_assign') =
  (select response from p081_results where name = 'main_assign_after_collect')
);
reset role;

-- Collect replay is exact; changing its payload under the same key conflicts.
set local role authenticated;
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000003'::uuid);
insert into p081_results(name, response)
select 'main_collect_replay', public.collect_return_items(
  (select id from p081_ids where name = 'main_task'),
  '08150000-0000-0000-0000-000000000510'::uuid,
  '[{"return_item_id":"08150000-0000-0000-0000-000000000301","quantity":2},{"return_item_id":"08150000-0000-0000-0000-000000000302","quantity":1}]'::jsonb
);
select pg_temp.assert_p081(
  'collect replay is exact',
  (select response from p081_results where name = 'main_collect') =
  (select response from p081_results where name = 'main_collect_replay')
);
select pg_temp.assert_p081_error(
  'collect key payload mismatch conflicts',
  $sql$select public.collect_return_items(
    (select id from p081_ids where name = 'main_task'),
    '08150000-0000-0000-0000-000000000510'::uuid,
    '[{"return_item_id":"08150000-0000-0000-0000-000000000301","quantity":1},{"return_item_id":"08150000-0000-0000-0000-000000000302","quantity":1}]'::jsonb)$sql$,
  'PT409', 'IDEMPOTENCY_CONFLICT'
);
select pg_temp.assert_p081_error(
  'new collect key after custody conflicts',
  $sql$select public.collect_return_items(
    (select id from p081_ids where name = 'main_task'),
    '08150000-0000-0000-0000-000000000511'::uuid,
    '[{"return_item_id":"08150000-0000-0000-0000-000000000301","quantity":2},{"return_item_id":"08150000-0000-0000-0000-000000000302","quantity":1}]'::jsonb)$sql$,
   'PT409', 'STATE_CONFLICT'
);
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000002'::uuid);
select pg_temp.assert_p081_error(
  'reassignment after custody is blocked',
  $sql$select public.assign_return_pickup_task(
    '08150000-0000-0000-0000-000000000210'::uuid,
    '08150000-0000-0000-0000-000000000004'::uuid,
    '08150000-0000-0000-0000-000000000512'::uuid,
    (select id from p081_ids where name = 'main_task'),
    '08150000-0000-0000-0000-000000000003'::uuid)$sql$,
  'PT409'
);

-- Reassignment is allowed only before custody.  The previous shipper is
-- denied after the CAS and cannot read the raw task row/history.
reset role;
set local role authenticated;
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000002'::uuid);
insert into p081_results(name, response)
select 'reassign_first', public.assign_return_pickup_task(
  '08150000-0000-0000-0000-000000000215'::uuid,
  '08150000-0000-0000-0000-000000000003'::uuid,
  '08150000-0000-0000-0000-000000000520'::uuid
);
insert into p081_ids(name, id)
select 'reassign_task', (response ->> 'task_id')::uuid
from p081_results where name = 'reassign_first';
insert into p081_results(name, response)
select 'reassign_second', public.assign_return_pickup_task(
  '08150000-0000-0000-0000-000000000215'::uuid,
  '08150000-0000-0000-0000-000000000004'::uuid,
  '08150000-0000-0000-0000-000000000521'::uuid,
  (select id from p081_ids where name = 'reassign_task'),
  '08150000-0000-0000-0000-000000000003'::uuid
);
select pg_temp.assert_p081(
  'reassignment keeps task identity and no custody',
  (select response ->> 'task_id' = (select id::text from p081_ids where name = 'reassign_task')
   from p081_results where name = 'reassign_second')
  and (select assigned_shipper_id = '08150000-0000-0000-0000-000000000004'::uuid
          and status = 'assigned' and accepted_at is null and started_at is null
       from public.delivery_tasks where id = (select id from p081_ids where name = 'reassign_task'))
);
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000003'::uuid);
select pg_temp.assert_p081_error(
  'old shipper cannot collect after reassignment',
  $sql$select public.collect_return_items(
    (select id from p081_ids where name = 'reassign_task'),
    '08150000-0000-0000-0000-000000000522'::uuid,
    '[{"return_item_id":"08150000-0000-0000-0000-000000000351","quantity":1}]'::jsonb)$sql$,
  '42501', 'NOT_FOUND_OR_FORBIDDEN'
);
select pg_temp.assert_p081_error(
  'old shipper cannot fail after reassignment',
  $sql$select public.fail_return_pickup_task(
    (select id from p081_ids where name = 'reassign_task'),
    '08150000-0000-0000-0000-000000000523'::uuid,
    'unreachable', 'old shipper')$sql$,
  '42501', 'NOT_FOUND_OR_FORBIDDEN'
);
select pg_temp.assert_p081(
  'old shipper sees no raw reassigned task',
  (select count(*) = 0 from public.delivery_tasks
   where id = (select id from p081_ids where name = 'reassign_task'))
);
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000004'::uuid);
insert into p081_results(name, response)
select 'reassign_collect', public.collect_return_items(
  (select id from p081_ids where name = 'reassign_task'),
  '08150000-0000-0000-0000-000000000524'::uuid,
  '[{"return_item_id":"08150000-0000-0000-0000-000000000351","quantity":1}]'::jsonb
);
reset role;

-- A pickup failure is only legal before collection.  It leaves the request
-- awaiting pickup and creates no outbound attempt.  Repeating this chain at
-- least three times proves that the outbound two-attempt cap is not reused.
set local role authenticated;
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000002'::uuid);
insert into p081_results(name, response)
select 'fail_assign_1', public.assign_return_pickup_task(
  '08150000-0000-0000-0000-000000000213'::uuid,
  '08150000-0000-0000-0000-000000000003'::uuid,
  '08150000-0000-0000-0000-000000000530'::uuid
);
insert into p081_ids(name, id)
select 'fail_task_1', (response ->> 'task_id')::uuid
from p081_results where name = 'fail_assign_1';
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000003'::uuid);
insert into p081_results(name, response)
select 'fail_1', public.fail_return_pickup_task(
  (select id from p081_ids where name = 'fail_task_1'),
  '08150000-0000-0000-0000-000000000531'::uuid,
  'unreachable', 'P081 first pickup failure'
);
insert into p081_results(name, response)
select 'fail_1_replay', public.fail_return_pickup_task(
  (select id from p081_ids where name = 'fail_task_1'),
  '08150000-0000-0000-0000-000000000531'::uuid,
  'unreachable', 'P081 first pickup failure'
);
select pg_temp.assert_p081(
  'failure replay is exact',
  (select response from p081_results where name = 'fail_1') =
  (select response from p081_results where name = 'fail_1_replay')
);
select pg_temp.assert_p081_error(
  'failure key payload mismatch conflicts',
  $sql$select public.fail_return_pickup_task(
    (select id from p081_ids where name = 'fail_task_1'),
    '08150000-0000-0000-0000-000000000531'::uuid,
    'reschedule', 'changed payload')$sql$,
  'PT409', 'IDEMPOTENCY_CONFLICT'
);
reset role;
select pg_temp.assert_p081(
  'failed pickup emits one manager notification per event and replay adds none',
  (select count(*) = 1
      and bool_and(p.role = 'manager'::public.user_role)
   from public.notifications n
   join public.profiles p on p.id = n.recipient_id
   where n.event_id = (
     select (response ->> 'event_id')::uuid
     from p081_results where name = 'fail_1'
   )
     and n.subject_id = (select id from p081_ids where name = 'fail_task_1')
     and n.title = 'Lấy hàng trả thất bại'
     and n.body = 'Một nhiệm vụ lấy hàng trả thất bại cần được xử lý.')
  and (select count(*) = 1
       from public.business_events e
       where e.id = (
         select (response ->> 'event_id')::uuid
         from p081_results where name = 'fail_1'
       )
         and e.reason = 'return_pickup_failed'
         and e.subject_id = (select id from p081_ids where name = 'fail_task_1'))
  and not exists (
    select 1
    from public.notifications n
    join public.profiles p on p.id = n.recipient_id
    where n.event_id = (
      select (response ->> 'event_id')::uuid
      from p081_results where name = 'fail_1'
    )
      and (n.recipient_id <> '08150000-0000-0000-0000-000000000002'::uuid
           or p.role <> 'manager'::public.user_role)
  )
);
select pg_temp.assert_p081_error('failed pickup plan cannot change without reapproval',
 $sql$update public.return_items set quantity_to_collect=quantity_to_collect+1
 where return_request_id=(select return_request_id from public.delivery_tasks
 where id=(select id from p081_ids where name='fail_task_1'))$sql$,
 'PT409','PLAN_IMMUTABLE');
select pg_temp.assert_p081_error('failed pickup plan cannot gain an unapproved item',
 $sql$insert into public.return_items(return_request_id,order_id,actual_item_name,quantity_to_collect)
 select return_request_id,order_id,'Unapproved added item',1
 from public.delivery_tasks where id=(select id from p081_ids where name='fail_task_1')$sql$,
 'PT409','PLAN_IMMUTABLE');
select pg_temp.assert_p081_error('collected plan stays immutable after custody',
 $sql$update public.return_items set actual_item_name='Changed after custody'
 where return_request_id='08150000-0000-0000-0000-000000000210'$sql$,
 'PT409','PLAN_IMMUTABLE');
select pg_temp.assert_p081(
  'first failed pickup leaves request awaiting and no attempt',
  (select t.status = 'failed' and t.accepted_at is null and t.started_at is null
      and r.status = 'awaiting_return_pickup'
   from public.delivery_tasks t
   join public.return_requests r on r.id = t.return_request_id
   where t.id = (select id from p081_ids where name = 'fail_task_1'))
  and not exists (select 1 from public.delivery_attempts
                  where task_id = (select id from p081_ids where name = 'fail_task_1'))
);
set local role authenticated;
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000002'::uuid);
select pg_temp.assert_p081_error(
  'new assignment after failure requires failed-task CAS pair',
  $sql$select public.assign_return_pickup_task(
    '08150000-0000-0000-0000-000000000213'::uuid,
    '08150000-0000-0000-0000-000000000004'::uuid,
    '08150000-0000-0000-0000-000000000537'::uuid)$sql$,
  'PT409', 'STALE_ASSIGNMENT'
);
reset role;
set local role authenticated;
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000003'::uuid);
select pg_temp.assert_p081(
  'failed pickup detail is restricted and has no item rows',
  (select count(*) = 1 and bool_and(snapshot_scope = 'restricted'
      and order_id is null and return_request_id is null
      and item_source = 'unavailable')
   from public.read_my_delivery_tasks(
     (select id from p081_ids where name = 'fail_task_1')))
  and (select count(*) = 0 from public.read_my_delivery_task_items(
     (select id from p081_ids where name = 'fail_task_1')))
);
reset role;

-- Second and third independent pickup tasks are legal after failures.
set local role authenticated;
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000002'::uuid);
insert into p081_results(name, response)
select 'fail_assign_2', public.assign_return_pickup_task(
  '08150000-0000-0000-0000-000000000213'::uuid,
  '08150000-0000-0000-0000-000000000004'::uuid,
  '08150000-0000-0000-0000-000000000532'::uuid,
  (select id from p081_ids where name = 'fail_task_1'),
  '08150000-0000-0000-0000-000000000003'::uuid
);
insert into p081_ids(name, id)
select 'fail_task_2', (response ->> 'task_id')::uuid
from p081_results where name = 'fail_assign_2';
set local role authenticated;
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000004'::uuid);
select pg_temp.assert_p081(
  'new shipper cannot unlock failed task history',
  (select count(*) = 0 from public.read_my_delivery_tasks(
     (select id from p081_ids where name = 'fail_task_1')))
  and (select count(*) = 1 from public.read_my_delivery_tasks(
     (select id from p081_ids where name = 'fail_task_2')))
);
reset role;
set local role authenticated;
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000004'::uuid);
insert into p081_results(name, response)
select 'fail_2', public.fail_return_pickup_task(
  (select id from p081_ids where name = 'fail_task_2'),
  '08150000-0000-0000-0000-000000000533'::uuid,
  'reschedule', 'P081 second pickup failure'
);
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000002'::uuid);
select pg_temp.assert_p081_error(
  'older failed task cannot satisfy latest failed-task CAS',
  $sql$select public.assign_return_pickup_task(
    '08150000-0000-0000-0000-000000000213'::uuid,
    '08150000-0000-0000-0000-000000000005'::uuid,
    '08150000-0000-0000-0000-000000000538'::uuid,
    (select id from p081_ids where name = 'fail_task_1'),
    '08150000-0000-0000-0000-000000000003'::uuid)$sql$,
  'PT409', 'STALE_ASSIGNMENT'
);
insert into p081_results(name, response)
select 'fail_assign_3', public.assign_return_pickup_task(
  '08150000-0000-0000-0000-000000000213'::uuid,
  '08150000-0000-0000-0000-000000000005'::uuid,
  '08150000-0000-0000-0000-000000000534'::uuid,
  (select id from p081_ids where name = 'fail_task_2'),
  '08150000-0000-0000-0000-000000000004'::uuid
);
insert into p081_ids(name, id)
select 'fail_task_3', (response ->> 'task_id')::uuid
from p081_results where name = 'fail_assign_3';
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000005'::uuid);
insert into p081_results(name, response)
select 'fail_3', public.fail_return_pickup_task(
  (select id from p081_ids where name = 'fail_task_3'),
  '08150000-0000-0000-0000-000000000535'::uuid,
  'other', 'P081 third pickup failure'
);
reset role;
select pg_temp.assert_p081(
  'three failed pickups are retained without outbound cap',
  (select count(*) = 3 and bool_and(status = 'failed')
   from public.delivery_tasks
   where return_request_id = '08150000-0000-0000-0000-000000000213'::uuid)
  and (select status = 'awaiting_return_pickup'
       from public.return_requests where id = '08150000-0000-0000-0000-000000000213'::uuid)
  and (select delivery_attempt_count = 0
       from public.orders where id = '08150000-0000-0000-0000-000000000013'::uuid)
  and not exists (select 1 from public.delivery_attempts a
                  join public.delivery_tasks t on t.id = a.task_id
                  where t.return_request_id = '08150000-0000-0000-0000-000000000213'::uuid)
);
select pg_temp.assert_p081(
  'failed pickup does not change inventory COD or return inspection',
  (select v.on_hand = 40 and v.reserved = 7 and v.damaged = 0
      and c.status = 'uncollected'::public.cod_status
      and c.collected_amount_vnd = 0 and c.received_amount_vnd = 0
      and r.inspection_started_at is null and r.inspected_at is null
      and r.refund_amount_vnd is null and r.refund_request_id is null
   from public.product_variants v
   join public.cod_collections c on c.order_id = '08150000-0000-0000-0000-000000000013'::uuid
   join public.return_requests r on r.id = '08150000-0000-0000-0000-000000000213'::uuid
   where v.id = '08150000-0000-0000-0000-000000000111'::uuid)
);

-- A new key cannot fail a task after collection/custody; the same shipper
-- can only replay the successful collect request.
set local role authenticated;
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000004'::uuid);
select pg_temp.assert_p081_error(
  'failure after reassigned collection is blocked',
  $sql$select public.fail_return_pickup_task(
    (select id from p081_ids where name = 'reassign_task'),
    '08150000-0000-0000-0000-000000000536'::uuid,
    'unreachable', 'after collection')$sql$,
  'PT409', 'CUSTODY_UNRESOLVED'
);
reset role;

-- Transactional isolation is part of this suite's contract.
-- Pickup handover: one report, never a manager receipt/inspection/restock.
set local role authenticated;
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000003');
select pg_temp.assert_p081('handover starts unreported',
 (public.get_my_return_pickup_handover((select id from p081_ids where name='main_task'))->>'reported')='false');
select pg_temp.assert_p081_error('partial handover rejected',
 $sql$select public.report_return_pickup_handover((select id from p081_ids where name='main_task'),
 '08150000-0000-0000-0000-000000000601',
 '[{"return_item_id":"08150000-0000-0000-0000-000000000301","quantity":1}]')$sql$,
 'PT409','ITEMS_MISMATCH');
reset role;
create function public.p081_handover_late_fault() returns trigger language plpgsql as $$
begin
 if new.title='Đã báo bàn giao hàng thu hồi' then
  raise exception using errcode='P0812',message='P081_HANDOVER_LATE_FAULT';
 end if;
 return new;
end;
$$;
create trigger p081_handover_late_fault after insert on public.notifications
for each row execute function public.p081_handover_late_fault();
set local role authenticated;
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000003');
select pg_temp.assert_p081_error('late handover failure rolls back',
 $sql$select public.report_return_pickup_handover((select id from p081_ids where name='main_task'),
 '08150000-0000-0000-0000-000000000602',
 '[{"return_item_id":"08150000-0000-0000-0000-000000000301","quantity":2},{"return_item_id":"08150000-0000-0000-0000-000000000302","quantity":1}]')$sql$,
 'P0812','P081_HANDOVER_LATE_FAULT');
reset role;
select pg_temp.assert_p081('late fault leaves no handover event/report/key',
 not exists(select 1 from public.business_events where task_id=(select id from p081_ids where name='main_task')
  and reason='return_pickup_handover_reported')
 and not exists(select 1 from private.return_pickup_handover_reports)
 and not exists(select 1 from private.return_pickup_requests where request_id='08150000-0000-0000-0000-000000000602'));
drop trigger p081_handover_late_fault on public.notifications;
drop function public.p081_handover_late_fault();
create temp table p081_handover_before as select
 (select row_to_json(t) from public.delivery_tasks t where id=(select id from p081_ids where name='main_task')) task,
 (select row_to_json(r) from public.return_requests r where id='08150000-0000-0000-0000-000000000210') request,
 (select count(*) from public.inventory_movements) inventory,
 (select jsonb_agg(to_jsonb(c) order by c.order_id) from public.cod_collections c) cod;
set local role authenticated;
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000003');
insert into p081_results(name,response) select 'handover',public.report_return_pickup_handover(
 (select id from p081_ids where name='main_task'),'08150000-0000-0000-0000-000000000603',
 '[{"return_item_id":"08150000-0000-0000-0000-000000000301","quantity":2},{"return_item_id":"08150000-0000-0000-0000-000000000302","quantity":1}]');
select pg_temp.assert_p081('same key replays exact handover ACK',
 public.report_return_pickup_handover((select id from p081_ids where name='main_task'),
 '08150000-0000-0000-0000-000000000603',
 '[{"return_item_id":"08150000-0000-0000-0000-000000000301","quantity":2},{"return_item_id":"08150000-0000-0000-0000-000000000302","quantity":1}]')
 = (select response from p081_results where name='handover'));
select pg_temp.assert_p081('marker read is minimal and reported',
 (select c->>'reported'='true' and c->>'reported_at' is not null
 and (select count(*) from jsonb_object_keys(c))=3
 from (select public.get_my_return_pickup_handover((select id from p081_ids where name='main_task')) c) q));
select pg_temp.assert_p081_error('new key cannot double report',
 $sql$select public.report_return_pickup_handover((select id from p081_ids where name='main_task'),
 '08150000-0000-0000-0000-000000000604',
 '[{"return_item_id":"08150000-0000-0000-0000-000000000301","quantity":2},{"return_item_id":"08150000-0000-0000-0000-000000000302","quantity":1}]')$sql$,
 'PT409','STATE_CONFLICT');
select pg_temp.assert_p081_error('handover key payload mismatch',
 $sql$select public.report_return_pickup_handover((select id from p081_ids where name='main_task'),
 '08150000-0000-0000-0000-000000000603',
 '[{"return_item_id":"08150000-0000-0000-0000-000000000301","quantity":1}]')$sql$,
 'PT409','IDEMPOTENCY_CONFLICT');
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000004');
select pg_temp.assert_p081_error('other shipper marker denied',
 $sql$select public.get_my_return_pickup_handover((select id from p081_ids where name='main_task'))$sql$,
 '42501','NOT_FOUND_OR_FORBIDDEN');
select pg_temp.assert_p081_error('other shipper report denied',
 $sql$select public.report_return_pickup_handover((select id from p081_ids where name='main_task'),
 '08150000-0000-0000-0000-000000000605',
 '[{"return_item_id":"08150000-0000-0000-0000-000000000301","quantity":2}]')$sql$,
 '42501','NOT_FOUND_OR_FORBIDDEN');
select pg_temp.set_p081_claims('08150000-0000-0000-0000-000000000002');
select pg_temp.assert_p081_error('manager cannot impersonate shipper report',
 $sql$select public.get_my_return_pickup_handover((select id from p081_ids where name='main_task'))$sql$,
 '42501','PERMISSION_DENIED');
reset role;
select pg_temp.assert_p081('report does not mutate task/request/inventory/COD',
 (select to_jsonb(t)=(select task::jsonb from p081_handover_before) from public.delivery_tasks t
 where id=(select id from p081_ids where name='main_task'))
 and (select to_jsonb(r)=(select request::jsonb from p081_handover_before) from public.return_requests r
 where id='08150000-0000-0000-0000-000000000210')
 and (select count(*)=(select inventory from p081_handover_before) from public.inventory_movements)
 and (select jsonb_agg(to_jsonb(c) order by c.order_id) from public.cod_collections c)
 is not distinct from (select cod from p081_handover_before));
select pg_temp.assert_p081('one owner notification, no customer/shipper',
 (select count(*)=1 and bool_and(p.role='manager') from public.notifications n
 join public.profiles p on p.id=n.recipient_id
 where n.event_id=(select (response->>'event_id')::uuid from p081_results where name='handover')));
select pg_temp.assert_p081('handover ACL authenticated only',
 has_function_privilege('authenticated','public.report_return_pickup_handover(uuid,uuid,jsonb)','execute')
 and not has_function_privilege('anon','public.report_return_pickup_handover(uuid,uuid,jsonb)','execute')
 and not has_table_privilege('authenticated','private.return_pickup_handover_reports','select'));
select 'return_pickup_production.sql: PASS';
rollback;
