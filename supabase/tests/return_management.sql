-- Return management (manager) phase 1 contract.
-- TEST FIXTURE ONLY. One transaction on the isolated PostgreSQL fixture,
-- rolled back at the end. Customers use the real MH13/MH14 RPCs; the manager
-- uses the new list/detail/approve/reject RPCs.

begin;

create or replace function pg_temp.t15_claims(p_user_id uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
  perform set_config('request.jwt.claims', case when p_user_id is null then ''
    else jsonb_build_object('sub', p_user_id::text, 'role', 'authenticated')::text
    end, true);
end;
$$;

create or replace function pg_temp.t15_assert(p_label text, p_condition boolean)
returns void language plpgsql as $$
begin
  if coalesce(p_condition, false) is not true then
    raise exception 'MH15 test failed: %', p_label;
  end if;
end;
$$;

create or replace function pg_temp.t15_error(
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
    raise exception 'MH15 test failed: % (expected %/%, got %/%)', p_label,
      p_state, coalesce(p_message, '<any>'), coalesce(l_state, 'success'),
      coalesce(l_message, '<none>');
  end if;
end;
$$;

grant execute on function pg_temp.t15_claims(uuid),
  pg_temp.t15_assert(text, boolean),
  pg_temp.t15_error(text, text, text, text)
  to authenticated, anon;

-- Actors: A/B customers, M manager, S shipper.
insert into auth.users (id, email) values
  ('15150000-0000-4000-8000-000000000001', 'mh15-a@example.invalid'),
  ('15150000-0000-4000-8000-000000000002', 'mh15-b@example.invalid'),
  ('15150000-0000-4000-8000-000000000003', 'mh15-manager@example.invalid'),
  ('15150000-0000-4000-8000-000000000004', 'mh15-shipper@example.invalid');
update public.profiles set
  role = case id
    when '15150000-0000-4000-8000-000000000003' then 'manager'::public.user_role
    when '15150000-0000-4000-8000-000000000004' then 'shipper'::public.user_role
    else 'customer'::public.user_role end,
  full_name = case id
    when '15150000-0000-4000-8000-000000000001' then 'Nguyễn Minh Anh'
    when '15150000-0000-4000-8000-000000000002' then 'Trần Bảo Ngọc'
    when '15150000-0000-4000-8000-000000000004' then 'Shipper Mười Lăm'
    else 'Quản lý' end,
  phone = case id
    when '15150000-0000-4000-8000-000000000001' then '0912345678'
    when '15150000-0000-4000-8000-000000000004' then '0900000015'
    else null end
where id::text like '15150000-0000-4000-8000-00000000000%';

insert into public.categories (id, code, name)
values ('15150000-0000-4000-8000-000000000100', 'MH15', 'MH15 fixture');
insert into public.products (id, category_id, name)
values ('15150000-0000-4000-8000-000000000101',
        '15150000-0000-4000-8000-000000000100', 'MH15 jersey');
insert into public.product_variants (
  id, product_id, sku, label, price_vnd, on_hand, reserved, damaged
) values ('15150000-0000-4000-8000-000000000111',
  '15150000-0000-4000-8000-000000000101', 'MH15-01', 'Đen / M', 275000, 10, 0, 0);

insert into public.orders (
  id, customer_id, request_id, status, recipient_name, recipient_phone,
  address_detail, latitude, longitude, subtotal_vnd, delivery_fee_vnd,
  delivered_at
) values
  ('15151000-0000-4000-8000-000000000001',
   '15150000-0000-4000-8000-000000000001', gen_random_uuid(), 'delivered',
   'Nguyễn Minh Anh', '0912345678', '25 Nguyễn Chí Thanh, Hà Nội', 21.03, 105.8,
   550000, 30000, now() - interval '2 days'),
  ('15151000-0000-4000-8000-000000000002',
   '15150000-0000-4000-8000-000000000002', gen_random_uuid(), 'delivered',
   'Trần Bảo Ngọc', '0900001515', '1 Tràng Tiền, Hà Nội', 21.02, 105.85,
   275000, 30000, now() - interval '1 day');
insert into public.order_items (
  id, order_id, product_id, variant_id, product_name, variant_label,
  unit_price_vnd, quantity
) values
  ('15151100-0000-4000-8000-000000000001', '15151000-0000-4000-8000-000000000001',
   '15150000-0000-4000-8000-000000000101', '15150000-0000-4000-8000-000000000111',
   'Áo thể thao Performance Core', 'Đen / M', 275000, 2),
  ('15151100-0000-4000-8000-000000000002', '15151000-0000-4000-8000-000000000002',
   '15150000-0000-4000-8000-000000000101', '15150000-0000-4000-8000-000000000111',
   'Áo thể thao Performance Core', 'Đen / M', 275000, 1);
insert into storage.objects (bucket_id, name, owner_id, metadata) values
  ('return-videos',
   '15150000-0000-4000-8000-000000000001/15151000-0000-4000-8000-000000000001/v.mp4',
   '15150000-0000-4000-8000-000000000001', '{"mimetype":"video/mp4","size":4096}'),
  ('return-videos',
   '15150000-0000-4000-8000-000000000002/15151000-0000-4000-8000-000000000002/v.mp4',
   '15150000-0000-4000-8000-000000000002', '{"mimetype":"video/mp4","size":4096}');

-- 1. Both customers submit through the real MH13 RPC.
select pg_temp.t15_claims('15150000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('t15.ra', (
  public.submit_return_request('15151000-0000-4000-8000-000000000001',
    '15153000-0000-4000-8000-000000000001', 'defective',
    'Đường may ở vai áo bị bung khi mở kiện hàng.',
    '15150000-0000-4000-8000-000000000001/15151000-0000-4000-8000-000000000001/v.mp4',
    'Vietcombank', '0011004392819', 'NGUYEN MINH ANH') ->> 'return_request_id'), true);
reset role;
select pg_temp.t15_claims('15150000-0000-4000-8000-000000000002');
set local role authenticated;
select set_config('t15.rb', (
  public.submit_return_request('15151000-0000-4000-8000-000000000002',
    '15153000-0000-4000-8000-000000000002', 'wrong_item',
    'Nhận sai màu áo so với đơn đã đặt.',
    '15150000-0000-4000-8000-000000000002/15151000-0000-4000-8000-000000000002/v.mp4',
    'Techcombank', '1903555500001', 'TRAN BAO NGOC') ->> 'return_request_id'), true);
reset role;

-- 2. Access control for every new RPC.
select pg_temp.t15_claims('15150000-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.t15_error('customer cannot list',
  'select public.list_manager_return_requests()', '42501', 'PERMISSION_DENIED');
select pg_temp.t15_error('customer cannot read detail',
  format('select public.get_manager_return_request(%L)', current_setting('t15.ra')),
  '42501', 'PERMISSION_DENIED');
select pg_temp.t15_error('customer cannot approve',
  format('select public.approve_return_collection(%L, gen_random_uuid(), %L, %L)',
    current_setting('t15.ra'),
    '[{"order_item_id":"15151100-0000-4000-8000-000000000001","quantity":1}]',
    '15150000-0000-4000-8000-000000000004'),
  '42501', 'PERMISSION_DENIED');
select pg_temp.t15_error('customer cannot reject',
  format('select public.reject_return_request(%L, gen_random_uuid(), %L)',
    current_setting('t15.ra'), 'Không đủ điều kiện'),
  '42501', 'PERMISSION_DENIED');
reset role;
select pg_temp.t15_claims('15150000-0000-4000-8000-000000000004');
set local role authenticated;
select pg_temp.t15_error('shipper cannot list',
  'select public.list_manager_return_requests()', '42501', 'PERMISSION_DENIED');
reset role;
select pg_temp.t15_claims(null);
set local role authenticated;
select pg_temp.t15_error('no identity',
  'select public.list_manager_return_requests()', '42501', 'AUTH_REQUIRED');
reset role;
set local role anon;
select pg_temp.t15_error('anon has no EXECUTE',
  'select public.list_manager_return_requests()', '42501');
select pg_temp.t15_error('anon cannot approve',
  format('select public.approve_return_collection(%L, gen_random_uuid(), %L, %L)',
    current_setting('t15.ra'), '[]', '15150000-0000-4000-8000-000000000004'),
  '42501');
reset role;

-- 3. Manager list: filters, counts and search.
select pg_temp.t15_claims('15150000-0000-4000-8000-000000000003');
set local role authenticated;
select pg_temp.t15_assert('list shows both pending with counts',
  (select jsonb_array_length(l -> 'items') = 2
      and (l -> 'counts' ->> 'pending_review')::int = 2
      and (l -> 'items' -> 0 ->> 'total_vnd')::bigint > 0
      and l -> 'items' -> 0 ? 'customer_name'
   from public.list_manager_return_requests() l));
select pg_temp.t15_assert('search by customer name',
  (select jsonb_array_length(l -> 'items') = 1
      and l -> 'items' -> 0 ->> 'return_id' = current_setting('t15.ra')
   from public.list_manager_return_requests(null, 'minh anh') l));
select pg_temp.t15_assert('search by order code with prefix and hyphens',
  (select jsonb_array_length(l -> 'items') = 1
      and l -> 'items' -> 0 ->> 'order_id' = '15151000-0000-4000-8000-000000000002'
   from public.list_manager_return_requests(null, '#DH-15151000-0000-4000-8000-000000000002') l));
select pg_temp.t15_assert('search by return code fragment',
  (select jsonb_array_length(l -> 'items') = 1
      and l -> 'items' -> 0 ->> 'return_id' = current_setting('t15.rb')
   from public.list_manager_return_requests(null,
     'TH-' || upper(left(current_setting('t15.rb'), 8))) l));
select pg_temp.t15_assert('short code fragments do not match everything',
  (select jsonb_array_length(l -> 'items') = 0
   from public.list_manager_return_requests(null, 'zz') l));
select pg_temp.t15_assert('status filter keeps all-status counts',
  (select jsonb_array_length(l -> 'items') = 0
      and (l -> 'counts' ->> 'pending_review')::int = 2
   from public.list_manager_return_requests('awaiting_return_pickup', null) l));
select pg_temp.t15_error('unknown status filter',
  'select public.list_manager_return_requests(''bogus'')', '22023', 'INVALID_ARGUMENT');

-- 4. Detail.
select pg_temp.t15_assert('detail exposes decision data to the manager',
  (select d ->> 'status' = 'pending_review'
      and d -> 'customer' ->> 'name' = 'Nguyễn Minh Anh'
      and d -> 'bank' ->> 'account_number' = '0011004392819'
      and jsonb_array_length(d -> 'video_paths') = 1
      and jsonb_array_length(d -> 'order_items') = 1
      and (d -> 'order_items' -> 0 ->> 'quantity')::int = 2
      and jsonb_array_length(d -> 'return_items') = 0
      and d -> 'pickup_task' = 'null'::jsonb
      and (d ->> 'total_vnd')::bigint = 580000
      and exists (select 1 from jsonb_array_elements(d -> 'shippers') s
                  where s ->> 'shipper_id' = '15150000-0000-4000-8000-000000000004')
   from public.get_manager_return_request(current_setting('t15.ra')::uuid) d));
select pg_temp.t15_error('unknown return',
  'select public.get_manager_return_request(gen_random_uuid())', 'PT404', 'RETURN_NOT_FOUND');

-- 5. Approve validation (nothing is written on failure).
select pg_temp.t15_error('empty plan',
  format('select public.approve_return_collection(%L, gen_random_uuid(), %L, %L)',
    current_setting('t15.ra'), '[]', '15150000-0000-4000-8000-000000000004'),
  '22023', 'INVALID_ARGUMENT');
select pg_temp.t15_error('zero quantity',
  format('select public.approve_return_collection(%L, gen_random_uuid(), %L, %L)',
    current_setting('t15.ra'),
    '[{"order_item_id":"15151100-0000-4000-8000-000000000001","quantity":0}]',
    '15150000-0000-4000-8000-000000000004'),
  '22023', 'INVALID_ARGUMENT');
select pg_temp.t15_error('extra keys',
  format('select public.approve_return_collection(%L, gen_random_uuid(), %L, %L)',
    current_setting('t15.ra'),
    '[{"order_item_id":"15151100-0000-4000-8000-000000000001","quantity":1,"price":1}]',
    '15150000-0000-4000-8000-000000000004'),
  '22023', 'INVALID_ARGUMENT');
select pg_temp.t15_error('more than ordered',
  format('select public.approve_return_collection(%L, gen_random_uuid(), %L, %L)',
    current_setting('t15.ra'),
    '[{"order_item_id":"15151100-0000-4000-8000-000000000001","quantity":3}]',
    '15150000-0000-4000-8000-000000000004'),
  'PT409', 'ITEMS_MISMATCH');
select pg_temp.t15_error('item from another order',
  format('select public.approve_return_collection(%L, gen_random_uuid(), %L, %L)',
    current_setting('t15.ra'),
    '[{"order_item_id":"15151100-0000-4000-8000-000000000002","quantity":1}]',
    '15150000-0000-4000-8000-000000000004'),
  'PT409', 'ITEMS_MISMATCH');
select pg_temp.t15_error('customer is not a shipper',
  format('select public.approve_return_collection(%L, gen_random_uuid(), %L, %L)',
    current_setting('t15.ra'),
    '[{"order_item_id":"15151100-0000-4000-8000-000000000001","quantity":1}]',
    '15150000-0000-4000-8000-000000000002'),
  'PT409', 'INVALID_SHIPPER');
reset role;
select pg_temp.t15_assert('failed approvals wrote nothing',
  (select count(*) = 0 from public.return_items
    where return_request_id = current_setting('t15.ra')::uuid)
  and (select status = 'pending_review' from public.return_requests
    where id = current_setting('t15.ra')::uuid));

-- 6. Approve + assign in one call.
select pg_temp.t15_claims('15150000-0000-4000-8000-000000000003');
set local role authenticated;
select set_config('t15.ack', public.approve_return_collection(
  current_setting('t15.ra')::uuid, '15154000-0000-4000-8000-000000000001',
  '[{"order_item_id":"15151100-0000-4000-8000-000000000001","quantity":1}]',
  '15150000-0000-4000-8000-000000000004')::text, true);
select pg_temp.t15_assert('ack shape',
  (select a ->> 'return_status' = 'awaiting_return_pickup'
      and a ->> 'task_id' is not null
      and a ->> 'shipper_id' = '15150000-0000-4000-8000-000000000004'
   from (select current_setting('t15.ack')::jsonb a) x));
select pg_temp.t15_assert('detail after approval',
  (select d ->> 'status' = 'awaiting_return_pickup'
      and jsonb_array_length(d -> 'return_items') = 1
      and (d -> 'return_items' -> 0 ->> 'quantity_to_collect')::int = 1
      and d -> 'pickup_task' ->> 'status' = 'assigned'
      and d -> 'pickup_task' ->> 'shipper_name' = 'Shipper Mười Lăm'
   from public.get_manager_return_request(current_setting('t15.ra')::uuid) d));
-- Replay: same key + payload returns the same ACK and writes nothing new.
select pg_temp.t15_assert('replay returns stored ack',
  public.approve_return_collection(
    current_setting('t15.ra')::uuid, '15154000-0000-4000-8000-000000000001',
    '[{"order_item_id":"15151100-0000-4000-8000-000000000001","quantity":1}]',
    '15150000-0000-4000-8000-000000000004') = current_setting('t15.ack')::jsonb);
select pg_temp.t15_error('same key, different payload',
  format('select public.approve_return_collection(%L, %L, %L, %L)',
    current_setting('t15.ra'), '15154000-0000-4000-8000-000000000001',
    '[{"order_item_id":"15151100-0000-4000-8000-000000000001","quantity":2}]',
    '15150000-0000-4000-8000-000000000004'),
  'PT409', 'IDEMPOTENCY_CONFLICT');
select pg_temp.t15_error('new key after approval',
  format('select public.approve_return_collection(%L, gen_random_uuid(), %L, %L)',
    current_setting('t15.ra'),
    '[{"order_item_id":"15151100-0000-4000-8000-000000000001","quantity":1}]',
    '15150000-0000-4000-8000-000000000004'),
  'PT409', 'STATE_CONFLICT');
select pg_temp.t15_error('cannot reject after approval',
  format('select public.reject_return_request(%L, gen_random_uuid(), %L)',
    current_setting('t15.ra'), 'Đổi ý sau khi duyệt'),
  'PT409', 'STATE_CONFLICT');
reset role;
select pg_temp.t15_assert('exactly one task, items, events and notifications',
  (select count(*) = 1 from public.delivery_tasks
    where return_request_id = current_setting('t15.ra')::uuid
      and kind = 'return_pickup' and status = 'assigned'
      and assigned_shipper_id = '15150000-0000-4000-8000-000000000004'
      and amount_to_collect_vnd = 0)
  and (select count(*) = 1 from public.return_items
    where return_request_id = current_setting('t15.ra')::uuid)
  and (select count(*) = 1 from public.notifications
    where recipient_id = '15150000-0000-4000-8000-000000000001'
      and title = 'Yêu cầu trả hàng đã được duyệt lấy hàng')
  and (select count(*) = 1 from public.notifications
    where recipient_id = '15150000-0000-4000-8000-000000000004'
      and title = 'Nhiệm vụ thu hồi hàng mới')
  and (select count(*) = 1 from private.return_management_requests
    where return_request_id = current_setting('t15.ra')::uuid));
select pg_temp.t15_assert('approval never touches refund, COD or stock',
  (select refund_amount_vnd is null and refunded_at is null
     from public.return_requests where id = current_setting('t15.ra')::uuid)
  and (select on_hand = 10 and reserved = 0 and damaged = 0
     from public.product_variants where id = '15150000-0000-4000-8000-000000000111')
  and (select status = 'delivered' from public.orders
     where id = '15151000-0000-4000-8000-000000000001'));

-- 7. The customer sees "Chờ lấy hàng" with the assigned shipper (MH14).
select pg_temp.t15_claims('15150000-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.t15_assert('MH14 shows awaiting pickup',
  (select t ->> 'status' = 'awaiting_return_pickup'
      and t -> 'pickup' <> 'null'::jsonb
      and t -> 'refund' = 'null'::jsonb
   from public.get_my_return_request(current_setting('t15.ra')::uuid) t));
reset role;

-- 8. Reject before pickup (customer B).
select pg_temp.t15_claims('15150000-0000-4000-8000-000000000003');
set local role authenticated;
select pg_temp.t15_error('reason required',
  format('select public.reject_return_request(%L, gen_random_uuid(), %L)',
    current_setting('t15.rb'), '  '),
  '22023', 'INVALID_ARGUMENT');
select set_config('t15.rack', public.reject_return_request(
  current_setting('t15.rb')::uuid, '15154000-0000-4000-8000-000000000002',
  'Video không thể hiện lỗi sản phẩm như mô tả.')::text, true);
select pg_temp.t15_assert('reject replay is idempotent',
  public.reject_return_request(
    current_setting('t15.rb')::uuid, '15154000-0000-4000-8000-000000000002',
    'Video không thể hiện lỗi sản phẩm như mô tả.') = current_setting('t15.rack')::jsonb);
select pg_temp.t15_error('cannot approve a rejected return',
  format('select public.approve_return_collection(%L, gen_random_uuid(), %L, %L)',
    current_setting('t15.rb'),
    '[{"order_item_id":"15151100-0000-4000-8000-000000000002","quantity":1}]',
    '15150000-0000-4000-8000-000000000004'),
  'PT409', 'STATE_CONFLICT');
select pg_temp.t15_assert('list counts after decisions',
  (select (l -> 'counts' ->> 'awaiting_return_pickup')::int = 1
      and (l -> 'counts' ->> 'initially_rejected')::int = 1
      and l -> 'counts' -> 'pending_review' is null
   from public.list_manager_return_requests() l));
reset role;
select pg_temp.t15_assert('rejection closes without pickup/refund',
  (select status = 'initially_rejected' and closed_at is not null
      and decision_reason = 'Video không thể hiện lỗi sản phẩm như mô tả.'
      and refund_amount_vnd is null
     from public.return_requests where id = current_setting('t15.rb')::uuid)
  and (select count(*) = 0 from public.delivery_tasks
     where return_request_id = current_setting('t15.rb')::uuid)
  and (select count(*) = 1 from public.notifications
     where recipient_id = '15150000-0000-4000-8000-000000000002'
       and title = 'Yêu cầu trả hàng không được duyệt'));
select pg_temp.t15_claims('15150000-0000-4000-8000-000000000002');
set local role authenticated;
select pg_temp.t15_assert('MH14 shows initial rejection with reason',
  (select t ->> 'status' = 'initially_rejected'
      and t ->> 'decision_reason' = 'Video không thể hiện lỗi sản phẩm như mô tả.'
   from public.get_my_return_request(current_setting('t15.rb')::uuid) t));
reset role;

select 'return_management.sql: PASS';
rollback;
