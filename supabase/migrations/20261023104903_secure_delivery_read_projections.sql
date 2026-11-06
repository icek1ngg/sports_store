-- P01.1: read projections only; no dispatch, assignment or state write API.
-- Base-table access remains available to the existing customer/manager scopes.
-- Shippers use explicitly masked, task-scoped projections instead.
-- The function owner is a dedicated NOLOGIN/NOBYPASSRLS role: SECURITY DEFINER
-- supplies only the column reads required by these projections, NOT an RLS bypass.

-- Roles are cluster-wide and can survive a local database rebuild. Reuse only
-- the exact locked-down role managed by this migration, never an unrelated role.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'sports_store_delivery_reader') then
    create role sports_store_delivery_reader nologin noinherit nobypassrls;
    comment on role sports_store_delivery_reader is 'sports_store P01.1 read projection owner';
  elsif not exists (
    select 1 from pg_roles r
    where r.rolname = 'sports_store_delivery_reader'
      and not r.rolcanlogin and not r.rolsuper and not r.rolbypassrls
      and not r.rolinherit and not r.rolcreaterole and not r.rolcreatedb
      and not r.rolreplication
      and shobj_description(r.oid, 'pg_authid') = 'sports_store P01.1 read projection owner'
  ) then
    raise exception 'P01.1 projection role already exists with unexpected configuration';
  end if;
end;
$$;
grant sports_store_delivery_reader to postgres;
grant usage on schema public, auth to sports_store_delivery_reader;
grant execute on function auth.uid() to sports_store_delivery_reader;
grant select (id, role) on public.profiles to sports_store_delivery_reader;
grant select (
  id, order_id, return_request_id, kind, assigned_shipper_id, status,
  attempt_number, amount_to_collect_vnd, destination_name, destination_phone,
  destination_address, destination_latitude, destination_longitude,
  assigned_at, accepted_at, started_at, completed_at, created_at
) on public.delivery_tasks to sports_store_delivery_reader;
grant select (
  id, order_id, product_name, variant_label, attributes, quantity,
  unit_price_vnd, line_total_vnd
) on public.order_items to sports_store_delivery_reader;
grant select (
  id, return_request_id, actual_item_name, quantity_to_collect, quantity_collected
) on public.return_items to sports_store_delivery_reader;

-- Do not use any historical task to grant a shipper base-table access.
alter policy tasks_read on public.delivery_tasks
  using ((select private.current_app_role()) = 'manager');
alter policy order_items_read on public.order_items
  using (
    (select private.current_app_role()) = 'manager'
    or exists (
      select 1 from public.orders o
      where o.id = order_items.order_id and o.customer_id = (select auth.uid())
    )
  );
alter policy return_items_read on public.return_items
  using (
    (select private.current_app_role()) = 'manager'
    or exists (
      select 1 from public.return_requests r
      where r.id = return_items.return_request_id and r.customer_id = (select auth.uid())
    )
  );
alter policy attempts_read on public.delivery_attempts
  using (
    (select private.current_app_role()) = 'manager'
    or exists (
      select 1 from public.orders o
      where o.id = delivery_attempts.order_id and o.customer_id = (select auth.uid())
    )
  );
-- Generic events contain unstructured reasons and are not a safe historical DTO.
alter policy business_events_read on public.business_events
  using ((select private.current_app_role()) = 'manager');

create policy delivery_reader_profile on public.profiles
  for select to sports_store_delivery_reader
  using (id = (select auth.uid()));

create policy delivery_reader_tasks on public.delivery_tasks
  for select to sports_store_delivery_reader
  using (
    assigned_shipper_id = (select auth.uid())
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.role = 'shipper'
    )
  );

create policy delivery_reader_order_items on public.order_items
  for select to sports_store_delivery_reader
  using (
    exists (
      select 1 from public.delivery_tasks t
      where t.order_id = order_items.order_id
        and t.kind = 'outbound'
        and t.status in ('assigned', 'accepted', 'in_transit')
        and t.assigned_shipper_id = (select auth.uid())
    )
  );
create policy delivery_reader_return_items on public.return_items
  for select to sports_store_delivery_reader
  using (
    exists (
      select 1 from public.delivery_tasks t
      where t.return_request_id = return_items.return_request_id
        and t.kind = 'return_pickup'
        and t.status in ('assigned', 'accepted', 'in_transit')
        and t.assigned_shipper_id = (select auth.uid())
    )
  );

create function public.read_my_delivery_tasks(p_task_id uuid default null)
returns table (
  task_id uuid,
  kind public.delivery_task_kind,
  status public.delivery_task_status,
  attempt_number smallint,
  snapshot_scope text,
  order_id uuid,
  return_request_id uuid,
  amount_to_collect_vnd bigint,
  destination_name text,
  destination_phone text,
  destination_address text,
  destination_latitude numeric,
  destination_longitude numeric,
  assigned_at timestamptz,
  accepted_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  item_source text
)
language sql stable security definer
set search_path = ''
as $$
  select t.id, t.kind, t.status, t.attempt_number,
    case
      when t.status in ('assigned', 'accepted', 'in_transit') then 'current'
      when t.status in ('delivered', 'cancelled', 'returned_to_store') then 'history'
      else 'restricted'
    end,
    case when t.status in ('assigned', 'accepted', 'in_transit') then t.order_id end,
    case when t.status in ('assigned', 'accepted', 'in_transit') then t.return_request_id end,
    case when t.status in ('assigned', 'accepted', 'in_transit') then t.amount_to_collect_vnd end,
    case when t.status in ('assigned', 'accepted', 'in_transit') then t.destination_name end,
    case when t.status in ('assigned', 'accepted', 'in_transit') then t.destination_phone end,
    case when t.status in ('assigned', 'accepted', 'in_transit') then t.destination_address end,
    case when t.status in ('assigned', 'accepted', 'in_transit') then t.destination_latitude end,
    case when t.status in ('assigned', 'accepted', 'in_transit') then t.destination_longitude end,
    case when t.status in ('assigned', 'accepted', 'in_transit') then t.assigned_at end,
    case when t.status in ('assigned', 'accepted', 'in_transit') then t.accepted_at end,
    case when t.status in ('assigned', 'accepted', 'in_transit') then t.started_at end,
    t.completed_at,
    case
      when t.status not in ('assigned', 'accepted', 'in_transit') then 'unavailable'
      when t.kind = 'outbound' then 'order_snapshot'
      when t.kind = 'return_pickup' then 'return_plan'
      else 'unavailable_redelivery_plan'
    end
  from public.delivery_tasks t
  where t.assigned_shipper_id = (select auth.uid())
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.role = 'shipper'
    )
    and (p_task_id is null or t.id = p_task_id)
  order by t.created_at desc, t.id desc;
$$;

create function public.read_my_delivery_task_items(p_task_id uuid)
returns table (
  item_id uuid,
  item_source text,
  product_name text,
  variant_label text,
  attributes jsonb,
  quantity bigint,
  quantity_collected bigint,
  unit_price_vnd bigint,
  line_total_vnd bigint
)
language sql stable security definer
set search_path = ''
as $$
  select i.id, 'order_snapshot'::text, i.product_name, i.variant_label,
    i.attributes, i.quantity, null::bigint, i.unit_price_vnd, i.line_total_vnd
  from public.delivery_tasks t
  join public.order_items i on i.order_id = t.order_id
  where t.id = p_task_id and t.assigned_shipper_id = (select auth.uid())
    and t.kind = 'outbound'
    and t.status in ('assigned', 'accepted', 'in_transit')
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.role = 'shipper'
    )
  union all
  select i.id, 'return_plan'::text, i.actual_item_name, null::text,
    null::jsonb, i.quantity_to_collect, i.quantity_collected,
    null::bigint, null::bigint
  from public.delivery_tasks t
  join public.return_items i on i.return_request_id = t.return_request_id
  where t.id = p_task_id and t.assigned_shipper_id = (select auth.uid())
    and t.kind = 'return_pickup'
    and t.status in ('assigned', 'accepted', 'in_transit')
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.role = 'shipper'
    )
  order by 1;
$$;

-- Ownership transfer needs CREATE on the schema only during this migration.
-- The owner cannot log in, bypass RLS, write tables, read orders/returns/COD,
-- or be assumed by an API role. All relations/functions are schema-qualified.
grant create on schema public to sports_store_delivery_reader;
alter function public.read_my_delivery_tasks(uuid) owner to sports_store_delivery_reader;
alter function public.read_my_delivery_task_items(uuid) owner to sports_store_delivery_reader;
revoke create on schema public from sports_store_delivery_reader;
revoke all on function public.read_my_delivery_tasks(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.read_my_delivery_task_items(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.read_my_delivery_tasks(uuid) to authenticated;
grant execute on function public.read_my_delivery_task_items(uuid) to authenticated;

comment on function public.read_my_delivery_tasks(uuid) is
  'P01.1 shipper-only current assignment projection; terminal rows are masked history, not immutable assignment history.';
comment on function public.read_my_delivery_task_items(uuid) is
  'P01.1 task-scoped active outbound/pickup items only; redelivery plan remains an explicit integration dependency.';

notify pgrst, 'reload schema';
