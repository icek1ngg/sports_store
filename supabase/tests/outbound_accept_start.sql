-- P04.1 production accept/start contract.
--
-- This suite is deliberately a real-schema test: it applies no temporary RPC
-- replacement and exercises the public functions through authenticated/anon
-- roles.  Fixture rows and the test fault trigger are rolled back together at
-- the end of the file.

begin;
set constraints all deferred;

create or replace function pg_temp.set_outbound_claims(
  p_user_id uuid,
  p_claimed_role text default 'authenticated'
) returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
  perform set_config(
    'request.jwt.claims',
    case when p_user_id is null then '' else
      jsonb_build_object(
        'sub', p_user_id::text,
        'role', p_claimed_role,
        'aud', p_claimed_role
      )::text
    end,
    true
  );
end;
$$;

create or replace function pg_temp.clear_outbound_claims()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
end;
$$;

create or replace function pg_temp.assert_outbound(
  p_label text,
  p_condition boolean
) returns void
language plpgsql
as $$
begin
  if coalesce(p_condition, false) is not true then
    raise exception 'P04.1 outbound accept/start test failed: %', p_label;
  end if;
end;
$$;

create or replace function pg_temp.assert_outbound_error(
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
      'P04.1 outbound test failed: % (expected SQLSTATE %, got %: %)',
      p_label, p_state, coalesce(l_state, 'success'), coalesce(l_message, '');
  end if;
  if p_message is not null and l_message is distinct from p_message then
    raise exception
      'P04.1 outbound test failed: % (expected message %, got %)',
      p_label, p_message, coalesce(l_message, '');
  end if;
end;
$$;

create or replace function pg_temp.assert_outbound_error_any(
  p_label text,
  p_sql text,
  p_state text,
  p_messages text[]
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

  if l_state is distinct from p_state or not (l_message = any(p_messages)) then
    raise exception
      'P04.1 outbound test failed: % (expected %/%; got %/%)',
      p_label, p_state, array_to_string(p_messages, '|'),
      coalesce(l_state, 'success'), coalesce(l_message, '');
  end if;
end;
$$;

-- Stable identities are only fixture data.  Auth's profile trigger creates the
-- rows; role changes below are server-side setup, not user-editable claims.
insert into auth.users (id, email)
values
  ('04120000-0000-0000-0000-000000000001'::uuid, 'p041-customer@example.invalid'),
  ('04120000-0000-0000-0000-000000000002'::uuid, 'p041-manager@example.invalid'),
  ('04120000-0000-0000-0000-000000000003'::uuid, 'p041-shipper-a@example.invalid'),
  ('04120000-0000-0000-0000-000000000004'::uuid, 'p041-shipper-b@example.invalid'),
  ('04120000-0000-0000-0000-000000000005'::uuid, 'p041-revoked-shipper@example.invalid');

update public.profiles
set role = case
  when id = '04120000-0000-0000-0000-000000000002'::uuid then 'manager'::public.user_role
  when id in (
    '04120000-0000-0000-0000-000000000003'::uuid,
    '04120000-0000-0000-0000-000000000004'::uuid,
    '04120000-0000-0000-0000-000000000005'::uuid
  ) then 'shipper'::public.user_role
  else 'customer'::public.user_role
end
where id in (
  '04120000-0000-0000-0000-000000000001'::uuid,
  '04120000-0000-0000-0000-000000000002'::uuid,
  '04120000-0000-0000-0000-000000000003'::uuid,
  '04120000-0000-0000-0000-000000000004'::uuid,
  '04120000-0000-0000-0000-000000000005'::uuid
);

insert into public.categories (id, code, name)
values ('04120000-0000-0000-0000-000000000100'::uuid, 'P041', 'P04.1 fixture');
insert into public.products (id, category_id, name, description)
values (
  '04120000-0000-0000-0000-000000000101'::uuid,
  '04120000-0000-0000-0000-000000000100'::uuid,
  'P04.1 fixture product',
  'Production accept/start test product'
);
insert into public.product_variants (
  id, product_id, sku, label, attributes, price_vnd
)
select x.id, '04120000-0000-0000-0000-000000000101'::uuid,
  'P041-' || x.n, 'P04.1 variant ' || x.n, '{}'::jsonb, 100000
from (values
  ('04120000-0000-0000-0000-000000000111'::uuid, '01'),
  ('04120000-0000-0000-0000-000000000112'::uuid, '02'),
  ('04120000-0000-0000-0000-000000000113'::uuid, '03'),
  ('04120000-0000-0000-0000-000000000114'::uuid, '04'),
  ('04120000-0000-0000-0000-000000000115'::uuid, '05'),
  ('04120000-0000-0000-0000-000000000116'::uuid, '06'),
  ('04120000-0000-0000-0000-000000000117'::uuid, '07'),
  ('04120000-0000-0000-0000-000000000118'::uuid, '08'),
  ('04120000-0000-0000-0000-000000000119'::uuid, '09'),
  ('04120000-0000-0000-0000-000000000120'::uuid, '10')
) as x(id, n);

-- The first pair deliberately leaves one unit on hand after dispatch.  The
-- remaining balances are isolated per order so rollback and replay assertions
-- cannot be masked by another fixture order.
update public.product_variants v set on_hand=x.on_hand, reserved=x.reserved
from (values
  ('04120000-0000-0000-0000-000000000111'::uuid, 3, 2),
  ('04120000-0000-0000-0000-000000000112'::uuid, 2, 1),
  ('04120000-0000-0000-0000-000000000113'::uuid, 1, 0),
  ('04120000-0000-0000-0000-000000000114'::uuid, 5, 1),
  ('04120000-0000-0000-0000-000000000115'::uuid, 5, 1),
  ('04120000-0000-0000-0000-000000000116'::uuid, 5, 1),
  ('04120000-0000-0000-0000-000000000117'::uuid, 5, 1),
  ('04120000-0000-0000-0000-000000000118'::uuid, 5, 1),
  ('04120000-0000-0000-0000-000000000119'::uuid, 5, 1),
  ('04120000-0000-0000-0000-000000000120'::uuid, 5, 1)) as x(variant_id,on_hand,reserved) where v.id=x.variant_id;

insert into public.orders (
  id, customer_id, request_id, status, recipient_name, recipient_phone,
  address_detail, latitude, longitude, subtotal_vnd
)
select x.id, '04120000-0000-0000-0000-000000000001'::uuid, x.id,
  x.status::public.order_status, 'P041 recipient ' || x.n,
  '0900000' || x.n, 'P04.1 Hanoi address ' || x.n,
  21.0285, 105.8542, 100000
from (values
  ('04120000-0000-0000-0000-000000000010'::uuid, 'normal', 'awaiting_pickup'),
  ('04120000-0000-0000-0000-000000000011'::uuid, 'borrowed', 'awaiting_pickup'),
  ('04120000-0000-0000-0000-000000000012'::uuid, 'dirty-cod', 'awaiting_pickup'),
  ('04120000-0000-0000-0000-000000000013'::uuid, 'mismatch', 'awaiting_pickup'),
  ('04120000-0000-0000-0000-000000000014'::uuid, 'retry', 'awaiting_pickup'),
  ('04120000-0000-0000-0000-000000000015'::uuid, 'invalid-state', 'preparing'),
  ('04120000-0000-0000-0000-000000000016'::uuid, 'late-fault', 'awaiting_pickup'),
  ('04120000-0000-0000-0000-000000000017'::uuid, 'return-kind', 'delivered'),
  ('04120000-0000-0000-0000-000000000018'::uuid, 'attempt-limit', 'awaiting_pickup')
) as x(id, n, status);

insert into public.order_items (
  id, order_id, product_id, variant_id, product_name, variant_label,
  attributes, unit_price_vnd, quantity
)
values
  ('04120000-0000-0000-0000-000000000201'::uuid, '04120000-0000-0000-0000-000000000010'::uuid,
    '04120000-0000-0000-0000-000000000101'::uuid, '04120000-0000-0000-0000-000000000111'::uuid,
    'P04.1 fixture product', 'P04.1 variant 01', '{}'::jsonb, 100000, 2),
  ('04120000-0000-0000-0000-000000000202'::uuid, '04120000-0000-0000-0000-000000000010'::uuid,
    '04120000-0000-0000-0000-000000000101'::uuid, '04120000-0000-0000-0000-000000000112'::uuid,
    'P04.1 fixture product', 'P04.1 variant 02', '{}'::jsonb, 100000, 1),
  ('04120000-0000-0000-0000-000000000203'::uuid, '04120000-0000-0000-0000-000000000011'::uuid,
    '04120000-0000-0000-0000-000000000101'::uuid, '04120000-0000-0000-0000-000000000113'::uuid,
    'P04.1 fixture product', 'P04.1 variant 03', '{}'::jsonb, 100000, 2),
  ('04120000-0000-0000-0000-000000000204'::uuid, '04120000-0000-0000-0000-000000000012'::uuid,
    '04120000-0000-0000-0000-000000000101'::uuid, '04120000-0000-0000-0000-000000000114'::uuid,
    'P04.1 fixture product', 'P04.1 variant 04', '{}'::jsonb, 100000, 1),
  ('04120000-0000-0000-0000-000000000205'::uuid, '04120000-0000-0000-0000-000000000013'::uuid,
    '04120000-0000-0000-0000-000000000101'::uuid, '04120000-0000-0000-0000-000000000115'::uuid,
    'P04.1 fixture product', 'P04.1 variant 05', '{}'::jsonb, 100000, 1),
  ('04120000-0000-0000-0000-000000000206'::uuid, '04120000-0000-0000-0000-000000000014'::uuid,
    '04120000-0000-0000-0000-000000000101'::uuid, '04120000-0000-0000-0000-000000000116'::uuid,
    'P04.1 fixture product', 'P04.1 variant 06', '{}'::jsonb, 100000, 1),
  ('04120000-0000-0000-0000-000000000207'::uuid, '04120000-0000-0000-0000-000000000015'::uuid,
    '04120000-0000-0000-0000-000000000101'::uuid, '04120000-0000-0000-0000-000000000117'::uuid,
    'P04.1 fixture product', 'P04.1 variant 07', '{}'::jsonb, 100000, 1),
  ('04120000-0000-0000-0000-000000000208'::uuid, '04120000-0000-0000-0000-000000000016'::uuid,
    '04120000-0000-0000-0000-000000000101'::uuid, '04120000-0000-0000-0000-000000000118'::uuid,
    'P04.1 fixture product', 'P04.1 variant 08', '{}'::jsonb, 100000, 1),
  ('04120000-0000-0000-0000-000000000209'::uuid, '04120000-0000-0000-0000-000000000017'::uuid,
    '04120000-0000-0000-0000-000000000101'::uuid, '04120000-0000-0000-0000-000000000119'::uuid,
    'P04.1 fixture product', 'P04.1 variant 09', '{}'::jsonb, 100000, 1),
  ('04120000-0000-0000-0000-000000000210'::uuid, '04120000-0000-0000-0000-000000000018'::uuid,
    '04120000-0000-0000-0000-000000000101'::uuid, '04120000-0000-0000-0000-000000000120'::uuid,
    'P04.1 fixture product', 'P04.1 variant 10', '{}'::jsonb, 100000, 1);

-- Reservation evidence is part of the accept precondition.  The borrowed
-- reservation order intentionally has an evidence row for two units while
-- its authoritative balance contains zero reserved units; accept must reject
-- it instead of trusting a movement row in isolation.
insert into public.inventory_movements (
  id, variant_id, order_id, event_id, kind, on_hand_delta, reserved_delta,
  damaged_delta, actor_id, reason
)
values
  ('04120000-0000-0000-0000-000000000501'::uuid, '04120000-0000-0000-0000-000000000111'::uuid,
    '04120000-0000-0000-0000-000000000010'::uuid, '04120000-0000-0000-0000-000000000501'::uuid,
    'reserve'::public.inventory_movement_kind, 0, 2, 0,
    '04120000-0000-0000-0000-000000000001'::uuid, 'P04.1 fixture reserve'),
  ('04120000-0000-0000-0000-000000000502'::uuid, '04120000-0000-0000-0000-000000000112'::uuid,
    '04120000-0000-0000-0000-000000000010'::uuid, '04120000-0000-0000-0000-000000000502'::uuid,
    'reserve'::public.inventory_movement_kind, 0, 1, 0,
    '04120000-0000-0000-0000-000000000001'::uuid, 'P04.1 fixture reserve'),
  ('04120000-0000-0000-0000-000000000503'::uuid, '04120000-0000-0000-0000-000000000113'::uuid,
    '04120000-0000-0000-0000-000000000011'::uuid, '04120000-0000-0000-0000-000000000503'::uuid,
    'reserve'::public.inventory_movement_kind, 0, 2, 0,
    '04120000-0000-0000-0000-000000000001'::uuid, 'P04.1 borrowed reserve'),
  ('04120000-0000-0000-0000-000000000504'::uuid, '04120000-0000-0000-0000-000000000114'::uuid,
    '04120000-0000-0000-0000-000000000012'::uuid, '04120000-0000-0000-0000-000000000504'::uuid,
    'reserve'::public.inventory_movement_kind, 0, 1, 0,
    '04120000-0000-0000-0000-000000000001'::uuid, 'P04.1 fixture reserve'),
  ('04120000-0000-0000-0000-000000000505'::uuid, '04120000-0000-0000-0000-000000000115'::uuid,
    '04120000-0000-0000-0000-000000000013'::uuid, '04120000-0000-0000-0000-000000000505'::uuid,
    'reserve'::public.inventory_movement_kind, 0, 1, 0,
    '04120000-0000-0000-0000-000000000001'::uuid, 'P04.1 fixture reserve'),
  ('04120000-0000-0000-0000-000000000506'::uuid, '04120000-0000-0000-0000-000000000116'::uuid,
    '04120000-0000-0000-0000-000000000014'::uuid, '04120000-0000-0000-0000-000000000506'::uuid,
    'reserve'::public.inventory_movement_kind, 0, 1, 0,
    '04120000-0000-0000-0000-000000000001'::uuid, 'P04.1 fixture reserve'),
  ('04120000-0000-0000-0000-000000000507'::uuid, '04120000-0000-0000-0000-000000000117'::uuid,
    '04120000-0000-0000-0000-000000000015'::uuid, '04120000-0000-0000-0000-000000000507'::uuid,
    'reserve'::public.inventory_movement_kind, 0, 1, 0,
    '04120000-0000-0000-0000-000000000001'::uuid, 'P04.1 fixture reserve'),
  ('04120000-0000-0000-0000-000000000508'::uuid, '04120000-0000-0000-0000-000000000118'::uuid,
    '04120000-0000-0000-0000-000000000016'::uuid, '04120000-0000-0000-0000-000000000508'::uuid,
    'reserve'::public.inventory_movement_kind, 0, 1, 0,
    '04120000-0000-0000-0000-000000000001'::uuid, 'P04.1 fixture reserve'),
  ('04120000-0000-0000-0000-000000000509'::uuid, '04120000-0000-0000-0000-000000000119'::uuid,
    '04120000-0000-0000-0000-000000000017'::uuid, '04120000-0000-0000-0000-000000000509'::uuid,
    'reserve'::public.inventory_movement_kind, 0, 1, 0,
    '04120000-0000-0000-0000-000000000001'::uuid, 'P04.1 fixture reserve'),
  ('04120000-0000-0000-0000-000000000510'::uuid, '04120000-0000-0000-0000-000000000120'::uuid,
    '04120000-0000-0000-0000-000000000018'::uuid, '04120000-0000-0000-0000-000000000510'::uuid,
    'reserve'::public.inventory_movement_kind, 0, 1, 0,
    '04120000-0000-0000-0000-000000000001'::uuid, 'P04.1 fixture reserve');

insert into public.cod_collections (
  order_id, shipper_id, status, expected_amount_vnd
)
select x, '04120000-0000-0000-0000-000000000003'::uuid,
  'uncollected'::public.cod_status, 130000
from unnest(array[
  '04120000-0000-0000-0000-000000000010'::uuid,
  '04120000-0000-0000-0000-000000000011'::uuid,
  '04120000-0000-0000-0000-000000000013'::uuid,
  '04120000-0000-0000-0000-000000000014'::uuid,
  '04120000-0000-0000-0000-000000000015'::uuid,
  '04120000-0000-0000-0000-000000000016'::uuid,
  '04120000-0000-0000-0000-000000000018'::uuid
]::uuid[]) as ids(x);
insert into public.cod_collections (
  order_id, shipper_id, status, expected_amount_vnd, collected_amount_vnd,
  collected_at, collected_by
) values (
  '04120000-0000-0000-0000-000000000012'::uuid,
  '04120000-0000-0000-0000-000000000003'::uuid,
  'collected'::public.cod_status, 130000, 130000, now(),
  '04120000-0000-0000-0000-000000000003'::uuid
);

insert into public.delivery_tasks (
  id, order_id, kind, assigned_shipper_id, assigned_by, status,
  attempt_number, destination_name, destination_phone, destination_address,
  destination_latitude, destination_longitude, amount_to_collect_vnd,
  assigned_at
)
select x.task_id, x.order_id, x.kind::public.delivery_task_kind,
  '04120000-0000-0000-0000-000000000003'::uuid,
  '04120000-0000-0000-0000-000000000002'::uuid,
  'assigned'::public.delivery_task_status, x.attempt_number,
  o.recipient_name, o.recipient_phone, o.address_detail,
  o.latitude, o.longitude,
  case when x.kind = 'outbound' then o.total_cod_vnd else 0 end,
  now()
from (values
  ('04120000-0000-0000-0000-000000000101'::uuid, '04120000-0000-0000-0000-000000000010'::uuid, 'outbound', 1),
  ('04120000-0000-0000-0000-000000000102'::uuid, '04120000-0000-0000-0000-000000000011'::uuid, 'outbound', 1),
  ('04120000-0000-0000-0000-000000000103'::uuid, '04120000-0000-0000-0000-000000000012'::uuid, 'outbound', 1),
  ('04120000-0000-0000-0000-000000000104'::uuid, '04120000-0000-0000-0000-000000000013'::uuid, 'outbound', 1),
  ('04120000-0000-0000-0000-000000000105'::uuid, '04120000-0000-0000-0000-000000000014'::uuid, 'outbound', 1),
  ('04120000-0000-0000-0000-000000000107'::uuid, '04120000-0000-0000-0000-000000000015'::uuid, 'outbound', 1),
  ('04120000-0000-0000-0000-000000000108'::uuid, '04120000-0000-0000-0000-000000000016'::uuid, 'outbound', 1),
  ('04120000-0000-0000-0000-000000000109'::uuid, '04120000-0000-0000-0000-000000000018'::uuid, 'outbound', 1)
) as x(task_id, order_id, kind, attempt_number)
join public.orders o on o.id = x.order_id;

-- Return-pickup is a separate kind and must never enter outbound dispatch.
insert into public.return_requests (
  id, order_id, customer_id, request_id, status, reason, description,
  video_object_path
) values (
  '04120000-0000-0000-0000-000000000301'::uuid,
  '04120000-0000-0000-0000-000000000017'::uuid,
  '04120000-0000-0000-0000-000000000001'::uuid,
  '04120000-0000-0000-0000-000000000302'::uuid,
  'awaiting_return_pickup'::public.return_request_status,
  'wrong_item'::public.return_reason, 'P04.1 return-kind fixture',
  '04120000-0000-0000-0000-000000000301/video.mp4'
);
insert into public.delivery_tasks (
  id, order_id, return_request_id, kind, assigned_shipper_id, assigned_by,
  status, attempt_number, destination_name, destination_phone,
  destination_address, destination_latitude, destination_longitude,
  amount_to_collect_vnd, assigned_at
) values (
  '04120000-0000-0000-0000-000000000110'::uuid,
  '04120000-0000-0000-0000-000000000017'::uuid,
  '04120000-0000-0000-0000-000000000301'::uuid,
  'return_pickup'::public.delivery_task_kind,
  '04120000-0000-0000-0000-000000000003'::uuid,
  '04120000-0000-0000-0000-000000000002'::uuid,
  'assigned'::public.delivery_task_status, 1, 'P041 return recipient',
  '0900000017', 'P04.1 return address', 21.0285, 105.8542, 0, now()
);

-- Function signatures and API ACL are part of the production contract.
do $$
declare
  l_accept oid := to_regprocedure('public.accept_delivery_task(uuid,uuid)');
  l_start oid := to_regprocedure('public.start_delivery_task(uuid,uuid)');
begin
  perform pg_temp.assert_outbound('accept RPC exists', l_accept is not null);
  perform pg_temp.assert_outbound('start RPC exists', l_start is not null);
  perform pg_temp.assert_outbound(
    'accept execute is authenticated-only',
    has_function_privilege('authenticated', l_accept, 'EXECUTE')
      and not has_function_privilege('anon', l_accept, 'EXECUTE')
      and not has_function_privilege('service_role', l_accept, 'EXECUTE')
      and not has_function_privilege('public', l_accept, 'EXECUTE')
  );
  perform pg_temp.assert_outbound(
    'start execute is authenticated-only',
    has_function_privilege('authenticated', l_start, 'EXECUTE')
      and not has_function_privilege('anon', l_start, 'EXECUTE')
      and not has_function_privilege('service_role', l_start, 'EXECUTE')
      and not has_function_privilege('public', l_start, 'EXECUTE')
  );
  perform pg_temp.assert_outbound(
    'client cannot write delivery/inventory tables',
    not has_table_privilege('authenticated', 'public.delivery_tasks', 'UPDATE')
      and not has_table_privilege('authenticated', 'public.product_variants', 'UPDATE')
      and not has_table_privilege('authenticated', 'public.inventory_movements', 'INSERT')
  );
  perform pg_temp.assert_outbound(
    'client cannot read private dispatch/custody/request ledgers',
    not has_table_privilege('authenticated', 'private.outbound_dispatches', 'SELECT')
      and not has_table_privilege('authenticated', 'private.outbound_custody_acceptances', 'SELECT')
      and not has_table_privilege('authenticated', 'private.outbound_command_requests', 'SELECT')
  );
  perform pg_temp.assert_outbound(
    'private outbound helpers are not client executable',
    not exists (
      select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'private'
        and p.proname like '%outbound%'
        and has_function_privilege('authenticated', p.oid, 'EXECUTE')
    )
  );
end;
$$;

-- Authentication and authorization fail before a task or order is disclosed.
set local role authenticated;
select pg_temp.clear_outbound_claims();
select pg_temp.assert_outbound_error(
  'authenticated without a JWT is rejected',
  $sql$select public.accept_delivery_task(
    '04120000-0000-0000-0000-000000000101'::uuid,
    '04120000-0000-0000-0000-000000000401'::uuid)$sql$,
  '42501', 'AUTH_REQUIRED'
);
set local role anon;
select pg_temp.clear_outbound_claims();
select pg_temp.assert_outbound_error(
  'anon cannot execute accept',
  $sql$select public.accept_delivery_task(
    '04120000-0000-0000-0000-000000000101'::uuid,
    '04120000-0000-0000-0000-000000000402'::uuid)$sql$,
  '42501'
);
reset role;

set local role authenticated;
select pg_temp.set_outbound_claims(
  '04120000-0000-0000-0000-000000000001'::uuid, 'manager'
);
select pg_temp.assert_outbound_error(
  'customer with forged manager claim is rejected',
  $sql$select public.accept_delivery_task(
    '04120000-0000-0000-0000-000000000101'::uuid,
    '04120000-0000-0000-0000-000000000403'::uuid)$sql$,
  '42501', 'PERMISSION_DENIED'
);
select pg_temp.set_outbound_claims(
  '04120000-0000-0000-0000-000000000004'::uuid
);
select pg_temp.assert_outbound_error(
  'other assigned shipper is rejected',
  $sql$select public.accept_delivery_task(
    '04120000-0000-0000-0000-000000000101'::uuid,
    '04120000-0000-0000-0000-000000000404'::uuid)$sql$,
  '42501', 'PERMISSION_DENIED'
);
select pg_temp.assert_outbound_error(
  'nonexistent task is uniformly rejected',
  $sql$select public.accept_delivery_task(
    '04120000-0000-0000-0000-000000009999'::uuid,
    '04120000-0000-0000-0000-000000000405'::uuid)$sql$,
  '42501', 'PERMISSION_DENIED'
);
select pg_temp.assert_outbound_error(
  'null task is invalid',
  $sql$select public.accept_delivery_task(
    null, '04120000-0000-0000-0000-000000000406'::uuid)$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_outbound_error(
  'null request is invalid',
  $sql$select public.start_delivery_task(
    '04120000-0000-0000-0000-000000000101'::uuid, null)$sql$,
  '22023', 'INVALID_ARGUMENT'
);
reset role;

-- First accept dispatches every order item exactly once and proves custody.
set local role authenticated;
select pg_temp.set_outbound_claims(
  '04120000-0000-0000-0000-000000000003'::uuid
);
create temp table p041_accept_result on commit drop as
select public.accept_delivery_task(
  '04120000-0000-0000-0000-000000000101'::uuid,
  '04120000-0000-0000-0000-000000000410'::uuid
) as response;
reset role;
select pg_temp.assert_outbound(
  'accept response has stable envelope',
  (select response ?& array[
    'task_id', 'order_id', 'operation', 'task_status', 'order_status',
    'attempt_number', 'delivery_attempt_count', 'accepted_at', 'started_at',
    'dispatch_event_id', 'event_id', 'request_id'
  ] from p041_accept_result)
  and (select response->>'operation' = 'accept'
    and response->>'task_id' = '04120000-0000-0000-0000-000000000101'
    and response->>'order_id' = '04120000-0000-0000-0000-000000000010'
    and response->>'task_status' = 'accepted'
    and response->>'order_status' = 'awaiting_pickup'
    and response->>'attempt_number' = '1'
    and response->>'delivery_attempt_count' = '0'
    and response->>'request_id' = '04120000-0000-0000-0000-000000000410'
    and response->>'accepted_at' is not null
    and response->>'started_at' is null
    and response->>'dispatch_event_id' is not null
    and response->>'event_id' is not null
  from p041_accept_result)
);
select pg_temp.assert_outbound(
  'accept updates task and leaves order count at zero',
  (select status = 'accepted' and accepted_at is not null and started_at is null
      from public.delivery_tasks
      where id = '04120000-0000-0000-0000-000000000101'::uuid)
  and (select status = 'awaiting_pickup' and delivery_attempt_count = 0
      from public.orders where id = '04120000-0000-0000-0000-000000000010'::uuid)
  and not exists (
    select 1 from public.delivery_attempts
    where order_id = '04120000-0000-0000-0000-000000000010'::uuid
  )
);
select pg_temp.assert_outbound(
  'accept decrements on-hand and reservation without going negative',
  (select on_hand = 1 and reserved = 0 from public.product_variants
    where id = '04120000-0000-0000-0000-000000000111'::uuid)
  and (select on_hand = 1 and reserved = 0 from public.product_variants
    where id = '04120000-0000-0000-0000-000000000112'::uuid)
  and (select count(*) = 2 from public.inventory_movements
    where order_id = '04120000-0000-0000-0000-000000000010'::uuid
      and kind = 'dispatch'
      and on_hand_delta < 0 and reserved_delta < 0)
  and (select count(*) = 2 from public.inventory_movements
    where order_id = '04120000-0000-0000-0000-000000000010'::uuid
      and event_id = ((select response->>'dispatch_event_id' from p041_accept_result)::uuid))
);
select pg_temp.assert_outbound(
  'accept records dispatch and custody proof privately',
  (select initial_task_id = '04120000-0000-0000-0000-000000000101'::uuid
      and holder_id = '04120000-0000-0000-0000-000000000003'::uuid
      and event_id = ((select response->>'dispatch_event_id' from p041_accept_result)::uuid)
      and jsonb_typeof(items_snapshot) = 'array'
      and jsonb_array_length(items_snapshot) = 2
    from private.outbound_dispatches
    where order_id = '04120000-0000-0000-0000-000000000010'::uuid)
  and (select task_id = '04120000-0000-0000-0000-000000000101'::uuid
      and order_id = '04120000-0000-0000-0000-000000000010'::uuid
      and holder_id = '04120000-0000-0000-0000-000000000003'::uuid
      and dispatch_event_id = ((select response->>'dispatch_event_id' from p041_accept_result)::uuid)
      and attempt_number = 1
    from private.outbound_custody_acceptances
    where order_id = '04120000-0000-0000-0000-000000000010'::uuid)
);
select pg_temp.assert_outbound_error(
  'command ledger is immutable',
  $sql$update private.outbound_command_requests
    set response = response
    where actor_id = '04120000-0000-0000-0000-000000000003'::uuid
      and request_id = '04120000-0000-0000-0000-000000000410'::uuid$sql$,
  '55000', 'P04.1 outbound ledgers are append-only'
);
select pg_temp.assert_outbound_error(
  'dispatch proof ledger is immutable',
  $sql$delete from private.outbound_dispatches
    where order_id = '04120000-0000-0000-0000-000000000010'::uuid$sql$,
  '55000', 'P04.1 outbound ledgers are append-only'
);

-- Start changes only the task/order state and count.  It does not create an
-- attempt result or dispatch inventory again.
set local role authenticated;
select pg_temp.set_outbound_claims(
  '04120000-0000-0000-0000-000000000003'::uuid
);
create temp table p041_start_result on commit drop as
select public.start_delivery_task(
  '04120000-0000-0000-0000-000000000101'::uuid,
  '04120000-0000-0000-0000-000000000411'::uuid
) as response;
reset role;
select pg_temp.assert_outbound(
  'start response has state/count and no attempt result',
  (select response->>'operation' = 'start'
    and response->>'task_status' = 'in_transit'
    and response->>'order_status' = 'delivering'
    and response->>'attempt_number' = '1'
    and response->>'delivery_attempt_count' = '1'
    and response->>'accepted_at' is not null
    and response->>'started_at' is not null
    and response->>'dispatch_event_id' = (select response->>'dispatch_event_id' from p041_accept_result)
    and response->>'event_id' is not null
    and response->>'request_id' = '04120000-0000-0000-0000-000000000411'
    from p041_start_result)
  and (select status = 'in_transit' and started_at is not null
      from public.delivery_tasks where id = '04120000-0000-0000-0000-000000000101'::uuid)
  and (select status = 'delivering' and delivery_attempt_count = 1
      from public.orders where id = '04120000-0000-0000-0000-000000000010'::uuid)
  and (select count(*) = 0 from public.delivery_attempts
      where order_id = '04120000-0000-0000-0000-000000000010'::uuid)
  and (select count(*) = 4 from public.inventory_movements
      where order_id = '04120000-0000-0000-0000-000000000010'::uuid)
);

-- Exact request replay returns the committed JSON, while a reused key with a
-- different operation/target conflicts and a new key re-evaluates state.
set local role authenticated;
select pg_temp.set_outbound_claims(
  '04120000-0000-0000-0000-000000000003'::uuid
);
create temp table p041_accept_replay_result on commit drop as
select public.accept_delivery_task(
    '04120000-0000-0000-0000-000000000101'::uuid,
    '04120000-0000-0000-0000-000000000410'::uuid
) as response;
reset role;
select pg_temp.assert_outbound(
  'accept replay after start is byte-equivalent',
  (select response = (select response from p041_accept_result)
     from p041_accept_replay_result)
);
set local role authenticated;
select pg_temp.set_outbound_claims(
  '04120000-0000-0000-0000-000000000003'::uuid
);
select pg_temp.assert_outbound_error(
  'same key with start operation conflicts',
  $sql$select public.start_delivery_task(
    '04120000-0000-0000-0000-000000000101'::uuid,
    '04120000-0000-0000-0000-000000000410'::uuid)$sql$,
  'PT409', 'IDEMPOTENCY_CONFLICT'
);
select pg_temp.assert_outbound_error(
  'same key with another task conflicts',
  $sql$select public.accept_delivery_task(
    '04120000-0000-0000-0000-000000000102'::uuid,
    '04120000-0000-0000-0000-000000000410'::uuid)$sql$,
  'PT409', 'IDEMPOTENCY_CONFLICT'
);
select pg_temp.assert_outbound_error(
  'new accept key after start is state conflict',
  $sql$select public.accept_delivery_task(
    '04120000-0000-0000-0000-000000000101'::uuid,
    '04120000-0000-0000-0000-000000000412'::uuid)$sql$,
  'PT409', 'STATE_CONFLICT'
);
reset role;

-- A role revocation and an assignment change must be checked before replaying
-- a stored response; a ledger row is not an authorization bypass.
update public.profiles
set role = 'customer'::public.user_role
where id = '04120000-0000-0000-0000-000000000003'::uuid;
set local role authenticated;
select pg_temp.set_outbound_claims(
  '04120000-0000-0000-0000-000000000003'::uuid
);
select pg_temp.assert_outbound_error(
  'revoked shipper cannot replay accept',
  $sql$select public.accept_delivery_task(
    '04120000-0000-0000-0000-000000000101'::uuid,
    '04120000-0000-0000-0000-000000000410'::uuid)$sql$,
  '42501', 'PERMISSION_DENIED'
);
reset role;
update public.profiles
set role = 'shipper'::public.user_role
where id = '04120000-0000-0000-0000-000000000003'::uuid;
-- The production custody trigger correctly rejects this mutation.  Disable
-- user triggers only around this privileged corruption fixture so the public
-- replay path can prove assignment is rechecked before returning a ledger
-- response; the trigger is restored immediately in the same transaction.
alter table public.delivery_tasks disable trigger user;
update public.delivery_tasks
set assigned_shipper_id = '04120000-0000-0000-0000-000000000004'::uuid
where id = '04120000-0000-0000-0000-000000000101'::uuid;
alter table public.delivery_tasks enable trigger user;
set local role authenticated;
select pg_temp.set_outbound_claims(
  '04120000-0000-0000-0000-000000000003'::uuid
);
select pg_temp.assert_outbound_error(
  'changed assignment cannot replay accept',
  $sql$select public.accept_delivery_task(
    '04120000-0000-0000-0000-000000000101'::uuid,
    '04120000-0000-0000-0000-000000000410'::uuid)$sql$,
  '42501', 'PERMISSION_DENIED'
);
reset role;
alter table public.delivery_tasks disable trigger user;
update public.delivery_tasks
set assigned_shipper_id = '04120000-0000-0000-0000-000000000003'::uuid
where id = '04120000-0000-0000-0000-000000000101'::uuid;
alter table public.delivery_tasks enable trigger user;

-- First-attempt guards: state/kind, dirty COD and a reservation borrowed by a
-- different order all fail without changing task, stock, or dispatch proof.
set local role authenticated;
select pg_temp.set_outbound_claims(
  '04120000-0000-0000-0000-000000000003'::uuid
);
select pg_temp.assert_outbound_error(
  'order/task state mismatch is rejected',
  $sql$select public.accept_delivery_task(
    '04120000-0000-0000-0000-000000000107'::uuid,
    '04120000-0000-0000-0000-000000000420'::uuid)$sql$,
  'PT409', 'STATE_CONFLICT'
);
select pg_temp.assert_outbound_error(
  'return pickup kind is denied by the outbound API',
  $sql$select public.accept_delivery_task(
    '04120000-0000-0000-0000-000000000110'::uuid,
    '04120000-0000-0000-0000-000000000421'::uuid)$sql$,
  '42501', 'PERMISSION_DENIED'
);
select pg_temp.assert_outbound_error(
  'dirty COD is rejected',
  $sql$select public.accept_delivery_task(
    '04120000-0000-0000-0000-000000000103'::uuid,
    '04120000-0000-0000-0000-000000000422'::uuid)$sql$,
  'PT409', 'COD_CONFLICT'
);
select pg_temp.assert_outbound_error_any(
  'borrowed reservation is rejected',
  $sql$select public.accept_delivery_task(
    '04120000-0000-0000-0000-000000000102'::uuid,
    '04120000-0000-0000-0000-000000000423'::uuid)$sql$,
  'PT409', array['ITEMS_MISMATCH', 'CUSTODY_UNRESOLVED', 'INVENTORY_UNAVAILABLE', 'STOCK_CONFLICT']
);
reset role;
select pg_temp.assert_outbound(
  'guard failures leave first-attempt rows untouched',
  (select status = 'assigned' and accepted_at is null and started_at is null
      from public.delivery_tasks where id = '04120000-0000-0000-0000-000000000102'::uuid)
  and (select on_hand = 1 and reserved = 0 from public.product_variants
      where id = '04120000-0000-0000-0000-000000000113'::uuid)
  and not exists (select 1 from private.outbound_dispatches
      where order_id = '04120000-0000-0000-0000-000000000011'::uuid)
  and (select count(*) = 1 from public.inventory_movements
      where order_id = '04120000-0000-0000-0000-000000000011'::uuid
        and kind = 'reserve')
  and not exists (select 1 from public.inventory_movements
      where order_id = '04120000-0000-0000-0000-000000000011'::uuid
        and kind = 'dispatch')
);

-- Mutating the authoritative order item after dispatch invalidates the proof;
-- start must not trust a stale items_snapshot.
set local role authenticated;
select pg_temp.set_outbound_claims(
  '04120000-0000-0000-0000-000000000003'::uuid
);
select public.accept_delivery_task(
  '04120000-0000-0000-0000-000000000104'::uuid,
  '04120000-0000-0000-0000-000000000424'::uuid
);
reset role;
update public.order_items
set quantity = quantity + 1
where id = '04120000-0000-0000-0000-000000000205'::uuid;
set local role authenticated;
select pg_temp.set_outbound_claims(
  '04120000-0000-0000-0000-000000000003'::uuid
);
select pg_temp.assert_outbound_error_any(
  'mismatched order items/dispatch proof is rejected',
  $sql$select public.start_delivery_task(
    '04120000-0000-0000-0000-000000000104'::uuid,
    '04120000-0000-0000-0000-000000000425'::uuid)$sql$,
  'PT409', array['ITEMS_MISMATCH', 'CUSTODY_UNRESOLVED']
);
reset role;

-- Build a real failed first attempt, then seed the explicit second-task
-- precondition.  The retry path reuses the same holder/proof and dispatches no
-- stock a second time; no failure/retry API is assumed by this suite.
set local role authenticated;
select pg_temp.set_outbound_claims(
  '04120000-0000-0000-0000-000000000003'::uuid
);
select public.accept_delivery_task(
  '04120000-0000-0000-0000-000000000105'::uuid,
  '04120000-0000-0000-0000-000000000430'::uuid);
select public.start_delivery_task(
  '04120000-0000-0000-0000-000000000105'::uuid,
  '04120000-0000-0000-0000-000000000431'::uuid);
reset role;
update public.delivery_tasks
set status = 'failed'::public.delivery_task_status,
    completed_at = now(), failure_reason = 'P04.1 seeded failed attempt'
where id = '04120000-0000-0000-0000-000000000105'::uuid;
update public.orders
set status = 'awaiting_pickup'::public.order_status
where id = '04120000-0000-0000-0000-000000000014'::uuid;
insert into public.delivery_attempts (
  task_id, order_id, attempt_number, task_kind, result, reason, shipper_id
) values (
  '04120000-0000-0000-0000-000000000105'::uuid,
  '04120000-0000-0000-0000-000000000014'::uuid,
  1, 'outbound'::public.delivery_task_kind, 'failed',
  'P04.1 seeded previous failed result',
  '04120000-0000-0000-0000-000000000003'::uuid
);
insert into public.delivery_tasks (
  id, order_id, kind, assigned_shipper_id, assigned_by, status,
  attempt_number, destination_name, destination_phone, destination_address,
  destination_latitude, destination_longitude, amount_to_collect_vnd,
  assigned_at
)
select '04120000-0000-0000-0000-000000000106'::uuid, o.id,
  'outbound'::public.delivery_task_kind,
  '04120000-0000-0000-0000-000000000003'::uuid,
  '04120000-0000-0000-0000-000000000002'::uuid,
  'assigned'::public.delivery_task_status, 2,
  o.recipient_name, o.recipient_phone, o.address_detail, o.latitude,
  o.longitude, o.total_cod_vnd, now()
from public.orders o
where o.id = '04120000-0000-0000-0000-000000000014'::uuid;
create temp table p041_retry_stock_before on commit drop as
select id as variant_id, on_hand, reserved
from public.product_variants
where id = '04120000-0000-0000-0000-000000000116'::uuid;
create temp table p041_retry_dispatch_before on commit drop as
select count(*)::bigint as n
from private.outbound_dispatches
where order_id = '04120000-0000-0000-0000-000000000014'::uuid;

-- Known loss/damage invalidates the same-holder full-goods precondition.
-- Privileged incident seed is not the future P07.4 report RPC.
savepoint p041_known_loss;
insert into public.business_events(actor_id,subject_type,subject_id,task_id,incident_kind,request_id,reason)
values ('04120000-0000-0000-0000-000000000003'::uuid, 'delivery_task',
  '04120000-0000-0000-0000-000000000105'::uuid,
  '04120000-0000-0000-0000-000000000105'::uuid, 'lost',
  '04120000-0000-0000-0000-000000000460'::uuid, 'TEST-ONLY known loss');
set local role authenticated;
select pg_temp.set_outbound_claims('04120000-0000-0000-0000-000000000003'::uuid);
select pg_temp.assert_outbound_error('known loss blocks second acceptance',
  $sql$select public.accept_delivery_task('04120000-0000-0000-0000-000000000106'::uuid,
    '04120000-0000-0000-0000-000000000461'::uuid)$sql$,
  'PT409', 'CUSTODY_UNRESOLVED');
reset role;
select pg_temp.assert_outbound('loss rejection preserves first dispatch and no second custody',
  (select count(*)=1 from private.outbound_dispatches where order_id='04120000-0000-0000-0000-000000000014'::uuid)
  and not exists(select 1 from private.outbound_custody_acceptances where task_id='04120000-0000-0000-0000-000000000106'::uuid));
rollback to savepoint p041_known_loss;
release savepoint p041_known_loss;

savepoint p041_extra_second_history;
insert into public.delivery_tasks(id,order_id,kind,status,attempt_number,assigned_shipper_id,
  destination_name,destination_phone,destination_address,destination_latitude,destination_longitude,
  amount_to_collect_vnd,completed_at,failure_reason)
select '04120000-0000-0000-0000-000000000998'::uuid,order_id,'outbound','failed',2,
  '04120000-0000-0000-0000-000000000004'::uuid,
  destination_name,destination_phone,destination_address,destination_latitude,destination_longitude,
  amount_to_collect_vnd,clock_timestamp(),'TEST-ONLY conflicting legacy attempt 2'
from public.delivery_tasks where id='04120000-0000-0000-0000-000000000106'::uuid;
set local role authenticated;
select pg_temp.set_outbound_claims('04120000-0000-0000-0000-000000000003'::uuid);
select pg_temp.assert_outbound_error_any('extra dirty task2 blocks second acceptance',
  $sql$select public.accept_delivery_task('04120000-0000-0000-0000-000000000106'::uuid,
    '04120000-0000-0000-0000-000000000462'::uuid)$sql$,
  'PT409', array['STATE_CONFLICT','CUSTODY_UNRESOLVED','ATTEMPT_LIMIT']);
reset role;
rollback to savepoint p041_extra_second_history;
release savepoint p041_extra_second_history;

set local role authenticated;
select pg_temp.set_outbound_claims(
  '04120000-0000-0000-0000-000000000003'::uuid
);
create temp table p041_retry_accept_result on commit drop as
select public.accept_delivery_task(
  '04120000-0000-0000-0000-000000000106'::uuid,
  '04120000-0000-0000-0000-000000000432'::uuid
) as response;
reset role;
select pg_temp.assert_outbound(
  'second task accepts with existing dispatch proof',
  (select response->>'operation' = 'accept'
    and response->>'task_status' = 'accepted'
    and response->>'order_status' = 'awaiting_pickup'
    and response->>'attempt_number' = '2'
    and response->>'delivery_attempt_count' = '1'
    and response->>'dispatch_event_id' = (
      select event_id::text from private.outbound_dispatches
      where order_id = '04120000-0000-0000-0000-000000000014'::uuid
    )
    and response->>'request_id' = '04120000-0000-0000-0000-000000000432'
    from p041_retry_accept_result)
  and (select count(*) = 1 from private.outbound_dispatches
      where order_id = '04120000-0000-0000-0000-000000000014'::uuid)
  and (select n = 1 from p041_retry_dispatch_before)
  and exists (
    select 1
    from private.outbound_custody_acceptances
    where order_id = '04120000-0000-0000-0000-000000000014'::uuid
      and task_id = '04120000-0000-0000-0000-000000000106'::uuid
      and holder_id = '04120000-0000-0000-0000-000000000003'::uuid
      and attempt_number = 2
  )
  and (select count(*) = 1 from public.inventory_movements
      where order_id = '04120000-0000-0000-0000-000000000014'::uuid
        and kind = 'dispatch')
  and (select count(*) = 2 from public.inventory_movements
      where order_id = '04120000-0000-0000-0000-000000000014'::uuid)
  and (select b.on_hand = a.on_hand and b.reserved = a.reserved
      from p041_retry_stock_before b
      join public.product_variants a on a.id=b.variant_id)
);

-- Assignment change is checked even on a successful second-task request
-- replay.  Restore it before the real start call.
reset role;
alter table public.delivery_tasks disable trigger user;
update public.delivery_tasks
set assigned_shipper_id = '04120000-0000-0000-0000-000000000004'::uuid
where id = '04120000-0000-0000-0000-000000000106'::uuid;
alter table public.delivery_tasks enable trigger user;
set local role authenticated;
select pg_temp.set_outbound_claims(
  '04120000-0000-0000-0000-000000000003'::uuid
);
select pg_temp.assert_outbound_error(
  'second-task replay by changed holder is denied',
  $sql$select public.accept_delivery_task(
    '04120000-0000-0000-0000-000000000106'::uuid,
    '04120000-0000-0000-0000-000000000432'::uuid)$sql$,
  '42501', 'PERMISSION_DENIED'
);
reset role;
alter table public.delivery_tasks disable trigger user;
update public.delivery_tasks
set assigned_shipper_id = '04120000-0000-0000-0000-000000000003'::uuid
where id = '04120000-0000-0000-0000-000000000106'::uuid;
alter table public.delivery_tasks enable trigger user;

set local role authenticated;
select pg_temp.set_outbound_claims(
  '04120000-0000-0000-0000-000000000003'::uuid
);
reset role;
savepoint p041_known_damage;
insert into public.business_events(actor_id,subject_type,subject_id,task_id,incident_kind,request_id,reason)
values ('04120000-0000-0000-0000-000000000003'::uuid, 'delivery_task',
  '04120000-0000-0000-0000-000000000106'::uuid,
  '04120000-0000-0000-0000-000000000106'::uuid, 'damaged',
  '04120000-0000-0000-0000-000000000463'::uuid, 'TEST-ONLY known damage after acceptance');
set local role authenticated;
select pg_temp.set_outbound_claims('04120000-0000-0000-0000-000000000003'::uuid);
select pg_temp.assert_outbound_error('damage after acceptance blocks start',
  $sql$select public.start_delivery_task('04120000-0000-0000-0000-000000000106'::uuid,
    '04120000-0000-0000-0000-000000000464'::uuid)$sql$,
  'PT409','CUSTODY_UNRESOLVED');
reset role;
select pg_temp.assert_outbound('damage rejection leaves count one and accepted state',
  (select delivery_attempt_count=1 from public.orders where id='04120000-0000-0000-0000-000000000014'::uuid)
  and (select status='accepted' from public.delivery_tasks where id='04120000-0000-0000-0000-000000000106'::uuid));
rollback to savepoint p041_known_damage;
release savepoint p041_known_damage;
set local role authenticated;
select pg_temp.set_outbound_claims('04120000-0000-0000-0000-000000000003'::uuid);
create temp table p041_retry_start_result on commit drop as
select public.start_delivery_task(
  '04120000-0000-0000-0000-000000000106'::uuid,
  '04120000-0000-0000-0000-000000000433'::uuid
) as response;
reset role;
select pg_temp.assert_outbound(
  'second task starts and increments count to two',
  (select response->>'task_status' = 'in_transit'
    and response->>'order_status' = 'delivering'
    and response->>'attempt_number' = '2'
    and response->>'delivery_attempt_count' = '2'
    and response->>'dispatch_event_id' is not null
    from p041_retry_start_result)
  and (select status = 'delivering' and delivery_attempt_count = 2
      from public.orders where id = '04120000-0000-0000-0000-000000000014'::uuid)
  and (select count(*) = 2 from public.inventory_movements
      where order_id = '04120000-0000-0000-0000-000000000014'::uuid)
  and not exists (select 1 from public.delivery_attempts
      where task_id = '04120000-0000-0000-0000-000000000106'::uuid)
);

-- Even with accepted custody, a count of two cannot start another command.
set local role authenticated;
select pg_temp.set_outbound_claims(
  '04120000-0000-0000-0000-000000000003'::uuid
);
select public.accept_delivery_task(
  '04120000-0000-0000-0000-000000000109'::uuid,
  '04120000-0000-0000-0000-000000000440'::uuid);
reset role;
update public.orders
set delivery_attempt_count = 2, status = 'delivering'::public.order_status
where id = '04120000-0000-0000-0000-000000000018'::uuid;
set local role authenticated;
select pg_temp.set_outbound_claims(
  '04120000-0000-0000-0000-000000000003'::uuid
);
select pg_temp.assert_outbound_error(
  'third attempt start is rejected at count two',
  $sql$select public.start_delivery_task(
    '04120000-0000-0000-0000-000000000109'::uuid,
    '04120000-0000-0000-0000-000000000441'::uuid)$sql$,
  'PT409', 'ATTEMPT_LIMIT'
);
reset role;

-- All-order history must be visible to the internal writer even when a prior
-- result belongs to a different shipper; a reset count does not permit dispatch.
savepoint p041_foreign_legacy;
insert into public.delivery_tasks(id,order_id,kind,status,attempt_number,assigned_shipper_id,
  destination_name,destination_phone,destination_address,destination_latitude,destination_longitude,
  amount_to_collect_vnd,accepted_at,started_at,completed_at,failure_reason)
select '04120000-0000-0000-0000-000000000999'::uuid,order_id,'outbound','failed',1,
  '04120000-0000-0000-0000-000000000004'::uuid,
  destination_name,destination_phone,destination_address,destination_latitude,destination_longitude,
  amount_to_collect_vnd,now()-interval '3 hours',now()-interval '2 hours',now()-interval '1 hour',
  'TEST-ONLY legacy failed other shipper'
from public.delivery_tasks where id='04120000-0000-0000-0000-000000000108'::uuid;
insert into public.delivery_attempts(task_id,order_id,attempt_number,task_kind,result,reason,shipper_id)
values('04120000-0000-0000-0000-000000000999'::uuid,
  '04120000-0000-0000-0000-000000000016'::uuid,1,'outbound','failed','Legacy fixture',
  '04120000-0000-0000-0000-000000000004'::uuid);
set local role authenticated;
select pg_temp.set_outbound_claims('04120000-0000-0000-0000-000000000003'::uuid);
select pg_temp.assert_outbound_error_any('other shipper history prevents a fresh dispatch',
  $sql$select public.accept_delivery_task('04120000-0000-0000-0000-000000000108'::uuid,
    '04120000-0000-0000-0000-000000000465'::uuid)$sql$,
  'PT409',array['STATE_CONFLICT','CUSTODY_UNRESOLVED','ATTEMPT_LIMIT']);
reset role;
select pg_temp.assert_outbound('foreign history rejection writes no dispatch',
  not exists(select 1 from private.outbound_dispatches where order_id='04120000-0000-0000-0000-000000000016'::uuid));
rollback to savepoint p041_foreign_legacy;
release savepoint p041_foreign_legacy;

-- A trigger installed by the privileged test setup fails after the command
-- has acquired all business locks.  The authenticated call must roll back
-- task/order/stock/dispatch/custody/event/request writes as one transaction.
create or replace function pg_temp.reject_outbound_fault()
returns trigger
language plpgsql
as $$
begin
  if new.request_id = '04120000-0000-0000-0000-000000000450'::uuid then
    raise exception using errcode = 'P0001', message = 'P041_TEST_FAULT';
  end if;
  return new;
end;
$$;
create trigger p041_outbound_fault
before insert on private.outbound_command_requests
for each row execute function pg_temp.reject_outbound_fault();

create temp table p041_fault_before on commit drop as
select
  (select status::text from public.delivery_tasks
   where id = '04120000-0000-0000-0000-000000000108'::uuid) as task_status,
  (select accepted_at from public.delivery_tasks
   where id = '04120000-0000-0000-0000-000000000108'::uuid) as accepted_at,
  (select started_at from public.delivery_tasks
   where id = '04120000-0000-0000-0000-000000000108'::uuid) as started_at,
  (select status::text from public.orders
   where id = '04120000-0000-0000-0000-000000000016'::uuid) as order_status,
  (select delivery_attempt_count from public.orders
   where id = '04120000-0000-0000-0000-000000000016'::uuid) as attempt_count,
  (select on_hand from public.product_variants
   where id = '04120000-0000-0000-0000-000000000118'::uuid) as on_hand,
  (select reserved from public.product_variants
   where id = '04120000-0000-0000-0000-000000000118'::uuid) as reserved,
  (select count(*) from public.inventory_movements
   where order_id = '04120000-0000-0000-0000-000000000016'::uuid) as movement_count,
  (select count(*) from private.outbound_dispatches
   where order_id = '04120000-0000-0000-0000-000000000016'::uuid) as dispatch_count,
  (select count(*) from private.outbound_custody_acceptances
   where order_id = '04120000-0000-0000-0000-000000000016'::uuid) as custody_count,
  (select count(*) from public.business_events
   where subject_id in (
     '04120000-0000-0000-0000-000000000108'::uuid,
     '04120000-0000-0000-0000-000000000016'::uuid
   )) as event_count,
  (select count(*) from private.outbound_command_requests
   where order_id = '04120000-0000-0000-0000-000000000016'::uuid) as request_count;

set local role authenticated;
select pg_temp.set_outbound_claims(
  '04120000-0000-0000-0000-000000000003'::uuid
);
select pg_temp.assert_outbound_error(
  'late event/request fault rolls back accept',
  $sql$select public.accept_delivery_task(
    '04120000-0000-0000-0000-000000000108'::uuid,
    '04120000-0000-0000-0000-000000000450'::uuid)$sql$,
  'P0001', 'P041_TEST_FAULT'
);
reset role;
drop trigger p041_outbound_fault on private.outbound_command_requests;
select pg_temp.assert_outbound(
  'late fault leaves every before/after value unchanged',
  (select task_status = (select status::text from public.delivery_tasks
      where id = '04120000-0000-0000-0000-000000000108'::uuid)
    and accepted_at is not distinct from (select accepted_at from public.delivery_tasks
      where id = '04120000-0000-0000-0000-000000000108'::uuid)
    and started_at is not distinct from (select started_at from public.delivery_tasks
      where id = '04120000-0000-0000-0000-000000000108'::uuid)
    and order_status = (select status::text from public.orders
      where id = '04120000-0000-0000-0000-000000000016'::uuid)
    and attempt_count = (select delivery_attempt_count from public.orders
      where id = '04120000-0000-0000-0000-000000000016'::uuid)
    and on_hand = (select on_hand from public.product_variants
      where id = '04120000-0000-0000-0000-000000000118'::uuid)
    and reserved = (select reserved from public.product_variants
      where id = '04120000-0000-0000-0000-000000000118'::uuid)
    and movement_count = (select count(*) from public.inventory_movements
      where order_id = '04120000-0000-0000-0000-000000000016'::uuid)
    and dispatch_count = (select count(*) from private.outbound_dispatches
      where order_id = '04120000-0000-0000-0000-000000000016'::uuid)
    and custody_count = (select count(*) from private.outbound_custody_acceptances
      where order_id = '04120000-0000-0000-0000-000000000016'::uuid)
    and event_count = (select count(*) from public.business_events
      where subject_id in (
        '04120000-0000-0000-0000-000000000108'::uuid,
        '04120000-0000-0000-0000-000000000016'::uuid
      ))
    and request_count = (select count(*) from private.outbound_command_requests
      where order_id = '04120000-0000-0000-0000-000000000016'::uuid)
    from p041_fault_before)
);

-- Direct client access to source/private relations and internal helpers stays
-- denied even though the public RPC can perform the server-side transaction.
set local role authenticated;
select pg_temp.set_outbound_claims(
  '04120000-0000-0000-0000-000000000003'::uuid
);
select pg_temp.assert_outbound_error(
  'authenticated cannot update inventory balances directly',
  $sql$update public.product_variants set reserved = reserved where id = '04120000-0000-0000-0000-000000000111'::uuid$sql$,
  '42501'
);
select pg_temp.assert_outbound_error(
  'authenticated cannot read private dispatch table directly',
  $sql$select order_id from private.outbound_dispatches$sql$,
  '42501'
);
select pg_temp.assert_outbound_error(
  'authenticated cannot write private request ledger directly',
  $sql$insert into private.outbound_command_requests(
    actor_id, request_id, operation, task_id, order_id, response
  ) values (
    '04120000-0000-0000-0000-000000000003'::uuid,
    '04120000-0000-0000-0000-000000000451'::uuid,
    'accept', '04120000-0000-0000-0000-000000000108'::uuid,
    '04120000-0000-0000-0000-000000000016'::uuid, '{}'::jsonb
  )$sql$,
  '42501'
);
reset role;

select 'outbound_accept_start.sql: PASS' as result,
  'P04.1 production accept/start RPCs; transaction rolled back' as scope;
rollback;
