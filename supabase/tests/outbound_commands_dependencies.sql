-- P04.1 TEST-ONLY dependency boundary.
-- Historical dependency boundary retained after the production P04.1 upgrade.
-- The temporary interfaces below intentionally remain fail-closed. This
-- suite verifies that explicitly labelled temporary interfaces fail closed
-- and cannot mutate delivery, order, attempt or inventory state.
-- It is not an authorization, custody, dispatch, cancellation-race or
-- idempotency-success test. Those tests belong after the owner-approved
-- inventory/custody contract is available.

begin;
set constraints all deferred;

-- P041_INTERFACE_FIXTURE

create or replace function pg_temp.assert_p041(
  p_label text,
  p_condition boolean
) returns void
language plpgsql
as $$
begin
  if coalesce(p_condition, false) is not true then
    raise exception 'P04.1 dependency fixture failed: %', p_label;
  end if;
end;
$$;

create or replace function pg_temp.set_p041_claims(
  p_user_id uuid
) returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
  perform set_config(
    'request.jwt.claims',
    case when p_user_id is null then ''
      else jsonb_build_object(
        'sub', p_user_id::text,
        'role', 'authenticated',
        'aud', 'authenticated'
      )::text
    end,
    true
  );
end;
$$;

create or replace function pg_temp.assert_p041_error(
  p_label text,
  p_sql text,
  p_state text,
  p_message text
) returns void
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
      'P04.1 dependency fixture failed: % (expected %/%; got %/%)',
      p_label, p_state, p_message, coalesce(l_state, 'success'), coalesce(l_message, '');
  end if;
end;
$$;

-- Realistic read-only fixture rows: one assigned task and one accepted task.
-- They are inserted by the privileged SQL test session and rolled back with
-- this suite; the temporary interfaces never inspect or mutate them.
insert into auth.users (id, email)
values
  ('04100000-0000-0000-0000-000000000001'::uuid, 'p041-customer@example.invalid'),
  ('04100000-0000-0000-0000-000000000002'::uuid, 'p041-shipper@example.invalid'),
  ('04100000-0000-0000-0000-000000000003'::uuid, 'p041-manager@example.invalid');
update public.profiles p set role = fixture.role::public.user_role,
  full_name = fixture.full_name
from (values
  ('04100000-0000-0000-0000-000000000001'::uuid, 'customer', 'P041 Customer'),
  ('04100000-0000-0000-0000-000000000002'::uuid, 'shipper', 'P041 Shipper'),
  ('04100000-0000-0000-0000-000000000003'::uuid, 'manager', 'P041 Manager')
) as fixture(id, role, full_name)
where p.id = fixture.id;
insert into public.categories (id, code, name)
values ('04100000-0000-0000-0000-000000000010'::uuid, 'p041', 'P041 Fixture');
insert into public.products (id, category_id, name, description)
values (
  '04100000-0000-0000-0000-000000000011'::uuid,
  '04100000-0000-0000-0000-000000000010'::uuid,
  'P041 Product', 'TEST-ONLY fixture'
);
insert into public.product_variants (
  id, product_id, sku, label, price_vnd, on_hand, reserved, damaged
) values (
  '04100000-0000-0000-0000-000000000012'::uuid,
  '04100000-0000-0000-0000-000000000011'::uuid,
  'P041-SKU', 'P041 Variant', 100000, 10, 2, 0
);
insert into public.orders (
  id, customer_id, request_id, status, recipient_name, recipient_phone,
  address_detail, latitude, longitude, subtotal_vnd
)
values
  ('04100000-0000-0000-0000-000000000020'::uuid,
   '04100000-0000-0000-0000-000000000001'::uuid,
   '04100000-0000-0000-0000-000000000120'::uuid,
   'awaiting_pickup', 'P041 Assigned', '0900000001', 'P041 Address A',
   21.0285, 105.8542, 100000),
  ('04100000-0000-0000-0000-000000000021'::uuid,
   '04100000-0000-0000-0000-000000000001'::uuid,
   '04100000-0000-0000-0000-000000000121'::uuid,
   'awaiting_pickup', 'P041 Accepted', '0900000002', 'P041 Address B',
   21.0285, 105.8542, 100000);
insert into public.order_items (
  id, order_id, product_id, variant_id, product_name, variant_label,
  unit_price_vnd, quantity
)
values
  ('04100000-0000-0000-0000-000000000030'::uuid,
   '04100000-0000-0000-0000-000000000020'::uuid,
   '04100000-0000-0000-0000-000000000011'::uuid,
   '04100000-0000-0000-0000-000000000012'::uuid,
   'P041 Product', 'P041 Variant', 100000, 1),
  ('04100000-0000-0000-0000-000000000031'::uuid,
   '04100000-0000-0000-0000-000000000021'::uuid,
   '04100000-0000-0000-0000-000000000011'::uuid,
   '04100000-0000-0000-0000-000000000012'::uuid,
   'P041 Product', 'P041 Variant', 100000, 1);
insert into public.delivery_tasks (
  id, order_id, kind, assigned_shipper_id, assigned_by, status, attempt_number,
  destination_name, destination_phone, destination_address,
  destination_latitude, destination_longitude, amount_to_collect_vnd,
  assigned_at, accepted_at
)
values
  ('04100000-0000-0000-0000-000000000040'::uuid,
   '04100000-0000-0000-0000-000000000020'::uuid, 'outbound',
   '04100000-0000-0000-0000-000000000002'::uuid,
   '04100000-0000-0000-0000-000000000003'::uuid, 'assigned', 1,
   'P041 Assigned', '0900000001', 'P041 Address A', 21.0285, 105.8542,
   130000, '2026-10-24T00:00:00Z', null),
  ('04100000-0000-0000-0000-000000000041'::uuid,
   '04100000-0000-0000-0000-000000000021'::uuid, 'outbound',
   '04100000-0000-0000-0000-000000000002'::uuid,
   '04100000-0000-0000-0000-000000000003'::uuid, 'accepted', 1,
   'P041 Accepted', '0900000002', 'P041 Address B', 21.0285, 105.8542,
   130000, '2026-10-24T00:00:00Z', '2026-10-24T00:05:00Z');
insert into public.cod_collections (
  order_id, shipper_id, status, expected_amount_vnd
)
values
  ('04100000-0000-0000-0000-000000000020'::uuid,
   '04100000-0000-0000-0000-000000000002'::uuid, 'uncollected', 130000),
  ('04100000-0000-0000-0000-000000000021'::uuid,
   '04100000-0000-0000-0000-000000000002'::uuid, 'uncollected', 130000);
insert into public.inventory_movements (
  variant_id, order_id, event_id, kind, reserved_delta, actor_id, reason
)
values
  ('04100000-0000-0000-0000-000000000012'::uuid,
   '04100000-0000-0000-0000-000000000020'::uuid,
   '04100000-0000-0000-0000-000000000050'::uuid,
   'reserve', 2, '04100000-0000-0000-0000-000000000001'::uuid,
   'P041 TEST-ONLY reservation');

-- Capture full row content, not only counts, so a future accidental update is
-- caught even when the interface does not insert/delete rows.
create temp table p041_state_before as
select
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.orders x) as orders,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.delivery_tasks x) as tasks,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.product_variants x) as variants,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.inventory_movements x) as movements,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.delivery_attempts x) as attempts,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.order_id), '[]'::jsonb)
     from public.cod_collections x) as cod,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.actor_id, x.request_id), '[]'::jsonb)
     from private.delivery_assignment_requests x) as assignment_requests,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from private.delivery_assignment_audits x) as assignment_audits;

select pg_temp.assert_p041(
  'temporary accept interface is loaded',
  to_regprocedure('pg_temp.accept_delivery_task_contract(uuid,uuid)') is not null
);
select pg_temp.assert_p041(
  'temporary start interface is loaded',
  to_regprocedure('pg_temp.start_delivery_task_contract(uuid,uuid)') is not null
);
select pg_temp.assert_p041(
  'production accept RPC is registered separately from the old boundary',
  to_regprocedure('public.accept_delivery_task(uuid,uuid)') is not null
);
select pg_temp.assert_p041(
  'production start RPC is registered separately from the old boundary',
  to_regprocedure('public.start_delivery_task(uuid,uuid)') is not null
);

set local role authenticated;

select pg_temp.set_p041_claims(null);
select pg_temp.assert_p041_error(
  'anonymous accept is rejected before dependency fallback',
  $sql$select pg_temp.accept_delivery_task_contract(
    '04100000-0000-0000-0000-000000000001'::uuid,
    '04100000-0000-0000-0000-000000000101'::uuid)$sql$,
  '42501', 'AUTH_REQUIRED'
);
select pg_temp.assert_p041_error(
  'anonymous start is rejected before dependency fallback',
  $sql$select pg_temp.start_delivery_task_contract(
    '04100000-0000-0000-0000-000000000001'::uuid,
    '04100000-0000-0000-0000-000000000102'::uuid)$sql$,
  '42501', 'AUTH_REQUIRED'
);

select pg_temp.set_p041_claims(
  '04100000-0000-0000-0000-000000000010'::uuid
);
select pg_temp.assert_p041_error(
  'accept rejects null task id',
  $sql$select pg_temp.accept_delivery_task_contract(
    null::uuid,
    '04100000-0000-0000-0000-000000000111'::uuid)$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p041_error(
  'start rejects null request id',
  $sql$select pg_temp.start_delivery_task_contract(
    '04100000-0000-0000-0000-000000000001'::uuid,
    null::uuid)$sql$,
  '22023', 'INVALID_ARGUMENT'
);

-- Every non-null request fails closed. Repeated request IDs and different
-- payloads cannot manufacture success or a fake idempotency result.
select pg_temp.assert_p041_error(
  'authenticated accept fails closed',
  $sql$select pg_temp.accept_delivery_task_contract(
    '04100000-0000-0000-0000-000000000001'::uuid,
    '04100000-0000-0000-0000-000000000111'::uuid)$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);
select pg_temp.assert_p041_error(
  'same accept request remains fail closed on retry',
  $sql$select pg_temp.accept_delivery_task_contract(
    '04100000-0000-0000-0000-000000000001'::uuid,
    '04100000-0000-0000-0000-000000000111'::uuid)$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);
select pg_temp.assert_p041_error(
  'different accept payload remains fail closed',
  $sql$select pg_temp.accept_delivery_task_contract(
    '04100000-0000-0000-0000-000000000002'::uuid,
    '04100000-0000-0000-0000-000000000112'::uuid)$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);
select pg_temp.assert_p041_error(
  'authenticated start fails closed',
  $sql$select pg_temp.start_delivery_task_contract(
    '04100000-0000-0000-0000-000000000001'::uuid,
    '04100000-0000-0000-0000-000000000121'::uuid)$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);
select pg_temp.assert_p041_error(
  'same start request remains fail closed on retry',
  $sql$select pg_temp.start_delivery_task_contract(
    '04100000-0000-0000-0000-000000000001'::uuid,
    '04100000-0000-0000-0000-000000000121'::uuid)$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);
select pg_temp.assert_p041_error(
  'known assigned task cannot be accepted through fixture',
  $sql$select pg_temp.accept_delivery_task_contract(
    '04100000-0000-0000-0000-000000000040'::uuid,
    '04100000-0000-0000-0000-000000000131'::uuid)$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);
select pg_temp.assert_p041_error(
  'known accepted task cannot be started through fixture',
  $sql$select pg_temp.start_delivery_task_contract(
    '04100000-0000-0000-0000-000000000041'::uuid,
    '04100000-0000-0000-0000-000000000132'::uuid)$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);

reset role;
select pg_temp.assert_p041(
  'fail-closed interfaces perform no DML',
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb) from public.orders x)
      = (select orders from p041_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb) from public.delivery_tasks x)
      = (select tasks from p041_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb) from public.product_variants x)
      = (select variants from p041_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb) from public.inventory_movements x)
      = (select movements from p041_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb) from public.delivery_attempts x)
      = (select attempts from p041_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.order_id), '[]'::jsonb) from public.cod_collections x)
      = (select cod from p041_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.actor_id, x.request_id), '[]'::jsonb)
       from private.delivery_assignment_requests x)
      = (select assignment_requests from p041_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
       from private.delivery_assignment_audits x)
      = (select assignment_audits from p041_state_before)
);

select 'outbound_commands_dependencies.sql: PASS' as result,
       'Historical TEST-ONLY boundary; real RPCs tested in outbound_accept_start.sql' as scope;
rollback;
