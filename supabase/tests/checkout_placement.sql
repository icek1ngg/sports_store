-- MH16 checkout placement acceptance fixture.
--
-- This suite is run against an isolated native PostgreSQL database.  Every
-- business row is inside one transaction and the final ROLLBACK is required.
-- The bootstrap Auth/Storage objects are test-only stubs; this file must not be
-- applied to a Supabase project as a seed or a deployment script.

begin;

set constraints all deferred;

create or replace function pg_temp.assert_rows(
  p_label text,
  p_query text,
  p_expected bigint
) returns void
language plpgsql
as $$
declare
  l_actual bigint;
begin
  execute format('select count(*) from (%s) as checkout_test_rows', p_query)
    into l_actual;
  if l_actual is distinct from p_expected then
    raise exception 'checkout test failed: % (expected %, got %)',
      p_label, p_expected, l_actual;
  end if;
end;
$$;

create or replace function pg_temp.assert_raises(
  p_label text,
  p_sql text,
  p_allowed_states text[]
) returns void
language plpgsql
as $$
declare
  l_succeeded boolean := false;
  l_state text;
  l_message text;
begin
  begin
    execute p_sql;
    l_succeeded := true;
  exception
    when others then
      get stacked diagnostics
        l_state = returned_sqlstate,
        l_message = message_text;
  end;
  if l_succeeded then
    raise exception 'checkout test failed: % (statement unexpectedly succeeded)',
      p_label;
  end if;
  if not l_state = any (p_allowed_states) then
    raise exception 'checkout test failed: % (unexpected SQLSTATE %): %',
      p_label, l_state, l_message;
  end if;
end;
$$;

create or replace function pg_temp.assert_code(
  p_label text,
  p_result jsonb,
  p_expected text
) returns void
language plpgsql
as $$
declare
  l_actual text := p_result #>> '{error,code}';
begin
  if coalesce((p_result ->> 'ok')::boolean, true)
     or l_actual is distinct from p_expected then
    raise exception 'checkout test failed: % (expected error %, got %)',
      p_label, p_expected, p_result;
  end if;
end;
$$;

create or replace function pg_temp.set_test_claims(
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

create temporary table checkout_test_results (
  name text primary key,
  result jsonb not null
) on commit drop;
grant all on checkout_test_results to authenticated;

-- Deterministic fixture identities.  The Auth trigger provisions all accounts
-- as customers; manager authority is then provisioned by this trusted fixture.
insert into auth.users (id, email)
values
  ('10000000-0000-0000-0000-000000000001', 'checkout-customer@example.invalid'),
  ('10000000-0000-0000-0000-000000000002', 'checkout-manager@example.invalid'),
  ('10000000-0000-0000-0000-000000000003', 'checkout-other@example.invalid');
update public.profiles
set role = 'manager'
where id = '10000000-0000-0000-0000-000000000002'::uuid;

insert into public.categories (id, code, name, is_active)
values (
  '20000000-0000-0000-0000-000000000001'::uuid,
  'checkout-fixture', 'Checkout fixture', true
);
insert into public.products (id, category_id, name, description, is_active)
values (
  '30000000-0000-0000-0000-000000000001'::uuid,
  '20000000-0000-0000-0000-000000000001'::uuid,
  'Checkout fixture product', 'Isolated checkout test product', true
);
insert into public.product_variants
  (id, product_id, sku, label, attributes, price_vnd, is_active,
   on_hand, reserved, damaged)
values
  ('40000000-0000-0000-0000-000000000001'::uuid,
   '30000000-0000-0000-0000-000000000001'::uuid,
   'CHECKOUT-001', 'Red / M', '{"color":"red","size":"M"}'::jsonb,
   520000, true, 2, 0, 0),
  ('40000000-0000-0000-0000-000000000002'::uuid,
   '30000000-0000-0000-0000-000000000001'::uuid,
   'CHECKOUT-002', 'Blue / L', '{"color":"blue","size":"L"}'::jsonb,
   730000, true, 3, 0, 0),
  ('40000000-0000-0000-0000-000000000003'::uuid,
   '30000000-0000-0000-0000-000000000001'::uuid,
   'CHECKOUT-003', 'Green / S', '{"color":"green","size":"S"}'::jsonb,
   990000, true, 0, 0, 0);

-- A small synthetic Polygon is intentionally used for pure-PG geometry tests.
-- The production Hanoi polygon is supplied by the root configuration
-- migration, not embedded in this checkout migration.
insert into public.store_settings (
  id, name, address, latitude, longitude, approved_service_area_geojson
)
values (
  true,
  'Checkout test store',
  'Synthetic fixture',
  20.5,
  105.5,
  '{
    "type":"Polygon",
    "coordinates":[
      [[105,20],[106,20],[106,21],[105,21],[105,20]],
      [[105.4,20.4],[105.6,20.4],[105.6,20.6],[105.4,20.6],[105.4,20.4]]
    ]
  }'::jsonb
)
on conflict (id) do update
set name = excluded.name,
    address = excluded.address,
    latitude = excluded.latitude,
    longitude = excluded.longitude,
    approved_service_area_geojson = excluded.approved_service_area_geojson;

-- Execute grants are narrow and the function itself enforces the current
-- server-managed customer role.
select pg_temp.assert_rows(
  'authenticated may execute placement',
  $$select 1 where has_function_privilege(
    'authenticated',
    'public.place_order(uuid,jsonb,text,text,text,numeric,numeric)',
    'EXECUTE'
  )$$,
  1
);
select pg_temp.assert_rows(
  'anon cannot execute placement',
  $$select 1 where not has_function_privilege(
    'anon',
    'public.place_order(uuid,jsonb,text,text,text,numeric,numeric)',
    'EXECUTE'
  )$$,
  1
);
select pg_temp.assert_rows(
  'private placement table has no client access',
  $$select 1 where not has_table_privilege(
    'authenticated', 'private.checkout_placements', 'SELECT'
  )$$,
  1
);

set local role authenticated;
select pg_temp.set_test_claims(
  '10000000-0000-0000-0000-000000000001'::uuid
);

-- Initial placement: item order is intentionally not UUID order and all
-- recipient strings contain surrounding whitespace.
insert into checkout_test_results (name, result)
values (
  'first',
  public.place_order(
    '50000000-0000-0000-0000-000000000001'::uuid,
    '[
      {"variant_id":"40000000-0000-0000-0000-000000000002","quantity":1},
      {"variant_id":"40000000-0000-0000-0000-000000000001","quantity":1}
    ]'::jsonb,
    '  Fixture Customer  ',
    '0900000001',
    '  Synthetic Hanoi address  ',
    20.2,
    105.2
  )
);

select pg_temp.assert_rows(
  'first placement succeeds',
  $$select 1 from checkout_test_results
    where name = 'first' and (result ->> 'ok')::boolean is true
      and (result #>> '{data,order,status}') = 'pending_confirmation'
      and (result #>> '{data,replayed}')::boolean is false$$,
  1
);
select pg_temp.assert_rows(
  'order DTO has exactly 21 keys',
  $$select 1 from checkout_test_results
    where name = 'first'
      and (select count(*) from jsonb_object_keys(result -> 'data' -> 'order')) = 21$$,
  1
);
select pg_temp.assert_rows(
  'order item DTO has exactly 11 keys',
  $$select 1 from checkout_test_results
    where name = 'first'
      and jsonb_array_length(result -> 'data' -> 'items') = 2
      and (select count(*) from jsonb_object_keys(
        (result -> 'data' -> 'items') -> 0
      )) = 11$$,
  1
);
-- Inventory/event/notification rows are server-private projections.  Switch
-- back to the fixture owner for invariant assertions; customer RLS denial is
-- tested explicitly at the end of this suite.
reset role;
select pg_temp.assert_rows(
  'first placement has one reservation movement per variant',
  format($sql$
    select variant_id from public.inventory_movements
    where order_id = %L::uuid and kind = 'reserve'
  $sql$, (select result #>> '{data,order,id}'
    from checkout_test_results where name = 'first')),
  2
);

select set_config(
  'checkout_test.order_id',
  (select result #>> '{data,order,id}' from checkout_test_results where name = 'first'),
  true
);
select set_config(
  'checkout_test.event_id',
  (select result #>> '{data,event_id}' from checkout_test_results where name = 'first'),
  true
);

select pg_temp.assert_rows(
  'two reservation movements',
  format($sql$
    select variant_id from public.inventory_movements
    where order_id = %L::uuid and kind = 'reserve'
  $sql$, current_setting('checkout_test.order_id')),
  2
);
select pg_temp.assert_rows(
  'reserved quantities are updated atomically',
  $$select id from public.product_variants
    where id in (
      '40000000-0000-0000-0000-000000000001'::uuid,
      '40000000-0000-0000-0000-000000000002'::uuid
    ) and reserved = 1$$,
  2
);
select pg_temp.assert_rows(
  'canonical order event keeps incident request null',
  format($sql$
    select id from public.business_events
    where id = %L::uuid and reason = 'order_placed'
      and subject_type = 'order' and request_id is null
  $sql$, current_setting('checkout_test.event_id')),
  1
);
select pg_temp.assert_rows(
  'manager receives one frozen notification',
  format($sql$
    select id from public.notifications
    where event_id = %L::uuid and recipient_id =
      '10000000-0000-0000-0000-000000000002'::uuid
  $sql$, current_setting('checkout_test.event_id')),
  1
);

set local role authenticated;
select pg_temp.set_test_claims(
  '10000000-0000-0000-0000-000000000001'::uuid
);

-- A retry with sorted-equivalent items, trimmed recipient fields and numeric
-- coordinate formatting replays the original snapshot without new effects.
insert into checkout_test_results (name, result)
values (
  'replay',
  public.place_order(
    '50000000-0000-0000-0000-000000000001'::uuid,
    '[
      {"variant_id":"40000000-0000-0000-0000-000000000001","quantity":1.0},
      {"variant_id":"40000000-0000-0000-0000-000000000002","quantity":1}
    ]'::jsonb,
    'Fixture Customer',
    ' 0900000001 ',
    'Synthetic Hanoi address',
    20.2000000,
    105.2000000
  )
);
select pg_temp.assert_rows(
  'same request replays same order and event',
  format($sql$
    select 1 from checkout_test_results
    where name = 'replay'
      and (result ->> 'ok')::boolean is true
      and (result #>> '{data,replayed}')::boolean is true
      and result #>> '{data,order,id}' = %L
      and result #>> '{data,event_id}' = %L
  $sql$,
  current_setting('checkout_test.order_id'),
  current_setting('checkout_test.event_id')),
  1
);
reset role;
select pg_temp.assert_rows(
  'replay does not duplicate movements or notifications',
  format($sql$
    select event_id from public.inventory_movements where event_id = %L::uuid
    union all
    select event_id from public.notifications where event_id = %L::uuid
  $sql$,
  current_setting('checkout_test.event_id'),
  current_setting('checkout_test.event_id')),
  3
);

-- Catalog changes do not rewrite a committed order snapshot used by replay.
reset role;
update public.products
set name = 'Changed catalog name'
where id = '30000000-0000-0000-0000-000000000001'::uuid;
update public.product_variants
set price_vnd = 999999
where id = '40000000-0000-0000-0000-000000000001'::uuid;
set local role authenticated;
select pg_temp.set_test_claims(
  '10000000-0000-0000-0000-000000000001'::uuid
);
insert into checkout_test_results (name, result)
values (
  'replay_after_catalog_change',
  public.place_order(
    '50000000-0000-0000-0000-000000000001'::uuid,
    '[{"variant_id":"40000000-0000-0000-0000-000000000001","quantity":1},
      {"variant_id":"40000000-0000-0000-0000-000000000002","quantity":1}]'::jsonb,
    'Fixture Customer', '0900000001', 'Synthetic Hanoi address', 20.2, 105.2
  )
);
select pg_temp.assert_rows(
  'replay returns immutable catalog snapshot',
  format($sql$
    select 1 from checkout_test_results
    where name = 'replay_after_catalog_change'
      and (result #>> '{data,items,0,product_name}') = 'Checkout fixture product'
      and (result #>> '{data,items,0,unit_price_vnd}') = '520000'
      and (result #>> '{data,order,subtotal_vnd}') = '1250000'
  $sql$),
  1
);

-- Same key with changed intent is a conflict before catalog/stock mutation.
insert into checkout_test_results (name, result)
values (
  'mismatch',
  public.place_order(
    '50000000-0000-0000-0000-000000000001'::uuid,
    '[{"variant_id":"40000000-0000-0000-0000-000000000001","quantity":2},
      {"variant_id":"40000000-0000-0000-0000-000000000002","quantity":1}]'::jsonb,
    'Fixture Customer', '0900000001', 'Synthetic Hanoi address', 20.2, 105.2
  )
);
select pg_temp.assert_code(
  'same key changed payload is rejected',
  (select result from checkout_test_results where name = 'mismatch'),
  'idempotency_conflict'
);
select pg_temp.assert_rows(
  'mismatch creates no extra order',
  format($sql$select id from public.orders where customer_id = %L::uuid$sql$,
    '10000000-0000-0000-0000-000000000001'),
  1
);

-- Lookup is customer scoped and does not expose another customer's placement.
select pg_temp.assert_rows(
  'current customer lookup is committed',
  format($sql$
    select 1 from jsonb_build_object(
      'result', public.get_placement_result(%L::uuid)
    ) as lookup
    where (lookup -> 'result' -> 'data' ->> 'state') = 'committed'
  $sql$, '50000000-0000-0000-0000-000000000001'),
  1
);
select pg_temp.set_test_claims(
  '10000000-0000-0000-0000-000000000003'::uuid
);
select pg_temp.assert_rows(
  'other customer lookup is not found',
  $$select 1 where (public.get_placement_result(
    '50000000-0000-0000-0000-000000000001'::uuid
  ) #>> '{data,state}') = 'not_found'$$,
  1
);

-- Return to the original customer for geometry and all-or-nothing checks.
select pg_temp.set_test_claims(
  '10000000-0000-0000-0000-000000000001'::uuid
);

-- Exterior boundary is accepted by the configured polygon.
insert into checkout_test_results (name, result)
values (
  'boundary',
  public.place_order(
    '50000000-0000-0000-0000-000000000002'::uuid,
    '[{"variant_id":"40000000-0000-0000-0000-000000000002","quantity":1}]'::jsonb,
    'Fixture Customer', '0900000001', 'Synthetic Hanoi boundary', 20.0, 105.0
  )
);
select pg_temp.assert_rows(
  'exterior boundary is serviceable',
  $$select 1 from checkout_test_results
    where name = 'boundary' and (result ->> 'ok')::boolean is true$$,
  1
);

-- A hole and an outside point fail closed before creating any order.
insert into checkout_test_results (name, result)
values
  ('hole', public.place_order(
    '50000000-0000-0000-0000-000000000003'::uuid,
    '[{"variant_id":"40000000-0000-0000-0000-000000000002","quantity":1}]'::jsonb,
    'Fixture Customer', '0900000001', 'Synthetic Hanoi hole', 20.5, 105.5
  )),
  ('outside', public.place_order(
    '50000000-0000-0000-0000-000000000004'::uuid,
    '[{"variant_id":"40000000-0000-0000-0000-000000000002","quantity":1}]'::jsonb,
    'Fixture Customer', '0900000001', 'Outside service area', 22.0, 105.5
  ));
select pg_temp.assert_code(
  'hole is outside service area',
  (select result from checkout_test_results where name = 'hole'),
  'outside_service_area'
);
select pg_temp.assert_code(
  'outside point is rejected',
  (select result from checkout_test_results where name = 'outside'),
  'outside_service_area'
);
select pg_temp.assert_rows(
  'geometry failures create no rows',
  $$select id from public.orders
    where request_id in (
      '50000000-0000-0000-0000-000000000003'::uuid,
      '50000000-0000-0000-0000-000000000004'::uuid
    )$$,
  0
);

-- A malformed area configuration fails closed as well.
reset role;
update public.store_settings
set approved_service_area_geojson = '{"type":"Polygon","coordinates":[[[105,20],[106,20],[106,21]]]}';
set local role authenticated;
select pg_temp.set_test_claims(
  '10000000-0000-0000-0000-000000000001'::uuid
);
select pg_temp.assert_code(
  'malformed polygon fails closed',
  public.place_order(
    '50000000-0000-0000-0000-000000000005'::uuid,
    '[{"variant_id":"40000000-0000-0000-0000-000000000002","quantity":1}]'::jsonb,
    'Fixture Customer', '0900000001', 'Malformed configuration', 20.2, 105.2
  ),
  'outside_service_area'
);

-- MultiPolygon accepts a point in any valid polygon, but must still validate
-- every polygon in the collection (a malformed later polygon fails closed).
reset role;
update public.store_settings
set approved_service_area_geojson = '{
  "type":"MultiPolygon",
  "coordinates":[
    [[[105,20],[106,20],[106,21],[105,21],[105,20]]],
    [[[106.5,20],[107,20],[107,20.5],[106.5,20.5],[106.5,20]]]
  ]
}'::jsonb;
set local role authenticated;
select pg_temp.set_test_claims(
  '10000000-0000-0000-0000-000000000001'::uuid
);
select pg_temp.assert_rows(
  'valid MultiPolygon accepts a point',
  $$select 1 where (public.place_order(
    '50000000-0000-0000-0000-000000000007'::uuid,
    '[{"variant_id":"40000000-0000-0000-0000-000000000002","quantity":1}]'::jsonb,
    'Fixture Customer', '0900000001', 'Valid MultiPolygon', 20.2, 105.2
  ) ->> 'ok')::boolean is true$$,
  1
);
reset role;
update public.store_settings
set approved_service_area_geojson = '{
  "type":"MultiPolygon",
  "coordinates":[
    [[[105,20],[106,20],[106,21],[105,21],[105,20]]],
    [[[106.5,20],[107,20],[107,20.5],[106.5,20.5]]]
  ]
}'::jsonb;
set local role authenticated;
select pg_temp.set_test_claims(
  '10000000-0000-0000-0000-000000000001'::uuid
);
select pg_temp.assert_code(
  'malformed later MultiPolygon fails closed',
  public.place_order(
    '50000000-0000-0000-0000-000000000008'::uuid,
    '[{"variant_id":"40000000-0000-0000-0000-000000000002","quantity":1}]'::jsonb,
    'Fixture Customer', '0900000001', 'Malformed MultiPolygon', 20.2, 105.2
  ),
  'outside_service_area'
);

-- A missing approved area is fail-closed, just like malformed GeoJSON.
reset role;
update public.store_settings
set approved_service_area_geojson = null;
set local role authenticated;
select pg_temp.set_test_claims(
  '10000000-0000-0000-0000-000000000001'::uuid
);
select pg_temp.assert_code(
  'null service area fails closed',
  public.place_order(
    '50000000-0000-0000-0000-000000000009'::uuid,
    '[{"variant_id":"40000000-0000-0000-0000-000000000002","quantity":1}]'::jsonb,
    'Fixture Customer', '0900000001', 'Null service area', 20.2, 105.2
  ),
  'outside_service_area'
);

-- Restore the synthetic area and verify missing stock rolls back all lines.
reset role;
update public.store_settings
set approved_service_area_geojson = '{
  "type":"Polygon",
  "coordinates":[
    [[105,20],[106,20],[106,21],[105,21],[105,20]],
    [[105.4,20.4],[105.6,20.4],[105.6,20.6],[105.4,20.6],[105.4,20.4]]
  ]
}'::jsonb;
set local role authenticated;
select pg_temp.set_test_claims(
  '10000000-0000-0000-0000-000000000001'::uuid
);
select pg_temp.assert_code(
  'multi-item insufficient stock is atomic',
  public.place_order(
    '50000000-0000-0000-0000-000000000006'::uuid,
    '[{"variant_id":"40000000-0000-0000-0000-000000000002","quantity":1},
      {"variant_id":"40000000-0000-0000-0000-000000000003","quantity":1}]'::jsonb,
    'Fixture Customer', '0900000001', 'Synthetic Hanoi address', 20.2, 105.2
  ),
  'insufficient_stock'
);
select pg_temp.assert_rows(
  'failed multi-item placement leaves no order',
  $$select id from public.orders
    where request_id = '50000000-0000-0000-0000-000000000006'::uuid$$,
  0
);
reset role;
select pg_temp.assert_rows(
  'failed multi-item placement leaves no reservation ledger',
  $$select id from public.inventory_movements
    where order_id in (select id from public.orders
      where request_id = '50000000-0000-0000-0000-000000000006'::uuid)$$,
  0
);
set local role authenticated;
select pg_temp.set_test_claims(
  '10000000-0000-0000-0000-000000000001'::uuid
);

-- Totals above JavaScript's exact integer range are rejected before any order
-- or reservation mutation.
reset role;
insert into public.product_variants
  (id, product_id, sku, label, attributes, price_vnd, is_active,
   on_hand, reserved, damaged)
values (
  '40000000-0000-0000-0000-000000000004'::uuid,
  '30000000-0000-0000-0000-000000000001'::uuid,
  'CHECKOUT-004', 'High value', '{}'::jsonb,
  9007199254740991, true, 1, 0, 0
);
set local role authenticated;
select pg_temp.set_test_claims(
  '10000000-0000-0000-0000-000000000001'::uuid
);
select pg_temp.assert_code(
  'unsafe JavaScript total is rejected',
  public.place_order(
    '50000000-0000-0000-0000-000000000010'::uuid,
    '[{"variant_id":"40000000-0000-0000-0000-000000000004","quantity":1}]'::jsonb,
    'Fixture Customer', '0900000001', 'Unsafe total', 20.2, 105.2
  ),
  'invalid_argument'
);
select pg_temp.assert_code(
  'malformed variant UUID is invalid argument',
  public.place_order(
    '50000000-0000-0000-0000-000000000011'::uuid,
    '[{"variant_id":"not-a-uuid","quantity":1}]'::jsonb,
    'Fixture Customer', '0900000001', 'Malformed item', 20.2, 105.2
  ),
  'invalid_argument'
);

-- Customer RLS still denies direct writes to order/inventory/private metadata;
-- the only write path is the trusted RPC above.
select pg_temp.assert_raises(
  'customer cannot update order directly',
  format(
    'update public.orders set status = status where id = %L::uuid',
    current_setting('checkout_test.order_id')
  ),
  array['42501']
);
select pg_temp.assert_raises(
  'customer cannot update inventory directly',
  $$update public.product_variants set reserved = reserved
    where id = '40000000-0000-0000-0000-000000000001'::uuid$$,
  array['42501']
);
select pg_temp.assert_raises(
  'customer cannot read private placement metadata',
  $$select customer_id from private.checkout_placements$$,
  array['42501']
);

reset role;
-- The shared inventory primitive must also reject partial order effects and
-- duplicates with new event IDs, not just duplicate HTTP requests.
do $$
declare
  o uuid := current_setting('checkout_test.order_id')::uuid;
  e uuid := gen_random_uuid();
  e2 uuid := gen_random_uuid();
  all_items jsonb;
  partial_items jsonb;
  original_reserved bigint;
  replay jsonb;
begin
  select jsonb_agg(jsonb_build_object('order_item_id', id,
      'variant_id', variant_id, 'quantity', quantity) order by variant_id)
    into all_items from public.order_items where order_id = o;
  partial_items := jsonb_build_array(all_items->0);
  select sum(reserved) into original_reserved from public.product_variants;
  insert into public.business_events(id, actor_id, subject_type, subject_id)
    values (e, '10000000-0000-0000-0000-000000000002', 'order', o),
           (e2, '10000000-0000-0000-0000-000000000002', 'order', o);
  perform pg_temp.assert_raises('partial release rejected', format(
    'select private.apply_order_inventory_event(%L,%L,%L,%L::jsonb,%L,null)',
    o, e, 'release', partial_items, '10000000-0000-0000-0000-000000000002'), array['P0001']);
  perform pg_temp.assert_raises('partial dispatch rejected', format(
    'select private.apply_order_inventory_event(%L,%L,%L,%L::jsonb,%L,null)',
    o, e, 'dispatch', partial_items, '10000000-0000-0000-0000-000000000002'), array['P0001']);
  if (select sum(reserved) from public.product_variants) <> original_reserved then
    raise exception 'partial inventory request changed stock';
  end if;
  perform private.apply_order_inventory_event(o,e,'release',all_items,
    '10000000-0000-0000-0000-000000000002',null);
  replay := private.apply_order_inventory_event(o,e,'release',all_items,
    '10000000-0000-0000-0000-000000000002',null);
  if (select sum(reserved) from public.product_variants) <> original_reserved - 2 then
    raise exception 'release replay changed stock twice';
  end if;
  perform pg_temp.assert_raises('new event cannot release same order twice', format(
    'select private.apply_order_inventory_event(%L,%L,%L,%L::jsonb,%L,null)',
    o,e2,'release',all_items,'10000000-0000-0000-0000-000000000002'),array['P0001']);
  perform pg_temp.assert_raises('released order cannot dispatch pooled stock', format(
    'select private.apply_order_inventory_event(%L,%L,%L,%L::jsonb,%L,null)',
    o,e2,'dispatch',all_items,'10000000-0000-0000-0000-000000000002'),array['P0001']);
  update public.inventory_movements set damaged_delta=1 where event_id=e;
  perform pg_temp.assert_raises('corrupt inventory receipt is not replayed', format(
    'select private.apply_order_inventory_event(%L,%L,%L,%L::jsonb,%L,null)',
    o,e,'release',all_items,'10000000-0000-0000-0000-000000000002'),array['P0001']);
end;
$$;
-- Simulate two distinct normalized payloads with the same stored hash. The
-- complete intent must still prevent replaying a different purchase request.
do $$
declare old_fingerprint text; intent jsonb; changed jsonb; result jsonb;
begin
  perform pg_temp.set_test_claims('10000000-0000-0000-0000-000000000001');
  select fingerprint, normalized_intent into old_fingerprint, intent
    from private.checkout_placements
    where customer_id='10000000-0000-0000-0000-000000000001'
      and request_id='50000000-0000-0000-0000-000000000001';
  changed := jsonb_set(intent,'{recipient_name}','"Collision simulation"'::jsonb);
  update private.checkout_placements set fingerprint=md5(changed::text)
    where customer_id='10000000-0000-0000-0000-000000000001'
      and request_id='50000000-0000-0000-0000-000000000001';
  result := public.place_order('50000000-0000-0000-0000-000000000001',
    changed->'items',changed->>'recipient_name',changed->>'recipient_phone',
    changed->>'address_detail',(changed->>'latitude')::numeric,(changed->>'longitude')::numeric);
  perform pg_temp.assert_code('exact intent comparison survives equal hash',result,'idempotency_conflict');
  update private.checkout_placements set fingerprint=old_fingerprint
    where customer_id='10000000-0000-0000-0000-000000000001'
      and request_id='50000000-0000-0000-0000-000000000001';
end;
$$;
select 'checkout_placement.sql: PASS' as result,
       'fixtures rolled back by final statement' as fixture_scope;
rollback;
