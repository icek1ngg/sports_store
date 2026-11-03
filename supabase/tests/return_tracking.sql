-- MH14 get_my_return_request contract.
-- TEST FIXTURE ONLY. One transaction on the isolated PostgreSQL fixture,
-- rolled back at the end. Manager decisions (MH15, not built yet) are
-- simulated with admin UPDATEs that set exactly the server-managed fields the
-- real commands are documented to set; the customer side uses the real RPCs.

begin;

create or replace function pg_temp.t14_claims(p_user_id uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
  perform set_config('request.jwt.claims', case when p_user_id is null then ''
    else jsonb_build_object('sub', p_user_id::text, 'role', 'authenticated')::text
    end, true);
end;
$$;

create or replace function pg_temp.t14_assert(p_label text, p_condition boolean)
returns void language plpgsql as $$
begin
  if coalesce(p_condition, false) is not true then
    raise exception 'MH14 test failed: %', p_label;
  end if;
end;
$$;

create or replace function pg_temp.t14_error(
  p_label text, p_sql text, p_state text, p_message text default null
) returns void language plpgsql as $$
declare
  l_state text;
  l_message text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics l_state = returned_sqlstate, l_message = message_text;
  end;
  if l_state is distinct from p_state
     or (p_message is not null and l_message is distinct from p_message) then
    raise exception 'MH14 test failed: % (expected %/%, got %/%)', p_label,
      p_state, coalesce(p_message, '<any>'), coalesce(l_state, 'success'),
      coalesce(l_message, '<none>');
  end if;
end;
$$;

-- Reads as customer A and returns the JSON (helper keeps tests short).
create or replace function pg_temp.t14_get()
returns jsonb language sql as $$
  select public.get_my_return_request(
    current_setting('t14.return_id')::uuid);
$$;

grant execute on function pg_temp.t14_claims(uuid),
  pg_temp.t14_assert(text, boolean),
  pg_temp.t14_error(text, text, text, text), pg_temp.t14_get()
  to authenticated, anon;

insert into auth.users (id, email) values
  ('14140000-0000-4000-8000-000000000001', 'mh14-a@example.invalid'),
  ('14140000-0000-4000-8000-000000000002', 'mh14-b@example.invalid'),
  ('14140000-0000-4000-8000-000000000003', 'mh14-manager@example.invalid'),
  ('14140000-0000-4000-8000-000000000004', 'mh14-shipper@example.invalid');
update public.profiles set
  role = case id
    when '14140000-0000-4000-8000-000000000003' then 'manager'::public.user_role
    when '14140000-0000-4000-8000-000000000004' then 'shipper'::public.user_role
    else 'customer'::public.user_role end,
  full_name = case id
    when '14140000-0000-4000-8000-000000000004' then 'Shipper Thử Nghiệm'
    else null end,
  phone = case id
    when '14140000-0000-4000-8000-000000000004' then '0900000014'
    else null end
where id::text like '14140000-0000-4000-8000-00000000000%';

insert into public.categories (id, code, name)
values ('14140000-0000-4000-8000-000000000100', 'MH14', 'MH14 fixture');
insert into public.products (id, category_id, name)
values ('14140000-0000-4000-8000-000000000101',
        '14140000-0000-4000-8000-000000000100', 'MH14 jersey');
insert into public.product_variants (
  id, product_id, sku, label, price_vnd, on_hand, reserved, damaged
) values ('14140000-0000-4000-8000-000000000111',
  '14140000-0000-4000-8000-000000000101', 'MH14-01', 'Đen / M', 260000, 10, 0, 0);

insert into public.orders (
  id, customer_id, request_id, status, recipient_name, recipient_phone,
  address_detail, latitude, longitude, subtotal_vnd, delivery_fee_vnd,
  delivered_at
) values (
  '14141000-0000-4000-8000-000000000001',
  '14140000-0000-4000-8000-000000000001', gen_random_uuid(), 'delivered',
  'MH14 recipient', '0900001414', '25 Nguyễn Chí Thanh, Hà Nội', 21.03, 105.8,
  520000, 30000, now() - interval '2 days');
insert into public.order_items (
  id, order_id, product_id, variant_id, product_name, variant_label,
  unit_price_vnd, quantity
) values (
  '14141100-0000-4000-8000-000000000001',
  '14141000-0000-4000-8000-000000000001',
  '14140000-0000-4000-8000-000000000101', '14140000-0000-4000-8000-000000000111',
  'Áo Thể Thao Nam', 'Màu Đen / Size M', 260000, 2);
insert into storage.objects (bucket_id, name, owner_id, metadata) values (
  'return-videos',
  '14140000-0000-4000-8000-000000000001/14141000-0000-4000-8000-000000000001/v.mp4',
  '14140000-0000-4000-8000-000000000001', '{"mimetype":"video/mp4","size":4096}');

-- 1. Customer A submits through the real MH13 RPC.
select pg_temp.t14_claims('14140000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('t14.return_id', (
  public.submit_return_request('14141000-0000-4000-8000-000000000001',
    '14143000-0000-4000-8000-000000000001', 'defective',
    'Áo bị bung chỉ ở vai trái khi mở kiện.',
    '14140000-0000-4000-8000-000000000001/14141000-0000-4000-8000-000000000001/v.mp4',
    'Vietcombank', '0123456789', 'Nguyen Van A') ->> 'return_request_id'), true);

select pg_temp.t14_assert('pending right after submit',
  (select t ->> 'status' = 'pending_review'
      and t -> 'pickup' = 'null'::jsonb
      and t -> 'refund' = 'null'::jsonb
      and t ->> 'refund_account_masked' = '••••6789'
      and (t ->> 'merchandise_vnd')::bigint = 520000
      and (t ->> 'delivery_fee_vnd')::bigint = 30000
      and jsonb_array_length(t -> 'items') = 0
      and not (t ? 'account_number')
      and not (t ? 'transfer_evidence_path')
   from pg_temp.t14_get() as t));
reset role;

-- 2. Access control: other customer, manager, shipper, anonymous.
select pg_temp.t14_claims('14140000-0000-4000-8000-000000000002');
set local role authenticated;
select pg_temp.t14_error('customer B cannot open A return',
  'select pg_temp.t14_get()', 'PT404', 'RETURN_NOT_FOUND');
reset role;
select pg_temp.t14_claims('14140000-0000-4000-8000-000000000003');
set local role authenticated;
select pg_temp.t14_error('manager uses MH15, not the customer read',
  'select pg_temp.t14_get()', '42501', 'PERMISSION_DENIED');
reset role;
select pg_temp.t14_claims('14140000-0000-4000-8000-000000000004');
set local role authenticated;
select pg_temp.t14_error('shipper cannot read customer return',
  'select pg_temp.t14_get()', '42501', 'PERMISSION_DENIED');
reset role;
select pg_temp.t14_claims(null);
set local role authenticated;
select pg_temp.t14_error('no identity', 'select pg_temp.t14_get()', '42501',
  'AUTH_REQUIRED');
reset role;
set local role anon;
select pg_temp.t14_error('anon has no EXECUTE', 'select pg_temp.t14_get()',
  '42501');
reset role;

-- 3. Simulated MH15 approval: status + decision provenance + approved items.
update public.return_requests
set status = 'awaiting_return_pickup', decided_by =
      '14140000-0000-4000-8000-000000000003',
    decision_at = now()
where id = current_setting('t14.return_id')::uuid;
insert into public.return_items (
  return_request_id, order_id, order_item_id, actual_item_name,
  variant_id, quantity_to_collect
) values (
  current_setting('t14.return_id')::uuid,
  '14141000-0000-4000-8000-000000000001',
  '14141100-0000-4000-8000-000000000001', 'Áo Thể Thao Nam',
  '14140000-0000-4000-8000-000000000111', 2);

select pg_temp.t14_claims('14140000-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.t14_assert('approval visible on next read',
  (select t ->> 'status' = 'awaiting_return_pickup'
      and t ->> 'decision_at' is not null
      and t -> 'pickup' = 'null'::jsonb
      and jsonb_array_length(t -> 'items') = 1
      and t -> 'items' -> 0 ->> 'variant_label' = 'Màu Đen / Size M'
      and (t -> 'items' -> 0 ->> 'quantity')::bigint = 2
   from pg_temp.t14_get() as t));
reset role;

-- 4. Pickup assigned: the customer sees only that person's name/phone.
insert into public.delivery_tasks (
  id, order_id, return_request_id, kind, assigned_shipper_id, assigned_by,
  status, destination_name, destination_phone, destination_address,
  destination_latitude, destination_longitude, assigned_at
) values (
  '14144000-0000-4000-8000-000000000001',
  '14141000-0000-4000-8000-000000000001',
  current_setting('t14.return_id')::uuid, 'return_pickup',
  '14140000-0000-4000-8000-000000000004',
  '14140000-0000-4000-8000-000000000003', 'assigned', 'MH14 recipient',
  '0900001414', '25 Nguyễn Chí Thanh, Hà Nội', 21.03, 105.8, now());

select pg_temp.t14_claims('14140000-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.t14_assert('assigned person visible',
  (select t -> 'pickup' ->> 'status' = 'assigned'
      and t -> 'pickup' -> 'person' ->> 'name' = 'Shipper Thử Nghiệm'
      and t -> 'pickup' -> 'person' ->> 'phone' = '0900000014'
      and t ->> 'pickup_address' = '25 Nguyễn Chí Thanh, Hà Nội'
   from pg_temp.t14_get() as t));
select pg_temp.t14_assert('customer still cannot read tasks/profiles directly',
  (select count(*) = 0 from public.delivery_tasks)
  and (select count(*) = 0 from public.profiles
       where id = '14140000-0000-4000-8000-000000000004'));
reset role;

-- 5. Collected, then received at store: person hidden after the task ends.
update public.delivery_tasks
set status = 'in_transit', accepted_at = now(), started_at = now()
where id = '14144000-0000-4000-8000-000000000001';
update public.return_requests set status = 'returning_to_store'
where id = current_setting('t14.return_id')::uuid;
update public.delivery_tasks
set status = 'returned_to_store', completed_at = now()
where id = '14144000-0000-4000-8000-000000000001';
update public.return_requests
set status = 'under_inspection', inspection_started_at = now()
where id = current_setting('t14.return_id')::uuid;

select pg_temp.t14_claims('14140000-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.t14_assert('inspection with collection time, no person',
  (select t ->> 'status' = 'under_inspection'
      and t -> 'pickup' ->> 'collected_at' is not null
      and t ->> 'received_at_store' is not null
      and t -> 'pickup' -> 'person' = 'null'::jsonb
   from pg_temp.t14_get() as t));
reset role;

-- 6. Accepted: awaiting refund is NOT refunded.
update public.return_requests
set status = 'awaiting_refund', inspected_at = now(),
    inspected_by = '14140000-0000-4000-8000-000000000003'
where id = current_setting('t14.return_id')::uuid;
select pg_temp.t14_claims('14140000-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.t14_assert('awaiting refund has no refund record',
  (select t ->> 'status' = 'awaiting_refund' and t -> 'refund' = 'null'::jsonb
   from pg_temp.t14_get() as t));
reset role;

-- 7. Manager records the external transfer (amount, time, evidence).
update public.return_requests
set status = 'refunded', refund_amount_vnd = 550000,
    refunded_by = '14140000-0000-4000-8000-000000000003', refunded_at = now(),
    transfer_evidence_path = current_setting('t14.return_id') || '/proof.png',
    refund_request_id = gen_random_uuid(), closed_at = now()
where id = current_setting('t14.return_id')::uuid;
select pg_temp.t14_claims('14140000-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.t14_assert('refund shown only once recorded',
  (select t ->> 'status' = 'refunded'
      and (t -> 'refund' ->> 'amount_vnd')::bigint = 550000
      and (t -> 'refund' ->> 'has_transfer_evidence')::boolean
      and not (t -> 'refund' ? 'transfer_evidence_path')
   from pg_temp.t14_get() as t));
reset role;

-- 8. B is still denied after every transition.
select pg_temp.t14_claims('14140000-0000-4000-8000-000000000002');
set local role authenticated;
select pg_temp.t14_error('customer B still denied', 'select pg_temp.t14_get()',
  'PT404', 'RETURN_NOT_FOUND');
reset role;

select 'return_tracking.sql: PASS' as result;
rollback;
