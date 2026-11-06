-- Transactional cloud verification, separate from the native Auth/Storage stubs.
-- No login-capable account is provisioned: these temporary Auth rows have no
-- password, identity or session. All fixture data and catalog changes ROLLBACK.
-- Run only against this project's reviewed schema through trusted SQL tooling.
begin;

create temporary table checkout_smoke_receipts (receipt jsonb);
grant all on checkout_smoke_receipts to authenticated;

insert into auth.users (id, email) values
  ('9b4d0000-0000-4000-8000-000000000001', 'checkout-smoke-a@example.invalid'),
  ('9b4d0000-0000-4000-8000-000000000002', 'checkout-smoke-b@example.invalid'),
  ('9b4d0000-0000-4000-8000-000000000003', 'checkout-smoke-manager@example.invalid');
update public.profiles set role = 'manager'
where id = '9b4d0000-0000-4000-8000-000000000003';

insert into public.categories (id, code, name) values
  ('9b4d0000-0000-4000-8000-000000000004', 'checkout-cloud-smoke', '[TEST ROLLBACK] Giày');
insert into public.products (id, category_id, name) values
  ('9b4d0000-0000-4000-8000-000000000005',
   '9b4d0000-0000-4000-8000-000000000004', '[TEST ROLLBACK] Sản phẩm');
insert into public.product_variants
  (id, product_id, sku, label, price_vnd, on_hand, reserved, damaged) values
  ('9b4d0000-0000-4000-8000-000000000006',
   '9b4d0000-0000-4000-8000-000000000005', 'CHECKOUT-CLOUD-SMOKE', 'Cỡ 40', 690000, 3, 0, 0);

select set_config('request.jwt.claim.sub', '9b4d0000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims',
  '{"sub":"9b4d0000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

insert into checkout_smoke_receipts
select public.place_order(
  '9b4d0000-0000-4000-8000-000000000007',
  '[{"variant_id":"9b4d0000-0000-4000-8000-000000000006","quantity":2}]',
  '[TEST] Văn Đức', '0901234567', 'Số 1 Tràng Tiền, Hoàn Kiếm, Hà Nội',
  21.0285, 105.8542
);
do $$
declare r jsonb;
begin
  select receipt into r from checkout_smoke_receipts;
  if r->>'ok' is distinct from 'true'
    or r#>>'{data,order,customer_id}' <> '9b4d0000-0000-4000-8000-000000000001'
    or (r#>>'{data,order,total_cod_vnd}')::bigint <> 1410000
    or r#>>'{data,order,status}' <> 'pending_confirmation' then
    raise exception 'cloud checkout placement failed: %', r;
  end if;
  r := public.place_order(
    '9b4d0000-0000-4000-8000-000000000007',
    '[{"variant_id":"9b4d0000-0000-4000-8000-000000000006","quantity":2}]',
    '[TEST] Văn Đức', '0901234567', 'Số 1 Tràng Tiền, Hoàn Kiếm, Hà Nội', 21.0285, 105.8542);
  if r#>>'{data,replayed}' is distinct from 'true' then
    raise exception 'cloud checkout replay failed';
  end if;
  r := public.place_order(
    '9b4d0000-0000-4000-8000-000000000007',
    '[{"variant_id":"9b4d0000-0000-4000-8000-000000000006","quantity":1}]',
    '[TEST] Văn Đức', '0901234567', 'Số 1 Tràng Tiền, Hoàn Kiếm, Hà Nội', 21.0285, 105.8542);
  if r#>>'{error,code}' is distinct from 'idempotency_conflict' then
    raise exception 'cloud changed-payload rejection failed';
  end if;
  r := public.place_order(
    '9b4d0000-0000-4000-8000-000000000008',
    '[{"variant_id":"9b4d0000-0000-4000-8000-000000000006","quantity":1}]',
    '[TEST] Văn Đức', '0901234567', 'Quận 1, Thành phố Hồ Chí Minh', 10.7769, 106.7009);
  if r#>>'{error,code}' is distinct from 'outside_service_area' then
    raise exception 'cloud outside-Hanoi rejection failed';
  end if;
end;
$$;

-- A different authenticated customer cannot look up the first customer's order.
select set_config('request.jwt.claim.sub', '9b4d0000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims',
  '{"sub":"9b4d0000-0000-4000-8000-000000000002","role":"authenticated"}', true);
do $$
declare r jsonb;
begin
  r := public.get_placement_result('9b4d0000-0000-4000-8000-000000000007');
  if r#>>'{data,state}' is distinct from 'not_found' then
    raise exception 'cloud cross-customer lookup leaked a placement';
  end if;
end;
$$;
reset role;

do $$
declare r jsonb; o uuid; e uuid;
begin
  select receipt into r from checkout_smoke_receipts;
  o := (r#>>'{data,order,id}')::uuid;
  e := (r#>>'{data,event_id}')::uuid;
  if (select reserved from public.product_variants
      where id = '9b4d0000-0000-4000-8000-000000000006') <> 2
    or (select on_hand from public.product_variants
      where id = '9b4d0000-0000-4000-8000-000000000006') <> 3
    or (select count(*) from public.inventory_movements where order_id = o) <> 1
    or (select count(*) from public.notifications where event_id = e and
      recipient_id = '9b4d0000-0000-4000-8000-000000000003') <> 1 then
    raise exception 'cloud reservation/event/notification was duplicated or incomplete';
  end if;
  -- Confirm compatibility with the delivery owner's deployed reservation proof.
  if to_regprocedure('private.validate_outbound_reservation(uuid,jsonb)') is not null then
    perform private.validate_outbound_reservation(o, private.outbound_items_snapshot(o));
  end if;
end;
$$;

select 'checkout_cloud_smoke.sql: PASS (all fixture data rolled back)' as result;
rollback;
