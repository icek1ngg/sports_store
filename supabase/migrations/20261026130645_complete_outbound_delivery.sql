-- P05.1 production: complete one successful outbound attempt.
--
-- The public RPC accepts only the task, idempotency key, customer-custody
-- attestation and claimed cash amount.  Identity, assignment, attempt,
-- expected COD, timestamps and recipients are server-derived.  All writes
-- happen in this transaction under the order -> task -> COD lock order.

do $$
begin
  if not exists (
    select 1 from pg_roles where rolname = 'sports_store_outbound_completion_writer'
  ) then
    create role sports_store_outbound_completion_writer
      nologin noinherit nobypassrls nocreatedb nocreaterole noreplication;
    comment on role sports_store_outbound_completion_writer is
      'sports_store P05.1 outbound completion writer; no-login, no-inherit, no-bypass-RLS';
  elsif not exists (
    select 1 from pg_roles r
    where r.rolname = 'sports_store_outbound_completion_writer'
      and not r.rolcanlogin and not r.rolsuper and not r.rolbypassrls
      and not r.rolinherit and not r.rolcreaterole and not r.rolcreatedb
      and not r.rolreplication
      and shobj_description(r.oid, 'pg_authid') =
        'sports_store P05.1 outbound completion writer; no-login, no-inherit, no-bypass-RLS'
  ) then
    raise exception 'P05.1 completion writer role already exists with unexpected configuration';
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
    where granted.rolname = 'sports_store_outbound_completion_writer'
      and member.rolname <> 'postgres'
  ) then
    raise exception 'P05.1 completion writer role has unexpected membership';
  end if;
end;
$$;

grant sports_store_outbound_completion_writer to postgres;
grant usage on schema public, private
  to sports_store_outbound_completion_writer;
grant execute on function private.delivery_request_user_id()
  to sports_store_outbound_completion_writer;
grant execute on function private.current_app_role()
  to sports_store_outbound_completion_writer;
grant create on schema public, private
  to sports_store_outbound_completion_writer;

create table private.outbound_completion_requests (
  actor_id uuid not null references public.profiles (id),
  request_id uuid not null,
  operation text not null,
  task_id uuid not null references public.delivery_tasks (id),
  order_id uuid not null references public.orders (id),
  received_all_items boolean not null,
  collected_amount_vnd bigint not null,
  payload_hash text not null,
  response jsonb not null,
  created_at timestamptz not null default now(),
  primary key (actor_id, request_id),
  constraint outbound_completion_requests_operation_valid
    check (operation = 'complete_outbound_delivery'),
  constraint outbound_completion_requests_amount_positive
    check (collected_amount_vnd > 0),
  constraint outbound_completion_requests_hash_nonblank
    check (btrim(payload_hash) <> ''),
  constraint outbound_completion_requests_response_object
    check (jsonb_typeof(response) = 'object')
);

-- A successful attempt is one immutable result per task and per order attempt.
-- The public delivery_attempts row remains the shared read projection; this
-- private ledger makes completion replay/concurrency explicit and durable.
create table private.outbound_completion_results (
  task_id uuid primary key references public.delivery_tasks (id),
  order_id uuid not null references public.orders (id),
  attempt_number smallint not null,
  actor_id uuid not null references public.profiles (id),
  event_id uuid not null unique references public.business_events (id),
  request_id uuid not null unique,
  collected_amount_vnd bigint not null,
  completed_at timestamptz not null,
  response jsonb not null,
  constraint outbound_completion_results_attempt_valid
    check (attempt_number between 1 and 2),
  constraint outbound_completion_results_amount_positive
    check (collected_amount_vnd > 0),
  constraint outbound_completion_results_response_object
    check (jsonb_typeof(response) = 'object'),
  constraint outbound_completion_results_order_attempt_unique
    unique (order_id, attempt_number)
);

alter table private.outbound_completion_requests enable row level security;
alter table private.outbound_completion_requests force row level security;
alter table private.outbound_completion_results enable row level security;
alter table private.outbound_completion_results force row level security;

create policy outbound_completion_requests_read
  on private.outbound_completion_requests
  for select to sports_store_outbound_completion_writer
  using (current_user = 'sports_store_outbound_completion_writer');
create policy outbound_completion_requests_insert
  on private.outbound_completion_requests
  for insert to sports_store_outbound_completion_writer
  with check (current_user = 'sports_store_outbound_completion_writer');
create policy outbound_completion_results_read
  on private.outbound_completion_results
  for select to sports_store_outbound_completion_writer
  using (current_user = 'sports_store_outbound_completion_writer');
create policy outbound_completion_results_insert
  on private.outbound_completion_results
  for insert to sports_store_outbound_completion_writer
  with check (current_user = 'sports_store_outbound_completion_writer');

revoke all on private.outbound_completion_requests,
  private.outbound_completion_results
  from public, anon, authenticated, service_role;
grant select, insert on private.outbound_completion_requests,
  private.outbound_completion_results
  to sports_store_outbound_completion_writer;

create or replace function private.reject_outbound_completion_ledger_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'P05.1 outbound completion ledgers are append-only'
    using errcode = '55000';
end;
$$;
revoke all on function private.reject_outbound_completion_ledger_mutation()
  from public, anon, authenticated, service_role;
create trigger outbound_completion_requests_append_only
before update or delete on private.outbound_completion_requests
for each row execute function private.reject_outbound_completion_ledger_mutation();
create trigger outbound_completion_results_append_only
before update or delete on private.outbound_completion_results
for each row execute function private.reject_outbound_completion_ledger_mutation();

-- Narrow column privileges for the non-login writer.
grant select (id, role) on public.profiles
  to sports_store_outbound_completion_writer;
grant update (id) on public.profiles
  to sports_store_outbound_completion_writer;
grant select (id, customer_id, status, total_cod_vnd,
              delivery_attempt_count, delivered_at, updated_at)
  on public.orders to sports_store_outbound_completion_writer;
grant update (status, delivered_at, updated_at)
  on public.orders to sports_store_outbound_completion_writer;
grant select (
  id, order_id, kind, assigned_shipper_id, status, attempt_number,
  amount_to_collect_vnd, accepted_at, started_at, completed_at,
  failure_reason, cancel_reason
) on public.delivery_tasks to sports_store_outbound_completion_writer;
grant update (status, completed_at, updated_at)
  on public.delivery_tasks to sports_store_outbound_completion_writer;
grant select (
  id, task_id, order_id, attempt_number, task_kind, result, reason,
  occurred_at, shipper_id
) on public.delivery_attempts
  to sports_store_outbound_completion_writer;
grant insert (
  id, task_id, order_id, attempt_number, task_kind, result, reason,
  occurred_at, shipper_id
) on public.delivery_attempts
  to sports_store_outbound_completion_writer;
grant select (
  order_id, shipper_id, status, expected_amount_vnd, collected_amount_vnd,
  received_amount_vnd, collected_at, collected_by, handed_over_at,
  received_at, received_by
) on public.cod_collections
  to sports_store_outbound_completion_writer;
grant update (
  status, collected_amount_vnd, collected_by, collected_at, updated_at
) on public.cod_collections
  to sports_store_outbound_completion_writer;
grant select (
  id, actor_id, subject_type, subject_id, task_id, incident_kind
) on public.business_events
  to sports_store_outbound_completion_writer;
grant insert (
  id, actor_id, subject_type, subject_id, from_state, to_state, reason,
  task_id, request_id, created_at
) on public.business_events
  to sports_store_outbound_completion_writer;
grant insert (
  id, recipient_id, event_id, subject_type, subject_id, title, body, created_at
) on public.notifications
  to sports_store_outbound_completion_writer;
grant select on private.outbound_dispatches,
  private.outbound_custody_acceptances
  to sports_store_outbound_completion_writer;
grant execute on function private.outbound_items_snapshot(uuid),
  private.validate_outbound_dispatch_proof(uuid, uuid, uuid, jsonb)
  to sports_store_outbound_completion_writer;
grant select (
  id, order_id, variant_id, product_name, variant_label, attributes,
  unit_price_vnd, quantity, line_total_vnd
) on public.order_items to sports_store_outbound_completion_writer;
grant select (
  id, variant_id, order_id, return_request_id, event_id, kind,
  on_hand_delta, reserved_delta, damaged_delta, actor_id, reason, created_at
) on public.inventory_movements to sports_store_outbound_completion_writer;

-- The writer is internal only.  These policies preserve least privilege while
-- allowing the completion function to inspect exactly its assigned order and
-- customer/manager recipient IDs.
create policy outbound_completion_profiles_read
  on public.profiles for select to sports_store_outbound_completion_writer
  using (
    current_user = 'sports_store_outbound_completion_writer'
    and (
      id = (select private.delivery_request_user_id())
      or role = 'manager'::public.user_role
      or exists (
        select 1
        from public.orders o
        join public.delivery_tasks t on t.order_id = o.id
        where o.customer_id = profiles.id
          and t.kind = 'outbound'::public.delivery_task_kind
          and t.assigned_shipper_id = (select private.delivery_request_user_id())
      )
    )
  );
create policy outbound_completion_profiles_lock
  on public.profiles for update to sports_store_outbound_completion_writer
  using (id = (select private.delivery_request_user_id()))
  with check (false);

create policy outbound_completion_orders_read
  on public.orders for select to sports_store_outbound_completion_writer
  using (
    current_user = 'sports_store_outbound_completion_writer'
    and exists (
      select 1 from public.delivery_tasks t
      where t.order_id = orders.id
        and t.kind = 'outbound'::public.delivery_task_kind
        and t.assigned_shipper_id = (select private.delivery_request_user_id())
    )
  );
create policy outbound_completion_orders_update
  on public.orders for update to sports_store_outbound_completion_writer
  using (
    current_user = 'sports_store_outbound_completion_writer'
    and exists (
      select 1 from public.delivery_tasks t
      where t.order_id = orders.id
        and t.kind = 'outbound'::public.delivery_task_kind
        and t.assigned_shipper_id = (select private.delivery_request_user_id())
    )
  )
  with check (
    current_user = 'sports_store_outbound_completion_writer'
    and status = 'delivered'::public.order_status
    and exists (
      select 1 from public.delivery_tasks t
      where t.order_id = orders.id
        and t.kind = 'outbound'::public.delivery_task_kind
        and t.assigned_shipper_id = (select private.delivery_request_user_id())
    )
  );

create policy outbound_completion_tasks_read
  on public.delivery_tasks for select to sports_store_outbound_completion_writer
  using (
    current_user = 'sports_store_outbound_completion_writer'
    and kind = 'outbound'::public.delivery_task_kind
    and assigned_shipper_id = (select private.delivery_request_user_id())
  );
create policy outbound_completion_tasks_update
  on public.delivery_tasks for update to sports_store_outbound_completion_writer
  using (
    current_user = 'sports_store_outbound_completion_writer'
    and kind = 'outbound'::public.delivery_task_kind
    and assigned_shipper_id = (select private.delivery_request_user_id())
  )
  with check (
    current_user = 'sports_store_outbound_completion_writer'
    and kind = 'outbound'::public.delivery_task_kind
    and status = 'delivered'::public.delivery_task_status
    and assigned_shipper_id = (select private.delivery_request_user_id())
  );

create policy outbound_completion_dispatches_read
  on private.outbound_dispatches for select
  to sports_store_outbound_completion_writer
  using (current_user = 'sports_store_outbound_completion_writer');
create policy outbound_completion_custody_read
  on private.outbound_custody_acceptances for select
  to sports_store_outbound_completion_writer
  using (current_user = 'sports_store_outbound_completion_writer');

create policy outbound_completion_order_items_read
  on public.order_items for select
  to sports_store_outbound_completion_writer
  using (
    current_user = 'sports_store_outbound_completion_writer'
    and exists (
      select 1 from public.delivery_tasks t
      where t.order_id = order_items.order_id
        and t.kind = 'outbound'::public.delivery_task_kind
        and t.assigned_shipper_id = (select private.delivery_request_user_id())
    )
  );
create policy outbound_completion_movements_read
  on public.inventory_movements for select
  to sports_store_outbound_completion_writer
  using (
    current_user = 'sports_store_outbound_completion_writer'
    and exists (
      select 1 from public.delivery_tasks t
      where t.order_id = inventory_movements.order_id
        and t.kind = 'outbound'::public.delivery_task_kind
        and t.assigned_shipper_id = (select private.delivery_request_user_id())
    )
  );

create policy outbound_completion_attempts_read
  on public.delivery_attempts for select to sports_store_outbound_completion_writer
  using (
    current_user = 'sports_store_outbound_completion_writer'
    and shipper_id = (select private.delivery_request_user_id())
  );
create policy outbound_completion_attempts_insert
  on public.delivery_attempts for insert to sports_store_outbound_completion_writer
  with check (
    current_user = 'sports_store_outbound_completion_writer'
    and result = 'success'::public.delivery_attempt_result
    and task_kind = 'outbound'::public.delivery_task_kind
    and shipper_id = (select private.delivery_request_user_id())
    and reason is null
    and exists (
      select 1 from public.delivery_tasks t
      where t.id = delivery_attempts.task_id
        and t.order_id = delivery_attempts.order_id
        and t.kind = 'outbound'::public.delivery_task_kind
        and t.assigned_shipper_id = (select private.delivery_request_user_id())
    )
  );

create policy outbound_completion_cod_read
  on public.cod_collections for select to sports_store_outbound_completion_writer
  using (
    current_user = 'sports_store_outbound_completion_writer'
    and shipper_id = (select private.delivery_request_user_id())
  );
create policy outbound_completion_cod_update
  on public.cod_collections for update to sports_store_outbound_completion_writer
  using (
    current_user = 'sports_store_outbound_completion_writer'
    and shipper_id = (select private.delivery_request_user_id())
  )
  with check (
    current_user = 'sports_store_outbound_completion_writer'
    and status = 'collected'::public.cod_status
    and collected_by = (select private.delivery_request_user_id())
    and collected_amount_vnd = expected_amount_vnd
    and received_amount_vnd = 0
  );

create policy outbound_completion_events_read
  on public.business_events for select to sports_store_outbound_completion_writer
  using (current_user = 'sports_store_outbound_completion_writer');
create policy outbound_completion_events_insert
  on public.business_events for insert to sports_store_outbound_completion_writer
  with check (
    current_user = 'sports_store_outbound_completion_writer'
    and actor_id = (select private.delivery_request_user_id())
    and subject_type = 'delivery_task'
    and subject_id = task_id
    and task_id is not null
    and incident_kind is null
    and from_state = 'in_transit'
    and to_state = 'delivered'
    and reason = 'delivery_completed'
    and request_id is not null
  );

create policy outbound_completion_notifications_insert
  on public.notifications for insert to sports_store_outbound_completion_writer
  with check (
    current_user = 'sports_store_outbound_completion_writer'
    and subject_type = 'delivery_task'
    and title = 'Giao hàng thành công'
    and body = 'Đơn hàng đã được giao thành công và thu đủ COD.'
    and exists (
      select 1
      from public.delivery_tasks t
      join public.orders o on o.id = t.order_id
      join public.profiles recipient on recipient.id = notifications.recipient_id
      join public.business_events e on e.id = notifications.event_id
      where t.id = notifications.subject_id
        and e.subject_id = t.id
        and e.actor_id = (select private.delivery_request_user_id())
        and (recipient.role = 'manager'::public.user_role
             or recipient.id = o.customer_id)
    )
  );

create or replace function public.complete_outbound_delivery(
  p_task_id uuid,
  p_request_id uuid,
  p_received_all_items boolean,
  p_collected_amount_vnd bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  l_actor_id uuid;
  l_actor_role text;
  l_payload_hash text;
  l_existing private.outbound_completion_requests%rowtype;
  l_result_ledger private.outbound_completion_results%rowtype;
  l_order record;
  l_task record;
  l_cod record;
  l_order_id uuid;
  l_custody private.outbound_custody_acceptances%rowtype;
  l_dispatch private.outbound_dispatches%rowtype;
  l_event_id uuid;
  l_notification_id uuid;
  l_now timestamptz;
  l_result jsonb;
  l_customer_id uuid;
  l_recipient record;
begin
  l_actor_id := (select private.delivery_request_user_id());
  if l_actor_id is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if p_task_id is null or p_request_id is null
     or p_received_all_items is not true
     or p_collected_amount_vnd is null
     or p_collected_amount_vnd <= 0 then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;

  select p.role::text into l_actor_role
  from public.profiles p where p.id = l_actor_id for share;
  if l_actor_role is distinct from 'shipper' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.complete_outbound_delivery:request:' || l_actor_id::text
      || ':' || p_request_id::text, 0
  ));
  select p.role::text into l_actor_role
  from public.profiles p where p.id = l_actor_id for share;
  if l_actor_role is distinct from 'shipper' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;

  select t.order_id into l_order_id
  from public.delivery_tasks t
  where t.id = p_task_id
    and t.kind = 'outbound'::public.delivery_task_kind
    and t.assigned_shipper_id = l_actor_id;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.complete_outbound_delivery:order:' || l_order_id::text, 0
  ));
  select o.id, o.customer_id, o.status, o.total_cod_vnd,
         o.delivery_attempt_count
    into l_order
  from public.orders o where o.id = l_order_id for update;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  select t.id, t.order_id, t.kind, t.assigned_shipper_id, t.status,
         t.attempt_number, t.amount_to_collect_vnd, t.accepted_at,
         t.started_at, t.completed_at
    into l_task
  from public.delivery_tasks t
  where t.id = p_task_id for update;
  if not found or l_task.order_id is distinct from l_order.id
     or l_task.assigned_shipper_id is distinct from l_actor_id then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  select c.order_id, c.shipper_id, c.status, c.expected_amount_vnd,
         c.collected_amount_vnd, c.received_amount_vnd, c.collected_by,
         c.collected_at
    into l_cod
  from public.cod_collections c
  where c.order_id = l_order.id for update;
  if not found then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;

  l_payload_hash := md5(pg_catalog.jsonb_build_object(
    'operation', 'complete_outbound_delivery',
    'task_id', p_task_id,
    'request_id', p_request_id,
    'received_all_items', p_received_all_items,
    'collected_amount_vnd', p_collected_amount_vnd
  )::text);
  select r.* into l_existing from private.outbound_completion_requests r
  where r.actor_id = l_actor_id and r.request_id = p_request_id;
  if found then
    if l_existing.operation <> 'complete_outbound_delivery'
       or l_existing.task_id is distinct from p_task_id
       or l_existing.order_id is distinct from l_order.id
       or l_existing.received_all_items is distinct from p_received_all_items
       or l_existing.collected_amount_vnd is distinct from p_collected_amount_vnd
       or l_existing.payload_hash <> l_payload_hash then
      raise exception using errcode = 'PT409', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return l_existing.response;
  end if;

  if l_task.kind <> 'outbound'::public.delivery_task_kind
     or l_task.status <> 'in_transit'::public.delivery_task_status
     or l_task.accepted_at is null or l_task.started_at is null
     or l_task.completed_at is not null
     or l_task.attempt_number not between 1 and 2
     or l_order.status <> 'delivering'::public.order_status
     or l_order.delivery_attempt_count <> l_task.attempt_number then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;

  if exists (
    select 1 from public.delivery_attempts a
    where a.task_id = l_task.id
       or (a.order_id = l_order.id and a.attempt_number = l_task.attempt_number)
  ) or exists (
    select 1 from private.outbound_completion_results r
    where r.order_id = l_order.id and r.attempt_number = l_task.attempt_number
  ) then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;

  select c.* into l_custody from private.outbound_custody_acceptances c
  where c.task_id = l_task.id;
  if not found or l_custody.order_id is distinct from l_order.id
     or l_custody.holder_id is distinct from l_actor_id
     or l_custody.attempt_number <> l_task.attempt_number then
    raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
  end if;
  select d.* into l_dispatch from private.outbound_dispatches d
  where d.order_id = l_order.id and d.event_id = l_custody.dispatch_event_id
  ;
  if not found or l_dispatch.holder_id is distinct from l_actor_id then
    raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
  end if;

  -- Revalidate the immutable dispatch proof against the current order-item
  -- snapshot and every inventory movement before recording cash or delivery.
  perform private.validate_outbound_dispatch_proof(
    l_order.id, l_custody.dispatch_event_id, l_actor_id,
    l_dispatch.items_snapshot
  );

  if l_order.total_cod_vnd <= 0
     or l_task.amount_to_collect_vnd is distinct from l_order.total_cod_vnd
     or l_cod.expected_amount_vnd is distinct from l_order.total_cod_vnd
     or p_collected_amount_vnd is distinct from l_order.total_cod_vnd
     or l_cod.status <> 'uncollected'::public.cod_status
     or l_cod.collected_amount_vnd <> 0
     or l_cod.received_amount_vnd <> 0
     or l_cod.shipper_id is distinct from l_actor_id
     or l_cod.collected_by is not null
     or l_cod.collected_at is not null then
    raise exception using errcode = 'PT409', message = 'AMOUNT_MISMATCH';
  end if;

  l_now := pg_catalog.clock_timestamp();
  l_event_id := pg_catalog.gen_random_uuid();
  l_result := pg_catalog.jsonb_build_object(
    'task_id', l_task.id,
    'order_id', l_order.id,
    'operation', 'complete',
    'task_status', 'delivered',
    'order_status', 'delivered',
    'attempt_number', l_task.attempt_number,
    'delivery_attempt_count', l_order.delivery_attempt_count,
    'collected_amount_vnd', l_order.total_cod_vnd,
    'completed_at', l_now,
    'event_id', l_event_id,
    'request_id', p_request_id
  );

  insert into public.delivery_attempts (
    id, task_id, order_id, attempt_number, task_kind, result, reason,
    occurred_at, shipper_id
  ) values (
    pg_catalog.gen_random_uuid(), l_task.id, l_order.id, l_task.attempt_number,
    'outbound'::public.delivery_task_kind,
    'success'::public.delivery_attempt_result, null, l_now, l_actor_id
  );
  update public.delivery_tasks
  set status = 'delivered'::public.delivery_task_status,
      completed_at = l_now, updated_at = l_now
  where id = l_task.id;
  update public.orders
  set status = 'delivered'::public.order_status,
      delivered_at = l_now, updated_at = l_now
  where id = l_order.id;
  update public.cod_collections
  set status = 'collected'::public.cod_status,
      collected_amount_vnd = l_order.total_cod_vnd,
      collected_by = l_actor_id,
      collected_at = l_now,
      updated_at = l_now
  where order_id = l_order.id;
  insert into public.business_events (
    id, actor_id, subject_type, subject_id, from_state, to_state,
    reason, task_id, request_id, created_at
  ) values (
    l_event_id, l_actor_id, 'delivery_task', l_task.id,
    'in_transit', 'delivered', 'delivery_completed',
    l_task.id, p_request_id, l_now
  );

  l_customer_id := l_order.customer_id;
  for l_recipient in
    select p.id
    from public.profiles p
    where p.role = 'manager'::public.user_role
       or p.id = l_customer_id
    order by p.id
  loop
    l_notification_id := pg_catalog.gen_random_uuid();
    insert into public.notifications (
      id, recipient_id, event_id, subject_type, subject_id, title, body, created_at
    ) values (
      l_notification_id, l_recipient.id, l_event_id,
      'delivery_task', l_task.id, 'Giao hàng thành công',
      'Đơn hàng đã được giao thành công và thu đủ COD.', l_now
    );
  end loop;

  insert into private.outbound_completion_results (
    task_id, order_id, attempt_number, actor_id, event_id, request_id,
    collected_amount_vnd, completed_at, response
  ) values (
    l_task.id, l_order.id, l_task.attempt_number, l_actor_id, l_event_id,
    p_request_id, l_order.total_cod_vnd, l_now, l_result
  );
  insert into private.outbound_completion_requests (
    actor_id, request_id, operation, task_id, order_id,
    received_all_items, collected_amount_vnd, payload_hash, response, created_at
  ) values (
    l_actor_id, p_request_id, 'complete_outbound_delivery', l_task.id, l_order.id,
    p_received_all_items, p_collected_amount_vnd, l_payload_hash, l_result, l_now
  );
  return l_result;
end;
$$;

grant create on schema public to sports_store_outbound_completion_writer;
alter function public.complete_outbound_delivery(uuid, uuid, boolean, bigint)
  owner to sports_store_outbound_completion_writer;
revoke create on schema public, private from sports_store_outbound_completion_writer;
revoke all on function public.complete_outbound_delivery(uuid, uuid, boolean, bigint)
  from public, anon, service_role, sports_store_outbound_completion_writer;
grant execute on function public.complete_outbound_delivery(uuid, uuid, boolean, bigint)
  to authenticated;

comment on function public.complete_outbound_delivery(uuid, uuid, boolean, bigint) is
  'P05.1 manager-independent shipper completion; server-validated custody, exact COD, one attempt/result and customer+manager notifications.';

notify pgrst, 'reload schema';
