-- MH13 get_return_request_context / submit_return_request contract.
-- TEST FIXTURE ONLY. Runs in one transaction on an isolated PostgreSQL
-- fixture after all migrations and rolls every row back.

begin;

create or replace function pg_temp.mh13_claims(p_user_id uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
  perform set_config('request.jwt.claims', case when p_user_id is null then ''
    else jsonb_build_object('sub', p_user_id::text, 'role', 'authenticated')::text
    end, true);
end;
$$;

create or replace function pg_temp.mh13_assert(p_label text, p_condition boolean)
returns void language plpgsql as $$
begin
  if coalesce(p_condition, false) is not true then
    raise exception 'MH13 test failed: %', p_label;
  end if;
end;
$$;

create or replace function pg_temp.mh13_error(
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
    raise exception 'MH13 test failed: % (expected %/%, got %/%)', p_label,
      p_state, coalesce(p_message, '<any>'), coalesce(l_state, 'success'),
      coalesce(l_message, '<none>');
  end if;
end;
$$;

grant execute on function pg_temp.mh13_claims(uuid), pg_temp.mh13_assert(text, boolean),
  pg_temp.mh13_error(text, text, text, text) to authenticated, anon;

-- Users: A customer, B customer, manager, shipper.
insert into auth.users (id, email) values
  ('13130000-0000-4000-8000-000000000001', 'mh13-a@example.invalid'),
  ('13130000-0000-4000-8000-000000000002', 'mh13-b@example.invalid'),
  ('13130000-0000-4000-8000-000000000003', 'mh13-manager@example.invalid'),
  ('13130000-0000-4000-8000-000000000004', 'mh13-shipper@example.invalid');
update public.profiles set role = case id
    when '13130000-0000-4000-8000-000000000003' then 'manager'::public.user_role
    when '13130000-0000-4000-8000-000000000004' then 'shipper'::public.user_role
    else 'customer'::public.user_role end
where id::text like '13130000-0000-4000-8000-00000000000%';

insert into public.categories (id, code, name)
values ('13130000-0000-4000-8000-000000000100', 'MH13', 'MH13 fixture');
insert into public.products (id, category_id, name)
values ('13130000-0000-4000-8000-000000000101',
        '13130000-0000-4000-8000-000000000100', 'MH13 jersey');
insert into public.product_variants (
  id, product_id, sku, label, price_vnd, on_hand, reserved, damaged
) values ('13130000-0000-4000-8000-000000000111',
  '13130000-0000-4000-8000-000000000101', 'MH13-01', 'Đen / M', 260000, 10, 0, 0);

-- o1 delivered 2 days ago, o2 8 days ago, o3 still delivering,
-- o4 6d23h ago (inside the window), o5 belongs to B.
insert into public.orders (
  id, customer_id, request_id, status, recipient_name, recipient_phone,
  address_detail, latitude, longitude, subtotal_vnd, delivery_fee_vnd,
  delivered_at
)
select ('13131000-0000-4000-8000-00000000000' || n)::uuid,
  case when n = 5 then '13130000-0000-4000-8000-000000000002'::uuid
       else '13130000-0000-4000-8000-000000000001'::uuid end,
  ('13132000-0000-4000-8000-00000000000' || n)::uuid,
  case when n = 3 then 'delivering'::public.order_status
       else 'delivered'::public.order_status end,
  'MH13 recipient', '0900001313', 'MH13 address, Ha Noi', 21.03, 105.80,
  520000, 30000,
  case n when 1 then now() - interval '2 days'
         when 2 then now() - interval '8 days'
         when 3 then null
         when 4 then now() - interval '6 days 23 hours'
         else now() - interval '1 day' end
from generate_series(1, 5) as s(n);

insert into public.order_items (
  order_id, product_id, variant_id, product_name, variant_label,
  unit_price_vnd, quantity
)
select ('13131000-0000-4000-8000-00000000000' || n)::uuid,
  '13130000-0000-4000-8000-000000000101', '13130000-0000-4000-8000-000000000111',
  'Áo Thể Thao Nam', 'Màu Đen / Size M', 260000, 2
from generate_series(1, 5) as s(n);

insert into storage.objects (bucket_id, name, owner_id, metadata) values
  ('return-videos',
   '13130000-0000-4000-8000-000000000001/13131000-0000-4000-8000-000000000001/v1.mp4',
   '13130000-0000-4000-8000-000000000001',
   '{"mimetype":"video/mp4","size":1048576}'),
  ('return-videos',
   '13130000-0000-4000-8000-000000000001/13131000-0000-4000-8000-000000000001/note.txt',
   '13130000-0000-4000-8000-000000000001',
   '{"mimetype":"text/plain","size":12}'),
  ('return-videos',
   '13130000-0000-4000-8000-000000000001/13131000-0000-4000-8000-000000000001/empty.mp4',
   '13130000-0000-4000-8000-000000000001',
   '{"mimetype":"video/mp4","size":0}'),
  ('return-videos',
   '13130000-0000-4000-8000-000000000002/13131000-0000-4000-8000-000000000001/b.mp4',
   '13130000-0000-4000-8000-000000000002',
   '{"mimetype":"video/mp4","size":2048}'),
  ('return-videos',
   '13130000-0000-4000-8000-000000000001/13131000-0000-4000-8000-000000000002/v2.mp4',
   '13130000-0000-4000-8000-000000000001',
   '{"mimetype":"video/mp4","size":2048}'),
  ('return-videos',
   '13130000-0000-4000-8000-000000000001/13131000-0000-4000-8000-000000000004/v4.mov',
   '13130000-0000-4000-8000-000000000001',
   '{"mimetype":"video/quicktime","size":4096}');

-- Template for a valid o1 submission; %s placeholders: request id, path.
create or replace function pg_temp.mh13_submit_sql(
  p_order text, p_request text, p_path text,
  p_description text default 'Áo bị rách đường may ở vai trái khi mở kiện.',
  p_account text default '0123 4567 89'
) returns text language sql as $$
  select format(
    'select public.submit_return_request(%L::uuid, %L::uuid, %L, %L, %L, %L, %L, %L)',
    p_order, p_request, 'defective', p_description, p_path,
    'Vietcombank', p_account, 'nguyen van a');
$$;
grant execute on function pg_temp.mh13_submit_sql(text, text, text, text, text)
  to authenticated, anon;

-- 1. Unauthenticated callers are rejected.
select pg_temp.mh13_claims(null);
set local role anon;
select pg_temp.mh13_error('anon cannot execute submit',
  pg_temp.mh13_submit_sql('13131000-0000-4000-8000-000000000001',
    '13133000-0000-4000-8000-000000000001', 'x/y/z.mp4'), '42501');
reset role;
set local role authenticated;
select pg_temp.mh13_error('missing identity',
  pg_temp.mh13_submit_sql('13131000-0000-4000-8000-000000000001',
    '13133000-0000-4000-8000-000000000001', 'x/y/z.mp4'), '42501', 'AUTH_REQUIRED');
reset role;

-- 2. Context for the owner: eligible, server deadline = delivered_at + 7d.
select pg_temp.mh13_claims('13130000-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.mh13_assert('context eligible',
  (public.get_return_request_context('13131000-0000-4000-8000-000000000001')
     ->> 'can_submit_return')::boolean);
select pg_temp.mh13_assert('context totals and items',
  (select (c ->> 'total_paid_vnd')::bigint = 550000
      and jsonb_array_length(c -> 'items') = 1
      and (c -> 'items' -> 0 ->> 'line_total_vnd')::bigint = 520000
      and (c -> 'items' -> 0) ? 'product_image_url'
   from (select public.get_return_request_context(
     '13131000-0000-4000-8000-000000000001') as c) s));
select pg_temp.mh13_assert('context expired reason',
  public.get_return_request_context('13131000-0000-4000-8000-000000000002')
    ->> 'eligibility_reason' = 'return_window_expired');
select pg_temp.mh13_assert('context not delivered reason',
  public.get_return_request_context('13131000-0000-4000-8000-000000000003')
    ->> 'eligibility_reason' = 'not_delivered');
select pg_temp.mh13_error('context hides other customer order',
  $q$select public.get_return_request_context('13131000-0000-4000-8000-000000000005')$q$,
  'PT404', 'ORDER_NOT_FOUND');
reset role;

-- 3. Ownership / role.
select pg_temp.mh13_claims('13130000-0000-4000-8000-000000000002');
set local role authenticated;
select pg_temp.mh13_error('B cannot submit for A order',
  pg_temp.mh13_submit_sql('13131000-0000-4000-8000-000000000001',
    '13133000-0000-4000-8000-000000000002',
    '13130000-0000-4000-8000-000000000002/13131000-0000-4000-8000-000000000001/b.mp4'),
  'PT404', 'ORDER_NOT_FOUND');
reset role;
select pg_temp.mh13_claims('13130000-0000-4000-8000-000000000003');
set local role authenticated;
select pg_temp.mh13_error('manager cannot submit',
  pg_temp.mh13_submit_sql('13131000-0000-4000-8000-000000000001',
    '13133000-0000-4000-8000-000000000003', 'x/y/z.mp4'), '42501', 'PERMISSION_DENIED');
select pg_temp.mh13_error('manager cannot read customer context',
  $q$select public.get_return_request_context('13131000-0000-4000-8000-000000000001')$q$,
  '42501', 'PERMISSION_DENIED');
reset role;
select pg_temp.mh13_claims('13130000-0000-4000-8000-000000000004');
set local role authenticated;
select pg_temp.mh13_error('shipper cannot submit',
  pg_temp.mh13_submit_sql('13131000-0000-4000-8000-000000000001',
    '13133000-0000-4000-8000-000000000004', 'x/y/z.mp4'), '42501', 'PERMISSION_DENIED');
reset role;

-- 4. Validation, state, deadline and video for customer A.
select pg_temp.mh13_claims('13130000-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.mh13_error('short description',
  pg_temp.mh13_submit_sql('13131000-0000-4000-8000-000000000001',
    '13133000-0000-4000-8000-000000000010',
    '13130000-0000-4000-8000-000000000001/13131000-0000-4000-8000-000000000001/v1.mp4',
    'Hỏng'), '22023', 'INVALID_ARGUMENT');
select pg_temp.mh13_error('bad account number',
  pg_temp.mh13_submit_sql('13131000-0000-4000-8000-000000000001',
    '13133000-0000-4000-8000-000000000011',
    '13130000-0000-4000-8000-000000000001/13131000-0000-4000-8000-000000000001/v1.mp4',
    p_account => '12ab'), '22023', 'INVALID_ARGUMENT');
select pg_temp.mh13_error('unknown reason',
  $q$select public.submit_return_request('13131000-0000-4000-8000-000000000001',
    '13133000-0000-4000-8000-000000000012', 'changed_mind', 'Không thích nữa, muốn trả.',
    '13130000-0000-4000-8000-000000000001/13131000-0000-4000-8000-000000000001/v1.mp4',
    'VCB', '0123456789', 'A')$q$, '22023', 'INVALID_ARGUMENT');
select pg_temp.mh13_error('expired window',
  pg_temp.mh13_submit_sql('13131000-0000-4000-8000-000000000002',
    '13133000-0000-4000-8000-000000000013',
    '13130000-0000-4000-8000-000000000001/13131000-0000-4000-8000-000000000002/v2.mp4'),
  'PT409', 'RETURN_WINDOW_EXPIRED');
select pg_temp.mh13_error('not delivered',
  pg_temp.mh13_submit_sql('13131000-0000-4000-8000-000000000003',
    '13133000-0000-4000-8000-000000000014',
    '13130000-0000-4000-8000-000000000001/13131000-0000-4000-8000-000000000003/v3.mp4'),
  'PT409', 'ORDER_NOT_DELIVERED');
select pg_temp.mh13_error('missing video object',
  pg_temp.mh13_submit_sql('13131000-0000-4000-8000-000000000001',
    '13133000-0000-4000-8000-000000000015',
    '13130000-0000-4000-8000-000000000001/13131000-0000-4000-8000-000000000001/none.mp4'),
  'PT422', 'VIDEO_REQUIRED');
select pg_temp.mh13_error('non-video object',
  pg_temp.mh13_submit_sql('13131000-0000-4000-8000-000000000001',
    '13133000-0000-4000-8000-000000000016',
    '13130000-0000-4000-8000-000000000001/13131000-0000-4000-8000-000000000001/note.txt'),
  'PT422', 'VIDEO_REQUIRED');
select pg_temp.mh13_error('empty video object',
  pg_temp.mh13_submit_sql('13131000-0000-4000-8000-000000000001',
    '13133000-0000-4000-8000-000000000017',
    '13130000-0000-4000-8000-000000000001/13131000-0000-4000-8000-000000000001/empty.mp4'),
  'PT422', 'VIDEO_REQUIRED');
select pg_temp.mh13_error('another customer video',
  pg_temp.mh13_submit_sql('13131000-0000-4000-8000-000000000001',
    '13133000-0000-4000-8000-000000000018',
    '13130000-0000-4000-8000-000000000002/13131000-0000-4000-8000-000000000001/b.mp4'),
  'PT422', 'VIDEO_REQUIRED');
select pg_temp.mh13_error('video from another order folder',
  pg_temp.mh13_submit_sql('13131000-0000-4000-8000-000000000001',
    '13133000-0000-4000-8000-000000000019',
    '13130000-0000-4000-8000-000000000001/13131000-0000-4000-8000-000000000002/v2.mp4'),
  'PT422', 'VIDEO_REQUIRED');
select pg_temp.mh13_error('client cannot insert return directly',
  $q$insert into public.return_requests (order_id, customer_id, request_id, reason,
     description, video_object_path) values ('13131000-0000-4000-8000-000000000001',
     '13130000-0000-4000-8000-000000000001', gen_random_uuid(), 'defective',
     'direct insert attempt', 'a/b/c.mp4')$q$, '42501');

-- 5. Success, then replay and conflicts.
select set_config('mh13.first', (
  public.submit_return_request('13131000-0000-4000-8000-000000000001',
    '13133000-0000-4000-8000-000000000020', 'defective',
    '  Áo bị rách   đường may ở vai trái khi mở kiện. ',
    '13130000-0000-4000-8000-000000000001/13131000-0000-4000-8000-000000000001/v1.mp4',
    'Vietcombank', '0123 4567 89', 'nguyen van a')
)::text, true);
select pg_temp.mh13_assert('first submit pending',
  (current_setting('mh13.first')::jsonb ->> 'status') = 'pending_review'
  and (current_setting('mh13.first')::jsonb ->> 'replayed')::boolean = false);
select pg_temp.mh13_assert('replay returns same return id',
  (public.submit_return_request('13131000-0000-4000-8000-000000000001',
    '13133000-0000-4000-8000-000000000020', 'defective',
    'Áo bị rách đường may ở vai trái khi mở kiện.',
    '13130000-0000-4000-8000-000000000001/13131000-0000-4000-8000-000000000001/v1.mp4',
    'Vietcombank', '0123456789', 'NGUYEN VAN A') ->> 'return_request_id')
  = current_setting('mh13.first')::jsonb ->> 'return_request_id');
select pg_temp.mh13_error('same key different payload',
  pg_temp.mh13_submit_sql('13131000-0000-4000-8000-000000000001',
    '13133000-0000-4000-8000-000000000020',
    '13130000-0000-4000-8000-000000000001/13131000-0000-4000-8000-000000000001/v1.mp4',
    'Một mô tả khác hoàn toàn cho cùng khóa.'), 'PT409', 'IDEMPOTENCY_CONFLICT');
select pg_temp.mh13_error('second active return blocked',
  pg_temp.mh13_submit_sql('13131000-0000-4000-8000-000000000001',
    '13133000-0000-4000-8000-000000000021',
    '13130000-0000-4000-8000-000000000001/13131000-0000-4000-8000-000000000001/v1.mp4'),
  'PT409', 'ACTIVE_RETURN_EXISTS');
select pg_temp.mh13_assert('context reports active return',
  public.get_return_request_context('13131000-0000-4000-8000-000000000001')
    ->> 'eligibility_reason' = 'active_return_exists');
select pg_temp.mh13_assert('inside-window boundary succeeds',
  public.submit_return_request('13131000-0000-4000-8000-000000000004',
    '13133000-0000-4000-8000-000000000022', 'wrong_item',
    'Nhận sai màu, đặt màu đen nhưng giao màu trắng.',
    '13130000-0000-4000-8000-000000000001/13131000-0000-4000-8000-000000000004/v4.mov',
    'Techcombank', '190312345678', 'Nguyen Van A') ->> 'status' = 'pending_review');
select pg_temp.mh13_error('boundary order now has an active return',
  pg_temp.mh13_submit_sql('13131000-0000-4000-8000-000000000004',
    '13133000-0000-4000-8000-000000000023',
    '13130000-0000-4000-8000-000000000001/13131000-0000-4000-8000-000000000001/v1.mp4'),
  'PT409', 'ACTIVE_RETURN_EXISTS');
reset role;

-- 6. Persisted state as admin: canonical values, events, notifications.
select pg_temp.mh13_assert('stored canonical row',
  (select count(*) = 1 from public.return_requests r
   where r.id = (current_setting('mh13.first')::jsonb ->> 'return_request_id')::uuid
     and r.description = 'Áo bị rách đường may ở vai trái khi mở kiện.'
     and r.account_number = '0123456789'
     and r.account_holder = 'NGUYEN VAN A'
     and r.status = 'pending_review'));
select pg_temp.mh13_assert('order and COD untouched',
  (select status = 'delivered' from public.orders
   where id = '13131000-0000-4000-8000-000000000001'));
select pg_temp.mh13_assert('one event per submission',
  (select count(*) = 2 from public.business_events
   where subject_type = 'return_request'
     and actor_id = '13130000-0000-4000-8000-000000000001'));
select pg_temp.mh13_assert('manager notified once per submission',
  (select count(*) = 2 from public.notifications
   where subject_type = 'return_request'
     and recipient_id = '13130000-0000-4000-8000-000000000003'));
select pg_temp.mh13_assert('no non-manager notified',
  (select count(*) = 0 from public.notifications
   where subject_type = 'return_request'
     and recipient_id <> '13130000-0000-4000-8000-000000000003'));

-- 7. B cannot read A's refund bank details through RLS.
select pg_temp.mh13_claims('13130000-0000-4000-8000-000000000002');
set local role authenticated;
select pg_temp.mh13_assert('B sees no A return',
  (select count(*) = 0 from public.return_requests
   where customer_id = '13130000-0000-4000-8000-000000000001'));
reset role;

select 'return_request_submission.sql: PASS' as result;
rollback;
