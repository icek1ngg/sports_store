-- Return management phase 2: info request <-> MH14 answer, receipt (existing
-- RPC), inspection accept + restock once, refund record with evidence, reject
-- after inspection with evidence + free redelivery assignment (existing RPC).
-- TEST FIXTURE ONLY. One transaction on the isolated fixture, rolled back.

begin;

create or replace function pg_temp.t2_claims(p_user_id uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
  perform set_config('request.jwt.claims', case when p_user_id is null then ''
    else jsonb_build_object('sub', p_user_id::text, 'role', 'authenticated')::text
    end, true);
end;
$$;
create or replace function pg_temp.t2_assert(p_label text, p_condition boolean)
returns void language plpgsql as $$
begin
  if coalesce(p_condition, false) is not true then
    raise exception 'MH15-2 test failed: %', p_label;
  end if;
end;
$$;
create or replace function pg_temp.t2_error(
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
    raise exception 'MH15-2 test failed: % (expected %/%, got %/%)', p_label,
      p_state, coalesce(p_message, '<any>'), coalesce(l_state, 'success'),
      coalesce(l_message, '<none>');
  end if;
end;
$$;
grant execute on function pg_temp.t2_claims(uuid), pg_temp.t2_assert(text, boolean),
  pg_temp.t2_error(text, text, text, text) to authenticated, anon;

-- Actors: A, B customers; M manager; S shipper.
insert into auth.users (id, email) values
  ('25250000-0000-4000-8000-000000000001', 'mh15b-a@example.invalid'),
  ('25250000-0000-4000-8000-000000000002', 'mh15b-b@example.invalid'),
  ('25250000-0000-4000-8000-000000000003', 'mh15b-m@example.invalid'),
  ('25250000-0000-4000-8000-000000000004', 'mh15b-s@example.invalid');
update public.profiles set
  role = case id
    when '25250000-0000-4000-8000-000000000003' then 'manager'::public.user_role
    when '25250000-0000-4000-8000-000000000004' then 'shipper'::public.user_role
    else 'customer'::public.user_role end,
  full_name = 'MH15-2 ' || right(id::text, 1),
  phone = '09000025' || right(id::text, 2)
where id::text like '25250000-0000-4000-8000-00000000000%';

insert into public.categories (id, code, name)
values ('25250000-0000-4000-8000-000000000100', 'MH152', 'MH15-2 fixture');
insert into public.products (id, category_id, name)
values ('25250000-0000-4000-8000-000000000101',
        '25250000-0000-4000-8000-000000000100', 'MH15-2 jersey');
insert into public.product_variants (id, product_id, sku, label, price_vnd, on_hand, reserved, damaged)
values ('25250000-0000-4000-8000-000000000111',
  '25250000-0000-4000-8000-000000000101', 'MH152-01', 'Đen / M', 275000, 10, 0, 0);

insert into public.orders (id, customer_id, request_id, status, recipient_name, recipient_phone,
  address_detail, latitude, longitude, subtotal_vnd, delivery_fee_vnd, delivered_at)
values
  ('25251000-0000-4000-8000-000000000001', '25250000-0000-4000-8000-000000000001',
   gen_random_uuid(), 'delivered', 'A', '0900002501', '25 Nguyễn Chí Thanh, Hà Nội',
   21.03, 105.8, 550000, 30000, now() - interval '2 days'),
  ('25251000-0000-4000-8000-000000000002', '25250000-0000-4000-8000-000000000002',
   gen_random_uuid(), 'delivered', 'B', '0900002502', '1 Tràng Tiền, Hà Nội',
   21.02, 105.85, 275000, 30000, now() - interval '1 day');
insert into public.order_items (id, order_id, product_id, variant_id, product_name,
  variant_label, unit_price_vnd, quantity)
values
  ('25251100-0000-4000-8000-000000000001', '25251000-0000-4000-8000-000000000001',
   '25250000-0000-4000-8000-000000000101', '25250000-0000-4000-8000-000000000111',
   'Áo thể thao', 'Đen / M', 275000, 2),
  ('25251100-0000-4000-8000-000000000002', '25251000-0000-4000-8000-000000000002',
   '25250000-0000-4000-8000-000000000101', '25250000-0000-4000-8000-000000000111',
   'Áo thể thao', 'Đen / M', 275000, 1);
insert into storage.objects (bucket_id, name, owner_id, metadata) values
  ('return-videos', '25250000-0000-4000-8000-000000000001/25251000-0000-4000-8000-000000000001/v.mp4',
   '25250000-0000-4000-8000-000000000001', '{"mimetype":"video/mp4","size":4096}'),
  ('return-videos', '25250000-0000-4000-8000-000000000001/25251000-0000-4000-8000-000000000001/extra.mp4',
   '25250000-0000-4000-8000-000000000001', '{"mimetype":"video/mp4","size":4096}'),
  ('return-videos', '25250000-0000-4000-8000-000000000002/25251000-0000-4000-8000-000000000002/v.mp4',
   '25250000-0000-4000-8000-000000000002', '{"mimetype":"video/mp4","size":4096}'),
  ('inspection-evidence', 'returns/b/inspection-1.jpg',
   '25250000-0000-4000-8000-000000000003', '{"mimetype":"image/jpeg","size":2048}'),
  ('refund-evidence', 'returns/a/transfer.jpg',
   '25250000-0000-4000-8000-000000000003', '{"mimetype":"image/jpeg","size":2048}');

-- Customers submit (real MH13 RPC).
select pg_temp.t2_claims('25250000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('t2.ra', (public.submit_return_request('25251000-0000-4000-8000-000000000001',
  '25253000-0000-4000-8000-000000000001', 'defective', 'Áo bị bung chỉ ở vai khi mở kiện.',
  '25250000-0000-4000-8000-000000000001/25251000-0000-4000-8000-000000000001/v.mp4',
  'Vietcombank', '0011004392819', 'NGUYEN VAN A') ->> 'return_request_id'), true);
reset role;
select pg_temp.t2_claims('25250000-0000-4000-8000-000000000002');
set local role authenticated;
select set_config('t2.rb', (public.submit_return_request('25251000-0000-4000-8000-000000000002',
  '25253000-0000-4000-8000-000000000002', 'wrong_item', 'Nhận sai màu áo so với đơn hàng.',
  '25250000-0000-4000-8000-000000000002/25251000-0000-4000-8000-000000000002/v.mp4',
  'Techcombank', '1903555500001', 'TRAN THI B') ->> 'return_request_id'), true);
select pg_temp.t2_assert('no info request yet',
  public.get_my_return_info_request(current_setting('t2.rb')::uuid) -> 'info_request' = 'null'::jsonb);
reset role;

-- 1. Information request <-> customer answer (A).
select pg_temp.t2_claims('25250000-0000-4000-8000-000000000003');
set local role authenticated;
select pg_temp.t2_error('message required',
  format('select public.request_return_info(%L, gen_random_uuid(), %L)', current_setting('t2.ra'), 'ab'),
  '22023', 'INVALID_ARGUMENT');
select public.request_return_info(current_setting('t2.ra')::uuid,
  '25254000-0000-4000-8000-000000000001', 'Vui lòng quay rõ đường may bị bung ở vai áo.');
select pg_temp.t2_assert('request replay is idempotent',
  (public.request_return_info(current_setting('t2.ra')::uuid,
    '25254000-0000-4000-8000-000000000001', 'Vui lòng quay rõ đường may bị bung ở vai áo.')
   ->> 'request_id') = '25254000-0000-4000-8000-000000000001');
select pg_temp.t2_error('only one open request',
  format('select public.request_return_info(%L, gen_random_uuid(), %L)', current_setting('t2.ra'),
    'Một yêu cầu khác'), 'PT409', 'STATE_CONFLICT');
select pg_temp.t2_error('manager cannot answer',
  format('select public.respond_return_info(%L, gen_random_uuid(), %L)', current_setting('t2.ra'),
    'Trả lời thay khách hàng'), '42501', 'PERMISSION_DENIED');
reset role;
select pg_temp.t2_claims('25250000-0000-4000-8000-000000000002');
set local role authenticated;
select pg_temp.t2_error('other customer cannot read the request',
  format('select public.get_my_return_info_request(%L)', current_setting('t2.ra')),
  'PT404', 'RETURN_NOT_FOUND');
select pg_temp.t2_error('other customer cannot answer',
  format('select public.respond_return_info(%L, gen_random_uuid(), %L)', current_setting('t2.ra'),
    'Tôi trả lời thay người khác'), 'PT404', 'RETURN_NOT_FOUND');
reset role;
select pg_temp.t2_claims('25250000-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.t2_assert('customer sees open request',
  (select i -> 'info_request' ->> 'message' = 'Vui lòng quay rõ đường may bị bung ở vai áo.'
      and i -> 'info_request' -> 'responded_at' = 'null'::jsonb
   from public.get_my_return_info_request(current_setting('t2.ra')::uuid) i));
select pg_temp.t2_error('video must exist',
  format('select public.respond_return_info(%L, gen_random_uuid(), %L, %L)', current_setting('t2.ra'),
    'Tôi gửi thêm video quay cận cảnh.',
    '25250000-0000-4000-8000-000000000001/25251000-0000-4000-8000-000000000001/missing.mp4'),
  'PT422', 'VIDEO_REQUIRED');
select pg_temp.t2_error('original video cannot be reused',
  format('select public.respond_return_info(%L, gen_random_uuid(), %L, %L)', current_setting('t2.ra'),
    'Tôi gửi lại video cũ để bổ sung.',
    '25250000-0000-4000-8000-000000000001/25251000-0000-4000-8000-000000000001/v.mp4'),
  'PT409', 'VIDEO_ALREADY_USED');
select public.respond_return_info(current_setting('t2.ra')::uuid,
  '25254000-0000-4000-8000-000000000002', 'Tôi gửi thêm video quay cận cảnh đường may.',
  '25250000-0000-4000-8000-000000000001/25251000-0000-4000-8000-000000000001/extra.mp4');
select pg_temp.t2_error('answer only once',
  format('select public.respond_return_info(%L, gen_random_uuid(), %L)', current_setting('t2.ra'),
    'Trả lời lần thứ hai'), 'PT409', 'STATE_CONFLICT');
select pg_temp.t2_assert('customer sees answered request',
  (select i -> 'info_request' ->> 'responded_at' is not null
   from public.get_my_return_info_request(current_setting('t2.ra')::uuid) i));
reset role;
select pg_temp.t2_claims('25250000-0000-4000-8000-000000000003');
set local role authenticated;
select pg_temp.t2_assert('manager detail shows answer and extra video',
  (select jsonb_array_length(d -> 'info_requests') = 1
      and d -> 'info_requests' -> 0 ->> 'response_text' = 'Tôi gửi thêm video quay cận cảnh đường may.'
      and jsonb_array_length(d -> 'video_paths') = 2
      and d ->> 'status' = 'pending_review'
   from public.get_manager_return_request(current_setting('t2.ra')::uuid) d));
reset role;
select pg_temp.t2_assert('one notice each way',
  (select count(*) = 1 from public.notifications
    where recipient_id = '25250000-0000-4000-8000-000000000001'
      and title = 'Cửa hàng cần bạn bổ sung thông tin')
  and (select count(*) = 1 from public.notifications
    where recipient_id = '25250000-0000-4000-8000-000000000003'
      and title = 'Khách đã bổ sung thông tin trả hàng'));

-- 2. Pickup chain for A (2 items) and B (1 item) up to store receipt.
select pg_temp.t2_claims('25250000-0000-4000-8000-000000000003');
set local role authenticated;
select set_config('t2.ta', public.approve_return_collection(current_setting('t2.ra')::uuid,
  gen_random_uuid(), '[{"order_item_id":"25251100-0000-4000-8000-000000000001","quantity":2}]',
  '25250000-0000-4000-8000-000000000004') ->> 'task_id', true);
select set_config('t2.tb', public.approve_return_collection(current_setting('t2.rb')::uuid,
  gen_random_uuid(), '[{"order_item_id":"25251100-0000-4000-8000-000000000002","quantity":1}]',
  '25250000-0000-4000-8000-000000000004') ->> 'task_id', true);
select pg_temp.t2_error('cannot accept before receipt',
  format('select public.accept_inspected_return(%L, gen_random_uuid(), %L)', current_setting('t2.ra'),
    (select jsonb_agg(jsonb_build_object('return_item_id', id, 'sellable_quantity', 2, 'damaged_quantity', 0))
       from public.return_items where return_request_id = current_setting('t2.ra')::uuid)),
  'PT409', 'STATE_CONFLICT');
select pg_temp.t2_assert('handover not reported yet',
  (select (d -> 'pickup_task' ->> 'handover_reported')::boolean = false
   from public.get_manager_return_request(current_setting('t2.ra')::uuid) d));
reset role;
select set_config('t2.pa', (select jsonb_agg(jsonb_build_object('return_item_id', id,
  'quantity', quantity_to_collect) order by id)::text from public.return_items
  where return_request_id = current_setting('t2.ra')::uuid), true);
select set_config('t2.pb', (select jsonb_agg(jsonb_build_object('return_item_id', id,
  'quantity', quantity_to_collect) order by id)::text from public.return_items
  where return_request_id = current_setting('t2.rb')::uuid), true);
select pg_temp.t2_claims('25250000-0000-4000-8000-000000000004');
set local role authenticated;
select public.collect_return_items(current_setting('t2.ta')::uuid, gen_random_uuid(), current_setting('t2.pa')::jsonb);
select public.report_return_pickup_handover(current_setting('t2.ta')::uuid, gen_random_uuid(), current_setting('t2.pa')::jsonb);
select public.collect_return_items(current_setting('t2.tb')::uuid, gen_random_uuid(), current_setting('t2.pb')::jsonb);
select public.report_return_pickup_handover(current_setting('t2.tb')::uuid, gen_random_uuid(), current_setting('t2.pb')::jsonb);
reset role;
select pg_temp.t2_claims('25250000-0000-4000-8000-000000000003');
set local role authenticated;
select pg_temp.t2_assert('handover flag visible to manager',
  (select (d -> 'pickup_task' ->> 'handover_reported')::boolean
      and d ->> 'status' = 'returning_to_store'
   from public.get_manager_return_request(current_setting('t2.ra')::uuid) d));
select public.receive_customer_return(current_setting('t2.ta')::uuid, gen_random_uuid(), current_setting('t2.pa')::jsonb);
select public.receive_customer_return(current_setting('t2.tb')::uuid, gen_random_uuid(), current_setting('t2.pb')::jsonb);
select pg_temp.t2_assert('both under inspection',
  (select count(*) = 2 from public.return_requests
    where id in (current_setting('t2.ra')::uuid, current_setting('t2.rb')::uuid)
      and status = 'under_inspection'));

-- 3. Accept A: 1 sellable + 1 damaged, restocked exactly once.
select set_config('t2.ia', (select id::text from public.return_items
  where return_request_id = current_setting('t2.ra')::uuid), true);
select pg_temp.t2_error('split must equal received quantity',
  format('select public.accept_inspected_return(%L, gen_random_uuid(), %L)', current_setting('t2.ra'),
    jsonb_build_array(jsonb_build_object('return_item_id', current_setting('t2.ia'),
      'sellable_quantity', 1, 'damaged_quantity', 0))),
  'PT409', 'ITEMS_MISMATCH');
select pg_temp.t2_error('unknown evidence rejected',
  format('select public.accept_inspected_return(%L, gen_random_uuid(), %L, %L)', current_setting('t2.ra'),
    jsonb_build_array(jsonb_build_object('return_item_id', current_setting('t2.ia'),
      'sellable_quantity', 1, 'damaged_quantity', 1)), '{returns/none.jpg}'),
  'PT422', 'EVIDENCE_REQUIRED');
select set_config('t2.acc', public.accept_inspected_return(current_setting('t2.ra')::uuid,
  '25254000-0000-4000-8000-000000000003',
  jsonb_build_array(jsonb_build_object('return_item_id', current_setting('t2.ia'),
    'sellable_quantity', 1, 'damaged_quantity', 1)))::text, true);
select pg_temp.t2_assert('accept replay returns same ack',
  public.accept_inspected_return(current_setting('t2.ra')::uuid,
    '25254000-0000-4000-8000-000000000003',
    jsonb_build_array(jsonb_build_object('return_item_id', current_setting('t2.ia'),
      'sellable_quantity', 1, 'damaged_quantity', 1))) = current_setting('t2.acc')::jsonb);
select pg_temp.t2_error('accept twice with a new key',
  format('select public.accept_inspected_return(%L, gen_random_uuid(), %L)', current_setting('t2.ra'),
    jsonb_build_array(jsonb_build_object('return_item_id', current_setting('t2.ia'),
      'sellable_quantity', 2, 'damaged_quantity', 0))),
  'PT409', 'STATE_CONFLICT');
reset role;
select pg_temp.t2_assert('stock: +1 sellable, +1 damaged, one movement',
  (select on_hand = 11 and damaged = 1 and reserved = 0 from public.product_variants
    where id = '25250000-0000-4000-8000-000000000111')
  and (select count(*) = 1 and sum(on_hand_delta) = 1 and sum(damaged_delta) = 1
    from public.inventory_movements where return_request_id = current_setting('t2.ra')::uuid)
  and (select status = 'awaiting_refund' and inspected_at is not null
         and refund_amount_vnd is null
    from public.return_requests where id = current_setting('t2.ra')::uuid));

-- 4. Refund A: full amount, evidence, real transfer time, once.
select pg_temp.t2_claims('25250000-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.t2_error('customer cannot record refund',
  format('select public.record_return_refund(%L, gen_random_uuid(), 580000, clock_timestamp(), %L)',
    current_setting('t2.ra'), 'returns/a/transfer.jpg'), '42501', 'PERMISSION_DENIED');
reset role;
select pg_temp.t2_claims('25250000-0000-4000-8000-000000000003');
set local role authenticated;
select pg_temp.t2_error('partial amount',
  format('select public.record_return_refund(%L, gen_random_uuid(), 550000, clock_timestamp(), %L)',
    current_setting('t2.ra'), 'returns/a/transfer.jpg'), 'PT409', 'AMOUNT_MISMATCH');
select pg_temp.t2_error('missing evidence',
  format('select public.record_return_refund(%L, gen_random_uuid(), 580000, clock_timestamp(), %L)',
    current_setting('t2.ra'), 'returns/a/none.jpg'), 'PT422', 'EVIDENCE_REQUIRED');
select pg_temp.t2_error('future transfer time',
  format('select public.record_return_refund(%L, gen_random_uuid(), 580000, now() + interval ''1 day'', %L)',
    current_setting('t2.ra'), 'returns/a/transfer.jpg'), '22023', 'INVALID_TRANSFER_TIME');
select pg_temp.t2_error('refund before inspection (B)',
  format('select public.record_return_refund(%L, gen_random_uuid(), 305000, clock_timestamp(), %L)',
    current_setting('t2.rb'), 'returns/a/transfer.jpg'), 'PT409', 'STATE_CONFLICT');
select public.record_return_refund(current_setting('t2.ra')::uuid,
  '25254000-0000-4000-8000-000000000004', 580000, clock_timestamp(), 'returns/a/transfer.jpg');
select pg_temp.t2_error('refund twice',
  format('select public.record_return_refund(%L, gen_random_uuid(), 580000, clock_timestamp(), %L)',
    current_setting('t2.ra'), 'returns/a/transfer.jpg'), 'PT409', 'STATE_CONFLICT');
reset role;
select pg_temp.t2_assert('refund closed once and customer notified',
  (select status = 'refunded' and closed_at is not null and refund_amount_vnd = 580000
      and transfer_evidence_path = 'returns/a/transfer.jpg'
      and refund_request_id = '25254000-0000-4000-8000-000000000004'
   from public.return_requests where id = current_setting('t2.ra')::uuid)
  and (select count(*) = 1 from public.notifications
    where recipient_id = '25250000-0000-4000-8000-000000000001'
      and title = 'Đã hoàn tiền yêu cầu trả hàng')
  and (select order_status = 'delivered' from (select status::text as order_status
    from public.orders where id = '25251000-0000-4000-8000-000000000001') o));
select pg_temp.t2_claims('25250000-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.t2_assert('MH14 shows the refund',
  (select t ->> 'status' = 'refunded' and t -> 'refund' <> 'null'::jsonb
   from public.get_my_return_request(current_setting('t2.ra')::uuid) t));
reset role;

-- 5. Reject B after inspection with evidence, then free redelivery.
select pg_temp.t2_claims('25250000-0000-4000-8000-000000000003');
set local role authenticated;
select pg_temp.t2_error('evidence required',
  format('select public.reject_inspected_return(%L, gen_random_uuid(), %L, %L)',
    current_setting('t2.rb'), 'Áo đúng màu như đơn đã đặt', '{}'), '22023', 'INVALID_ARGUMENT');
select pg_temp.t2_error('evidence must be uploaded',
  format('select public.reject_inspected_return(%L, gen_random_uuid(), %L, %L)',
    current_setting('t2.rb'), 'Áo đúng màu như đơn đã đặt', '{returns/b/none.jpg}'),
  'PT422', 'EVIDENCE_REQUIRED');
select set_config('t2.rej', public.reject_inspected_return(current_setting('t2.rb')::uuid,
  '25254000-0000-4000-8000-000000000005', 'Áo đúng màu như đơn đã đặt',
  '{returns/b/inspection-1.jpg}')::text, true);
select pg_temp.t2_assert('reject replay',
  public.reject_inspected_return(current_setting('t2.rb')::uuid,
    '25254000-0000-4000-8000-000000000005', 'Áo đúng màu như đơn đã đặt',
    '{returns/b/inspection-1.jpg}') = current_setting('t2.rej')::jsonb);
select set_config('t2.rd', public.assign_redelivery_task(current_setting('t2.rb')::uuid,
  '25250000-0000-4000-8000-000000000004', gen_random_uuid()) ->> 'task_id', true);
select pg_temp.t2_assert('detail shows evidence and redelivery',
  (select d ->> 'status' = 'awaiting_redelivery'
      and d -> 'inspection_evidence_paths' = '["returns/b/inspection-1.jpg"]'::jsonb
      and d -> 'redelivery_task' ->> 'status' = 'assigned'
   from public.get_manager_return_request(current_setting('t2.rb')::uuid) d));
reset role;
select pg_temp.t2_assert('rejection keeps stock and creates a free task',
  (select on_hand = 11 and damaged = 1 from public.product_variants
    where id = '25250000-0000-4000-8000-000000000111')
  and (select count(*) = 0 from public.inventory_movements
    where return_request_id = current_setting('t2.rb')::uuid)
  and (select amount_to_collect_vnd = 0 from public.delivery_tasks
    where id = current_setting('t2.rd')::uuid));

-- 6. Access: shipper/customer never reach manager resolution commands.
select pg_temp.t2_claims('25250000-0000-4000-8000-000000000004');
set local role authenticated;
select pg_temp.t2_error('shipper cannot request info',
  format('select public.request_return_info(%L, gen_random_uuid(), %L)', current_setting('t2.rb'),
    'Bổ sung giúp tôi'), '42501', 'PERMISSION_DENIED');
reset role;
set local role anon;
select pg_temp.t2_error('anon cannot answer',
  format('select public.respond_return_info(%L, gen_random_uuid(), %L)', current_setting('t2.ra'),
    'Trả lời ẩn danh'), '42501');
reset role;

select 'return_management_resolution.sql: PASS';
rollback;
