-- P06.3 confirm_cod_received contract.
-- TEST FIXTURE ONLY. The runner executes this file in one transaction and
-- rolls every row/temporary trigger back. It must run only after the additive
-- confirm_cod_received migration in an isolated PostgreSQL/Auth fixture.

begin;
set constraints all deferred;

create or replace function pg_temp.set_cod_receipt_claims(
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

create or replace function pg_temp.clear_cod_receipt_claims()
returns void language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
end;
$$;

create or replace function pg_temp.assert_cod_receipt(
  p_label text,
  p_condition boolean
) returns void
language plpgsql
as $$
begin
  if coalesce(p_condition, false) is not true then
    raise exception 'COD receipt test failed: %', p_label;
  end if;
end;
$$;

create or replace function pg_temp.assert_cod_receipt_error(
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

  if l_state is distinct from p_state
     or (p_message is not null and l_message is distinct from p_message) then
    raise exception
      'COD receipt test failed: % (expected state %, message %, got state %, message %)',
      p_label, p_state, coalesce(p_message, '<any>'),
      coalesce(l_state, 'success'), coalesce(l_message, '<none>');
  end if;
end;
$$;

-- Auth/role state is server-managed; the JWT role claim is intentionally not
-- used by the RPC authorization check.
insert into auth.users (id, email)
values
  ('06330000-0000-0000-0000-000000000001'::uuid, 'cod-manager-a@example.invalid'),
  ('06330000-0000-0000-0000-000000000002'::uuid, 'cod-shipper-a@example.invalid'),
  ('06330000-0000-0000-0000-000000000003'::uuid, 'cod-shipper-b@example.invalid'),
  ('06330000-0000-0000-0000-000000000004'::uuid, 'cod-customer@example.invalid'),
  ('06330000-0000-0000-0000-000000000005'::uuid, 'cod-manager-b@example.invalid');

update public.profiles
set role = case id
  when '06330000-0000-0000-0000-000000000001'::uuid then 'manager'::public.user_role
  when '06330000-0000-0000-0000-000000000002'::uuid then 'shipper'::public.user_role
  when '06330000-0000-0000-0000-000000000003'::uuid then 'shipper'::public.user_role
  when '06330000-0000-0000-0000-000000000005'::uuid then 'manager'::public.user_role
  else 'customer'::public.user_role
end
where id in (
  '06330000-0000-0000-0000-000000000001'::uuid,
  '06330000-0000-0000-0000-000000000002'::uuid,
  '06330000-0000-0000-0000-000000000003'::uuid,
  '06330000-0000-0000-0000-000000000004'::uuid,
  '06330000-0000-0000-0000-000000000005'::uuid
);

insert into public.orders (
  id, customer_id, request_id, status, recipient_name, recipient_phone,
  address_detail, latitude, longitude, subtotal_vnd, delivery_fee_vnd
)
select
  ('06331000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  '06330000-0000-0000-0000-000000000004'::uuid,
  ('06332000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  'delivered'::public.order_status,
  format('COD recipient %s', n), format('09000063%02s', n),
  format('COD address %s, Ha Noi', n), 21.03, 105.80, 520000, 30000
from generate_series(1, 8) as numbers(n);

-- A return/refund workflow must not alter the COD obligation. Receipt is still
-- a full-COD operation and never subtracts a refund.
insert into public.return_requests (
  id, order_id, customer_id, request_id, status, reason, description,
  video_object_path
)
values (
  '06333000-0000-0000-0000-000000000006'::uuid,
  '06331000-0000-0000-0000-000000000006'::uuid,
  '06330000-0000-0000-0000-000000000004'::uuid,
  '06334000-0000-0000-0000-000000000006'::uuid,
  'awaiting_refund'::public.return_request_status,
  'defective'::public.return_reason,
  'COD obligation remains separate from refund workflow',
  'cod-receipt/return-proof-006.mp4'
);

insert into public.cod_collections (
  order_id, shipper_id, status, expected_amount_vnd,
  collected_amount_vnd, received_amount_vnd, collected_at, collected_by,
  handed_over_at, received_at, received_by, created_at, updated_at
)
values
  ('06331000-0000-0000-0000-000000000001'::uuid,
   '06330000-0000-0000-0000-000000000002'::uuid,
   'collected'::public.cod_status, 550000, 550000, 0,
   now() - interval '8 minutes',
   '06330000-0000-0000-0000-000000000002'::uuid,
   null, null, null, now(), now()),
  ('06331000-0000-0000-0000-000000000002'::uuid,
   '06330000-0000-0000-0000-000000000002'::uuid,
   'uncollected'::public.cod_status, 550000, 0, 0,
   null, null, null, null, null, now(), now()),
  ('06331000-0000-0000-0000-000000000003'::uuid,
   '06330000-0000-0000-0000-000000000002'::uuid,
   'received'::public.cod_status, 550000, 550000, 550000,
   now() - interval '6 minutes',
   '06330000-0000-0000-0000-000000000002'::uuid,
   now() - interval '3 minutes', now() - interval '3 minutes',
   '06330000-0000-0000-0000-000000000001'::uuid, now(), now()),
  ('06331000-0000-0000-0000-000000000004'::uuid,
   '06330000-0000-0000-0000-000000000002'::uuid,
   'collected'::public.cod_status, 550000, 550000, 0,
   now() - interval '5 minutes',
   '06330000-0000-0000-0000-000000000002'::uuid,
   null, null, null, now(), now()),
  ('06331000-0000-0000-0000-000000000005'::uuid,
   '06330000-0000-0000-0000-000000000002'::uuid,
   'collected'::public.cod_status, 550000, 550000, 0,
   now() - interval '5 minutes',
   '06330000-0000-0000-0000-000000000003'::uuid,
   null, null, null, now(), now()),
  ('06331000-0000-0000-0000-000000000006'::uuid,
   '06330000-0000-0000-0000-000000000003'::uuid,
   'collected'::public.cod_status, 550000, 550000, 0,
   now() - interval '4 minutes',
   '06330000-0000-0000-0000-000000000003'::uuid,
   null, null, null, now(), now()),
  ('06331000-0000-0000-0000-000000000007'::uuid,
   '06330000-0000-0000-0000-000000000002'::uuid,
   'collected'::public.cod_status, 550000, 550000, 0,
   now() - interval '3 minutes',
   '06330000-0000-0000-0000-000000000002'::uuid,
   null, null, null, now(), now()),
  ('06331000-0000-0000-0000-000000000008'::uuid,
   '06330000-0000-0000-0000-000000000002'::uuid,
   'collected'::public.cod_status, 550000, 550000, 0,
   now() - interval '2 minutes',
   '06330000-0000-0000-0000-000000000002'::uuid,
   null, null, null, now(), now());

-- Mark the return as refunded before receipt. The COD row is deliberately
-- unchanged; receipt must not subtract or otherwise offset the refund.
update public.return_requests
set status = 'refunded'::public.return_request_status,
    bank_name = 'Test Bank',
    account_number = '000063300006',
    account_holder = 'COD customer',
    refund_amount_vnd = 550000,
    refunded_by = '06330000-0000-0000-0000-000000000001'::uuid,
    refunded_at = now(),
    transfer_evidence_path = 'refunds/cod-receipt-006.pdf',
    refund_request_id = '06336000-0000-0000-0000-000000000006'::uuid,
    closed_at = now()
where id = '06333000-0000-0000-0000-000000000006'::uuid;

-- Function ACL and dedicated owner are part of the security contract.
select pg_temp.assert_cod_receipt(
  'RPC execute only authenticated',
  has_function_privilege(
    'authenticated',
    'public.confirm_cod_received(uuid,bigint,uuid)', 'EXECUTE'
  )
  and not has_function_privilege(
    'anon', 'public.confirm_cod_received(uuid,bigint,uuid)', 'EXECUTE'
  )
  and not has_function_privilege(
    'service_role', 'public.confirm_cod_received(uuid,bigint,uuid)', 'EXECUTE'
  )
);
select pg_temp.assert_cod_receipt(
  'writer is no-login no-bypassrls',
  (select not rolcanlogin and not rolinherit and not rolsuper
      and not rolbypassrls and not rolcreaterole and not rolcreatedb
      and not rolreplication
    from pg_roles where rolname = 'sports_store_cod_receipt_writer')
);
select pg_temp.assert_cod_receipt(
  'function owner is dedicated writer',
  (select pg_get_userbyid(p.proowner) = 'sports_store_cod_receipt_writer'
   from pg_proc p
   where p.oid = 'public.confirm_cod_received(uuid,bigint,uuid)'::regprocedure)
);
select pg_temp.assert_cod_receipt(
  'authenticated has no direct COD update',
  not has_table_privilege('authenticated', 'public.cod_collections', 'UPDATE')
);

-- Shipper/customer/forged JWT claims cannot execute the manager-only write.
set local role authenticated;
select pg_temp.set_cod_receipt_claims(
  '06330000-0000-0000-0000-000000000002'::uuid, 'manager'
);
select pg_temp.assert_cod_receipt_error(
  'shipper denied despite forged manager JWT claim',
  $sql$select public.confirm_cod_received(
    '06331000-0000-0000-0000-000000000007'::uuid, 550000,
    '06335000-0000-0000-0000-000000000007'::uuid)$sql$,
  '42501', 'PERMISSION_DENIED'
);
select pg_temp.set_cod_receipt_claims(
  '06330000-0000-0000-0000-000000000004'::uuid
);
select pg_temp.assert_cod_receipt_error(
  'customer denied',
  $sql$select public.confirm_cod_received(
    '06331000-0000-0000-0000-000000000007'::uuid, 550000,
    '06335000-0000-0000-0000-000000000008'::uuid)$sql$,
  '42501', 'PERMISSION_DENIED'
);
reset role;
select pg_temp.clear_cod_receipt_claims();
set local role anon;
select pg_temp.assert_cod_receipt_error(
  'anonymous denied',
  $sql$select public.confirm_cod_received(
    '06331000-0000-0000-0000-000000000007'::uuid, 550000,
    '06335000-0000-0000-0000-000000000009'::uuid)$sql$,
  '42501'
);
reset role;

-- Manager success: 520,000 merchandise + 30,000 fee = 550,000. The
-- manager's amount is an attestation and must equal the server COD amount.
set local role authenticated;
select pg_temp.set_cod_receipt_claims(
  '06330000-0000-0000-0000-000000000001'::uuid
);
select pg_temp.assert_cod_receipt(
  'manager confirms exact full amount',
  (public.confirm_cod_received(
    '06331000-0000-0000-0000-000000000001'::uuid,
    550000,
    '06335000-0000-0000-0000-000000000001'::uuid
  )->>'status') = 'received'
);
reset role;
select pg_temp.assert_cod_receipt(
  'success writes received and handover at same server timestamp',
  (select status = 'received'
      and collected_amount_vnd = 550000
      and received_amount_vnd = 550000
      and received_by = '06330000-0000-0000-0000-000000000001'::uuid
      and received_at is not null
      and received_at = handed_over_at
   from public.cod_collections
   where order_id = '06331000-0000-0000-0000-000000000001'::uuid)
);
select pg_temp.assert_cod_receipt(
  'one event and one shipper-holder notification',
  (select count(*) = 1 from public.business_events
   where subject_type = 'cod_collection'
     and subject_id = '06331000-0000-0000-0000-000000000001'::uuid
     and from_state = 'collected' and to_state = 'received')
  and (select count(*) = 1 from public.notifications n
       join public.business_events e on e.id = n.event_id
       where n.recipient_id = '06330000-0000-0000-0000-000000000002'::uuid
         and n.subject_type = 'cod_collection'
         and n.subject_id = '06331000-0000-0000-0000-000000000001'::uuid)
  and (select count(*) = 0 from public.notifications
       where recipient_id = '06330000-0000-0000-0000-000000000001'::uuid)
);

-- The read projection still binds the result to the current holder. With the
-- order filter the received row has no outstanding amount; another shipper
-- cannot discover it through a deep-linked COD filter.
set local role authenticated;
select pg_temp.set_cod_receipt_claims(
  '06330000-0000-0000-0000-000000000002'::uuid
);
with response as (
  select public.list_cod_collections(
    null, '06331000-0000-0000-0000-000000000001'::uuid,
    array['received'::public.cod_status], 20, null
  ) as body
)
select pg_temp.assert_cod_receipt(
  'holder sees received row and zero order outstanding',
  jsonb_array_length(body->'items') = 1
  and body->'items'->0->>'status' = 'received'
  and (body->'items'->0->>'expected_amount_vnd')::bigint = 550000
  and (body->'items'->0->>'collected_amount_vnd')::bigint = 550000
  and (body->'items'->0->>'received_amount_vnd')::bigint = 550000
  and (body->>'outstanding_vnd')::bigint = 0
) from response;
select pg_temp.set_cod_receipt_claims(
  '06330000-0000-0000-0000-000000000003'::uuid
);
with response as (
  select public.list_cod_collections(
    null, '06331000-0000-0000-0000-000000000001'::uuid,
    array['received'::public.cod_status], 20, null
  ) as body
)
select pg_temp.assert_cod_receipt(
  'other shipper sees empty order scope',
  jsonb_array_length(body->'items') = 0
  and (body->>'filtered_total')::integer = 0
  and (body->>'outstanding_vnd')::bigint = 0
) from response;
reset role;
select pg_temp.assert_cod_receipt(
  'private ledger has one successful order row',
  (select count(*) = 1 from private.cod_receipt_requests
   where order_id = '06331000-0000-0000-0000-000000000001'::uuid
     and actor_id = '06330000-0000-0000-0000-000000000001'::uuid
     and request_id = '06335000-0000-0000-0000-000000000001'::uuid
     and received_amount_vnd = 550000)
);

-- Same request is a replay, not a second money/event/notification write.
set local role authenticated;
select pg_temp.set_cod_receipt_claims(
  '06330000-0000-0000-0000-000000000001'::uuid
);
select pg_temp.assert_cod_receipt(
  'same request replays prior result',
  (public.confirm_cod_received(
    '06331000-0000-0000-0000-000000000001'::uuid,
    550000,
    '06335000-0000-0000-0000-000000000001'::uuid
  )->>'status') = 'received'
);
select pg_temp.assert_cod_receipt_error(
  'same request different amount conflicts',
  $sql$select public.confirm_cod_received(
    '06331000-0000-0000-0000-000000000001'::uuid, 549999,
    '06335000-0000-0000-0000-000000000001'::uuid)$sql$,
  'PT409', 'IDEMPOTENCY_CONFLICT'
);
select pg_temp.assert_cod_receipt_error(
  'same request different target conflicts',
  $sql$select public.confirm_cod_received(
    '06331000-0000-0000-0000-000000000006'::uuid, 550000,
    '06335000-0000-0000-0000-000000000001'::uuid)$sql$,
  'PT409', 'IDEMPOTENCY_CONFLICT'
);
reset role;
select pg_temp.assert_cod_receipt(
  'replay keeps one event notification and ledger row',
  (select count(*) = 1 from private.cod_receipt_requests
   where order_id = '06331000-0000-0000-0000-000000000001'::uuid)
  and (select count(*) = 1 from public.business_events
       where subject_id = '06331000-0000-0000-0000-000000000001'::uuid
         and subject_type = 'cod_collection')
  and (select count(*) = 1 from public.notifications
       where subject_id = '06331000-0000-0000-0000-000000000001'::uuid)
);

-- A new request for an already received order is rejected by the per-order
-- successful ledger, and a different manager cannot replay another actor's
-- request. A role downgrade also blocks replay before reading the ledger.
set local role authenticated;
select pg_temp.set_cod_receipt_claims(
  '06330000-0000-0000-0000-000000000001'::uuid
);
select pg_temp.assert_cod_receipt_error(
  'new request after receipt is state conflict',
  $sql$select public.confirm_cod_received(
    '06331000-0000-0000-0000-000000000001'::uuid, 550000,
    '06335000-0000-0000-0000-000000000002'::uuid)$sql$,
  'PT409', 'STATE_CONFLICT'
);
select pg_temp.set_cod_receipt_claims(
  '06330000-0000-0000-0000-000000000005'::uuid
);
select pg_temp.assert_cod_receipt_error(
  'different manager cannot replay another actor request',
  $sql$select public.confirm_cod_received(
    '06331000-0000-0000-0000-000000000001'::uuid, 550000,
    '06335000-0000-0000-0000-000000000001'::uuid)$sql$,
  'PT409', 'STATE_CONFLICT'
);
reset role;
update public.profiles
set role = 'customer'::public.user_role
where id = '06330000-0000-0000-0000-000000000001'::uuid;
set local role authenticated;
select pg_temp.set_cod_receipt_claims(
  '06330000-0000-0000-0000-000000000001'::uuid
);
select pg_temp.assert_cod_receipt_error(
  'role downgrade blocks replay',
  $sql$select public.confirm_cod_received(
    '06331000-0000-0000-0000-000000000001'::uuid, 550000,
    '06335000-0000-0000-0000-000000000001'::uuid)$sql$,
  '42501', 'PERMISSION_DENIED'
);
reset role;
update public.profiles
set role = 'manager'::public.user_role
where id = '06330000-0000-0000-0000-000000000001'::uuid;

-- Invalid state/amount/corrupt collector rows fail without side effects.
set local role authenticated;
select pg_temp.set_cod_receipt_claims(
  '06330000-0000-0000-0000-000000000001'::uuid
);
select pg_temp.assert_cod_receipt_error(
  'partial amount rejected',
  $sql$select public.confirm_cod_received(
    '06331000-0000-0000-0000-000000000004'::uuid, 549999,
    '06335000-0000-0000-0000-000000000004'::uuid)$sql$,
  'PT409', 'AMOUNT_MISMATCH'
);
select pg_temp.assert_cod_receipt_error(
  'uncollected rejected',
  $sql$select public.confirm_cod_received(
    '06331000-0000-0000-0000-000000000002'::uuid, 550000,
    '06335000-0000-0000-0000-000000000005'::uuid)$sql$,
  'PT409', 'STATE_CONFLICT'
);
select pg_temp.assert_cod_receipt_error(
  'already received rejected',
  $sql$select public.confirm_cod_received(
    '06331000-0000-0000-0000-000000000003'::uuid, 550000,
    '06335000-0000-0000-0000-000000000006'::uuid)$sql$,
  'PT409', 'STATE_CONFLICT'
);
select pg_temp.assert_cod_receipt_error(
  'collector holder mismatch rejected',
  $sql$select public.confirm_cod_received(
    '06331000-0000-0000-0000-000000000005'::uuid, 550000,
    '06335000-0000-0000-0000-000000000007'::uuid)$sql$,
  'PT409', 'CORRUPT_COD_STATE'
);
select pg_temp.assert_cod_receipt_error(
  'zero amount invalid',
  $sql$select public.confirm_cod_received(
    '06331000-0000-0000-0000-000000000004'::uuid, 0,
    '06335000-0000-0000-0000-000000000008'::uuid)$sql$,
  '22023', 'INVALID_ARGUMENT'
);
reset role;
select pg_temp.assert_cod_receipt(
  'rejected calls leave no ledger/events',
  not exists (select 1 from private.cod_receipt_requests
    where order_id in (
      '06331000-0000-0000-0000-000000000002'::uuid,
      '06331000-0000-0000-0000-000000000003'::uuid,
      '06331000-0000-0000-0000-000000000004'::uuid,
      '06331000-0000-0000-0000-000000000005'::uuid))
  and (select status = 'collected' and received_amount_vnd = 0
       from public.cod_collections
       where order_id = '06331000-0000-0000-0000-000000000004'::uuid)
);

-- Receipt remains independent from a return/refund workflow and never offsets
-- the obligation. The holder is shipper B, so only shipper B is notified.
set local role authenticated;
select pg_temp.set_cod_receipt_claims(
  '06330000-0000-0000-0000-000000000001'::uuid
);
select pg_temp.assert_cod_receipt(
  'receipt during return workflow uses full COD',
  (public.confirm_cod_received(
    '06331000-0000-0000-0000-000000000006'::uuid,
    550000,
    '06335000-0000-0000-0000-000000000006'::uuid
  )->>'received_amount_vnd')::bigint = 550000
);
reset role;
select pg_temp.assert_cod_receipt(
  'refund does not reduce COD received amount',
  (select status = 'received'
      and expected_amount_vnd = 550000
      and collected_amount_vnd = 550000
      and received_amount_vnd = 550000
   from public.cod_collections
   where order_id = '06331000-0000-0000-0000-000000000006'::uuid)
  and (select count(*) = 1 from public.notifications
       where subject_id = '06331000-0000-0000-0000-000000000006'::uuid
         and recipient_id = '06330000-0000-0000-0000-000000000003'::uuid)
);

-- Inject a failure after the COD update (notification write) to prove the
-- transaction rolls back money, event, notification and request ledger.
create or replace function pg_temp.fail_cod_receipt_notification()
returns trigger
language plpgsql
as $$
begin
  raise exception 'COD_RECEIPT_TEST_FAILURE' using errcode = 'P0001';
end;
$$;
create trigger cod_receipt_test_failure
before insert on public.notifications
for each row execute function pg_temp.fail_cod_receipt_notification();

set local role authenticated;
select pg_temp.set_cod_receipt_claims(
  '06330000-0000-0000-0000-000000000001'::uuid
);
select pg_temp.assert_cod_receipt_error(
  'notification failure rolls back whole receipt',
  $sql$select public.confirm_cod_received(
    '06331000-0000-0000-0000-000000000008'::uuid, 550000,
    '06335000-0000-0000-0000-000000000008'::uuid)$sql$,
  'P0001', 'COD_RECEIPT_TEST_FAILURE'
);
reset role;
drop trigger cod_receipt_test_failure on public.notifications;
select pg_temp.assert_cod_receipt(
  'rollback keeps COD collected and no side effects',
  (select status = 'collected'
      and collected_amount_vnd = 550000
      and received_amount_vnd = 0
      and received_by is null
      and received_at is null
      and handed_over_at is null
   from public.cod_collections
   where order_id = '06331000-0000-0000-0000-000000000008'::uuid)
  and not exists (select 1 from private.cod_receipt_requests
    where order_id = '06331000-0000-0000-0000-000000000008'::uuid)
  and not exists (select 1 from public.business_events
    where subject_id = '06331000-0000-0000-0000-000000000008'::uuid)
  and not exists (select 1 from public.notifications
    where subject_id = '06331000-0000-0000-0000-000000000008'::uuid)
);

set local role authenticated;
select pg_temp.set_cod_receipt_claims(
  '06330000-0000-0000-0000-000000000001'::uuid
);
select pg_temp.assert_cod_receipt_error(
  'authenticated cannot read private receipt ledger',
  $sql$select count(*) from private.cod_receipt_requests$sql$,
  '42501'
);
select pg_temp.assert_cod_receipt_error(
  'authenticated cannot update COD directly',
  $sql$update public.cod_collections
    set received_amount_vnd = 550000
    where order_id = '06331000-0000-0000-0000-000000000008'::uuid$sql$,
  '42501'
);
reset role;
select pg_temp.clear_cod_receipt_claims();

select 'cod_receipt.sql: PASS' as result,
       'fixtures rolled back by final statement' as fixture_scope;
rollback;
