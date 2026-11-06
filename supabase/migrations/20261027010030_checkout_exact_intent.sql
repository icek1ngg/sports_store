-- Compare the complete normalized intent as well as its compact fingerprint.
-- Replay identity must not depend on hash collision resistance.
create or replace function public.place_order(
  p_request_id uuid,
  p_items jsonb,
  p_recipient_name text,
  p_recipient_phone text,
  p_address_detail text,
  p_latitude numeric,
  p_longitude numeric
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  l_user_id uuid;
  l_role public.user_role;
  l_item jsonb;
  l_variant_id uuid;
  l_quantity_numeric numeric;
  l_quantity bigint;
  l_variant_ids uuid[] := array[]::uuid[];
  l_quantities bigint[] := array[]::bigint[];
  l_normalized_items jsonb;
  l_normalized_intent jsonb;
  l_fingerprint text;
  l_name text;
  l_phone text;
  l_address text;
  l_latitude numeric;
  l_longitude numeric;
  l_geojson jsonb;
  l_existing private.checkout_placements%rowtype;
  l_has_existing boolean := false;
  l_manager_ids uuid[];
  l_manager_id uuid;
  l_order_id uuid;
  l_event_id uuid;
  l_order_item_id uuid;
  l_subtotal numeric := 0;
  l_line_total numeric;
  l_product_name text;
  l_variant_label text;
  l_attributes jsonb;
  l_price bigint;
  l_reserve_items jsonb := '[]'::jsonb;
  l_inventory_result jsonb;
begin
  l_user_id := (select auth.uid());
  if l_user_id is null or p_request_id is null then
    raise exception using message = 'forbidden_or_unavailable', errcode = 'P0001';
  end if;

  select p.role
  into l_role
  from public.profiles as p
  where p.id = l_user_id
  for share;
  if not found or l_role <> 'customer'::public.user_role then
    raise exception using message = 'forbidden_or_unavailable', errcode = 'P0001';
  end if;

  -- Request identity is claimed before any order/variant lock.  The lock is
  -- transaction-scoped, so retries and concurrent submits for one customer/key
  -- serialize without holding a lock across a client/network call.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      pg_catalog.concat(l_user_id::text, ':', p_request_id::text),
      0
    )
  );

  l_name := pg_catalog.btrim(coalesce(p_recipient_name, ''));
  l_phone := pg_catalog.btrim(coalesce(p_recipient_phone, ''));
  l_address := pg_catalog.btrim(coalesce(p_address_detail, ''));
  l_latitude := pg_catalog.round(p_latitude, 6);
  l_longitude := pg_catalog.round(p_longitude, 6);

  if pg_catalog.length(l_name) < 2
     or pg_catalog.length(l_name) > 200
     or pg_catalog.length(l_phone) < 7
     or pg_catalog.length(l_phone) > 30
     or l_phone !~ '^[0-9+(). -]+$'
     or pg_catalog.length(pg_catalog.regexp_replace(l_phone, '[^0-9]', '', 'g')) < 7
     or pg_catalog.length(l_address) < 5
     or pg_catalog.length(l_address) > 500
     or p_latitude is null
     or p_longitude is null
     or p_latitude::text = 'NaN'
     or p_longitude::text = 'NaN'
     or l_latitude < -90
     or l_latitude > 90
     or l_longitude < -180
     or l_longitude > 180 then
    raise exception using message = 'invalid_argument', errcode = 'P0001';
  end if;

  if p_items is null
     or pg_catalog.jsonb_typeof(p_items) <> 'array'
     or pg_catalog.jsonb_array_length(p_items) = 0 then
    raise exception using message = 'invalid_argument', errcode = 'P0001';
  end if;

  for l_item in
    select e.value
    from pg_catalog.jsonb_array_elements(p_items) as e(value)
  loop
    if pg_catalog.jsonb_typeof(l_item) <> 'object'
       or not (l_item ? 'variant_id')
       or not (l_item ? 'quantity')
       or exists (
         select 1
         from pg_catalog.jsonb_object_keys(l_item) as keys(key_name)
         where keys.key_name not in ('variant_id', 'quantity')
       )
       or pg_catalog.jsonb_typeof(l_item -> 'variant_id') <> 'string'
       or pg_catalog.jsonb_typeof(l_item -> 'quantity') <> 'number' then
      raise exception using message = 'invalid_argument', errcode = 'P0001';
    end if;

    l_variant_id := (l_item ->> 'variant_id')::uuid;
    l_quantity_numeric := (l_item ->> 'quantity')::numeric;
    if l_quantity_numeric <= 0
       or l_quantity_numeric <> pg_catalog.trunc(l_quantity_numeric)
       or l_quantity_numeric > 9007199254740991
       or l_variant_id = any(l_variant_ids) then
      raise exception using message = 'invalid_argument', errcode = 'P0001';
    end if;
    l_quantity := l_quantity_numeric::bigint;
    l_variant_ids := pg_catalog.array_append(l_variant_ids, l_variant_id);
    l_quantities := pg_catalog.array_append(l_quantities, l_quantity);
  end loop;

  select pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'variant_id', requested.variant_id,
      'quantity', requested.quantity
    ) order by requested.variant_id
  )
  into l_normalized_items
  from unnest(l_variant_ids, l_quantities)
    as requested(variant_id, quantity);

  l_normalized_intent := pg_catalog.jsonb_build_object(
    'items', l_normalized_items,
    'recipient_name', l_name,
    'recipient_phone', l_phone,
    'address_detail', l_address,
    'latitude', l_latitude,
    'longitude', l_longitude
  );
  l_fingerprint := pg_catalog.md5(l_normalized_intent::text);

  select *
  into l_existing
  from private.checkout_placements as p
  where p.customer_id = l_user_id
    and p.request_id = p_request_id
  for update;
  l_has_existing := found;
  if l_has_existing then
    if l_existing.fingerprint <> l_fingerprint or l_existing.normalized_intent is distinct from l_normalized_intent then
      raise exception using message = 'idempotency_conflict', errcode = 'P0001';
    end if;
    if not exists (
      select 1 from public.orders as o where o.id = l_existing.order_id
    ) or not exists (
      select 1 from public.business_events as e where e.id = l_existing.event_id
    ) then
      raise exception using message = 'external_dependency_unavailable', errcode = 'P0001';
    end if;
    return pg_catalog.jsonb_build_object(
      'ok', true,
      'data', pg_catalog.jsonb_build_object(
        'order', private.checkout_order_json(l_existing.order_id),
        'items', private.checkout_items_json(l_existing.order_id),
        'event_id', l_existing.event_id,
        'replayed', true
      ),
      'error', null
    );
  end if;

  select s.approved_service_area_geojson
  into l_geojson
  from public.store_settings as s
  where s.id = true
  for share;
  if not found
     or not private.checkout_geojson_contains(
       l_geojson, l_latitude, l_longitude
     ) then
    raise exception using message = 'outside_service_area', errcode = 'P0001';
  end if;

  l_manager_ids := array[]::uuid[];
  for l_manager_id in
    select p.id
    from public.profiles as p
    where p.role = 'manager'::public.user_role
    order by p.id
    for share
  loop
    l_manager_ids := pg_catalog.array_append(l_manager_ids, l_manager_id);
  end loop;

  -- Lock every requested variant in UUID order and snapshot the active product
  -- and category in the same read.  Catalog writes cannot change a locked
  -- variant's snapshot after this point in the transaction.
  for l_variant_id in
    select variant_id
    from pg_catalog.unnest(l_variant_ids) as ids(variant_id)
    order by variant_id
  loop
    select p.name, v.label, v.attributes, v.price_vnd
    into l_product_name, l_variant_label, l_attributes, l_price
    from public.product_variants as v
    join public.products as p on p.id = v.product_id
    join public.categories as c on c.id = p.category_id
    where v.id = l_variant_id
      and v.is_active
      and p.is_active
      and c.is_active
    for update of v for share of p, c;
    if not found then
      raise exception using message = 'forbidden_or_unavailable', errcode = 'P0001';
    end if;

    select v.price_vnd
    into l_price
    from public.product_variants as v
    where v.id = l_variant_id;
    l_line_total := l_price::numeric
      * (l_quantities[pg_catalog.array_position(l_variant_ids, l_variant_id)]::numeric);
    if l_line_total > 9007199254740991
       or l_line_total < 0 then
      raise exception using message = 'invalid_argument', errcode = 'P0001';
    end if;
    l_subtotal := l_subtotal + l_line_total;
    if l_subtotal > 9007199254740991 - 30000 then
      raise exception using message = 'invalid_argument', errcode = 'P0001';
    end if;
  end loop;

  insert into public.orders (
    customer_id, request_id, status, recipient_name, recipient_phone,
    address_detail, latitude, longitude, subtotal_vnd, delivery_fee_vnd
  ) values (
    l_user_id,
    p_request_id,
    'pending_confirmation'::public.order_status,
    l_name,
    l_phone,
    l_address,
    l_latitude,
    l_longitude,
    l_subtotal::bigint,
    30000
  ) returning id into l_order_id;

  for l_variant_id in
    select variant_id
    from pg_catalog.unnest(l_variant_ids) as ids(variant_id)
    order by variant_id
  loop
    select p.name, v.label, v.attributes, v.price_vnd
    into l_product_name, l_variant_label, l_attributes, l_price
    from public.product_variants as v
    join public.products as p on p.id = v.product_id
    where v.id = l_variant_id;
    insert into public.order_items (
      order_id, product_id, variant_id, product_name, variant_label,
      attributes, unit_price_vnd, quantity
    ) values (
      l_order_id,
      (select v.product_id from public.product_variants as v where v.id = l_variant_id),
      l_variant_id,
      l_product_name,
      l_variant_label,
      l_attributes,
      l_price,
      l_quantities[pg_catalog.array_position(l_variant_ids, l_variant_id)]
    ) returning id into l_order_item_id;
    l_reserve_items := l_reserve_items || pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'order_item_id', l_order_item_id,
        'variant_id', l_variant_id,
        'quantity', l_quantities[pg_catalog.array_position(l_variant_ids, l_variant_id)]
      )
    );
  end loop;

  l_event_id := pg_catalog.gen_random_uuid();
  insert into public.business_events (
    id, actor_id, subject_type, subject_id, from_state, to_state, reason,
    request_id
  ) values (
    l_event_id,
    l_user_id,
    'order',
    l_order_id,
    null,
    'pending_confirmation',
    'order_placed',
    null
  );

  l_inventory_result := private.apply_order_inventory_event(
    l_order_id,
    l_event_id,
    'reserve',
    l_reserve_items,
    l_user_id,
    'order_placed'
  );

  foreach l_manager_id in array l_manager_ids loop
    insert into public.notifications (
      recipient_id, event_id, subject_type, subject_id, title, body
    ) values (
      l_manager_id,
      l_event_id,
      'order',
      l_order_id,
      'Đơn hàng mới cần xác nhận',
      'Có đơn hàng mới được đặt và đang chờ xác nhận.'
    );
  end loop;

  insert into private.checkout_placements (
    customer_id, request_id, fingerprint, normalized_intent,
    order_id, event_id, event_type, origin_module, source_operation_key,
    manager_recipient_ids
  ) values (
    l_user_id,
    p_request_id,
    l_fingerprint,
    l_normalized_intent,
    l_order_id,
    l_event_id,
    'order_placed',
    'checkout',
    pg_catalog.concat(l_user_id::text, ':', p_request_id::text),
    l_manager_ids
  );

  return pg_catalog.jsonb_build_object(
    'ok', true,
    'data', pg_catalog.jsonb_build_object(
      'order', private.checkout_order_json(l_order_id),
      'items', private.checkout_items_json(l_order_id),
      'event_id', l_event_id,
      'replayed', false
    ),
    'error', null
  );
exception
  when sqlstate 'P0001' then
    return pg_catalog.jsonb_build_object(
      'ok', false,
      'data', null,
      'error', pg_catalog.jsonb_build_object('code', sqlerrm)
    );
  when invalid_text_representation or numeric_value_out_of_range then
    return pg_catalog.jsonb_build_object(
      'ok', false,
      'data', null,
      'error', pg_catalog.jsonb_build_object('code', 'invalid_argument')
    );
  when others then
    return pg_catalog.jsonb_build_object(
      'ok', false,
      'data', null,
      'error', pg_catalog.jsonb_build_object('code', 'external_dependency_unavailable')
    );
end;
$$;
