-- P04.2: one shipper action atomically accepts custody and starts outbound
-- delivery. The existing P04.1 RPCs remain the source of truth for all
-- custody, dispatch, COD and attempt checks; this wrapper only composes them
-- in one transaction and gives each child command a stable idempotency key.

create or replace function public.accept_and_start_delivery_task(
  p_task_id uuid,
  p_request_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  l_actor_id uuid;
  l_accept_request_id uuid;
  l_start_request_id uuid;
  l_accept_response jsonb;
  l_start_response jsonb;
begin
  l_actor_id := (select auth.uid());
  if l_actor_id is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if p_task_id is null or p_request_id is null then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;

  -- Deterministic child keys avoid a second command row when the
  -- network response is ambiguous. The child calls run in this same
  -- transaction, so a failed start rolls back the accept and dispatch too.
  l_accept_request_id := (
    pg_catalog.substr(pg_catalog.md5(p_request_id::text || ':accept_and_start:accept'), 1, 8) || '-' ||
    pg_catalog.substr(pg_catalog.md5(p_request_id::text || ':accept_and_start:accept'), 9, 4) || '-' ||
    pg_catalog.substr(pg_catalog.md5(p_request_id::text || ':accept_and_start:accept'), 13, 4) || '-' ||
    pg_catalog.substr(pg_catalog.md5(p_request_id::text || ':accept_and_start:accept'), 17, 4) || '-' ||
    pg_catalog.substr(pg_catalog.md5(p_request_id::text || ':accept_and_start:accept'), 21, 12)
  )::uuid;
  l_start_request_id := (
    pg_catalog.substr(pg_catalog.md5(p_request_id::text || ':accept_and_start:start'), 1, 8) || '-' ||
    pg_catalog.substr(pg_catalog.md5(p_request_id::text || ':accept_and_start:start'), 9, 4) || '-' ||
    pg_catalog.substr(pg_catalog.md5(p_request_id::text || ':accept_and_start:start'), 13, 4) || '-' ||
    pg_catalog.substr(pg_catalog.md5(p_request_id::text || ':accept_and_start:start'), 17, 4) || '-' ||
    pg_catalog.substr(pg_catalog.md5(p_request_id::text || ':accept_and_start:start'), 21, 12)
  )::uuid;

  -- Acquire both child command locks in a deterministic order before either
  -- nested RPC locks the order row. This prevents an external direct start
  -- from inverting the wrapper's lock order during a concurrent retry.
  if l_accept_request_id < l_start_request_id then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      'sports_store.outbound.command:' || l_actor_id::text || ':' || l_accept_request_id::text, 0));
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      'sports_store.outbound.command:' || l_actor_id::text || ':' || l_start_request_id::text, 0));
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      'sports_store.outbound.command:' || l_actor_id::text || ':' || l_start_request_id::text, 0));
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      'sports_store.outbound.command:' || l_actor_id::text || ':' || l_accept_request_id::text, 0));
  end if;

  l_accept_response := public.accept_delivery_task(
    p_task_id, l_accept_request_id
  );
  l_start_response := public.start_delivery_task(
    p_task_id, l_start_request_id
  );

  return pg_catalog.jsonb_set(
    pg_catalog.jsonb_set(l_start_response, '{operation}', '"accept_and_start"'::jsonb),
    '{request_id}', pg_catalog.to_jsonb(p_request_id)
  );
end;
$$;

revoke all on function public.accept_and_start_delivery_task(uuid, uuid)
  from public, anon, service_role;
grant execute on function public.accept_and_start_delivery_task(uuid, uuid)
  to authenticated;

comment on function public.accept_and_start_delivery_task(uuid, uuid) is
  'P04.2 invoker wrapper atomically composes the guarded shipper custody acceptance and outbound start RPCs; child request keys are deterministic for replay.';

-- The read projection intentionally masks terminal order IDs. This narrow
-- boolean helper lets the list owner distinguish a first failure awaiting
-- retry from a manager early-return decision without exposing order data.
grant usage on schema private to sports_store_delivery_reader;
create or replace function private.outbound_retry_order_is_awaiting_redelivery(
  p_order_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.orders o
    where o.id = p_order_id
      and o.status = 'awaiting_redelivery'::public.order_status
  );
$$;
grant create on schema private to sports_store_outbound_retry_writer;
alter function private.outbound_retry_order_is_awaiting_redelivery(uuid)
  owner to sports_store_outbound_retry_writer;
revoke create on schema private from sports_store_outbound_retry_writer;
revoke all on function private.outbound_retry_order_is_awaiting_redelivery(uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.outbound_retry_order_is_awaiting_redelivery(uuid)
  to sports_store_delivery_reader;

-- Expose separate retry and final-failure groups. The old failed count stays
-- a subset of ungrouped so older clients retain their total-count contract.
do $migration$
declare
  l_definition text;
  l_authorized_guard constant text := $needle$
  with authorized as materialized (
    select projection.*, task.created_at
    from public.read_my_delivery_tasks(null::uuid) as projection
    join public.delivery_tasks as task on task.id = projection.task_id
  ),$needle$;
  l_authorized_replacement constant text := $replacement$
  with authorized as materialized (
    select projection.*, task.created_at, task.order_id as raw_order_id
    from public.read_my_delivery_tasks(null::uuid) as projection
    join public.delivery_tasks as task on task.id = projection.task_id
  ),$replacement$;
  l_state_guard constant text := $needle$
  if l_state_group is not null
     and l_state_group not in ('waiting', 'in_transit', 'completed', 'failed') then$needle$;
  l_state_replacement constant text := $replacement$
  if l_state_group is not null
     and l_state_group not in ('waiting', 'in_transit', 'completed', 'retry', 'failed') then$replacement$;
  l_group_guard constant text := $needle$
      or (l_state_group = 'completed' and status in ('delivered', 'returned_to_store'))
      or (l_state_group = 'failed' and status = 'failed')$needle$;
  l_group_replacement constant text := $replacement$
      or (l_state_group = 'completed' and status in ('delivered', 'returned_to_store'))
      or (
        l_state_group = 'retry'
        and status = 'failed'
        and kind = 'outbound'
        and attempt_number = 1
        and private.outbound_retry_order_is_awaiting_redelivery(raw_order_id)
        and not exists (
          select 1 from public.delivery_tasks successor
          where successor.order_id = raw_order_id
            and successor.kind = 'outbound'::public.delivery_task_kind
            and successor.attempt_number = 2
        )
      )
      or (
        l_state_group = 'failed'
        and status = 'failed'
        and not (kind = 'outbound' and attempt_number = 1)
      )$replacement$;
  l_count_guard constant text := $needle$
      count(*) filter (where status = 'failed')::integer as failed,
      count(*) filter (
        where status not in (
          'assigned', 'accepted', 'in_transit', 'delivered', 'returned_to_store'
        )
      )::integer as ungrouped$needle$;
  l_count_replacement constant text := $replacement$
      count(*) filter (
        where status = 'failed'
          and not (kind = 'outbound' and attempt_number = 1)
      )::integer as failed,
      count(*) filter (
        where status = 'failed'
          and kind = 'outbound'
          and attempt_number = 1
          and private.outbound_retry_order_is_awaiting_redelivery(raw_order_id)
          and not exists (
            select 1 from public.delivery_tasks successor
            where successor.order_id = raw_order_id
              and successor.kind = 'outbound'::public.delivery_task_kind
              and successor.attempt_number = 2
          )
      )::integer as retry,
      count(*) filter (
        where status not in (
          'assigned', 'accepted', 'in_transit', 'delivered', 'returned_to_store'
        )
      )::integer as ungrouped$replacement$;
  l_counts_guard constant text := $needle$
      'completed', count_rows.completed,
      'failed', count_rows.failed,
      'ungrouped', count_rows.ungrouped$needle$;
  l_counts_replacement constant text := $replacement$
      'completed', count_rows.completed,
      'retry', count_rows.retry,
      'failed', count_rows.failed,
      'ungrouped', count_rows.ungrouped$replacement$;
begin
  select pg_catalog.pg_get_functiondef(
    'public.list_my_delivery_tasks(public.delivery_task_kind,text,text,integer,text)'::pg_catalog.regprocedure
  ) into l_definition;
  if l_definition is null then
    raise exception 'P04.2 requires list_my_delivery_tasks';
  end if;
  if pg_catalog.strpos(l_definition, l_authorized_guard) < 1
     or pg_catalog.strpos(l_definition, l_state_guard) < 1
     or pg_catalog.strpos(l_definition, l_group_guard) < 1
     or pg_catalog.strpos(l_definition, l_count_guard) < 1
     or pg_catalog.strpos(l_definition, l_counts_guard) < 1 then
    raise exception 'P04.2 could not locate task-list contract';
  end if;
  l_definition := pg_catalog.replace(l_definition, l_authorized_guard, l_authorized_replacement);
  l_definition := pg_catalog.replace(l_definition, l_state_guard, l_state_replacement);
  l_definition := pg_catalog.replace(l_definition, l_group_guard, l_group_replacement);
  l_definition := pg_catalog.replace(l_definition, l_count_guard, l_count_replacement);
  l_definition := pg_catalog.replace(l_definition, l_counts_guard, l_counts_replacement);
  execute l_definition;
end;
$migration$;

notify pgrst, 'reload schema';
