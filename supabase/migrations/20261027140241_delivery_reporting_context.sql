-- P07.5: narrow read model for reporting controls on restricted MH11 tasks.
-- No base-table grant/policy is broadened. Reuse the P07.4 constrained owner
-- and custody validator; never return its internal order/holder/price payload.
create function public.get_my_delivery_reporting_context(p_task_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  l_actor uuid := (select private.delivery_request_user_id());
  l_role text;
  l_order uuid;
  l_kind public.delivery_task_kind;
  l_status public.delivery_task_status;
  l_context jsonb;
  l_handover jsonb;
  l_incident jsonb;
  l_handover_error text;
  l_incident_error text;
  l_reported boolean := false;
  l_items jsonb := '[]'::jsonb;
begin
  if l_actor is null then
    raise exception using errcode='42501',message='AUTH_REQUIRED';
  end if;
  if p_task_id is null then
    raise exception using errcode='22023',message='INVALID_ARGUMENT';
  end if;
  select role::text into l_role from public.profiles where id=l_actor for share;
  if l_role is distinct from 'shipper' then
    raise exception using errcode='42501',message='PERMISSION_DENIED';
  end if;
  select order_id,kind into l_order,l_kind from public.delivery_tasks
    where id=p_task_id and assigned_shipper_id=l_actor;
  if not found then
    raise exception using errcode='42501',message='NOT_FOUND_OR_FORBIDDEN';
  end if;
  if l_kind <> 'outbound'::public.delivery_task_kind then
    raise exception using errcode='PT409',message='UNSUPPORTED_TASK_KIND';
  end if;
  -- Same short transaction boundary/order as P04/P05/P07 outcomes. This read
  -- cannot race a manager decision and combine two different custody epochs.
  perform pg_advisory_xact_lock(hashtextextended(
    'sports_store.complete_outbound_delivery:order:'||l_order::text,0));
  perform 1 from public.orders where id=l_order for share;
  if not found then
    raise exception using errcode='42501',message='NOT_FOUND_OR_FORBIDDEN';
  end if;
  perform 1 from public.delivery_tasks where order_id=l_order and kind='outbound'
    order by id for share;
  select status into l_status from public.delivery_tasks
    where id=p_task_id and assigned_shipper_id=l_actor;
  if not found then
    raise exception using errcode='42501',message='NOT_FOUND_OR_FORBIDDEN';
  end if;
  -- MH11 history never unlocks the newer attempt's reporting/item snapshot.
  -- Use the canonical latest task, even where a same-holder incident mutation
  -- can legitimately retain its original task reference for audit history.
  if exists(select 1 from public.delivery_tasks newer
    join public.delivery_tasks target on target.id=p_task_id
    where newer.order_id=l_order and newer.kind='outbound'
      and newer.attempt_number > target.attempt_number) then
    return jsonb_build_object(
      'task_id',p_task_id,'task_status',l_status::text,'order_status',null,
      'can_handover',false,'can_incident',false,'handover_reported',false,
      'handover_block_reason','STATE_CONFLICT',
      'incident_block_reason','STATE_CONFLICT','items','[]'::jsonb);
  end if;
  perform 1 from public.cod_collections
    where order_id=l_order and shipper_id=l_actor for share;
  if not found then
    return jsonb_build_object(
      'task_id',p_task_id,'task_status',l_status::text,'order_status',null,
      'can_handover',false,'can_incident',false,'handover_reported',false,
      'handover_block_reason','CUSTODY_UNRESOLVED',
      'incident_block_reason','CUSTODY_UNRESOLVED','items','[]'::jsonb);
  end if;
  -- Known custody/state conflicts mean no action. Authentication, SQL errors
  -- and unexpected server failures must propagate; never manufacture a context.
  begin
    l_incident := private.validate_outbound_report_context(
      p_task_id,'report_delivery_incident');
  exception when sqlstate 'PT409' then
    get stacked diagnostics l_incident_error = message_text;
    if l_incident_error not in ('STATE_CONFLICT','CUSTODY_UNRESOLVED','ITEMS_MISMATCH') then
      raise;
    end if;
  end;
  begin
    l_handover := private.validate_outbound_report_context(
      p_task_id,'report_store_handover');
  exception when sqlstate 'PT409' then
    get stacked diagnostics l_handover_error = message_text;
    if l_handover_error not in ('STATE_CONFLICT','CUSTODY_UNRESOLVED','ITEMS_MISMATCH') then
      raise;
    end if;
  end;
  l_context := coalesce(l_incident,l_handover);
  if l_context is not null then
    select exists(select 1 from private.outbound_handover_reports
      where order_id=l_order and holder_id=l_actor) into l_reported;
  end if;
  if l_handover is not null and not l_reported then
    select coalesce(jsonb_agg(jsonb_build_object(
      'order_item_id',item->>'order_item_id',
      'product_name',item->>'product_name',
      'variant_label',item->>'variant_label',
      'quantity',(item->>'quantity')::integer
    ) order by item->>'order_item_id'),'[]'::jsonb) into l_items
    from jsonb_array_elements(l_handover->'items_snapshot') item;
  end if;
  return jsonb_build_object(
    'task_id',p_task_id,'task_status',l_status::text,
    'order_status',l_context->>'order_status',
    'can_handover',l_handover is not null and not l_reported,
    'can_incident',l_incident is not null,'handover_reported',l_reported,
    'handover_block_reason',case when l_reported then 'STATE_CONFLICT' else l_handover_error end,
    'incident_block_reason',l_incident_error,'items',l_items);
end;
$$;
grant create on schema public to sports_store_outbound_reporting_writer;
alter function public.get_my_delivery_reporting_context(uuid)
  owner to sports_store_outbound_reporting_writer;
revoke create on schema public from sports_store_outbound_reporting_writer;
revoke all on function public.get_my_delivery_reporting_context(uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.get_my_delivery_reporting_context(uuid)
  to authenticated;
comment on function public.get_my_delivery_reporting_context(uuid) is
  'P07.5 outbound custody-authorized report controls; no contact, order ID, money or Storage assets.';
notify pgrst,'reload schema';
