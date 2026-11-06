-- MH16 checkout placement and inventory reservation.
--
-- This migration is intentionally additive.  Public tables remain client
-- read-only; placement is the one authenticated RPC that may write the order
-- aggregate, inventory ledger, canonical event and manager notifications.  A
-- native PostgreSQL geometry predicate is used because PostGIS is not part of
-- the project's deployed database contract.

create table private.checkout_placements (
  customer_id uuid not null references public.profiles (id) on delete cascade,
  request_id uuid not null,
  fingerprint text not null,
  normalized_intent jsonb not null,
  order_id uuid not null references public.orders (id),
  event_id uuid not null references public.business_events (id),
  event_type text not null default 'order_placed',
  origin_module text not null default 'checkout',
  source_operation_key text not null,
  manager_recipient_ids uuid[] not null default '{}'::uuid[],
  committed_at timestamptz not null default clock_timestamp(),
  primary key (customer_id, request_id),
  unique (order_id),
  unique (event_id),
  unique (origin_module, source_operation_key),
  constraint checkout_placements_intent_object
    check (jsonb_typeof(normalized_intent) = 'object'),
  constraint checkout_placements_event_type
    check (event_type = 'order_placed'),
  constraint checkout_placements_origin_module
    check (origin_module = 'checkout'),
  constraint checkout_placements_source_key_nonblank
    check (btrim(source_operation_key) <> ''),
  constraint checkout_placements_manager_ids_no_null
    check (array_position(manager_recipient_ids, null) is null)
);

alter table private.checkout_placements enable row level security;
alter table private.checkout_placements force row level security;
revoke all on table private.checkout_placements
  from public, anon, authenticated, service_role;

-- The geometry helpers return false for every malformed or unsupported shape.
-- GeoJSON coordinates are [longitude, latitude].  An exterior boundary is
-- included; a hole boundary is excluded, which is the conservative delivery
-- interpretation for a point on a prohibited boundary.
create or replace function private.checkout_ring_location(
  p_ring jsonb,
  p_x numeric,
  p_y numeric
) returns smallint
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  l_count integer;
  l_index integer;
  l_point jsonb;
  l_x numeric;
  l_y numeric;
  l_first_x numeric;
  l_first_y numeric;
  l_previous_x numeric;
  l_previous_y numeric;
  l_intersection_x numeric;
  l_inside boolean := false;
  l_on_boundary boolean := false;
begin
  if p_ring is null
     or pg_catalog.jsonb_typeof(p_ring) <> 'array'
     or p_x is null
     or p_y is null
     or p_x::text = 'NaN'
     or p_y::text = 'NaN'
     or p_x < -180
     or p_x > 180
     or p_y < -90
     or p_y > 90 then
    return -2;
  end if;

  l_count := pg_catalog.jsonb_array_length(p_ring);
  if l_count < 4 then
    return -2;
  end if;

  for l_index in 0..(l_count - 1) loop
    l_point := p_ring -> l_index;
    if pg_catalog.jsonb_typeof(l_point) <> 'array'
       or pg_catalog.jsonb_array_length(l_point) <> 2
       or pg_catalog.jsonb_typeof(l_point -> 0) <> 'number'
       or pg_catalog.jsonb_typeof(l_point -> 1) <> 'number' then
      return -2;
    end if;

    l_x := (l_point ->> 0)::numeric;
    l_y := (l_point ->> 1)::numeric;
    if l_x::text = 'NaN'
       or l_y::text = 'NaN'
       or l_x < -180
       or l_x > 180
       or l_y < -90
       or l_y > 90 then
      return -2;
    end if;

    if l_index = 0 then
      l_first_x := l_x;
      l_first_y := l_y;
      l_previous_x := l_x;
      l_previous_y := l_y;
    else
      if (
        (p_x - l_previous_x) * (l_y - l_previous_y)
          = (p_y - l_previous_y) * (l_x - l_previous_x)
        and p_x between least(l_previous_x, l_x)
          and greatest(l_previous_x, l_x)
        and p_y between least(l_previous_y, l_y)
          and greatest(l_previous_y, l_y)
      ) then
        l_on_boundary := true;
      elsif (l_previous_y > p_y) <> (l_y > p_y) then
        l_intersection_x := l_previous_x
          + (p_y - l_previous_y) * (l_x - l_previous_x)
            / (l_y - l_previous_y);
        if p_x < l_intersection_x then
          l_inside := not l_inside;
        end if;
      end if;

      l_previous_x := l_x;
      l_previous_y := l_y;
    end if;
  end loop;

  -- GeoJSON linear rings must be closed.  This also checks the final segment
  -- against the first point, which is needed for the ray crossing algorithm.
  if l_first_x is distinct from l_previous_x
     or l_first_y is distinct from l_previous_y then
    return -2;
  end if;

  if (
    (p_x - l_previous_x) * (l_first_y - l_previous_y)
      = (p_y - l_previous_y) * (l_first_x - l_previous_x)
    and p_x between least(l_previous_x, l_first_x)
      and greatest(l_previous_x, l_first_x)
    and p_y between least(l_previous_y, l_first_y)
      and greatest(l_previous_y, l_first_y)
  ) then
    l_on_boundary := true;
  elsif (l_previous_y > p_y) <> (l_first_y > p_y) then
    l_intersection_x := l_previous_x
      + (p_y - l_previous_y) * (l_first_x - l_previous_x)
        / (l_first_y - l_previous_y);
    if p_x < l_intersection_x then
      l_inside := not l_inside;
    end if;
  end if;

  return case
    when l_on_boundary then -1
    when l_inside then 1
    else 0
  end;
exception
  when others then
    return -2;
end;
$$;

create or replace function private.checkout_polygon_location(
  p_polygon jsonb,
  p_x numeric,
  p_y numeric
) returns smallint
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  l_ring_count integer;
  l_index integer;
  l_location smallint;
  l_exterior_inside boolean := false;
  l_hole_contains_point boolean := false;
begin
  if p_polygon is null
     or pg_catalog.jsonb_typeof(p_polygon) <> 'array' then
    return -2;
  end if;

  l_ring_count := pg_catalog.jsonb_array_length(p_polygon);
  if l_ring_count < 1 then
    return -2;
  end if;

  l_location := private.checkout_ring_location(p_polygon -> 0, p_x, p_y);
  if l_location = -2 then
    return -2;
  elsif l_location in (-1, 1) then
    l_exterior_inside := true;
  end if;

  if l_ring_count > 1 then
    for l_index in 1..(l_ring_count - 1) loop
      l_location := private.checkout_ring_location(
        p_polygon -> l_index, p_x, p_y
      );
      if l_location = -2 then
        return -2;
      elsif l_location in (-1, 1) then
        -- A point in a hole, including its boundary, is outside.  Continue
        -- validating every later ring so malformed geometry fails closed even
        -- when an earlier ring already determines the point's result.
        l_hole_contains_point := true;
      end if;
    end loop;
  end if;

  if l_exterior_inside and not l_hole_contains_point then
    return 1;
  end if;
  return 0;
exception
  when others then
    return -2;
end;
$$;

create or replace function private.checkout_geojson_contains(
  p_geojson jsonb,
  p_latitude numeric,
  p_longitude numeric
) returns boolean
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  l_type text;
  l_polygons jsonb;
  l_index integer;
  l_location smallint;
  l_inside boolean := false;
begin
  if p_geojson is null
     or pg_catalog.jsonb_typeof(p_geojson) <> 'object'
     or p_latitude is null
     or p_longitude is null
     or p_latitude::text = 'NaN'
     or p_longitude::text = 'NaN'
     or p_latitude < -90
     or p_latitude > 90
     or p_longitude < -180
     or p_longitude > 180 then
    return false;
  end if;

  l_type := p_geojson ->> 'type';
  l_polygons := p_geojson -> 'coordinates';
  if l_type = 'Polygon' then
    l_location := private.checkout_polygon_location(
      l_polygons, p_longitude, p_latitude
    );
    return l_location = 1;
  elsif l_type = 'MultiPolygon' then
    if l_polygons is null
       or pg_catalog.jsonb_typeof(l_polygons) <> 'array'
       or pg_catalog.jsonb_array_length(l_polygons) < 1 then
      return false;
    end if;

    for l_index in 0..(pg_catalog.jsonb_array_length(l_polygons) - 1) loop
      l_location := private.checkout_polygon_location(
        l_polygons -> l_index, p_longitude, p_latitude
      );
      if l_location = -2 then
        return false;
      elsif l_location = 1 then
        l_inside := true;
      end if;
    end loop;
    return l_inside;
  end if;

  return false;
exception
  when others then
    return false;
end;
$$;

-- Shared internal inventory primitive.  It is deliberately not a client RPC;
-- public placement uses only reserve today, while future trusted order/delivery
-- wrappers can use release and dispatch with the same ledger idempotency key.
create or replace function private.apply_order_inventory_event(
  p_order_id uuid,
  p_event_id uuid,
  p_effect text,
  p_items jsonb,
  p_actor_id uuid,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  l_item jsonb;
  l_item_id uuid;
  l_supplied_variant_id uuid;
  l_actual_variant_id uuid;
  l_quantity_numeric numeric;
  l_quantity bigint;
  l_order_item_quantity bigint;
  l_item_ids uuid[] := array[]::uuid[];
  l_quantities bigint[] := array[]::bigint[];
  l_variant_ids uuid[] := array[]::uuid[];
  l_variant_id uuid;
  l_existing_count integer;
  l_expected_on_hand_delta bigint;
  l_expected_reserved_delta bigint;
  l_existing_on_hand_delta bigint;
  l_existing_reserved_delta bigint;
  l_on_hand bigint;
  l_reserved bigint;
  l_delta_on_hand bigint;
  l_delta_reserved bigint;
  l_reason text;
  l_order_exists boolean;
begin
  if p_order_id is null or p_event_id is null
     or p_effect is null
     or p_effect not in ('reserve', 'release', 'dispatch')
     or p_items is null
     or pg_catalog.jsonb_typeof(p_items) <> 'array'
     or pg_catalog.jsonb_array_length(p_items) = 0 then
    raise exception using message = 'invalid_argument', errcode = 'P0001';
  end if;
  l_reason := nullif(pg_catalog.btrim(coalesce(p_reason, '')), '');

  for l_item in
    select e.value
    from pg_catalog.jsonb_array_elements(p_items) as e(value)
  loop
    if pg_catalog.jsonb_typeof(l_item) <> 'object'
       or not (l_item ? 'order_item_id')
       or not (l_item ? 'quantity')
       or exists (
         select 1
         from pg_catalog.jsonb_object_keys(l_item) as keys(key_name)
         where keys.key_name not in ('order_item_id', 'variant_id', 'quantity')
       )
       or pg_catalog.jsonb_typeof(l_item -> 'order_item_id') <> 'string'
       or pg_catalog.jsonb_typeof(l_item -> 'quantity') <> 'number' then
      raise exception using message = 'invalid_argument', errcode = 'P0001';
    end if;

    l_item_id := (l_item ->> 'order_item_id')::uuid;
    l_quantity_numeric := (l_item ->> 'quantity')::numeric;
    if l_quantity_numeric <= 0
       or l_quantity_numeric <> pg_catalog.trunc(l_quantity_numeric)
       or l_quantity_numeric > 9007199254740991 then
      raise exception using message = 'invalid_argument', errcode = 'P0001';
    end if;
    l_quantity := l_quantity_numeric::bigint;
    if l_item_id = any(l_item_ids) then
      raise exception using message = 'invalid_argument', errcode = 'P0001';
    end if;

    l_supplied_variant_id := null;
    if l_item ? 'variant_id' then
      if pg_catalog.jsonb_typeof(l_item -> 'variant_id') <> 'string' then
        raise exception using message = 'invalid_argument', errcode = 'P0001';
      end if;
      l_supplied_variant_id := (l_item ->> 'variant_id')::uuid;
    end if;

    select i.variant_id, i.quantity
    into l_actual_variant_id, l_order_item_quantity
    from public.order_items as i
    where i.id = l_item_id
      and i.order_id = p_order_id;
    if not found
       or l_order_item_quantity <> l_quantity
       or (l_supplied_variant_id is not null
           and l_supplied_variant_id <> l_actual_variant_id) then
      raise exception using message = 'invalid_argument', errcode = 'P0001';
    end if;

    if l_actual_variant_id = any(l_variant_ids) then
      raise exception using message = 'invalid_argument', errcode = 'P0001';
    end if;
    l_item_ids := pg_catalog.array_append(l_item_ids, l_item_id);
    l_quantities := pg_catalog.array_append(l_quantities, l_quantity);
    l_variant_ids := pg_catalog.array_append(l_variant_ids, l_actual_variant_id);
  end loop;

  select true
  into l_order_exists
  from public.orders as o
  where o.id = p_order_id
  for update;
  if not coalesce(l_order_exists, false) then
    raise exception using message = 'forbidden_or_unavailable', errcode = 'P0001';
  end if;

  -- Each inventory transition covers the complete immutable order aggregate.
  -- A partial release/dispatch could consume another order's pooled reservation.
  if (select count(*) from public.order_items where order_id = p_order_id)
       <> pg_catalog.cardinality(l_item_ids) then
    raise exception using message = 'invalid_argument', errcode = 'P0001';
  end if;

  -- Always acquire variant row locks in UUID order.  This is the shared L-order
  -- boundary used by placement and future release/dispatch wrappers.
  for l_variant_id in
    select variant_id
    from pg_catalog.unnest(l_variant_ids) as ids(variant_id)
    order by variant_id
  loop
    select v.on_hand, v.reserved
    into l_on_hand, l_reserved
    from public.product_variants as v
    where v.id = l_variant_id
    for update;
    if not found then
      raise exception using message = 'forbidden_or_unavailable', errcode = 'P0001';
    end if;
  end loop;

  select count(*)::integer
  into l_existing_count
  from public.inventory_movements as m
  where m.event_id = p_event_id;
  if l_existing_count > 0 then
    if l_existing_count <> pg_catalog.cardinality(l_variant_ids)
       or exists (
         select 1
         from public.inventory_movements as m
         where m.event_id = p_event_id
           and (m.order_id is distinct from p_order_id
             or m.kind::text is distinct from p_effect
             or m.actor_id is distinct from p_actor_id
             or m.reason is distinct from l_reason
             or m.damaged_delta <> 0
             or m.return_request_id is not null)
       ) then
      raise exception using message = 'idempotency_conflict', errcode = 'P0001';
    end if;

    for l_item_id, l_quantity, l_variant_id in
      select item_id, quantity, variant_id
      from unnest(l_item_ids, l_quantities, l_variant_ids)
        as requested(item_id, quantity, variant_id)
    loop
      if p_effect = 'reserve' then
        l_expected_on_hand_delta := 0;
        l_expected_reserved_delta := l_quantity;
      elsif p_effect = 'release' then
        l_expected_on_hand_delta := 0;
        l_expected_reserved_delta := -l_quantity;
      else
        l_expected_on_hand_delta := -l_quantity;
        l_expected_reserved_delta := -l_quantity;
      end if;
      select m.on_hand_delta, m.reserved_delta
      into l_existing_on_hand_delta, l_existing_reserved_delta
      from public.inventory_movements as m
      where m.event_id = p_event_id
        and m.variant_id = l_variant_id;
      if not found
         or l_existing_on_hand_delta <> l_expected_on_hand_delta
         or l_existing_reserved_delta <> l_expected_reserved_delta then
        raise exception using message = 'idempotency_conflict', errcode = 'P0001';
      end if;
    end loop;

    return pg_catalog.jsonb_build_object(
      'event_id', p_event_id,
      'order_id', p_order_id,
      'movements', coalesce(
        (
          select pg_catalog.jsonb_agg(
            pg_catalog.jsonb_build_object(
              'variant_id', m.variant_id,
              'on_hand_delta', m.on_hand_delta,
              'reserved_delta', m.reserved_delta,
              'damaged_delta', m.damaged_delta
            ) order by m.variant_id
          )
          from public.inventory_movements as m
          where m.event_id = p_event_id
        ),
        '[]'::jsonb
      )
    );
  end if;

  -- A new event ID cannot repeat an already completed physical stock effect.
  -- Order row locking serializes both this primitive and state-command wrappers.
  if exists (
    select 1 from public.inventory_movements m
    where m.order_id = p_order_id and m.kind::text = p_effect
  ) or (p_effect in ('release', 'dispatch') and exists (
    select 1 from public.inventory_movements m
    where m.order_id = p_order_id and m.kind in ('release', 'dispatch')
  )) then
    raise exception using message = 'idempotency_conflict', errcode = 'P0001';
  end if;

  if p_effect in ('release', 'dispatch') and exists (
    select 1 from public.order_items i
    where i.order_id = p_order_id and i.quantity <> coalesce((
      select sum(m.reserved_delta) from public.inventory_movements m
      where m.order_id = p_order_id and m.variant_id = i.variant_id
        and m.kind in ('reserve', 'release', 'dispatch')
    ), 0)
  ) then
    raise exception using message = 'data_integrity', errcode = 'P0001';
  end if;

  if p_effect = 'reserve' then
    l_delta_on_hand := 0;
    l_delta_reserved := 1;
  elsif p_effect = 'release' then
    l_delta_on_hand := 0;
    l_delta_reserved := -1;
  else
    l_delta_on_hand := -1;
    l_delta_reserved := -1;
  end if;

  for l_item_id, l_quantity, l_variant_id in
    select item_id, quantity, variant_id
    from unnest(l_item_ids, l_quantities, l_variant_ids)
      as requested(item_id, quantity, variant_id)
  loop
    select v.on_hand, v.reserved
    into l_on_hand, l_reserved
    from public.product_variants as v
    where v.id = l_variant_id
    for update;

    if p_effect = 'reserve' then
      if l_on_hand - l_reserved < l_quantity then
        raise exception using message = 'insufficient_stock', errcode = 'P0001';
      end if;
    elsif p_effect = 'release' then
      if l_reserved < l_quantity then
        raise exception using message = 'data_integrity', errcode = 'P0001';
      end if;
    elsif l_on_hand < l_quantity or l_reserved < l_quantity then
      raise exception using message = 'data_integrity', errcode = 'P0001';
    end if;

    update public.product_variants
    set on_hand = on_hand + (l_delta_on_hand * l_quantity),
        reserved = reserved + (l_delta_reserved * l_quantity)
    where id = l_variant_id;

    insert into public.inventory_movements (
      variant_id, order_id, event_id, kind,
      on_hand_delta, reserved_delta, damaged_delta, actor_id, reason
    ) values (
      l_variant_id,
      p_order_id,
      p_event_id,
      p_effect::public.inventory_movement_kind,
      l_delta_on_hand * l_quantity,
      l_delta_reserved * l_quantity,
      0,
      p_actor_id,
      l_reason
    );
  end loop;

  return pg_catalog.jsonb_build_object(
    'event_id', p_event_id,
    'order_id', p_order_id,
    'movements', coalesce(
      (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'variant_id', m.variant_id,
            'on_hand_delta', m.on_hand_delta,
            'reserved_delta', m.reserved_delta,
            'damaged_delta', m.damaged_delta
          ) order by m.variant_id
        )
        from public.inventory_movements as m
        where m.event_id = p_event_id
      ),
      '[]'::jsonb
    )
  );
end;
$$;

revoke all on function private.checkout_ring_location(jsonb, numeric, numeric)
  from public, anon, authenticated, service_role;
revoke all on function private.checkout_polygon_location(jsonb, numeric, numeric)
  from public, anon, authenticated, service_role;
revoke all on function private.checkout_geojson_contains(jsonb, numeric, numeric)
  from public, anon, authenticated, service_role;
revoke all on function private.apply_order_inventory_event(
  uuid, uuid, text, jsonb, uuid, text
) from public, anon, authenticated, service_role;

create or replace function private.checkout_order_json(p_order_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'id', o.id,
    'customer_id', o.customer_id,
    'request_id', o.request_id,
    'status', o.status,
    'recipient_name', o.recipient_name,
    'recipient_phone', o.recipient_phone,
    'address_detail', o.address_detail,
    'latitude', o.latitude,
    'longitude', o.longitude,
    'subtotal_vnd', o.subtotal_vnd,
    'delivery_fee_vnd', o.delivery_fee_vnd,
    'total_cod_vnd', o.total_cod_vnd,
    'delivery_attempt_count', o.delivery_attempt_count,
    'placed_at', o.placed_at,
    'confirmed_at', o.confirmed_at,
    'source', o.source,
    'confirmed_by', o.confirmed_by,
    'delivered_at', o.delivered_at,
    'cancel_reason', o.cancel_reason,
    'created_at', o.created_at,
    'updated_at', o.updated_at
  )
  from public.orders as o
  where o.id = p_order_id
$$;

create or replace function private.checkout_items_json(p_order_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'id', i.id,
        'order_id', i.order_id,
        'product_id', i.product_id,
        'variant_id', i.variant_id,
        'product_name', i.product_name,
        'variant_label', i.variant_label,
        'attributes', i.attributes,
        'unit_price_vnd', i.unit_price_vnd,
        'quantity', i.quantity,
        'line_total_vnd', i.line_total_vnd,
        'created_at', i.created_at
      ) order by i.variant_id
    ),
    '[]'::jsonb
  )
  from public.order_items as i
  where i.order_id = p_order_id
$$;

revoke all on function private.checkout_order_json(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.checkout_items_json(uuid)
  from public, anon, authenticated, service_role;

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
    if l_existing.fingerprint <> l_fingerprint then
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

create or replace function public.get_placement_result(p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  l_user_id uuid;
  l_role public.user_role;
  l_existing private.checkout_placements%rowtype;
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

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      pg_catalog.concat(l_user_id::text, ':', p_request_id::text),
      0
    )
  );

  select *
  into l_existing
  from private.checkout_placements as p
  where p.customer_id = l_user_id
    and p.request_id = p_request_id;
  if not found then
    return pg_catalog.jsonb_build_object(
      'ok', true,
      'data', pg_catalog.jsonb_build_object(
        'state', 'not_found',
        'order', null,
        'items', '[]'::jsonb,
        'event_id', null,
        'replayed', false
      ),
      'error', null
    );
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
      'state', 'committed',
      'order', private.checkout_order_json(l_existing.order_id),
      'items', private.checkout_items_json(l_existing.order_id),
      'event_id', l_existing.event_id,
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
  when others then
    return pg_catalog.jsonb_build_object(
      'ok', false,
      'data', null,
      'error', pg_catalog.jsonb_build_object('code', 'external_dependency_unavailable')
    );
end;
$$;

revoke all on function public.place_order(
  uuid, jsonb, text, text, text, numeric, numeric
) from public, anon, service_role;
revoke all on function public.get_placement_result(uuid)
  from public, anon, service_role;
grant execute on function public.place_order(
  uuid, jsonb, text, text, text, numeric, numeric
) to authenticated;
grant execute on function public.get_placement_result(uuid) to authenticated;

comment on function public.place_order(
  uuid, jsonb, text, text, text, numeric, numeric
) is 'MH16 atomic customer checkout placement; returns {ok,data,error} and owns idempotent reservation/event/manager notifications.';
comment on function public.get_placement_result(uuid)
  is 'MH16 current-customer placement recovery lookup; returns committed or not_found envelope.';
