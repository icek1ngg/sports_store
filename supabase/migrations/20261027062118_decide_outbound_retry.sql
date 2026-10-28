-- P07.2 production: manager decision after outbound attempt 1 failed.
--
-- The manager chooses exactly one first decision: create an assigned attempt 2
-- for the existing holder, or move the order to store return.  A retry may be
-- changed to return while task 2 is still assigned/accepted but not started;
-- that transition cancels task 2 without deleting its custody proof or the
-- failed attempt-1 history.  This migration deliberately does not change the
-- existing assignment, accept, start, completion, or failure RPC bodies.

do $$
begin
  if not exists (
    select 1 from pg_roles where rolname = 'sports_store_outbound_retry_writer'
  ) then
    create role sports_store_outbound_retry_writer
      nologin noinherit nobypassrls nocreatedb nocreaterole noreplication;
    comment on role sports_store_outbound_retry_writer is
      'sports_store P07.2 outbound retry decision writer; no-login, no-inherit, no-bypass-RLS';
  elsif not exists (
    select 1
    from pg_roles r
    where r.rolname = 'sports_store_outbound_retry_writer'
      and not r.rolcanlogin
      and not r.rolsuper
      and not r.rolbypassrls
      and not r.rolinherit
      and not r.rolcreaterole
      and not r.rolcreatedb
      and not r.rolreplication
      and shobj_description(r.oid, 'pg_authid') =
        'sports_store P07.2 outbound retry decision writer; no-login, no-inherit, no-bypass-RLS'
  ) then
    raise exception
      'P07.2 outbound retry writer role already exists with unexpected configuration';
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
    where granted.rolname = 'sports_store_outbound_retry_writer'
      and member.rolname <> 'postgres'
  ) then
    raise exception 'P07.2 outbound retry writer role has unexpected membership';
  end if;
end;
$$;

grant sports_store_outbound_retry_writer to postgres;
grant usage on schema public, private
  to sports_store_outbound_retry_writer;
grant execute on function private.delivery_request_user_id()
  to sports_store_outbound_retry_writer;
grant execute on function private.current_app_role()
  to sports_store_outbound_retry_writer;

-- The shared SQL snapshot helper can reuse RLS plans prepared by accept/start
-- within the same session. Its failure writer must be allowed to evaluate
-- the same server-managed role helper; this grants no client/table access.
grant execute on function private.current_app_role()
  to sports_store_outbound_failure_writer;
grant execute on function private.outbound_items_snapshot(uuid)
  to sports_store_outbound_retry_writer;
grant create on schema public, private
  to sports_store_outbound_retry_writer;

-- The request and decision ledgers are separate.  Requests retain the exact
-- client payload and ACK for safe replay; decisions retain the immutable
-- business transition and event.  A second decision row is only used for the
-- explicit retry -> return transition.
create table private.outbound_retry_requests (
  actor_id uuid not null references public.profiles (id),
  request_id uuid not null,
  operation text not null,
  order_id uuid not null references public.orders (id),
  expected_failed_task_id uuid not null references public.delivery_tasks (id),
  expected_retry_task_id uuid references public.delivery_tasks (id),
  decision text not null,
  retry_task_id uuid references public.delivery_tasks (id),
  payload_hash text not null,
  response jsonb not null,
  created_at timestamptz not null default statement_timestamp(),
  primary key (actor_id, request_id),
  constraint outbound_retry_requests_operation_valid
    check (operation = 'decide_outbound_retry'),
  constraint outbound_retry_requests_decision_valid
    check (decision in ('retry', 'return_to_store')),
  constraint outbound_retry_requests_hash_nonblank
    check (btrim(payload_hash) <> ''),
  constraint outbound_retry_requests_response_object
    check (jsonb_typeof(response) = 'object')
);

create table private.outbound_retry_decisions (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references public.profiles (id),
  request_id uuid not null,
  order_id uuid not null references public.orders (id),
  failed_task_id uuid not null references public.delivery_tasks (id),
  retry_task_id uuid references public.delivery_tasks (id),
  decision_number smallint not null,
  decision text not null,
  from_order_status public.order_status not null,
  to_order_status public.order_status not null,
  event_id uuid not null unique references public.business_events (id),
  response jsonb not null,
  created_at timestamptz not null default statement_timestamp(),
  constraint outbound_retry_decisions_number_valid
    check (decision_number between 1 and 2),
  constraint outbound_retry_decisions_decision_valid
    check (decision in ('retry', 'return_to_store')),
  constraint outbound_retry_decisions_retry_has_task
    check (decision <> 'retry' or retry_task_id is not null),
  constraint outbound_retry_decisions_response_object
    check (jsonb_typeof(response) = 'object'),
  constraint outbound_retry_decisions_order_number_unique
    unique (order_id, decision_number)
);

alter table private.outbound_retry_requests enable row level security;
alter table private.outbound_retry_requests force row level security;
alter table private.outbound_retry_decisions enable row level security;
alter table private.outbound_retry_decisions force row level security;

revoke all on private.outbound_retry_requests,
  private.outbound_retry_decisions
  from public, anon, authenticated, service_role;
grant select, insert on private.outbound_retry_requests,
  private.outbound_retry_decisions
  to sports_store_outbound_retry_writer;

create policy outbound_retry_requests_writer_read
  on private.outbound_retry_requests
  for select to sports_store_outbound_retry_writer
  using (current_user = 'sports_store_outbound_retry_writer');
create policy outbound_retry_requests_writer_insert
  on private.outbound_retry_requests
  for insert to sports_store_outbound_retry_writer
  with check (current_user = 'sports_store_outbound_retry_writer');
create policy outbound_retry_decisions_writer_read
  on private.outbound_retry_decisions
  for select to sports_store_outbound_retry_writer
  using (current_user = 'sports_store_outbound_retry_writer');
create policy outbound_retry_decisions_writer_insert
  on private.outbound_retry_decisions
  for insert to sports_store_outbound_retry_writer
  with check (current_user = 'sports_store_outbound_retry_writer');

-- The old custody trigger runs as sports_store_outbound_writer.  It needs one
-- read-only, actor-scoped view of the decision row to authorize the one
-- manager-owned task-2 cancellation below; no setting/GUC is used as a
-- privilege or trigger bypass.
grant select on private.outbound_retry_decisions
  to sports_store_outbound_writer;
create policy outbound_retry_decisions_custody_guard_read
  on private.outbound_retry_decisions
  for select to sports_store_outbound_writer
  using (
    current_user = 'sports_store_outbound_writer'
    and actor_id = (select private.delivery_request_user_id())
  );

create function private.reject_outbound_retry_ledger_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'P07.2 outbound retry ledgers are append-only'
    using errcode = '55000';
end;
$$;
revoke all on function private.reject_outbound_retry_ledger_mutation()
  from public, anon, authenticated, service_role;
create trigger outbound_retry_requests_append_only
before update or delete on private.outbound_retry_requests
for each row execute function private.reject_outbound_retry_ledger_mutation();
create trigger outbound_retry_decisions_append_only
before update or delete on private.outbound_retry_decisions
for each row execute function private.reject_outbound_retry_ledger_mutation();

-- Source columns are limited to the decision transaction.  UPDATE privileges
-- on a stable key are lock-only where a FOR UPDATE/SHARE lock needs them.
grant select (id, role) on public.profiles
  to sports_store_outbound_retry_writer;
grant update (id) on public.profiles
  to sports_store_outbound_retry_writer;
grant select (
  id, status, total_cod_vnd, delivery_attempt_count,
  recipient_name, recipient_phone, address_detail, latitude, longitude
) on public.orders to sports_store_outbound_retry_writer;
grant update (status, updated_at) on public.orders
  to sports_store_outbound_retry_writer;
grant select (
  id, order_id, kind, assigned_shipper_id, assigned_by, status,
  attempt_number, destination_name, destination_phone, destination_address,
  destination_latitude, destination_longitude, amount_to_collect_vnd,
  assigned_at, accepted_at, started_at, completed_at, failure_reason,
  cancel_reason
) on public.delivery_tasks to sports_store_outbound_retry_writer;
grant insert (
  id, order_id, kind, assigned_shipper_id, assigned_by, status,
  attempt_number, destination_name, destination_phone, destination_address,
  destination_latitude, destination_longitude, amount_to_collect_vnd,
  assigned_at
) on public.delivery_tasks to sports_store_outbound_retry_writer;
grant update (status, completed_at, cancel_reason, updated_at)
  on public.delivery_tasks to sports_store_outbound_retry_writer;
grant select (
  id, task_id, order_id, attempt_number, task_kind, result, shipper_id,
  occurred_at, reason
) on public.delivery_attempts to sports_store_outbound_retry_writer;
grant update (id) on public.delivery_attempts
  to sports_store_outbound_retry_writer;
grant select (
  order_id, shipper_id, status, expected_amount_vnd,
  collected_amount_vnd, received_amount_vnd, collected_at, collected_by,
  handed_over_at, received_at, received_by
) on public.cod_collections to sports_store_outbound_retry_writer;
grant update (order_id) on public.cod_collections
  to sports_store_outbound_retry_writer;
grant select (
  id, order_id, variant_id, product_name, variant_label, attributes,
  unit_price_vnd, quantity, line_total_vnd
) on public.order_items to sports_store_outbound_retry_writer;
grant update (id) on public.order_items
  to sports_store_outbound_retry_writer;
grant select (
  id, variant_id, order_id, return_request_id, event_id, kind,
  on_hand_delta, reserved_delta, damaged_delta, actor_id, reason, created_at
) on public.inventory_movements to sports_store_outbound_retry_writer;
grant update (id) on public.inventory_movements
  to sports_store_outbound_retry_writer;
grant select (id, actor_id, reason, subject_type, subject_id, task_id, incident_kind)
  on public.business_events to sports_store_outbound_retry_writer;
grant insert (
  id, actor_id, subject_type, subject_id, from_state, to_state, reason,
  task_id, request_id, created_at
) on public.business_events to sports_store_outbound_retry_writer;
grant insert (
  id, recipient_id, event_id, subject_type, subject_id, title, body, created_at
) on public.notifications to sports_store_outbound_retry_writer;
grant select on private.outbound_dispatches,
  private.outbound_custody_acceptances
  to sports_store_outbound_retry_writer;

create policy outbound_retry_profiles_read
  on public.profiles for select to sports_store_outbound_retry_writer
  using (
    id = (select private.delivery_request_user_id())
    or role = 'shipper'::public.user_role
  );
create policy outbound_retry_profiles_lock
  on public.profiles for update to sports_store_outbound_retry_writer
  using (
    current_user = 'sports_store_outbound_retry_writer'
    or id = (select private.delivery_request_user_id())
  )
  with check (false);

create policy outbound_retry_orders_read
  on public.orders for select to sports_store_outbound_retry_writer
  using (current_user = 'sports_store_outbound_retry_writer');
create policy outbound_retry_orders_update
  on public.orders for update to sports_store_outbound_retry_writer
  using (current_user = 'sports_store_outbound_retry_writer')
  with check (current_user = 'sports_store_outbound_retry_writer');

create policy outbound_retry_tasks_read
  on public.delivery_tasks for select to sports_store_outbound_retry_writer
  using (
    current_user = 'sports_store_outbound_retry_writer'
    and kind = 'outbound'::public.delivery_task_kind
  );
create policy outbound_retry_tasks_insert
  on public.delivery_tasks for insert to sports_store_outbound_retry_writer
  with check (
    current_user = 'sports_store_outbound_retry_writer'
    and kind = 'outbound'::public.delivery_task_kind
    and return_request_id is null
    and attempt_number between 1 and 2
  );
create policy outbound_retry_tasks_update
  on public.delivery_tasks for update to sports_store_outbound_retry_writer
  using (
    current_user = 'sports_store_outbound_retry_writer'
    and kind = 'outbound'::public.delivery_task_kind
  )
  with check (
    current_user = 'sports_store_outbound_retry_writer'
    and kind = 'outbound'::public.delivery_task_kind
  );

create policy outbound_retry_attempts_read
  on public.delivery_attempts for select to sports_store_outbound_retry_writer
  using (current_user = 'sports_store_outbound_retry_writer');
create policy outbound_retry_cod_read
  on public.cod_collections for select to sports_store_outbound_retry_writer
  using (current_user = 'sports_store_outbound_retry_writer');
create policy outbound_retry_cod_lock
  on public.cod_collections for update to sports_store_outbound_retry_writer
  using (current_user = 'sports_store_outbound_retry_writer')
  with check (false);
create policy outbound_retry_order_items_read
  on public.order_items for select to sports_store_outbound_retry_writer
  using (current_user = 'sports_store_outbound_retry_writer');
create policy outbound_retry_movements_read
  on public.inventory_movements for select to sports_store_outbound_retry_writer
  using (current_user = 'sports_store_outbound_retry_writer');
create policy outbound_retry_events_read
  on public.business_events for select to sports_store_outbound_retry_writer
  using (current_user = 'sports_store_outbound_retry_writer');
create policy outbound_retry_events_insert
  on public.business_events for insert to sports_store_outbound_retry_writer
  with check (
    current_user = 'sports_store_outbound_retry_writer'
    and actor_id = (select private.delivery_request_user_id())
    and request_id = id
    and subject_type in ('order', 'delivery_task')
  );
create policy outbound_retry_notifications_insert
  on public.notifications for insert to sports_store_outbound_retry_writer
  with check (
    current_user = 'sports_store_outbound_retry_writer'
    and subject_type = 'delivery_task'
    and title = 'Cập nhật nhiệm vụ giao hàng'
    and body = 'Một nhiệm vụ giao hàng đã được cập nhật. Mở nhiệm vụ để xem chi tiết.'
    and exists (
      select 1
      from public.delivery_tasks t
      join public.profiles recipient on recipient.id = notifications.recipient_id
      join public.business_events e on e.id = notifications.event_id
      where t.id = notifications.subject_id
        and t.kind = 'outbound'::public.delivery_task_kind
        and t.assigned_shipper_id = notifications.recipient_id
        and recipient.role = 'shipper'::public.user_role
        and e.actor_id = (select private.delivery_request_user_id())
        and e.subject_type = 'order'
        and e.subject_id = t.order_id
        and e.reason in ('outbound_retry_selected', 'outbound_return_selected')
        and (e.task_id is null or e.task_id = t.id)
    )
  );

create policy outbound_retry_dispatches_read
  on private.outbound_dispatches for select
  to sports_store_outbound_retry_writer
  using (current_user = 'sports_store_outbound_retry_writer');
create policy outbound_retry_custody_read
  on private.outbound_custody_acceptances for select
  to sports_store_outbound_retry_writer
  using (current_user = 'sports_store_outbound_retry_writer');

-- The existing trigger still rejects every post-custody assignee mutation.  A
-- single exception is allowed only when this transaction has already written
-- a manager decision row for the same accepted, unstarted attempt-2 task.
create or replace function private.guard_outbound_task_custody()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  l_authorized_return boolean := false;
begin
  if old.kind = 'outbound'::public.delivery_task_kind
     and (
       old.accepted_at is not null
       or exists (
         select 1
         from private.outbound_custody_acceptances c
         where c.task_id = old.id
       )
     )
     and (
       new.assigned_shipper_id is distinct from old.assigned_shipper_id
       or new.assigned_by is distinct from old.assigned_by
       or new.assigned_at is distinct from old.assigned_at
       or (
         new.status = 'cancelled'::public.delivery_task_status
         and old.status is distinct from new.status
       )
     ) then
    l_authorized_return :=
      old.attempt_number = 2
      and old.status = 'accepted'::public.delivery_task_status
      and old.accepted_at is not null
      and old.started_at is null
      and old.completed_at is null
      and old.failure_reason is null
      and old.cancel_reason is null
      and new.status = 'cancelled'::public.delivery_task_status
      and new.assigned_shipper_id is not distinct from old.assigned_shipper_id
      and new.assigned_by is not distinct from old.assigned_by
      and new.assigned_at is not distinct from old.assigned_at
      and new.accepted_at is not distinct from old.accepted_at
      and new.started_at is null
      and new.completed_at is not null
      and new.failure_reason is null
      and new.cancel_reason = 'manager_return_to_store'
      and exists (
        select 1
        from private.outbound_custody_acceptances c
        where c.task_id = old.id
          and c.order_id = old.order_id
          and c.holder_id = old.assigned_shipper_id
          and c.attempt_number = 2
      )
      and exists (
        select 1
        from private.outbound_retry_decisions d
        where d.order_id = old.order_id
          and d.retry_task_id = old.id
          and d.decision = 'return_to_store'
          and d.actor_id = (select private.delivery_request_user_id())
          and d.response ->> 'task_status' = 'cancelled'
      );
    if not l_authorized_return then
      raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
    end if;
  end if;
  return new;
end;
$$;
alter function private.guard_outbound_task_custody()
  owner to sports_store_outbound_writer;
revoke all on function private.guard_outbound_task_custody()
  from public, anon, authenticated, service_role;

drop trigger if exists delivery_tasks_block_post_accept_mutation
  on public.delivery_tasks;
create trigger delivery_tasks_block_post_accept_mutation
before update of assigned_shipper_id, assigned_by, assigned_at, status
on public.delivery_tasks
for each row execute function private.guard_outbound_task_custody();

create or replace function public.decide_outbound_retry(
  p_order_id uuid,
  p_request_id uuid,
  p_decision text,
  p_expected_failed_task_id uuid,
  p_expected_retry_task_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  l_actor_id uuid;
  l_actor_role text;
  l_decision text;
  l_payload_hash text;
  l_existing private.outbound_retry_requests%rowtype;
  l_order record;
  l_cod record;
  l_task_row record;
  l_failed_task_id uuid;
  l_failed_shipper_id uuid;
  l_failed_status public.delivery_task_status;
  l_failed_attempt smallint;
  l_failed_amount bigint;
  l_failed_assigned_at timestamptz;
  l_failed_accepted_at timestamptz;
  l_failed_started_at timestamptz;
  l_failed_completed_at timestamptz;
  l_failed_reason text;
  l_failed_cancel_reason text;
  l_retry_task_id uuid;
  l_retry_status public.delivery_task_status;
  l_retry_shipper_id uuid;
  l_retry_assigned_by uuid;
  l_retry_attempt smallint;
  l_retry_amount bigint;
  l_retry_name text;
  l_retry_phone text;
  l_retry_address text;
  l_retry_latitude numeric(9, 6);
  l_retry_longitude numeric(9, 6);
  l_retry_assigned_at timestamptz;
  l_retry_accepted_at timestamptz;
  l_retry_started_at timestamptz;
  l_retry_completed_at timestamptz;
  l_retry_failure_reason text;
  l_retry_cancel_reason text;
  l_outbound_task_count bigint := 0;
  l_attempt_one_count bigint := 0;
  l_attempt_two_count bigint := 0;
  l_failed_found boolean := false;
  l_retry_found boolean := false;
  l_attempt_rows bigint := 0;
  l_previous_attempt record;
  l_custody private.outbound_custody_acceptances%rowtype;
  l_dispatch private.outbound_dispatches%rowtype;
  l_dispatch_row record;
  l_item record;
  l_snapshot jsonb;
  l_item_count bigint;
  l_variant_count bigint;
  l_dispatch_count bigint;
  l_movement_count bigint;
  l_reserved_sum bigint;
  l_on_hand_sum bigint;
  l_decision_row private.outbound_retry_decisions%rowtype;
  l_decision_count smallint := 0;
  l_first_decision text;
  l_second_decision text;
  l_decision_number smallint;
  l_from_order_status public.order_status;
  l_to_order_status public.order_status;
  l_task_status public.delivery_task_status;
  l_target_task_id uuid;
  l_event_id uuid;
  l_notification_id uuid;
  l_now timestamptz;
  l_response jsonb;
begin
  l_actor_id := (select private.delivery_request_user_id());
  if l_actor_id is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;

  l_decision := nullif(
    pg_catalog.regexp_replace(coalesce(p_decision, ''),
      '^[[:space:]]+|[[:space:]]+$', '', 'g'),
    ''
  );
  if p_order_id is null
     or p_request_id is null
     or p_expected_failed_task_id is null
     or l_decision is null
     or l_decision not in ('retry', 'return_to_store')
     or (l_decision = 'retry' and p_expected_retry_task_id is not null) then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;

  select p.role::text
    into l_actor_role
  from public.profiles p
  where p.id = l_actor_id
  for share;
  if l_actor_role is distinct from 'manager' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.outbound.retry.request:' || l_actor_id::text || ':'
      || p_request_id::text,
    0
  ));

  -- Recheck the server-managed profile after waiting on the idempotency key.
  select p.role::text
    into l_actor_role
  from public.profiles p
  where p.id = l_actor_id
  for share;
  if l_actor_role is distinct from 'manager' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;

  -- The order is always the first business lock.  Failure/completion/start
  -- all serialize through this row before any state is changed.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.complete_outbound_delivery:order:' || p_order_id::text,
    0
  ));
  select o.id, o.status, o.total_cod_vnd, o.delivery_attempt_count,
         o.recipient_name, o.recipient_phone, o.address_detail,
         o.latitude, o.longitude
    into l_order
  from public.orders o
  where o.id = p_order_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'ORDER_NOT_FOUND';
  end if;

  -- Lock every outbound task in deterministic UUID order before locking COD.
  -- The loop also records the immutable task-1/task-2 shape used below.
  for l_task_row in
    select t.id, t.order_id, t.kind, t.assigned_shipper_id, t.assigned_by,
           t.status, t.attempt_number, t.destination_name,
           t.destination_phone, t.destination_address,
           t.destination_latitude, t.destination_longitude,
           t.amount_to_collect_vnd, t.assigned_at, t.accepted_at,
           t.started_at, t.completed_at, t.failure_reason, t.cancel_reason
    from public.delivery_tasks t
    where t.order_id = p_order_id
      and t.kind = 'outbound'::public.delivery_task_kind
    order by t.id
    for update
  loop
    l_outbound_task_count := l_outbound_task_count + 1;
    if l_task_row.attempt_number = 1 then
      l_attempt_one_count := l_attempt_one_count + 1;
      if l_task_row.id = p_expected_failed_task_id then
        l_failed_found := true;
        l_failed_task_id := l_task_row.id;
        l_failed_shipper_id := l_task_row.assigned_shipper_id;
        l_failed_status := l_task_row.status;
        l_failed_attempt := l_task_row.attempt_number;
        l_failed_amount := l_task_row.amount_to_collect_vnd;
        l_failed_assigned_at := l_task_row.assigned_at;
        l_failed_accepted_at := l_task_row.accepted_at;
        l_failed_started_at := l_task_row.started_at;
        l_failed_completed_at := l_task_row.completed_at;
        l_failed_reason := l_task_row.failure_reason;
        l_failed_cancel_reason := l_task_row.cancel_reason;
      end if;
    elsif l_task_row.attempt_number = 2 then
      l_attempt_two_count := l_attempt_two_count + 1;
      if l_task_row.id = p_expected_retry_task_id then
        l_retry_found := true;
        l_retry_task_id := l_task_row.id;
        l_retry_status := l_task_row.status;
        l_retry_shipper_id := l_task_row.assigned_shipper_id;
        l_retry_assigned_by := l_task_row.assigned_by;
        l_retry_attempt := l_task_row.attempt_number;
        l_retry_amount := l_task_row.amount_to_collect_vnd;
        l_retry_name := l_task_row.destination_name;
        l_retry_phone := l_task_row.destination_phone;
        l_retry_address := l_task_row.destination_address;
        l_retry_latitude := l_task_row.destination_latitude;
        l_retry_longitude := l_task_row.destination_longitude;
        l_retry_assigned_at := l_task_row.assigned_at;
        l_retry_accepted_at := l_task_row.accepted_at;
        l_retry_started_at := l_task_row.started_at;
        l_retry_completed_at := l_task_row.completed_at;
        l_retry_failure_reason := l_task_row.failure_reason;
        l_retry_cancel_reason := l_task_row.cancel_reason;
      end if;
    else
      raise exception using errcode = 'PT409', message = 'ATTEMPT_LIMIT';
    end if;
  end loop;

  select c.order_id, c.shipper_id, c.status, c.expected_amount_vnd,
         c.collected_amount_vnd, c.received_amount_vnd, c.collected_at,
         c.collected_by, c.handed_over_at, c.received_at, c.received_by
    into l_cod
  from public.cod_collections c
  where c.order_id = p_order_id
  for update;
  if not found then
    raise exception using errcode = 'PT409', message = 'COD_CONFLICT';
  end if;

  l_payload_hash := md5(pg_catalog.jsonb_build_object(
    'operation', 'decide_outbound_retry',
    'order_id', p_order_id,
    'request_id', p_request_id,
    'decision', l_decision,
    'expected_failed_task_id', p_expected_failed_task_id,
    'expected_retry_task_id', p_expected_retry_task_id
  )::text);

  -- The authorization, order, task and COD locks precede replay lookup.  A
  -- replay is safe only after the current manager profile was rechecked.
  select r.*
    into l_existing
  from private.outbound_retry_requests r
  where r.actor_id = l_actor_id
    and r.request_id = p_request_id;
  if found then
    if l_existing.operation <> 'decide_outbound_retry'
       or l_existing.order_id is distinct from p_order_id
       or l_existing.expected_failed_task_id is distinct from p_expected_failed_task_id
       or l_existing.expected_retry_task_id is distinct from p_expected_retry_task_id
       or l_existing.decision is distinct from l_decision
       or l_existing.payload_hash <> l_payload_hash then
      raise exception using errcode = 'PT409', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return l_existing.response;
  end if;

  -- A decision is only legal after the first failed attempt.  Reject an
  -- already-consumed second attempt before inspecting money/custody details;
  -- this keeps every third-attempt path on the stable ATTEMPT_LIMIT marker.
  if l_order.delivery_attempt_count >= 2 then
    raise exception using errcode = 'PT409', message = 'ATTEMPT_LIMIT';
  end if;
  if l_order.delivery_attempt_count <> 1 then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;

  if not l_failed_found
     or l_outbound_task_count > 2
     or l_attempt_one_count <> 1
     or l_failed_task_id <> p_expected_failed_task_id
     or l_failed_attempt <> 1
     or l_failed_status <> 'failed'::public.delivery_task_status
     or l_failed_shipper_id is null
     or l_failed_assigned_at is null
     or l_failed_accepted_at is null
     or l_failed_started_at is null
     or l_failed_completed_at is null
     or l_failed_reason is null
     or btrim(l_failed_reason) = ''
     or l_failed_cancel_reason is not null then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;

  if l_order.delivery_attempt_count <> 1
     or l_order.total_cod_vnd <= 0
     or l_failed_amount is distinct from l_order.total_cod_vnd
     or l_cod.status <> 'uncollected'::public.cod_status
     or l_cod.shipper_id is distinct from l_failed_shipper_id
     or l_cod.expected_amount_vnd is distinct from l_order.total_cod_vnd
     or l_cod.collected_amount_vnd <> 0
     or l_cod.received_amount_vnd <> 0
     or l_cod.collected_at is not null
     or l_cod.collected_by is not null
     or l_cod.handed_over_at is not null
     or l_cod.received_at is not null
     or l_cod.received_by is not null then
    raise exception using errcode = 'PT409', message = 'COD_CONFLICT';
  end if;

  -- The holder is server-derived from the failed task; a manager cannot
  -- provide a replacement shipper or amount.  Recheck the managed role while
  -- the task/order locks are held.
  perform 1
  from public.profiles p
  where p.id = l_failed_shipper_id
    and p.role = 'shipper'::public.user_role
  for share;
  if not found then
    raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
  end if;

  select count(*)
    into l_attempt_rows
  from public.delivery_attempts a
  where a.order_id = p_order_id;
  if l_attempt_rows <> 1 then
    raise exception using errcode = 'PT409', message = 'ATTEMPT_LIMIT';
  end if;
  select a.task_id, a.order_id, a.attempt_number, a.task_kind,
         a.result, a.shipper_id
    into l_previous_attempt
  from public.delivery_attempts a
  where a.order_id = p_order_id
    and a.attempt_number = 1
    and a.task_kind = 'outbound'::public.delivery_task_kind;
  if not found
     or l_previous_attempt.task_id is distinct from l_failed_task_id
     or l_previous_attempt.result <> 'failed'::public.delivery_attempt_result
     or l_previous_attempt.shipper_id is distinct from l_failed_shipper_id then
    raise exception using errcode = 'PT409', message = 'ATTEMPT_LIMIT';
  end if;

  select c.*
    into l_custody
  from private.outbound_custody_acceptances c
  where c.task_id = l_failed_task_id;
  if not found
     or l_custody.order_id is distinct from p_order_id
     or l_custody.holder_id is distinct from l_failed_shipper_id
     or l_custody.attempt_number <> 1
     or l_custody.accepted_at is distinct from l_failed_accepted_at then
    raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
  end if;
  select d.*
    into l_dispatch
  from private.outbound_dispatches d
  where d.order_id = p_order_id
    and d.event_id = l_custody.dispatch_event_id;
  if not found
     or l_dispatch.initial_task_id is distinct from l_failed_task_id
     or l_dispatch.holder_id is distinct from l_failed_shipper_id then
    raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
  end if;
  -- Revalidate the immutable dispatch/custody proof under the manager writer
  -- RLS policies.  This is intentionally an inline read-only proof check: the
  -- existing P04 helper is shipper-scoped because its caller is accept/start.
  l_snapshot := private.outbound_items_snapshot(p_order_id);
  if l_dispatch.items_snapshot is distinct from l_snapshot then
    raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
  end if;
  select count(*), count(distinct oi.variant_id)
    into l_item_count, l_variant_count
  from public.order_items oi
  where oi.order_id = p_order_id;
  if l_item_count = 0 or l_item_count <> l_variant_count then
    raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
  end if;
  if exists (
    select 1
    from public.business_events e
    where e.incident_kind in (
      'damaged'::public.delivery_incident_kind,
      'lost'::public.delivery_incident_kind
    )
      and (
        (e.subject_type = 'order' and e.subject_id = p_order_id)
        or exists (
          select 1
          from public.delivery_tasks t
          where t.id = e.task_id and t.order_id = p_order_id
        )
      )
  ) then
    raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
  end if;
  if exists (
    select 1
    from public.inventory_movements m
    where m.order_id = p_order_id
      and (
        m.variant_id is null
        or m.variant_id not in (
          select oi.variant_id
          from public.order_items oi
          where oi.order_id = p_order_id
        )
        or m.kind not in (
          'reserve'::public.inventory_movement_kind,
          'release'::public.inventory_movement_kind,
          'dispatch'::public.inventory_movement_kind
        )
        or m.return_request_id is not null
        or (m.kind in (
          'reserve'::public.inventory_movement_kind,
          'release'::public.inventory_movement_kind
        ) and (
          m.on_hand_delta <> 0 or m.damaged_delta <> 0
          or (m.kind = 'reserve'::public.inventory_movement_kind
              and m.reserved_delta <= 0)
          or (m.kind = 'release'::public.inventory_movement_kind
              and m.reserved_delta >= 0)
        ))
      )
  ) then
    raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
  end if;
  select count(*)
    into l_dispatch_count
  from public.inventory_movements m
  where m.order_id = p_order_id
    and m.kind = 'dispatch'::public.inventory_movement_kind;
  if l_dispatch_count <> l_item_count then
    raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
  end if;
  if exists (
    select 1
    from public.inventory_movements m
    where m.order_id = p_order_id
      and m.kind = 'dispatch'::public.inventory_movement_kind
      and (
        m.event_id is distinct from l_custody.dispatch_event_id
        or m.actor_id is distinct from l_dispatch.holder_id
        or m.on_hand_delta >= 0
        or m.reserved_delta >= 0
        or m.damaged_delta <> 0
        or m.return_request_id is not null
        or m.variant_id not in (
          select oi.variant_id
          from public.order_items oi
          where oi.order_id = p_order_id
        )
      )
  ) then
    raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
  end if;
  for l_item in
    select oi.variant_id, oi.quantity
    from public.order_items oi
    where oi.order_id = p_order_id
    order by oi.variant_id
  loop
    select count(*), coalesce(sum(m.reserved_delta), 0)
      into l_movement_count, l_reserved_sum
    from public.inventory_movements m
    where m.order_id = p_order_id
      and m.variant_id = l_item.variant_id
      and m.kind in (
        'reserve'::public.inventory_movement_kind,
        'release'::public.inventory_movement_kind
      );
    if l_movement_count = 0 or l_reserved_sum <> l_item.quantity then
      raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
    end if;
    select count(*), coalesce(sum(m.on_hand_delta), 0)
      into l_movement_count, l_on_hand_sum
    from public.inventory_movements m
    where m.order_id = p_order_id
      and m.variant_id = l_item.variant_id
      and m.kind = 'dispatch'::public.inventory_movement_kind;
    if l_movement_count <> 1 or l_on_hand_sum <> -l_item.quantity then
      raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
    end if;
    select m.*
      into l_dispatch_row
    from public.inventory_movements m
    where m.order_id = p_order_id
      and m.variant_id = l_item.variant_id
      and m.kind = 'dispatch'::public.inventory_movement_kind;
    if l_dispatch_row.event_id is distinct from l_custody.dispatch_event_id
       or l_dispatch_row.reserved_delta <> -l_item.quantity
       or l_dispatch_row.on_hand_delta <> -l_item.quantity
       or l_dispatch_row.damaged_delta <> 0
       or l_dispatch_row.actor_id is distinct from l_dispatch.holder_id then
      raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
    end if;
  end loop;

  -- Decisions are serialized by the order lock.  A request with a different
  -- manager/key cannot replace the first decision; only an explicit task-2
  -- expected ID can authorize the single retry -> return transition.
  for l_decision_row in
    select d.*
    from private.outbound_retry_decisions d
    where d.order_id = p_order_id
    order by d.decision_number, d.id
  loop
    l_decision_count := l_decision_count + 1;
    if l_decision_count = 1 then
      l_first_decision := l_decision_row.decision;
    elsif l_decision_count = 2 then
      l_second_decision := l_decision_row.decision;
    else
      raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
    end if;
  end loop;

  if l_decision_count = 0 then
    if l_outbound_task_count <> 1
       or l_attempt_two_count <> 0
       or l_order.status <> 'awaiting_redelivery'::public.order_status
       or p_expected_retry_task_id is not null then
      raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
    end if;
    l_decision_number := 1;
  elsif l_decision_count = 1 then
    if l_first_decision <> 'retry'
       or l_decision <> 'return_to_store'
       or not l_retry_found
       or p_expected_retry_task_id is null
       or l_retry_task_id is distinct from p_expected_retry_task_id
       or l_outbound_task_count <> 2
       or l_attempt_two_count <> 1
       or l_order.status <> 'awaiting_pickup'::public.order_status then
      raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
    end if;
    l_decision_number := 2;
  else
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;

  if l_decision = 'retry' then
    if l_decision_count <> 0 then
      raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
    end if;
    l_retry_task_id := pg_catalog.gen_random_uuid();
    l_now := pg_catalog.clock_timestamp();
    insert into public.delivery_tasks (
      id, order_id, kind, assigned_shipper_id, assigned_by, status,
      attempt_number, destination_name, destination_phone,
      destination_address, destination_latitude, destination_longitude,
      amount_to_collect_vnd, assigned_at
    ) values (
      l_retry_task_id, p_order_id, 'outbound'::public.delivery_task_kind,
      l_failed_shipper_id, l_actor_id, 'assigned'::public.delivery_task_status,
      2, l_order.recipient_name, l_order.recipient_phone,
      l_order.address_detail, l_order.latitude, l_order.longitude,
      l_order.total_cod_vnd, l_now
    );
    l_from_order_status := 'awaiting_redelivery'::public.order_status;
    l_to_order_status := 'awaiting_pickup'::public.order_status;
    l_task_status := 'assigned'::public.delivery_task_status;
    l_target_task_id := l_retry_task_id;
  elsif l_decision = 'return_to_store' and l_decision_count = 0 then
    l_now := pg_catalog.clock_timestamp();
    l_from_order_status := 'awaiting_redelivery'::public.order_status;
    l_to_order_status := 'awaiting_store_return'::public.order_status;
    l_task_status := 'failed'::public.delivery_task_status;
    l_target_task_id := l_failed_task_id;
    l_retry_task_id := null;
  else
    -- The second return decision cancels task 2 but leaves its holder/custody
    -- row untouched.  The trigger guard below sees the decision row before
    -- this UPDATE and permits only this exact status transition.
    if l_retry_status not in (
         'assigned'::public.delivery_task_status,
         'accepted'::public.delivery_task_status
       )
       or l_retry_shipper_id is distinct from l_failed_shipper_id
       or l_retry_assigned_by is null
       or l_retry_attempt <> 2
       or l_retry_amount is distinct from l_order.total_cod_vnd
       or l_retry_name is distinct from l_order.recipient_name
       or l_retry_phone is distinct from l_order.recipient_phone
       or l_retry_address is distinct from l_order.address_detail
       or l_retry_latitude is distinct from l_order.latitude
       or l_retry_longitude is distinct from l_order.longitude
       or l_retry_assigned_at is null
       or l_retry_assigned_at > pg_catalog.clock_timestamp()
       or l_retry_started_at is not null
       or l_retry_completed_at is not null
       or l_retry_failure_reason is not null
       or l_retry_cancel_reason is not null
       or (
         l_retry_status = 'accepted'::public.delivery_task_status
         and (
           l_retry_accepted_at is null
           or not exists (
             select 1
             from private.outbound_custody_acceptances c
             where c.task_id = l_retry_task_id
               and c.order_id = p_order_id
               and c.holder_id = l_failed_shipper_id
               and c.dispatch_event_id = l_custody.dispatch_event_id
               and c.attempt_number = 2
               and c.accepted_at is not distinct from l_retry_accepted_at
           )
         )
       ) then
      raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
    end if;
    if l_retry_status = 'assigned'::public.delivery_task_status
       and (
         l_retry_accepted_at is not null
         or exists (
           select 1
           from private.outbound_custody_acceptances c
           where c.task_id = l_retry_task_id
         )
       ) then
      raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
    end if;
    l_now := pg_catalog.clock_timestamp();
    l_from_order_status := 'awaiting_pickup'::public.order_status;
    l_to_order_status := 'awaiting_store_return'::public.order_status;
    l_task_status := 'cancelled'::public.delivery_task_status;
    l_target_task_id := l_retry_task_id;
  end if;

  l_event_id := pg_catalog.gen_random_uuid();
  l_response := pg_catalog.jsonb_build_object(
    'task_id', l_target_task_id,
    'failed_task_id', l_failed_task_id,
    'retry_task_id', l_retry_task_id,
    'order_id', p_order_id,
    'operation', 'decide_outbound_retry',
    'decision', l_decision,
    'task_status', l_task_status,
    'order_status', l_to_order_status,
    'attempt_number', case
      when l_decision = 'retry' then 2 else
        case when l_decision_number = 2 then 2 else 1 end
      end,
    'delivery_attempt_count', l_order.delivery_attempt_count,
    'holder_id', l_failed_shipper_id,
    'accepted_at', case
      when l_decision = 'retry' then null
      when l_decision_number = 2 then l_retry_accepted_at
      else l_failed_accepted_at
      end,
    'started_at', null,
    'event_id', l_event_id,
    'request_id', p_request_id
  );

  insert into public.business_events (
    id, actor_id, subject_type, subject_id, from_state, to_state,
    reason, task_id, request_id, created_at
  ) values (
    l_event_id, l_actor_id, 'order', p_order_id,
    l_from_order_status::text, l_to_order_status::text,
    case when l_decision = 'retry'
      then 'outbound_retry_selected'
      else 'outbound_return_selected'
    end,
    case when l_decision_number = 2 then l_retry_task_id else null end,
    l_event_id, l_now
  );

  insert into public.notifications (
    id, recipient_id, event_id, subject_type, subject_id, title, body, created_at
  ) values (
    pg_catalog.gen_random_uuid(), l_failed_shipper_id, l_event_id,
    'delivery_task', l_target_task_id,
    'Cập nhật nhiệm vụ giao hàng',
    'Một nhiệm vụ giao hàng đã được cập nhật. Mở nhiệm vụ để xem chi tiết.',
    l_now
  );

  insert into private.outbound_retry_decisions (
    id, actor_id, request_id, order_id, failed_task_id, retry_task_id,
    decision_number, decision, from_order_status, to_order_status,
    event_id, response, created_at
  ) values (
    pg_catalog.gen_random_uuid(), l_actor_id, p_request_id, p_order_id,
    l_failed_task_id, l_retry_task_id, l_decision_number, l_decision,
    l_from_order_status, l_to_order_status, l_event_id, l_response, l_now
  );

  if l_decision_number = 2 then
    update public.delivery_tasks
    set status = 'cancelled'::public.delivery_task_status,
        completed_at = l_now,
        cancel_reason = 'manager_return_to_store',
        updated_at = l_now
    where id = l_retry_task_id;
  end if;

  update public.orders
  set status = l_to_order_status,
      updated_at = l_now
  where id = p_order_id;

  insert into private.outbound_retry_requests (
    actor_id, request_id, operation, order_id, expected_failed_task_id,
    expected_retry_task_id, decision, retry_task_id, payload_hash,
    response, created_at
  ) values (
    l_actor_id, p_request_id, 'decide_outbound_retry', p_order_id,
    p_expected_failed_task_id, p_expected_retry_task_id, l_decision,
    l_retry_task_id, l_payload_hash, l_response, l_now
  );

  return l_response;
end;
$$;

grant create on schema public to sports_store_outbound_retry_writer;
alter function public.decide_outbound_retry(uuid, uuid, text, uuid, uuid)
  owner to sports_store_outbound_retry_writer;
revoke create on schema public, private
  from sports_store_outbound_retry_writer;
revoke all on function public.decide_outbound_retry(uuid, uuid, text, uuid, uuid)
  from public, anon, service_role, sports_store_outbound_retry_writer;
grant execute on function public.decide_outbound_retry(uuid, uuid, text, uuid, uuid)
  to authenticated;

comment on function public.decide_outbound_retry(uuid, uuid, text, uuid, uuid) is
  'P07.2 manager-only first failure decision. Retry creates same-holder task 2 without dispatch/custody; return may cancel an unstarted task 2 through an append-only decision permit.';

notify pgrst, 'reload schema';
