-- Quản lý yêu cầu trả hàng (manager), giai đoạn 1.
--
-- Reads (SECURITY INVOKER; manager RLS already covers every table read):
--   list_manager_return_requests(p_status, p_query)
--   get_manager_return_request(p_return_request_id)
-- Writes (SECURITY DEFINER, restricted no-login writer, idempotent per
-- actor + request id):
--   approve_return_collection: defines the goods to collect from the
--     delivered order, then runs the production primitives
--     approve_return_pickup_plan + assign_return_pickup_task in the SAME
--     transaction. Approving collection is NOT a refund decision.
--   reject_return_request: pending_review -> initially_rejected with a
--     reason; goods stay with the customer, no pickup/refund.
-- Never changes COD, stock, refund or the delivered order.

-- 1. Restricted NOLOGIN/NOBYPASSRLS owner for the write commands.
do $$
begin
  if not exists (
    select 1 from pg_roles where rolname = 'sports_store_return_management_writer'
  ) then
    create role sports_store_return_management_writer
      nologin noinherit nobypassrls nocreatedb nocreaterole noreplication;
    comment on role sports_store_return_management_writer is
      'sports_store return management writer; no-login, no-inherit, no-bypass-RLS';
  elsif not exists (
    select 1 from pg_roles r
    where r.rolname = 'sports_store_return_management_writer'
      and not r.rolcanlogin and not r.rolsuper and not r.rolbypassrls
      and not r.rolinherit and not r.rolcreaterole and not r.rolcreatedb
      and not r.rolreplication
  ) then
    raise exception
      'return management writer role already exists with unexpected configuration';
  end if;
end;
$$;

grant sports_store_return_management_writer to postgres;
grant usage on schema public, private to sports_store_return_management_writer;
grant execute on function private.delivery_request_user_id(),
  private.current_app_role()
  to sports_store_return_management_writer;
grant execute on function
  public.approve_return_pickup_plan(uuid, uuid, jsonb),
  public.assign_return_pickup_task(uuid, uuid, uuid, uuid, uuid)
  to sports_store_return_management_writer;

-- 2. Idempotency ledger (append-only, private).
create table private.return_management_requests (
  actor_id uuid not null,
  request_id uuid not null,
  operation text not null,
  return_request_id uuid not null,
  payload jsonb not null,
  payload_hash text not null,
  response jsonb not null,
  created_at timestamptz not null default now(),
  primary key (actor_id, request_id),
  constraint return_management_requests_operation_valid
    check (operation in ('approve_return_collection', 'reject_return_request'))
);
alter table private.return_management_requests enable row level security;
alter table private.return_management_requests force row level security;
revoke all on private.return_management_requests
  from public, anon, authenticated, service_role;
grant select, insert on private.return_management_requests
  to sports_store_return_management_writer;
create policy return_management_ledger_read
  on private.return_management_requests
  for select to sports_store_return_management_writer
  using (actor_id = (select private.delivery_request_user_id()));
create policy return_management_ledger_insert
  on private.return_management_requests
  for insert to sports_store_return_management_writer
  with check (actor_id = (select private.delivery_request_user_id()));

-- 3. Minimal column privileges + policies scoped to the writer role.
grant select (id, role) on public.profiles
  to sports_store_return_management_writer;
grant select (id, customer_id, status) on public.orders
  to sports_store_return_management_writer;
grant select (id, order_id, variant_id, product_name, variant_label, quantity)
  on public.order_items to sports_store_return_management_writer;
grant select (id, order_id, customer_id, status) on public.return_requests
  to sports_store_return_management_writer;
grant update (status, decision_reason, decision_at, decided_by, closed_at,
  updated_at) on public.return_requests
  to sports_store_return_management_writer;
grant select (id, return_request_id, order_id, quantity_to_collect)
  on public.return_items
  to sports_store_return_management_writer;
grant insert (id, return_request_id, order_id, order_item_id,
  actual_item_name, variant_id, quantity_to_collect, created_at, updated_at)
  on public.return_items to sports_store_return_management_writer;
grant insert (id, actor_id, subject_type, subject_id, from_state, to_state,
  reason, request_id, created_at) on public.business_events
  to sports_store_return_management_writer;
grant insert (id, recipient_id, event_id, subject_type, subject_id, title,
  body, created_at) on public.notifications
  to sports_store_return_management_writer;

create policy return_management_writer_profiles_read
  on public.profiles for select to sports_store_return_management_writer
  using (
    id = (select private.delivery_request_user_id())
    or role in ('shipper'::public.user_role, 'customer'::public.user_role)
  );
create policy return_management_writer_orders_read
  on public.orders for select to sports_store_return_management_writer
  using ((select private.current_app_role()) = 'manager');
create policy return_management_writer_order_items_read
  on public.order_items for select to sports_store_return_management_writer
  using ((select private.current_app_role()) = 'manager');
create policy return_management_writer_returns_read
  on public.return_requests for select to sports_store_return_management_writer
  using ((select private.current_app_role()) = 'manager');
create policy return_management_writer_returns_update
  on public.return_requests for update to sports_store_return_management_writer
  using ((select private.current_app_role()) = 'manager')
  with check (
    (select private.current_app_role()) = 'manager'
    and status in ('pending_review'::public.return_request_status,
                   'initially_rejected'::public.return_request_status)
  );
create policy return_management_writer_items_read
  on public.return_items for select to sports_store_return_management_writer
  using ((select private.current_app_role()) = 'manager');
create policy return_management_writer_items_insert
  on public.return_items for insert to sports_store_return_management_writer
  with check (
    (select private.current_app_role()) = 'manager'
    and exists (
      select 1 from public.return_requests r
      where r.id = return_request_id and r.order_id = return_items.order_id
        and r.status = 'pending_review'::public.return_request_status
    )
  );
create policy return_management_writer_events_insert
  on public.business_events for insert to sports_store_return_management_writer
  with check (
    actor_id = (select private.delivery_request_user_id())
    and (select private.current_app_role()) = 'manager'
    and subject_type = 'return_request'
    and from_state = 'pending_review'
    and to_state = 'initially_rejected'
    and reason = 'return_initially_rejected'
    and request_id = id
    and incident_kind is null
    and task_id is null
  );
create policy return_management_writer_notifications_insert
  on public.notifications for insert to sports_store_return_management_writer
  with check (
    (select private.current_app_role()) = 'manager'
    and subject_type in ('return_request', 'delivery_task')
    and title in ('Yêu cầu trả hàng đã được duyệt lấy hàng',
                  'Yêu cầu trả hàng không được duyệt',
                  'Nhiệm vụ thu hồi hàng mới')
  );

-- 4. Helpers.
create function private.return_management_derived_uuid(p_base uuid, p_tag text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.md5(p_base::text || ':' || p_tag)::uuid
$$;
revoke all on function private.return_management_derived_uuid(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function private.return_management_derived_uuid(uuid, text)
  to sports_store_return_management_writer;

-- Definer: reads only the caller's JWT identity and profile role.
create function private.require_manager()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  l_actor uuid := (select private.delivery_request_user_id());
begin
  if l_actor is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if (select private.current_app_role()) is distinct from 'manager' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;
  return l_actor;
end;
$$;
revoke all on function private.require_manager()
  from public, anon, authenticated, service_role;
grant execute on function private.require_manager()
  to authenticated, sports_store_return_management_writer;

-- 5. List (filters + search + per-status counts).
create function public.list_manager_return_requests(
  p_status text default null,
  p_query text default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  l_query text := nullif(btrim(coalesce(p_query, '')), '');
  l_needle text;
  l_status public.return_request_status;
  l_items jsonb;
  l_counts jsonb;
begin
  perform private.require_manager();
  if p_status is not null then
    begin
      l_status := p_status::public.return_request_status;
    exception when invalid_text_representation then
      raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
    end;
  end if;
  if l_query is not null and length(l_query) > 100 then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;
  -- Strip a leading "TH"/"DH" code prefix, then keep hex digits only.
  l_needle := regexp_replace(
    regexp_replace(lower(coalesce(l_query, '')), '^\s*#?\s*(th|dh)\s*-?', ''),
    '[^0-9a-f]', '', 'g');

  with base as (
    select r.id, r.order_id, r.status, r.reason, r.submitted_at,
           coalesce(nullif(btrim(p.full_name), ''), 'Khách hàng') as customer_name,
           o.total_cod_vnd,
           (select count(*) from public.order_items oi where oi.order_id = r.order_id) as line_count,
           (select oi.product_name from public.order_items oi
             where oi.order_id = r.order_id order by oi.created_at, oi.id limit 1) as first_item
    from public.return_requests r
    join public.orders o on o.id = r.order_id
    left join public.profiles p on p.id = r.customer_id
  ),
  searched as (
    select * from base b
    where l_query is null
       -- Codes: compare hex digits only, so "#DH-1972 07d6", "1972-07d6"
       -- and a full UUID all match. At least 4 hex digits.
       or (length(l_needle) >= 4 and (
             replace(b.id::text, '-', '') like '%' || l_needle || '%'
          or replace(b.order_id::text, '-', '') like '%' || l_needle || '%'))
       or b.customer_name ilike '%' || l_query || '%'
  )
  select
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'return_id', s.id,
        'order_id', s.order_id,
        'status', s.status,
        'reason', s.reason,
        'submitted_at', s.submitted_at,
        'customer_name', s.customer_name,
        'total_vnd', s.total_cod_vnd,
        'line_count', s.line_count,
        'first_item_name', s.first_item
      ) order by s.submitted_at desc, s.id)
      from searched s
      where l_status is null or s.status = l_status
    ), '[]'::jsonb),
    coalesce((
      select jsonb_object_agg(c.status, c.n)
      from (select s.status::text as status, count(*) as n
            from searched s group by s.status) c
    ), '{}'::jsonb)
  into l_items, l_counts;

  return jsonb_build_object(
    'items', l_items,
    'counts', l_counts,
    'server_now', pg_catalog.now()
  );
end;
$$;
revoke all on function public.list_manager_return_requests(text, text)
  from public, anon;
grant execute on function public.list_manager_return_requests(text, text)
  to authenticated;

-- 6. Detail (everything the manager needs to decide; video path is resolved
-- to a signed URL by the client through the existing Storage policy).
create function public.get_manager_return_request(p_return_request_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  l_return public.return_requests%rowtype;
  l_order public.orders%rowtype;
  l_customer jsonb;
  l_task jsonb;
begin
  perform private.require_manager();
  if p_return_request_id is null then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;
  select r.* into l_return from public.return_requests r
  where r.id = p_return_request_id;
  if not found then
    raise exception using errcode = 'PT404', message = 'RETURN_NOT_FOUND';
  end if;
  select o.* into strict l_order from public.orders o where o.id = l_return.order_id;

  select jsonb_build_object(
    'name', coalesce(nullif(btrim(p.full_name), ''), 'Khách hàng'),
    'phone', nullif(btrim(p.phone), '')
  ) into l_customer
  from public.profiles p where p.id = l_return.customer_id;

  select jsonb_build_object(
    'task_id', t.id,
    'status', t.status,
    'shipper_id', t.assigned_shipper_id,
    'shipper_name', coalesce(nullif(btrim(sp.full_name), ''), 'Shipper'),
    'shipper_phone', nullif(btrim(sp.phone), ''),
    'assigned_at', t.assigned_at,
    'completed_at', t.completed_at,
    'failure_reason', t.failure_reason
  ) into l_task
  from public.delivery_tasks t
  left join public.profiles sp on sp.id = t.assigned_shipper_id
  where t.return_request_id = l_return.id
    and t.kind = 'return_pickup'::public.delivery_task_kind
  order by t.created_at desc, t.id
  limit 1;

  return jsonb_build_object(
    'return_id', l_return.id,
    'order_id', l_return.order_id,
    'status', l_return.status,
    'reason', l_return.reason,
    'description', l_return.description,
    'submitted_at', l_return.submitted_at,
    'decision_reason', l_return.decision_reason,
    'decision_at', l_return.decision_at,
    'closed_at', l_return.closed_at,
    'customer', coalesce(l_customer, jsonb_build_object('name', 'Khách hàng', 'phone', null)),
    'recipient', jsonb_build_object(
      'name', l_order.recipient_name,
      'phone', l_order.recipient_phone,
      'address', l_order.address_detail
    ),
    'delivered_at', l_order.delivered_at,
    'subtotal_vnd', l_order.subtotal_vnd,
    'delivery_fee_vnd', l_order.delivery_fee_vnd,
    'total_vnd', l_order.total_cod_vnd,
    'order_items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'order_item_id', oi.id,
        'product_name', oi.product_name,
        'variant_label', oi.variant_label,
        'quantity', oi.quantity,
        'unit_price_vnd', oi.unit_price_vnd,
        'line_total_vnd', oi.line_total_vnd,
        'image_url', oi.product_image_url
      ) order by oi.created_at, oi.id)
      from public.order_items oi where oi.order_id = l_return.order_id
    ), '[]'::jsonb),
    'return_items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'return_item_id', i.id,
        'order_item_id', i.order_item_id,
        'name', i.actual_item_name,
        'quantity_to_collect', i.quantity_to_collect,
        'quantity_collected', i.quantity_collected,
        'sellable_quantity', i.sellable_quantity,
        'damaged_quantity', i.damaged_quantity
      ) order by i.id)
      from public.return_items i where i.return_request_id = l_return.id
    ), '[]'::jsonb),
    'video_paths', to_jsonb(array[l_return.video_object_path] || l_return.additional_video_paths),
    'bank', case when l_return.bank_name is null then null else jsonb_build_object(
      'bank_name', l_return.bank_name,
      'account_number', l_return.account_number,
      'account_holder', l_return.account_holder
    ) end,
    'pickup_task', l_task,
    'shippers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'shipper_id', p.id,
        'name', coalesce(nullif(btrim(p.full_name), ''), 'Shipper'),
        'phone', nullif(btrim(p.phone), '')
      ) order by p.full_name nulls last, p.id)
      from public.profiles p where p.role = 'shipper'::public.user_role
    ), '[]'::jsonb),
    'server_now', pg_catalog.now()
  );
end;
$$;
revoke all on function public.get_manager_return_request(uuid) from public, anon;
grant execute on function public.get_manager_return_request(uuid) to authenticated;

-- 7. Approve collection = define goods + approve plan + assign shipper, once.
create function public.approve_return_collection(
  p_return_request_id uuid,
  p_request_id uuid,
  p_items jsonb,
  p_shipper_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  l_actor uuid;
  l_return record;
  l_existing private.return_management_requests%rowtype;
  l_items jsonb;
  l_payload jsonb;
  l_hash text;
  l_item record;
  l_plan jsonb;
  l_approve jsonb;
  l_assign jsonb;
  l_response jsonb;
  l_now timestamptz;
begin
  l_actor := private.require_manager();
  if p_return_request_id is null or p_request_id is null or p_items is null
     or p_shipper_id is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 50 then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;
  -- Normalize: [{order_item_id uuid, quantity int > 0}] unique, sorted.
  begin
    select jsonb_agg(jsonb_build_object('order_item_id', x.order_item_id, 'quantity', x.quantity)
                     order by x.order_item_id)
      into l_items
    from (
      select (e ->> 'order_item_id')::uuid as order_item_id,
             (e ->> 'quantity')::bigint as quantity
      from jsonb_array_elements(p_items) e
      where jsonb_typeof(e) = 'object'
        and (select count(*) from jsonb_object_keys(e)) = 2
    ) x;
  exception when others then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end;
  if l_items is null or jsonb_array_length(l_items) <> jsonb_array_length(p_items)
     or exists (select 1 from jsonb_array_elements(l_items) e
                where e ->> 'order_item_id' is null
                   or coalesce((e ->> 'quantity')::bigint, 0) <= 0)
     or (select count(distinct e ->> 'order_item_id') from jsonb_array_elements(l_items) e)
        <> jsonb_array_length(l_items) then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.return_management:request:' || l_actor::text || ':'
      || p_request_id::text, 0));
  l_payload := jsonb_build_object(
    'operation', 'approve_return_collection',
    'return_request_id', p_return_request_id,
    'shipper_id', p_shipper_id,
    'items', l_items
  );
  l_hash := md5(l_payload::text);
  select * into l_existing from private.return_management_requests m
  where m.actor_id = l_actor and m.request_id = p_request_id;
  if found then
    if l_existing.operation <> 'approve_return_collection'
       or l_existing.payload_hash <> l_hash then
      raise exception using errcode = 'PT409', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return l_existing.response;
  end if;

  select r.id, r.order_id, r.status into l_return
  from public.return_requests r where r.id = p_return_request_id
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  if l_return.status <> 'pending_review'::public.return_request_status
     or exists (select 1 from public.return_items i
                where i.return_request_id = p_return_request_id) then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;
  if not exists (select 1 from public.profiles p
                 where p.id = p_shipper_id and p.role = 'shipper'::public.user_role) then
    raise exception using errcode = 'PT409', message = 'INVALID_SHIPPER';
  end if;

  l_now := pg_catalog.clock_timestamp();
  for l_item in
    select oi.id, oi.variant_id, oi.product_name, oi.variant_label,
           oi.quantity as ordered, (e ->> 'quantity')::bigint as wanted
    from jsonb_array_elements(l_items) e
    left join public.order_items oi
      on oi.id = (e ->> 'order_item_id')::uuid and oi.order_id = l_return.order_id
  loop
    if l_item.id is null or l_item.wanted > l_item.ordered then
      raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
    end if;
    insert into public.return_items (
      return_request_id, order_id, order_item_id, actual_item_name,
      variant_id, quantity_to_collect, created_at, updated_at
    ) values (
      p_return_request_id, l_return.order_id, l_item.id,
      l_item.product_name || coalesce(' — ' || nullif(btrim(l_item.variant_label), ''), ''),
      l_item.variant_id, l_item.wanted, l_now, l_now
    );
  end loop;

  select jsonb_agg(jsonb_build_object('return_item_id', i.id, 'quantity', i.quantity_to_collect)
                   order by i.id)
    into l_plan
  from public.return_items i where i.return_request_id = p_return_request_id;

  l_approve := public.approve_return_pickup_plan(
    p_return_request_id,
    private.return_management_derived_uuid(p_request_id, 'approve'),
    l_plan);
  l_assign := public.assign_return_pickup_task(
    p_return_request_id, p_shipper_id,
    private.return_management_derived_uuid(p_request_id, 'assign'));

  insert into public.notifications (recipient_id, event_id, subject_type, subject_id, title, body)
  select r.customer_id, (l_approve ->> 'event_id')::uuid, 'return_request', r.id,
         'Yêu cầu trả hàng đã được duyệt lấy hàng',
         'Cửa hàng sẽ cử nhân viên đến lấy hàng. Đây chưa phải xác nhận hoàn tiền.'
  from public.return_requests r where r.id = p_return_request_id;
  if l_assign ->> 'event_id' is not null then
    insert into public.notifications (recipient_id, event_id, subject_type, subject_id, title, body)
    values (p_shipper_id, (l_assign ->> 'event_id')::uuid, 'delivery_task',
            (l_assign ->> 'task_id')::uuid, 'Nhiệm vụ thu hồi hàng mới',
            'Bạn được phân công lấy hàng trả từ khách.');
  end if;

  l_response := jsonb_build_object(
    'operation', 'approve_return_collection',
    'return_request_id', p_return_request_id,
    'order_id', l_return.order_id,
    'return_status', 'awaiting_return_pickup',
    'task_id', l_assign ->> 'task_id',
    'shipper_id', p_shipper_id,
    'approved_at', l_approve ->> 'approved_at',
    'request_id', p_request_id
  );
  insert into private.return_management_requests (
    actor_id, request_id, operation, return_request_id, payload, payload_hash, response
  ) values (
    l_actor, p_request_id, 'approve_return_collection', p_return_request_id,
    l_payload, l_hash, l_response
  );
  return l_response;
end;
$$;
grant create on schema public to sports_store_return_management_writer;
alter function public.approve_return_collection(uuid, uuid, jsonb, uuid)
  owner to sports_store_return_management_writer;
revoke create on schema public from sports_store_return_management_writer;
revoke all on function public.approve_return_collection(uuid, uuid, jsonb, uuid)
  from public, anon;
grant execute on function public.approve_return_collection(uuid, uuid, jsonb, uuid)
  to authenticated;

-- 8. Reject before pickup.
create function public.reject_return_request(
  p_return_request_id uuid,
  p_request_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  l_actor uuid;
  l_reason text := btrim(coalesce(p_reason, ''));
  l_return record;
  l_existing private.return_management_requests%rowtype;
  l_payload jsonb;
  l_hash text;
  l_event uuid;
  l_now timestamptz;
  l_response jsonb;
begin
  l_actor := private.require_manager();
  if p_return_request_id is null or p_request_id is null
     or length(l_reason) < 5 or length(l_reason) > 500 then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.return_management:request:' || l_actor::text || ':'
      || p_request_id::text, 0));
  l_payload := jsonb_build_object(
    'operation', 'reject_return_request',
    'return_request_id', p_return_request_id,
    'reason', l_reason
  );
  l_hash := md5(l_payload::text);
  select * into l_existing from private.return_management_requests m
  where m.actor_id = l_actor and m.request_id = p_request_id;
  if found then
    if l_existing.operation <> 'reject_return_request'
       or l_existing.payload_hash <> l_hash then
      raise exception using errcode = 'PT409', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return l_existing.response;
  end if;

  select r.id, r.order_id, r.customer_id, r.status into l_return
  from public.return_requests r where r.id = p_return_request_id
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  if l_return.status <> 'pending_review'::public.return_request_status
     or exists (select 1 from public.return_items i
                where i.return_request_id = p_return_request_id) then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;

  l_now := pg_catalog.clock_timestamp();
  update public.return_requests
  set status = 'initially_rejected'::public.return_request_status,
      decision_reason = l_reason,
      decision_at = l_now,
      decided_by = l_actor,
      closed_at = l_now,
      updated_at = l_now
  where id = p_return_request_id;
  l_event := pg_catalog.gen_random_uuid();
  insert into public.business_events (
    id, actor_id, subject_type, subject_id, from_state, to_state, reason,
    request_id, created_at
  ) values (
    l_event, l_actor, 'return_request', p_return_request_id, 'pending_review',
    'initially_rejected', 'return_initially_rejected', l_event, l_now
  );
  insert into public.notifications (recipient_id, event_id, subject_type, subject_id, title, body)
  values (l_return.customer_id, l_event, 'return_request', p_return_request_id,
          'Yêu cầu trả hàng không được duyệt',
          'Cửa hàng đã xem xét và chưa thể nhận trả hàng. Xem lý do trong chi tiết yêu cầu.');

  l_response := jsonb_build_object(
    'operation', 'reject_return_request',
    'return_request_id', p_return_request_id,
    'order_id', l_return.order_id,
    'return_status', 'initially_rejected',
    'rejected_at', l_now,
    'event_id', l_event,
    'request_id', p_request_id
  );
  insert into private.return_management_requests (
    actor_id, request_id, operation, return_request_id, payload, payload_hash, response
  ) values (
    l_actor, p_request_id, 'reject_return_request', p_return_request_id,
    l_payload, l_hash, l_response
  );
  return l_response;
end;
$$;
grant create on schema public to sports_store_return_management_writer;
alter function public.reject_return_request(uuid, uuid, text)
  owner to sports_store_return_management_writer;
revoke create on schema public from sports_store_return_management_writer;
revoke all on function public.reject_return_request(uuid, uuid, text)
  from public, anon;
grant execute on function public.reject_return_request(uuid, uuid, text)
  to authenticated;

comment on function public.approve_return_collection(uuid, uuid, jsonb, uuid) is
  'Manager: define goods to collect, approve pickup plan and assign a shipper in one transaction. Not a refund decision.';
comment on function public.reject_return_request(uuid, uuid, text) is
  'Manager: reject a pending return before pickup; goods stay with the customer.';
