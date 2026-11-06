-- P05.1 TEST-ONLY completion contract suite.
-- The runner replaces P051_COMPLETION_FIXTURE with the guarded isolated
-- fixture.  This never calls a public completion RPC and must not run against
-- a shared/cloud database.
begin;
set constraints all deferred;

-- P051_COMPLETION_FIXTURE

create or replace function pg_temp.assert_p051(
  p_label text,
  p_condition boolean
) returns void
language plpgsql
as $$
begin
  if coalesce(p_condition, false) is not true then
    raise exception 'P05.1 completion fixture failed: %', p_label;
  end if;
end;
$$;

create or replace function pg_temp.set_p051_claims(p_user_id uuid)
returns void language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claim.sub', coalesce(p_user_id::text, ''), true
  );
  perform set_config(
    'request.jwt.claims',
    case when p_user_id is null then '' else jsonb_build_object(
      'sub', p_user_id::text, 'role', 'authenticated', 'aud', 'authenticated'
    )::text end,
    true
  );
end;
$$;

create or replace function pg_temp.assert_p051_error(
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
  exception when others then
    get stacked diagnostics
      l_state = returned_sqlstate,
      l_message = message_text;
  end;
  if l_state is distinct from p_state then
    raise exception
      'P05.1 completion fixture failed: % (expected SQLSTATE %, got %: %)',
      p_label, p_state, coalesce(l_state, 'success'), coalesce(l_message, '');
  end if;
  if p_message is not null and l_message is distinct from p_message then
    raise exception
      'P05.1 completion fixture failed: % (expected message %, got %)',
      p_label, p_message, coalesce(l_message, '');
  end if;
end;
$$;

insert into p051_fixture.actors (id, role)
values
  ('05100000-0000-0000-0000-000000000001'::uuid, 'customer'),
  ('05100000-0000-0000-0000-000000000002'::uuid, 'shipper'),
  ('05100000-0000-0000-0000-000000000003'::uuid, 'shipper'),
  ('05100000-0000-0000-0000-000000000004'::uuid, 'manager'),
  ('05100000-0000-0000-0000-000000000005'::uuid, 'manager'),
  ('05100000-0000-0000-0000-000000000006'::uuid, 'customer');

-- The normal fixtures use server-derived 520000 + 30000 = 550000 VND.
-- Individual rows intentionally violate one completion precondition.
insert into p051_fixture.orders (
  id, customer_id, subtotal_vnd, delivery_fee_vnd, status, attempt_count
)
values
  ('05100000-0000-0000-0000-000000000010'::uuid,
   '05100000-0000-0000-0000-000000000001'::uuid, 520000, 30000, 'delivering', 1),
  ('05100000-0000-0000-0000-000000000011'::uuid,
   '05100000-0000-0000-0000-000000000001'::uuid, 520000, 30000, 'delivering', 1),
  ('05100000-0000-0000-0000-000000000012'::uuid,
   '05100000-0000-0000-0000-000000000001'::uuid, 520000, 30000, 'delivering', 1),
  ('05100000-0000-0000-0000-000000000013'::uuid,
   '05100000-0000-0000-0000-000000000001'::uuid, 520000, 30000, 'delivering', 1),
  ('05100000-0000-0000-0000-000000000014'::uuid,
   '05100000-0000-0000-0000-000000000001'::uuid, 520000, 30000, 'awaiting_pickup', 0),
  ('05100000-0000-0000-0000-000000000015'::uuid,
   '05100000-0000-0000-0000-000000000001'::uuid, 520000, 30000, 'delivering', 1),
  ('05100000-0000-0000-0000-000000000016'::uuid,
   '05100000-0000-0000-0000-000000000001'::uuid, 520000, 30000, 'delivering', 1),
  ('05100000-0000-0000-0000-000000000017'::uuid,
   '05100000-0000-0000-0000-000000000001'::uuid, 520000, 30000, 'delivering', 1),
  ('05100000-0000-0000-0000-000000000018'::uuid,
   '05100000-0000-0000-0000-000000000001'::uuid, 520000, 30000, 'delivering', 1),
  ('05100000-0000-0000-0000-000000000019'::uuid,
   '05100000-0000-0000-0000-000000000001'::uuid, 520000, 30000, 'delivering', 1),
  ('05100000-0000-0000-0000-000000000020'::uuid,
   '05100000-0000-0000-0000-000000000001'::uuid, 520000, 30000, 'delivering', 1);

insert into p051_fixture.tasks (
  id, order_id, shipper_id, kind, status, attempt_number,
  amount_to_collect_vnd, accepted_at, started_at
)
values
  ('05100000-0000-0000-0000-000000000101'::uuid,
   '05100000-0000-0000-0000-000000000010'::uuid,
   '05100000-0000-0000-0000-000000000002'::uuid, 'outbound', 'in_transit', 1, 550000,
   '2026-10-25T00:01:00Z', '2026-10-25T00:02:00Z'),
  ('05100000-0000-0000-0000-000000000102'::uuid,
   '05100000-0000-0000-0000-000000000011'::uuid,
   '05100000-0000-0000-0000-000000000002'::uuid, 'outbound', 'in_transit', 1, 550000,
   '2026-10-25T00:03:00Z', '2026-10-25T00:04:00Z'),
  ('05100000-0000-0000-0000-000000000103'::uuid,
   '05100000-0000-0000-0000-000000000012'::uuid,
   '05100000-0000-0000-0000-000000000002'::uuid, 'outbound', 'in_transit', 1, 550000,
   '2026-10-25T00:05:00Z', '2026-10-25T00:06:00Z'),
  ('05100000-0000-0000-0000-000000000104'::uuid,
   '05100000-0000-0000-0000-000000000013'::uuid,
   '05100000-0000-0000-0000-000000000002'::uuid, 'outbound', 'in_transit', 1, 550000,
   '2026-10-25T00:07:00Z', '2026-10-25T00:08:00Z'),
  ('05100000-0000-0000-0000-000000000105'::uuid,
   '05100000-0000-0000-0000-000000000014'::uuid,
   '05100000-0000-0000-0000-000000000002'::uuid, 'outbound', 'assigned', 1, 550000, null, null),
  ('05100000-0000-0000-0000-000000000106'::uuid,
   '05100000-0000-0000-0000-000000000015'::uuid,
   '05100000-0000-0000-0000-000000000002'::uuid, 'outbound', 'in_transit', 1, 550000,
   '2026-10-25T00:09:00Z', '2026-10-25T00:10:00Z'),
  ('05100000-0000-0000-0000-000000000107'::uuid,
   '05100000-0000-0000-0000-000000000016'::uuid,
   '05100000-0000-0000-0000-000000000002'::uuid, 'outbound', 'in_transit', 1, 549999,
   '2026-10-25T00:11:00Z', '2026-10-25T00:12:00Z'),
  ('05100000-0000-0000-0000-000000000108'::uuid,
   '05100000-0000-0000-0000-000000000017'::uuid,
   '05100000-0000-0000-0000-000000000002'::uuid, 'redelivery', 'in_transit', 1, 0,
   '2026-10-25T00:13:00Z', '2026-10-25T00:14:00Z'),
  ('05100000-0000-0000-0000-000000000109'::uuid,
   '05100000-0000-0000-0000-000000000018'::uuid,
   '05100000-0000-0000-0000-000000000002'::uuid, 'outbound', 'in_transit', 1, 550000,
   '2026-10-25T00:15:00Z', '2026-10-25T00:16:00Z'),
  ('05100000-0000-0000-0000-000000000110'::uuid,
   '05100000-0000-0000-0000-000000000019'::uuid,
   '05100000-0000-0000-0000-000000000002'::uuid, 'outbound', 'in_transit', 1, 550000,
   '2026-10-25T00:17:00Z', '2026-10-25T00:18:00Z'),
  ('05100000-0000-0000-0000-000000000111'::uuid,
   '05100000-0000-0000-0000-000000000020'::uuid,
   '05100000-0000-0000-0000-000000000002'::uuid, 'outbound', 'in_transit', 1, 550000,
   '2026-10-25T00:19:00Z', '2026-10-25T00:20:00Z');

insert into p051_fixture.cod (
  order_id, shipper_id, status, expected_amount_vnd
)
select o.id, '05100000-0000-0000-0000-000000000002'::uuid,
  case when o.id = '05100000-0000-0000-0000-000000000015'::uuid
       then 'collected' else 'uncollected' end,
  550000
from p051_fixture.orders o;

update p051_fixture.cod
   set status = 'uncollected',
       collected_amount_vnd = 0,
       collected_by = '05100000-0000-0000-0000-000000000002'::uuid,
       collected_at = '2026-10-25T00:21:00Z',
       handed_over_at = '2026-10-25T00:22:00Z',
       received_by = '05100000-0000-0000-0000-000000000004'::uuid,
       received_at = '2026-10-25T00:23:00Z'
 where order_id = '05100000-0000-0000-0000-000000000015'::uuid;

insert into p051_fixture.custody (task_id, holder_id, dispatch_proof)
values
  ('05100000-0000-0000-0000-000000000101'::uuid, '05100000-0000-0000-0000-000000000002'::uuid, true),
  ('05100000-0000-0000-0000-000000000102'::uuid, '05100000-0000-0000-0000-000000000002'::uuid, true),
  ('05100000-0000-0000-0000-000000000103'::uuid, '05100000-0000-0000-0000-000000000002'::uuid, true),
  ('05100000-0000-0000-0000-000000000104'::uuid, '05100000-0000-0000-0000-000000000002'::uuid, false),
  ('05100000-0000-0000-0000-000000000106'::uuid, '05100000-0000-0000-0000-000000000002'::uuid, true),
  ('05100000-0000-0000-0000-000000000107'::uuid, '05100000-0000-0000-0000-000000000002'::uuid, true),
  ('05100000-0000-0000-0000-000000000108'::uuid, '05100000-0000-0000-0000-000000000002'::uuid, true),
  ('05100000-0000-0000-0000-000000000109'::uuid, '05100000-0000-0000-0000-000000000002'::uuid, true),
  ('05100000-0000-0000-0000-000000000110'::uuid, '05100000-0000-0000-0000-000000000002'::uuid, true),
  ('05100000-0000-0000-0000-000000000111'::uuid, '05100000-0000-0000-0000-000000000002'::uuid, true);

insert into p051_fixture.attempts (
  task_id, order_id, attempt_number, result, shipper_id
)
values (
  '05100000-0000-0000-0000-000000000110'::uuid,
  '05100000-0000-0000-0000-000000000019'::uuid,
  1, 'success', '05100000-0000-0000-0000-000000000002'::uuid
);

-- Explicit fixture-only recipient sets.  D7 production recipients remain
-- unresolved; the function never infers manager or shipper recipients.
insert into p051_fixture.recipients (order_id, recipient_id)
select o.id, r.recipient_id
from (values
  ('05100000-0000-0000-0000-000000000010'::uuid),
  ('05100000-0000-0000-0000-000000000011'::uuid),
  ('05100000-0000-0000-0000-000000000012'::uuid),
  ('05100000-0000-0000-0000-000000000013'::uuid),
  ('05100000-0000-0000-0000-000000000015'::uuid),
  ('05100000-0000-0000-0000-000000000016'::uuid),
  ('05100000-0000-0000-0000-000000000017'::uuid),
  ('05100000-0000-0000-0000-000000000019'::uuid),
  ('05100000-0000-0000-0000-000000000020'::uuid)
) as o(id)
cross join (values
  ('05100000-0000-0000-0000-000000000001'::uuid),
  ('05100000-0000-0000-0000-000000000004'::uuid)
) as r(recipient_id);

select pg_temp.assert_p051(
  'production completion RPC remains absent',
  not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'complete_outbound_delivery'
  )
);

select pg_temp.set_p051_claims(null);
select pg_temp.assert_p051_error(
  'anonymous caller is rejected',
  $q$select p051_fixture.complete_outbound_delivery(
    '05100000-0000-0000-0000-000000000101'::uuid,
    '05100000-0000-0000-0000-000000000200'::uuid,
    true, 550000
  )$q$,
  '42501', 'AUTH_REQUIRED'
);

select pg_temp.set_p051_claims(
  '05100000-0000-0000-0000-000000000002'::uuid
);

create temp table p051_success_result as
select p051_fixture.complete_outbound_delivery(
  '05100000-0000-0000-0000-000000000101'::uuid,
  '05100000-0000-0000-0000-000000000201'::uuid,
  true, 550000
) as result;

select pg_temp.assert_p051(
  'success response is authoritative and includes 550000',
  (select result->>'status' = 'delivered'
      and result->>'order_status' = 'delivered'
      and result->>'collected_amount_vnd' = '550000'
      and result->>'attempt_number' = '1'
      and result->>'request_id' = '05100000-0000-0000-0000-000000000201'
   from p051_success_result)
);

select pg_temp.assert_p051(
  'success updates task/order but does not increment start count',
  (select status = 'delivered' and completed_at is not null
     from p051_fixture.tasks
    where id = '05100000-0000-0000-0000-000000000101'::uuid)
  and (select status = 'delivered' and attempt_count = 1
              and delivered_at is not null
     from p051_fixture.orders
    where id = '05100000-0000-0000-0000-000000000010'::uuid)
);

select pg_temp.assert_p051(
  'success writes exactly one result with server shipper',
  (select count(*) = 1 and bool_and(result = 'success')
     from p051_fixture.attempts
    where task_id = '05100000-0000-0000-0000-000000000101'::uuid)
  and (select shipper_id = '05100000-0000-0000-0000-000000000002'::uuid
     from p051_fixture.attempts
    where task_id = '05100000-0000-0000-0000-000000000101'::uuid)
);

select pg_temp.assert_p051(
  'success collects exact server COD and records event',
  (select status = 'collected'
       and expected_amount_vnd = 550000
       and collected_amount_vnd = 550000
       and received_amount_vnd = 0
       and collected_by = '05100000-0000-0000-0000-000000000002'::uuid
       and collected_at is not null
       and handed_over_at is null and received_by is null and received_at is null
     from p051_fixture.cod
    where order_id = '05100000-0000-0000-0000-000000000010'::uuid)
  and (select count(*) = 1 and bool_and(event_type = 'outbound_delivered')
     from p051_fixture.events
    where task_id = '05100000-0000-0000-0000-000000000101'::uuid)
  and (select count(*) = 2
     from p051_fixture.notifications
    where event_id = '05100000-0000-0000-0000-000000000101'::uuid)
  and not exists (
    select 1 from p051_fixture.notifications n
    where n.event_id = '05100000-0000-0000-0000-000000000101'::uuid
      and n.recipient_id = '05100000-0000-0000-0000-000000000002'::uuid
  )
);

select pg_temp.assert_p051(
  'same request and exact payload replay prior result',
  p051_fixture.complete_outbound_delivery(
    '05100000-0000-0000-0000-000000000101'::uuid,
    '05100000-0000-0000-0000-000000000201'::uuid,
    true, 550000
  ) = (select result from p051_success_result)
);

update p051_fixture.tasks set shipper_id = null
 where id = '05100000-0000-0000-0000-000000000101'::uuid;
select pg_temp.assert_p051_error(
  'exact replay after assignment revocation is denied',
  $q$select p051_fixture.complete_outbound_delivery(
    '05100000-0000-0000-0000-000000000101'::uuid,
    '05100000-0000-0000-0000-000000000201'::uuid,
    true, 550000
  )$q$,
  '42501', 'NOT_FOUND_OR_FORBIDDEN'
);
update p051_fixture.tasks
   set shipper_id = '05100000-0000-0000-0000-000000000002'::uuid
 where id = '05100000-0000-0000-0000-000000000101'::uuid;

update p051_fixture.actors set role = 'manager'
 where id = '05100000-0000-0000-0000-000000000002'::uuid;
select pg_temp.assert_p051_error(
  'exact replay after role revocation is denied',
  $q$select p051_fixture.complete_outbound_delivery(
    '05100000-0000-0000-0000-000000000101'::uuid,
    '05100000-0000-0000-0000-000000000201'::uuid,
    true, 550000
  )$q$,
  '42501', 'PERMISSION_DENIED'
);
update p051_fixture.actors set role = 'shipper'
 where id = '05100000-0000-0000-0000-000000000002'::uuid;

select pg_temp.assert_p051_error(
  'same request with changed payload is rejected',
  $q$select p051_fixture.complete_outbound_delivery(
    '05100000-0000-0000-0000-000000000101'::uuid,
    '05100000-0000-0000-0000-000000000201'::uuid,
    false, 550000
  )$q$,
  'P0001', 'IDEMPOTENCY_CONFLICT'
);

select pg_temp.assert_p051_error(
  'new request cannot complete an already delivered task',
  $q$select p051_fixture.complete_outbound_delivery(
    '05100000-0000-0000-0000-000000000101'::uuid,
    '05100000-0000-0000-0000-000000000202'::uuid,
    true, 550000
  )$q$,
  'P0001', 'STATE_CONFLICT'
);

select pg_temp.set_p051_claims(
  '05100000-0000-0000-0000-000000000003'::uuid
);
select pg_temp.assert_p051_error(
  'other shipper cannot learn whether task exists',
  $q$select p051_fixture.complete_outbound_delivery(
    '05100000-0000-0000-0000-000000000102'::uuid,
    '05100000-0000-0000-0000-000000000203'::uuid,
    true, 550000
  )$q$,
  '42501', 'NOT_FOUND_OR_FORBIDDEN'
);

select pg_temp.set_p051_claims(
  '05100000-0000-0000-0000-000000000001'::uuid
);
select pg_temp.assert_p051_error(
  'customer cannot complete delivery',
  $q$select p051_fixture.complete_outbound_delivery(
    '05100000-0000-0000-0000-000000000102'::uuid,
    '05100000-0000-0000-0000-000000000204'::uuid,
    true, 550000
  )$q$,
  '42501', 'PERMISSION_DENIED'
);

select pg_temp.set_p051_claims(
  '05100000-0000-0000-0000-000000000004'::uuid
);
select pg_temp.assert_p051_error(
  'manager cannot complete delivery',
  $q$select p051_fixture.complete_outbound_delivery(
    '05100000-0000-0000-0000-000000000102'::uuid,
    '05100000-0000-0000-0000-000000000205'::uuid,
    true, 550000
  )$q$,
  '42501', 'PERMISSION_DENIED'
);

select pg_temp.set_p051_claims(
  '05100000-0000-0000-0000-000000000002'::uuid
);
select pg_temp.assert_p051_error(
  'unknown task is non-enumerating',
  $q$select p051_fixture.complete_outbound_delivery(
    '05100000-0000-0000-0000-000000009999'::uuid,
    '05100000-0000-0000-0000-000000000206'::uuid,
    true, 550000
  )$q$,
  '42501', 'NOT_FOUND_OR_FORBIDDEN'
);

select pg_temp.assert_p051_error(
  'assigned task is not in transit',
  $q$select p051_fixture.complete_outbound_delivery(
    '05100000-0000-0000-0000-000000000105'::uuid,
    '05100000-0000-0000-0000-000000000207'::uuid,
    true, 550000
  )$q$,
  'P0001', 'STATE_CONFLICT'
);

select pg_temp.assert_p051_error(
  'return pickup/redelivery kind cannot use outbound completion',
  $q$select p051_fixture.complete_outbound_delivery(
    '05100000-0000-0000-0000-000000000108'::uuid,
    '05100000-0000-0000-0000-000000000208'::uuid,
    true, 550000
  )$q$,
  'P0001', 'STATE_CONFLICT'
);

select pg_temp.assert_p051_error(
  'missing dispatch proof is blocked',
  $q$select p051_fixture.complete_outbound_delivery(
    '05100000-0000-0000-0000-000000000104'::uuid,
    '05100000-0000-0000-0000-000000000209'::uuid,
    true, 550000
  )$q$,
  'P0001', 'CUSTODY_UNRESOLVED'
);

select pg_temp.assert_p051_error(
  'existing attempt result blocks a second result',
  $q$select p051_fixture.complete_outbound_delivery(
    '05100000-0000-0000-0000-000000000110'::uuid,
    '05100000-0000-0000-0000-000000000210'::uuid,
    true, 550000
  )$q$,
  'P0001', 'STATE_CONFLICT'
);

select pg_temp.assert_p051_error(
  'cross-table amount mismatch is blocked',
  $q$select p051_fixture.complete_outbound_delivery(
    '05100000-0000-0000-0000-000000000107'::uuid,
    '05100000-0000-0000-0000-000000000211'::uuid,
    true, 550000
  )$q$,
  'P0001', 'AMOUNT_MISMATCH'
);

update p051_fixture.tasks
   set amount_to_collect_vnd = 550000
 where id = '05100000-0000-0000-0000-000000000107'::uuid;
update p051_fixture.cod
   set expected_amount_vnd = 549999
 where order_id = '05100000-0000-0000-0000-000000000016'::uuid;
select pg_temp.assert_p051_error(
  'COD-only amount mismatch is blocked',
  $q$select p051_fixture.complete_outbound_delivery(
    '05100000-0000-0000-0000-000000000107'::uuid,
    '05100000-0000-0000-0000-000000000220'::uuid,
    true, 550000
  )$q$,
  'P0001', 'AMOUNT_MISMATCH'
);

select pg_temp.assert_p051_error(
  'dirty COD cannot be overwritten',
  $q$select p051_fixture.complete_outbound_delivery(
    '05100000-0000-0000-0000-000000000106'::uuid,
    '05100000-0000-0000-0000-000000000212'::uuid,
    true, 550000
  )$q$,
  'P0001', 'STATE_CONFLICT'
);
select pg_temp.assert_p051(
  'dirty COD fixture includes historical handover/receipt markers',
  (select status = 'uncollected' and collected_amount_vnd = 0
      and collected_by is not null and collected_at is not null
      and handed_over_at is not null and received_by is not null
      and received_at is not null
     from p051_fixture.cod
    where order_id = '05100000-0000-0000-0000-000000000015'::uuid)
);

select pg_temp.assert_p051_error(
  'false customer receipt is blocked',
  $q$select p051_fixture.complete_outbound_delivery(
    '05100000-0000-0000-0000-000000000103'::uuid,
    '05100000-0000-0000-0000-000000000213'::uuid,
    false, 550000
  )$q$,
  'P0001', 'ITEMS_MISMATCH'
);

select pg_temp.assert_p051_error(
  'missing customer receipt flag is blocked',
  $q$select p051_fixture.complete_outbound_delivery(
    '05100000-0000-0000-0000-000000000103'::uuid,
    '05100000-0000-0000-0000-000000000214'::uuid,
    null::boolean, 550000
  )$q$,
  'P0001', 'ITEMS_MISMATCH'
);

select pg_temp.assert_p051_error(
  'missing collected amount is blocked',
  $q$select p051_fixture.complete_outbound_delivery(
    '05100000-0000-0000-0000-000000000102'::uuid,
    '05100000-0000-0000-0000-000000000215'::uuid,
    true, null::bigint
  )$q$,
  'P0001', 'AMOUNT_MISMATCH'
);

select pg_temp.assert_p051_error(
  'partial collected amount is blocked',
  $q$select p051_fixture.complete_outbound_delivery(
    '05100000-0000-0000-0000-000000000102'::uuid,
    '05100000-0000-0000-0000-000000000216'::uuid,
    true, 549999
  )$q$,
  'P0001', 'AMOUNT_MISMATCH'
);

select pg_temp.assert_p051_error(
  'excess collected amount is blocked',
  $q$select p051_fixture.complete_outbound_delivery(
    '05100000-0000-0000-0000-000000000102'::uuid,
    '05100000-0000-0000-0000-000000000217'::uuid,
    true, 550001
  )$q$,
  'P0001', 'AMOUNT_MISMATCH'
);

select pg_temp.assert_p051_error(
  'missing D7 recipient configuration fails closed',
  $q$select p051_fixture.complete_outbound_delivery(
    '05100000-0000-0000-0000-000000000109'::uuid,
    '05100000-0000-0000-0000-000000000218'::uuid,
    true, 550000
  )$q$,
  'P0001', 'DEPENDENCY_NOT_READY'
);

create or replace function pg_temp.p051_notification_fault()
returns trigger
language plpgsql
as $$
begin
  raise exception using errcode = 'P0001', message = 'P051_NOTIFICATION_FAULT';
end;
$$;

create trigger p051_notification_fault
before insert on p051_fixture.notifications
for each row execute function pg_temp.p051_notification_fault();

select pg_temp.assert_p051_error(
  'late notification failure rolls back all completion writes',
  $q$select p051_fixture.complete_outbound_delivery(
    '05100000-0000-0000-0000-000000000111'::uuid,
    '05100000-0000-0000-0000-000000000219'::uuid,
    true, 550000
  )$q$,
  'P0001', 'P051_NOTIFICATION_FAULT'
);

select pg_temp.assert_p051(
  'late failure leaves source rows unchanged',
  (select status = 'in_transit' and completed_at is null
     from p051_fixture.tasks
    where id = '05100000-0000-0000-0000-000000000111'::uuid)
  and (select status = 'delivering' and attempt_count = 1
     from p051_fixture.orders
    where id = '05100000-0000-0000-0000-000000000020'::uuid)
  and (select status = 'uncollected' and collected_amount_vnd = 0
         and received_amount_vnd = 0 and collected_by is null
         and collected_at is null and handed_over_at is null
         and received_by is null and received_at is null
     from p051_fixture.cod
    where order_id = '05100000-0000-0000-0000-000000000020'::uuid)
  and not exists (
    select 1 from p051_fixture.attempts
    where task_id = '05100000-0000-0000-0000-000000000111'::uuid
  )
  and not exists (
    select 1 from p051_fixture.events
    where task_id = '05100000-0000-0000-0000-000000000111'::uuid
  )
  and not exists (
    select 1 from p051_fixture.notifications
    where event_id = '05100000-0000-0000-0000-000000000111'::uuid
  )
  and not exists (
    select 1 from p051_fixture.requests
    where request_id = '05100000-0000-0000-0000-000000000219'::uuid
  )
);

drop trigger p051_notification_fault on p051_fixture.notifications;

create temp table p051_retry_result as
select p051_fixture.complete_outbound_delivery(
  '05100000-0000-0000-0000-000000000111'::uuid,
  '05100000-0000-0000-0000-000000000219'::uuid,
  true, 550000
) as result;

select pg_temp.assert_p051(
  'same request retries after rolled-back transaction',
  (select result->>'status' = 'delivered' from p051_retry_result)
  and (select count(*) = 1 from p051_fixture.attempts
       where task_id = '05100000-0000-0000-0000-000000000111'::uuid)
  and (select count(*) = 1 from p051_fixture.events
       where task_id = '05100000-0000-0000-0000-000000000111'::uuid)
);

-- Explicitly seeded attempt history, not a retry/failure workflow endpoint.
insert into p051_fixture.orders(id,customer_id,subtotal_vnd,delivery_fee_vnd,status,attempt_count)
values
 ('05100000-0000-0000-0000-000000000900','05100000-0000-0000-0000-000000000001',520000,30000,'delivering',2),
 ('05100000-0000-0000-0000-000000000901','05100000-0000-0000-0000-000000000001',520000,30000,'delivering',1);
insert into p051_fixture.tasks(id,order_id,shipper_id,kind,status,attempt_number,amount_to_collect_vnd,accepted_at,started_at,completed_at)
values
 ('05100000-0000-0000-0000-000000000910','05100000-0000-0000-0000-000000000900','05100000-0000-0000-0000-000000000002','outbound','failed',1,550000,now(),now(),now()),
 ('05100000-0000-0000-0000-000000000911','05100000-0000-0000-0000-000000000900','05100000-0000-0000-0000-000000000002','outbound','in_transit',2,550000,now(),now(),null),
 ('05100000-0000-0000-0000-000000000912','05100000-0000-0000-0000-000000000901','05100000-0000-0000-0000-000000000002','outbound','in_transit',2,550000,now(),now(),null);
insert into p051_fixture.attempts(task_id,order_id,attempt_number,result,shipper_id)
values('05100000-0000-0000-0000-000000000910','05100000-0000-0000-0000-000000000900',1,'failed','05100000-0000-0000-0000-000000000002');
insert into p051_fixture.cod(order_id,shipper_id,status,expected_amount_vnd)
select id,'05100000-0000-0000-0000-000000000002','uncollected',550000
from p051_fixture.orders where id in ('05100000-0000-0000-0000-000000000900','05100000-0000-0000-0000-000000000901');
insert into p051_fixture.custody(task_id,holder_id,dispatch_proof)
values
 ('05100000-0000-0000-0000-000000000911','05100000-0000-0000-0000-000000000002',true),
 ('05100000-0000-0000-0000-000000000912','05100000-0000-0000-0000-000000000002',true);
insert into p051_fixture.recipients(order_id,recipient_id)
select o.id,a.id from p051_fixture.orders o cross join p051_fixture.actors a
where o.id in ('05100000-0000-0000-0000-000000000900','05100000-0000-0000-0000-000000000901')
  and a.id in ('05100000-0000-0000-0000-000000000001','05100000-0000-0000-0000-000000000004');
select pg_temp.set_p051_claims('05100000-0000-0000-0000-000000000002');
create temp table p051_second_result as
select p051_fixture.complete_outbound_delivery('05100000-0000-0000-0000-000000000911','05100000-0000-0000-0000-000000000920',true,550000) result;
select pg_temp.assert_p051('second completion preserves prior result and count',
 (select (result->>'attempt_number')::int=2 from p051_second_result)
 and (select attempt_count=2 and status='delivered' from p051_fixture.orders where id='05100000-0000-0000-0000-000000000900')
 and (select count(*)=2 and count(*) filter(where result='failed')=1 and count(*) filter(where result='success')=1
      from p051_fixture.attempts where order_id='05100000-0000-0000-0000-000000000900')
 and (select status='collected' and collected_amount_vnd=550000 from p051_fixture.cod where order_id='05100000-0000-0000-0000-000000000900'));
select pg_temp.assert_p051_error('task attempt must equal started order count',
 $q$select p051_fixture.complete_outbound_delivery('05100000-0000-0000-0000-000000000912','05100000-0000-0000-0000-000000000921',true,550000)$q$,
 'P0001','STATE_CONFLICT');
select pg_temp.assert_p051('counter mismatch writes no outcome or money',
 not exists(select 1 from p051_fixture.attempts where order_id='05100000-0000-0000-0000-000000000901')
 and not exists(select 1 from p051_fixture.requests where request_id='05100000-0000-0000-0000-000000000921')
 and (select status='uncollected' and collected_amount_vnd=0 from p051_fixture.cod where order_id='05100000-0000-0000-0000-000000000901'));

select 'outbound_completion.sql: PASS' as result,
  'P05.1 isolated fixture only; no live completion RPC' as scope;
rollback;
