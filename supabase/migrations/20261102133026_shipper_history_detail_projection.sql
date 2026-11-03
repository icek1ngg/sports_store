-- P03.2: immutable history detail for the shipper who held the task.
--
-- P01.1 intentionally masks terminal task projections.  That is useful for
-- a list that can contain stale IDs, but it makes the shipper's own completed
-- or failed task impossible to reconcile in MH11.  This additive RPC keeps the
-- old function and its default strict contract unchanged.  Its opt-in caller
-- accepts the full terminal snapshot and returns only the
-- task's stored snapshots, its order items/return plan and the narrow COD
-- ledger fields needed to explain money; it never reads customer/order PII
-- from the live order row and never permits a write.

grant select (
  order_id, shipper_id, status, expected_amount_vnd,
  collected_amount_vnd, received_amount_vnd, collected_at,
  handed_over_at, received_at
) on public.cod_collections to sports_store_delivery_reader;

create policy delivery_reader_cod_history_read
  on public.cod_collections
  for select to sports_store_delivery_reader
  using (shipper_id = (select auth.uid()));

-- The projection owner is already a NOLOGIN/NOBYPASSRLS role.  Its only new
-- base-table access is used by the function below after the task ownership
-- predicate has been applied.  Clients still receive no table grant.
alter policy delivery_reader_order_items on public.order_items
  using (
    exists (
      select 1
      from public.delivery_tasks t
      where t.order_id = order_items.order_id
        and t.kind = 'outbound'::public.delivery_task_kind
        and t.assigned_shipper_id = (select auth.uid())
    )
  );

alter policy delivery_reader_return_items on public.return_items
  using (
    exists (
      select 1
      from public.delivery_tasks t
      where t.return_request_id = return_items.return_request_id
        and t.kind = 'return_pickup'::public.delivery_task_kind
        and t.assigned_shipper_id = (select auth.uid())
    )
  );

alter policy redelivery_task_items_reader_read
  on private.redelivery_task_items
  using (
    current_user = 'sports_store_delivery_reader'
    and exists (
      select 1
      from public.delivery_tasks t
      where t.id = redelivery_task_items.task_id
        and t.kind = 'redelivery'::public.delivery_task_kind
        and t.assigned_shipper_id = (select auth.uid())
    )
  );

create or replace function public.get_my_delivery_task_history(p_task_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  l_actor_id uuid;
  -- Keep this record aligned with the delivery_reader column grant.  A
  -- `select t.*` here would accidentally require assigned_by/failure_reason
  -- and make the secured projection fail at runtime.
  l_task record;
  l_items jsonb;
  l_cod jsonb;
  l_can_retry boolean := false;
begin
  if p_task_id is null then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;

  l_actor_id := (select auth.uid());
  if l_actor_id is null
     or not exists (
       select 1
       from public.profiles p
       where p.id = l_actor_id
         and p.role = 'shipper'::public.user_role
     ) then
    raise exception using errcode = '42501', message = 'DELIVERY_TASK_FORBIDDEN';
  end if;

  -- Assignment is the authorization boundary for both live and terminal
  -- rows.  A former shipper cannot use a historical UUID after reassignment.
  select t.id, t.order_id, t.return_request_id, t.kind, t.assigned_shipper_id,
         t.status, t.attempt_number, t.amount_to_collect_vnd,
         t.destination_name, t.destination_phone, t.destination_address,
         t.destination_latitude, t.destination_longitude, t.assigned_at,
         t.accepted_at, t.started_at, t.completed_at
    into l_task
  from public.delivery_tasks t
  where t.id = p_task_id
    and t.assigned_shipper_id = l_actor_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;

  -- A pending-assignment row has no shipper-facing history yet.  Keep it
  -- indistinguishable from a missing task instead of turning an assignment
  -- placeholder into an unmasked detail response.
  if l_task.status = 'pending_assignment'::public.delivery_task_status then
    raise exception using errcode = 'P0002', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;

  -- Keep the history view read-only while exposing the server's structural
  -- retry eligibility.  The client must never infer this from `failed` alone:
  -- manager early-return and an already-created attempt 2 both make retry
  -- invalid even though task 1 remains in immutable history.
  if l_task.kind = 'outbound'::public.delivery_task_kind
     and l_task.status = 'failed'::public.delivery_task_status
     and l_task.attempt_number = 1
     and l_task.order_id is not null
     and private.outbound_retry_order_is_awaiting_redelivery(l_task.order_id)
     and not exists (
       select 1
       from public.delivery_tasks successor
       where successor.order_id = l_task.order_id
         and successor.kind = 'outbound'::public.delivery_task_kind
         and successor.attempt_number = 2
     ) then
    l_can_retry := true;
  end if;

  if l_task.kind = 'outbound'::public.delivery_task_kind then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'item_id', i.id,
          'item_source', 'order_snapshot',
          'product_name', i.product_name,
          'variant_label', i.variant_label,
          'attributes', i.attributes,
          'quantity', i.quantity,
          'quantity_collected', null,
          'unit_price_vnd', i.unit_price_vnd,
          'line_total_vnd', i.line_total_vnd,
          'image_url', i.product_image_url
        )
        order by i.id
      ),
      '[]'::jsonb
    )
      into l_items
    from public.order_items i
    where i.order_id = l_task.order_id;
  elsif l_task.kind = 'return_pickup'::public.delivery_task_kind then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'item_id', i.id,
          'item_source', 'return_plan',
          'product_name', i.actual_item_name,
          'variant_label', null,
          'attributes', null,
          'quantity', i.quantity_to_collect,
          'quantity_collected', i.quantity_collected,
          'unit_price_vnd', null,
          'line_total_vnd', null,
          'image_url', null
        )
        order by i.id
      ),
      '[]'::jsonb
    )
      into l_items
    from public.return_items i
    where i.return_request_id = l_task.return_request_id;
  elsif l_task.kind = 'redelivery'::public.delivery_task_kind then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'item_id', i.return_item_id,
          'item_source', 'return_plan',
          'product_name', i.actual_item_name,
          'variant_label', i.variant_label,
          'attributes', i.attributes,
          'quantity', i.quantity,
          'quantity_collected', null,
          'unit_price_vnd', null,
          'line_total_vnd', null,
          'image_url', null
        )
        order by i.return_item_id
      ),
      '[]'::jsonb
    )
      into l_items
    from private.redelivery_task_items i
    where i.task_id = l_task.id
      and i.order_id = l_task.order_id
      and i.return_request_id = l_task.return_request_id;
  else
    -- Unknown future task kinds remain bounded to an empty approved projection.
    l_items := '[]'::jsonb;
  end if;

  if l_task.kind <> 'outbound'::public.delivery_task_kind
     or l_task.order_id is null then
    l_cod := null;
  else
    select jsonb_build_object(
      'status', c.status,
      'expected_amount_vnd', c.expected_amount_vnd,
      'collected_amount_vnd', c.collected_amount_vnd,
      'received_amount_vnd', c.received_amount_vnd,
      'collected_at', c.collected_at,
      'handed_over_at', c.handed_over_at,
      'received_at', c.received_at
    )
      into l_cod
    from public.cod_collections c
    where c.order_id = l_task.order_id
      and c.shipper_id = l_actor_id;
  end if;

  return jsonb_build_object(
    'task', jsonb_build_object(
      'task_id', l_task.id,
      'kind', l_task.kind,
      'status', l_task.status,
      'attempt_number', l_task.attempt_number,
      -- `history` is full only through this explicit history RPC; the legacy
      -- get_my_delivery_task() function still returns its masked history DTO.
      'snapshot_scope', case
        when l_task.status in ('assigned', 'accepted', 'in_transit')
          then 'current'
        when l_task.status in (
          'delivered', 'failed', 'cancelled', 'returned_to_store',
          'manager_action_required'
        ) then 'history'
        else 'restricted'
      end,
      'order_id', l_task.order_id,
      'return_request_id', l_task.return_request_id,
      'amount_to_collect_vnd', l_task.amount_to_collect_vnd,
      'destination_name', l_task.destination_name,
      'destination_phone', l_task.destination_phone,
      'destination_address', l_task.destination_address,
      'destination_latitude', l_task.destination_latitude,
      'destination_longitude', l_task.destination_longitude,
      'assigned_at', l_task.assigned_at,
      'accepted_at', l_task.accepted_at,
      'started_at', l_task.started_at,
      'completed_at', l_task.completed_at,
      'item_source', case
        when l_task.status in ('assigned', 'accepted', 'in_transit', 'delivered', 'failed', 'cancelled', 'returned_to_store', 'manager_action_required')
             and l_task.kind = 'outbound' then 'order_snapshot'
        when l_task.status in ('assigned', 'accepted', 'in_transit', 'delivered', 'failed', 'cancelled', 'returned_to_store', 'manager_action_required')
             and l_task.kind = 'return_pickup' then 'return_plan'
        when l_task.kind = 'redelivery'
             and exists (
               select 1 from private.redelivery_task_items ri
               where ri.task_id = l_task.id
             ) then 'return_plan'
        else 'unavailable_redelivery_plan'
      end
    ),
    'items', l_items,
    'cod', l_cod,
    'capabilities', jsonb_build_object('can_retry', l_can_retry),
    'notes', null,
    'notes_source', 'unavailable_schema',
    'as_of', statement_timestamp()
  );
end;
$$;

grant create on schema public to sports_store_delivery_reader;
alter function public.get_my_delivery_task_history(uuid)
  owner to sports_store_delivery_reader;
revoke create on schema public from sports_store_delivery_reader;
revoke all on function public.get_my_delivery_task_history(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_my_delivery_task_history(uuid)
  to authenticated;

comment on function public.get_my_delivery_task_history(uuid) is
  'P03.2 shipper-only immutable task history/detail with recipient/item snapshots and narrow COD ledger status; assignment remains the authorization boundary.';

notify pgrst, 'reload schema';
