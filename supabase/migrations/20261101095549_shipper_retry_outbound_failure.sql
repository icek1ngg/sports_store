-- P07.2.1: allow the holder of outbound attempt 1 to request the existing
-- idempotent same-holder retry transition without a manager approval step.

do $migration$
declare
  l_definition text;
  l_role_guard constant text := $needle$
  if l_actor_role is distinct from 'manager' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;$needle$;
  l_role_replacement constant text := $replacement$
  if not coalesce(
      l_actor_role = 'manager'
      or (l_actor_role = 'shipper' and l_decision = 'retry'),
      false
    ) then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;$replacement$;
  l_cod_marker constant text := $needle$
  select c.order_id, c.shipper_id, c.status, c.expected_amount_vnd,
         c.collected_amount_vnd, c.received_amount_vnd, c.collected_at,
         c.collected_by, c.handed_over_at, c.received_at, c.received_by
    into l_cod
  from public.cod_collections c
  where c.order_id = p_order_id
  for update;$needle$;
  l_actor_check constant text := $replacement$
  if l_actor_role = 'shipper'
     and l_failed_shipper_id is distinct from l_actor_id then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;

  select c.order_id, c.shipper_id, c.status, c.expected_amount_vnd,
         c.collected_amount_vnd, c.received_amount_vnd, c.collected_at,
         c.collected_by, c.handed_over_at, c.received_at, c.received_by
    into l_cod
  from public.cod_collections c
  where c.order_id = p_order_id
  for update;$replacement$;
begin
  select pg_catalog.pg_get_functiondef(
    'public.decide_outbound_retry(uuid,uuid,text,uuid,uuid)'::pg_catalog.regprocedure
  ) into l_definition;
  if l_definition is null then
    raise exception 'P07.2.1 requires public.decide_outbound_retry(uuid,uuid,text,uuid,uuid)';
  end if;
  if pg_catalog.strpos(l_definition, l_role_guard) < 1 then
    raise exception 'P07.2.1 could not locate the manager role guard';
  end if;
  if (
      pg_catalog.length(l_definition)
      - pg_catalog.length(pg_catalog.replace(l_definition, l_role_guard, ''))
    ) / pg_catalog.length(l_role_guard) <> 2 then
    raise exception 'P07.2.1 expected two manager role guards';
  end if;
  l_definition := pg_catalog.replace(l_definition, l_role_guard, l_role_replacement);
  if pg_catalog.strpos(l_definition, l_cod_marker) < 1 then
    raise exception 'P07.2.1 could not locate the COD lock marker';
  end if;
  l_definition := pg_catalog.replace(l_definition, l_cod_marker, l_actor_check);
  execute l_definition;
end;
$migration$;

-- Keep failed attempt 1 visible/actionable in the same task-list contract.
-- The projection still masks terminal PII; the task id is sufficient for the
-- shipper-only retry RPC above. This guarded replacement fails closed when a
-- production function has drifted instead of silently changing its contract.
do $migration$
declare
  l_definition text;
  l_state_guard constant text := $needle$
  if l_state_group is not null
     and l_state_group not in ('waiting', 'in_transit', 'completed') then$needle$;
  l_state_replacement constant text := $replacement$
  if l_state_group is not null
     and l_state_group not in ('waiting', 'in_transit', 'completed', 'failed') then$replacement$;
  l_group_guard constant text := $needle$
      or (l_state_group = 'completed' and status in ('delivered', 'returned_to_store'))$needle$;
  l_group_replacement constant text := $replacement$
      or (l_state_group = 'completed' and status in ('delivered', 'returned_to_store'))
      or (l_state_group = 'failed' and status = 'failed')$replacement$;
  l_count_guard constant text := $needle$
      count(*) filter (where status in ('delivered', 'returned_to_store'))::integer as completed,
      count(*) filter (
        where status not in (
          'assigned', 'accepted', 'in_transit', 'delivered', 'returned_to_store'
        )
      )::integer as ungrouped$needle$;
  l_count_replacement constant text := $replacement$
      count(*) filter (where status in ('delivered', 'returned_to_store'))::integer as completed,
      count(*) filter (where status = 'failed')::integer as failed,
      count(*) filter (
        where status not in (
          'assigned', 'accepted', 'in_transit', 'delivered', 'returned_to_store'
        )
      )::integer as ungrouped$replacement$;
  l_counts_guard constant text := $needle$
      'completed', count_rows.completed,
      'ungrouped', count_rows.ungrouped$needle$;
  l_counts_replacement constant text := $replacement$
      'completed', count_rows.completed,
      'failed', count_rows.failed,
      'ungrouped', count_rows.ungrouped$replacement$;
begin
  select pg_catalog.pg_get_functiondef(
    'public.list_my_delivery_tasks(public.delivery_task_kind,text,text,integer,text)'::pg_catalog.regprocedure
  ) into l_definition;
  if l_definition is null then
    raise exception 'P07.2.1 requires public.list_my_delivery_tasks(delivery_task_kind,text,text,integer,text)';
  end if;
  if pg_catalog.strpos(l_definition, l_state_guard) < 1
     or pg_catalog.strpos(l_definition, l_group_guard) < 1
     or pg_catalog.strpos(l_definition, l_count_guard) < 1
     or pg_catalog.strpos(l_definition, l_counts_guard) < 1 then
    raise exception 'P07.2.1 could not locate the task-list grouping contract';
  end if;
  l_definition := pg_catalog.replace(l_definition, l_state_guard, l_state_replacement);
  l_definition := pg_catalog.replace(l_definition, l_group_guard, l_group_replacement);
  l_definition := pg_catalog.replace(l_definition, l_count_guard, l_count_replacement);
  l_definition := pg_catalog.replace(l_definition, l_counts_guard, l_counts_replacement);
  execute l_definition;
end;
$migration$;

-- The failure projection may mask order_id after task 1 fails. Derive it from
-- the assigned failed task so the client cannot retry another order or shipper.
create or replace function public.retry_outbound_delivery_task(
  p_task_id uuid,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  l_actor_id uuid;
  l_actor_role text;
  l_order_id uuid;
begin
  l_actor_id := (select private.delivery_request_user_id());
  if l_actor_id is null or p_task_id is null or p_request_id is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  -- Keep the server-managed shipper role lock while the nested decision RPC
  -- runs. A former shipper must not reach the manager-capable RPC after a
  -- concurrent role change, and a role update waits for this transaction.
  select p.role::text into l_actor_role
  from public.profiles p
  where p.id = l_actor_id
  for share;
  if l_actor_role is distinct from 'shipper' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;
  select t.order_id into l_order_id
  from public.delivery_tasks t
  where t.id = p_task_id
    and t.kind = 'outbound'::public.delivery_task_kind
    and t.attempt_number = 1
    and t.status = 'failed'::public.delivery_task_status
    and t.assigned_shipper_id = l_actor_id;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  return public.decide_outbound_retry(
    l_order_id, p_request_id, 'retry', p_task_id, null
  );
end;
$$;

grant create on schema public to sports_store_outbound_retry_writer;
alter function public.retry_outbound_delivery_task(uuid, uuid)
  owner to sports_store_outbound_retry_writer;
revoke create on schema public from sports_store_outbound_retry_writer;
-- The wrapper is SECURITY DEFINER under the same restricted writer role.  The
-- existing P07.2 migration revokes that role's EXECUTE on the nested decision
-- RPC, so restore only this narrowly scoped function privilege; without it a
-- valid shipper retry fails before the decision RPC can enforce its guards.
grant execute on function public.decide_outbound_retry(uuid, uuid, text, uuid, uuid)
  to sports_store_outbound_retry_writer;
revoke all on function public.retry_outbound_delivery_task(uuid, uuid)
  from public, anon, service_role, sports_store_outbound_retry_writer;
grant execute on function public.retry_outbound_delivery_task(uuid, uuid)
  to authenticated;

comment on function public.retry_outbound_delivery_task(uuid, uuid) is
  'P07.2.1 shipper-only same-holder retry after outbound attempt 1 failure; delegates to the locked idempotent retry transition.';

comment on function public.decide_outbound_retry(uuid, uuid, text, uuid, uuid) is
  'P07.2 manager retry/return decision plus assigned failed-task holder retry; retry creates same-holder task 2 without dispatch/custody and return may cancel an unstarted task 2 through an append-only decision permit.';

notify pgrst, 'reload schema';
