-- MH14 customer return tracking read.
--
-- Read-only. Projects one return request owned by the calling customer from
-- existing tables: return_requests, orders, return_items/order_items and the
-- return_pickup / redelivery delivery_tasks of that same return. The only
-- shipper data exposed is name + phone of the person assigned to an ACTIVE
-- task of the caller's own return. No schedule, route or location exists in
-- the schema, so none is returned. Refund completion is reported only when
-- the manager's refund bundle (amount, time, transfer evidence) is recorded.
-- Bank account number is masked; transfer evidence paths are never returned.

do $$
begin
  if not exists (
    select 1 from pg_roles where rolname = 'sports_store_return_tracking_reader'
  ) then
    create role sports_store_return_tracking_reader
      nologin noinherit nobypassrls nocreatedb nocreaterole noreplication;
    comment on role sports_store_return_tracking_reader is
      'sports_store MH14 return-tracking reader; no-login, no-inherit, no-bypass-RLS';
  elsif not exists (
    select 1
    from pg_roles r
    where r.rolname = 'sports_store_return_tracking_reader'
      and not r.rolcanlogin
      and not r.rolsuper
      and not r.rolbypassrls
      and not r.rolinherit
      and not r.rolcreaterole
      and not r.rolcreatedb
      and not r.rolreplication
      and shobj_description(r.oid, 'pg_authid') =
        'sports_store MH14 return-tracking reader; no-login, no-inherit, no-bypass-RLS'
  ) then
    raise exception
      'MH14 return-tracking reader role already exists with unexpected configuration';
  end if;
end;
$$;

do $$
begin
  if exists (
    select 1
    from pg_auth_members m
    join pg_roles granted on granted.oid = m.roleid
    join pg_roles member on member.oid = m.member
    where granted.rolname = 'sports_store_return_tracking_reader'
      and member.rolname <> 'postgres'
  ) then
    raise exception 'MH14 return-tracking reader role has unexpected membership';
  end if;
end;
$$;

grant sports_store_return_tracking_reader to postgres;
grant usage on schema public, private to sports_store_return_tracking_reader;
grant execute on function private.delivery_request_user_id(),
  private.current_app_role()
  to sports_store_return_tracking_reader;

-- Column-minimal SELECT only. No write privilege of any kind.
grant select (
  id, order_id, customer_id, status, reason, submitted_at, decision_reason,
  decision_at, inspection_started_at, inspected_at, closed_at, bank_name,
  account_number, refund_amount_vnd, refunded_at, transfer_evidence_path,
  updated_at
) on public.return_requests to sports_store_return_tracking_reader;
grant select (id, customer_id, subtotal_vnd, delivery_fee_vnd, address_detail)
  on public.orders to sports_store_return_tracking_reader;
grant select (
  id, return_request_id, order_id, order_item_id, actual_item_name,
  quantity_to_collect, created_at
) on public.return_items to sports_store_return_tracking_reader;
grant select (id, order_id, variant_label)
  on public.order_items to sports_store_return_tracking_reader;
grant select (
  id, return_request_id, kind, assigned_shipper_id, status, assigned_at,
  accepted_at, started_at, completed_at, created_at
) on public.delivery_tasks to sports_store_return_tracking_reader;
grant select (id, role, full_name, phone)
  on public.profiles to sports_store_return_tracking_reader;

create policy return_tracking_reader_returns
  on public.return_requests for select
  to sports_store_return_tracking_reader
  using (customer_id = (select private.delivery_request_user_id()));

create policy return_tracking_reader_orders
  on public.orders for select
  to sports_store_return_tracking_reader
  using (customer_id = (select private.delivery_request_user_id()));

create policy return_tracking_reader_return_items
  on public.return_items for select
  to sports_store_return_tracking_reader
  using (exists (
    select 1 from public.return_requests r
    where r.id = return_request_id
      and r.customer_id = (select private.delivery_request_user_id())
  ));

create policy return_tracking_reader_order_items
  on public.order_items for select
  to sports_store_return_tracking_reader
  using (exists (
    select 1 from public.orders o
    where o.id = order_id
      and o.customer_id = (select private.delivery_request_user_id())
  ));

create policy return_tracking_reader_tasks
  on public.delivery_tasks for select
  to sports_store_return_tracking_reader
  using (
    kind in ('return_pickup'::public.delivery_task_kind,
             'redelivery'::public.delivery_task_kind)
    and exists (
      select 1 from public.return_requests r
      where r.id = return_request_id
        and r.customer_id = (select private.delivery_request_user_id())
    )
  );

-- A profile row is visible only as the caller itself (role check) or as the
-- person assigned to an active task of the caller's own return.
create policy return_tracking_reader_profiles
  on public.profiles for select
  to sports_store_return_tracking_reader
  using (
    id = (select private.delivery_request_user_id())
    or exists (
      select 1
      from public.delivery_tasks t
      join public.return_requests r on r.id = t.return_request_id
      where t.assigned_shipper_id = profiles.id
        and t.kind in ('return_pickup'::public.delivery_task_kind,
                       'redelivery'::public.delivery_task_kind)
        and t.status in ('assigned'::public.delivery_task_status,
                         'accepted'::public.delivery_task_status,
                         'in_transit'::public.delivery_task_status)
        and r.customer_id = (select private.delivery_request_user_id())
    )
  );

create function public.get_my_return_request(p_return_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  l_uid uuid;
  l_return record;
  l_order record;
  l_pickup record;
  l_redelivery record;
  l_items jsonb;
  l_pickup_person jsonb;
  l_redelivery_person jsonb;
begin
  l_uid := (select private.delivery_request_user_id());
  if l_uid is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if p_return_id is null then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;
  if (select private.current_app_role()) is distinct from 'customer' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;

  -- RLS for this owner role already limits rows to the caller; the explicit
  -- predicate keeps the intent obvious. Another customer's id = not found.
  select r.id, r.order_id, r.status::text as status, r.reason::text as reason,
         r.submitted_at, r.decision_reason, r.decision_at,
         r.inspection_started_at, r.inspected_at, r.closed_at, r.bank_name,
         r.account_number, r.refund_amount_vnd, r.refunded_at,
         r.transfer_evidence_path, r.updated_at
    into l_return
  from public.return_requests r
  where r.id = p_return_id and r.customer_id = l_uid;
  if not found then
    raise exception using errcode = 'PT404', message = 'RETURN_NOT_FOUND';
  end if;

  select o.subtotal_vnd, o.delivery_fee_vnd, o.address_detail
    into l_order
  from public.orders o
  where o.id = l_return.order_id and o.customer_id = l_uid;

  select coalesce(jsonb_agg(jsonb_build_object(
           'name', i.actual_item_name,
           'variant_label', oi.variant_label,
           'quantity', i.quantity_to_collect
         ) order by i.created_at, i.id), '[]'::jsonb)
    into l_items
  from public.return_items i
  left join public.order_items oi on oi.id = i.order_item_id
  where i.return_request_id = p_return_id;

  select t.id, t.status::text as status, t.assigned_shipper_id,
         t.assigned_at, t.started_at, t.completed_at
    into l_pickup
  from public.delivery_tasks t
  where t.return_request_id = p_return_id
    and t.kind = 'return_pickup'::public.delivery_task_kind
  order by t.created_at desc, t.id desc
  limit 1;

  select t.id, t.status::text as status, t.assigned_shipper_id,
         t.assigned_at, t.started_at, t.completed_at
    into l_redelivery
  from public.delivery_tasks t
  where t.return_request_id = p_return_id
    and t.kind = 'redelivery'::public.delivery_task_kind
  order by t.created_at desc, t.id desc
  limit 1;

  if l_pickup.status in ('assigned', 'accepted', 'in_transit')
     and l_pickup.assigned_shipper_id is not null then
    select jsonb_build_object('name', coalesce(nullif(btrim(p.full_name), ''),
                                               'Nhân viên cửa hàng'),
                              'phone', nullif(btrim(p.phone), ''))
      into l_pickup_person
    from public.profiles p
    where p.id = l_pickup.assigned_shipper_id;
  end if;

  if l_redelivery.status in ('assigned', 'accepted', 'in_transit')
     and l_redelivery.assigned_shipper_id is not null then
    select jsonb_build_object('name', coalesce(nullif(btrim(p.full_name), ''),
                                               'Nhân viên cửa hàng'),
                              'phone', nullif(btrim(p.phone), ''))
      into l_redelivery_person
    from public.profiles p
    where p.id = l_redelivery.assigned_shipper_id;
  end if;

  return jsonb_build_object(
    'return_id', l_return.id,
    'order_id', l_return.order_id,
    'status', l_return.status,
    'reason', l_return.reason,
    'submitted_at', l_return.submitted_at,
    'decision_reason', l_return.decision_reason,
    'decision_at', l_return.decision_at,
    'received_at_store', l_return.inspection_started_at,
    'inspected_at', l_return.inspected_at,
    'closed_at', l_return.closed_at,
    'merchandise_vnd', l_order.subtotal_vnd,
    'delivery_fee_vnd', l_order.delivery_fee_vnd,
    'pickup_address', l_order.address_detail,
    'items', l_items,
    'pickup', case when l_pickup.id is null then null else jsonb_build_object(
      'status', l_pickup.status,
      'assigned_at', l_pickup.assigned_at,
      'collected_at', l_pickup.started_at,
      'completed_at', l_pickup.completed_at,
      'person', l_pickup_person
    ) end,
    'redelivery', case when l_redelivery.id is null then null
      else jsonb_build_object(
        'status', l_redelivery.status,
        'assigned_at', l_redelivery.assigned_at,
        'completed_at', l_redelivery.completed_at,
        'person', l_redelivery_person
      ) end,
    'refund', case
      when l_return.refunded_at is not null
       and l_return.refund_amount_vnd is not null
       and l_return.transfer_evidence_path is not null
      then jsonb_build_object(
        'amount_vnd', l_return.refund_amount_vnd,
        'refunded_at', l_return.refunded_at,
        'has_transfer_evidence', true
      ) end,
    'refund_bank_name', l_return.bank_name,
    'refund_account_masked', case
      when l_return.account_number is null then null
      else '••••' || right(l_return.account_number, 4) end,
    'server_now', pg_catalog.now()
  );
end;
$$;

grant create on schema public to sports_store_return_tracking_reader;
alter function public.get_my_return_request(uuid)
  owner to sports_store_return_tracking_reader;
revoke create on schema public from sports_store_return_tracking_reader;
revoke all on function public.get_my_return_request(uuid)
  from public, anon, service_role, sports_store_return_tracking_reader;
grant execute on function public.get_my_return_request(uuid) to authenticated;

comment on function public.get_my_return_request(uuid) is
  'MH14 customer-only read of one owned return: status, server timestamps, approved items, assigned pickup/redelivery person (active tasks only), refund only when recorded; masked bank account.';

notify pgrst, 'reload schema';
