-- P03.3: manager-only first outbound assignment/reassignment contract.
--
-- This migration intentionally owns only the outbound assignment write path.
-- It does not write delivery_attempts, inventory, notifications, or generic
-- workflow events. The caller supplies identity and optimistic concurrency
-- tokens only; all task snapshots and COD values come from the locked order.

-- The SECURITY DEFINER owner is a dedicated, non-login, non-inheriting role.
-- It is deliberately NOBYPASSRLS: the policies below are the authorization
-- boundary for every relation touched by the function.
do $$
begin
  if not exists (
    select 1 from pg_roles where rolname = 'sports_store_delivery_writer'
  ) then
    create role sports_store_delivery_writer nologin noinherit nobypassrls;
    comment on role sports_store_delivery_writer is
      'sports_store P03.3 outbound assignment writer; no-login, no-inherit, no-bypass-RLS';
  elsif not exists (
    select 1
    from pg_roles r
    where r.rolname = 'sports_store_delivery_writer'
      and not r.rolcanlogin
      and not r.rolsuper
      and not r.rolbypassrls
      and not r.rolinherit
      and not r.rolcreaterole
      and not r.rolcreatedb
      and not r.rolreplication
      and shobj_description(r.oid, 'pg_authid') =
        'sports_store P03.3 outbound assignment writer; no-login, no-inherit, no-bypass-RLS'
  ) then
    raise exception
      'P03.3 assignment writer role already exists with unexpected configuration';
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
    where granted.rolname = 'sports_store_delivery_writer'
      and member.rolname <> 'postgres'
  ) then
    raise exception
      'P03.3 assignment writer role has an unexpected membership';
  end if;
end;
$$;

grant sports_store_delivery_writer to postgres;
grant usage on schema public, auth, private to sports_store_delivery_writer;
grant execute on function auth.uid() to sports_store_delivery_writer;
grant execute on function private.current_app_role() to sports_store_delivery_writer;

-- These ledgers are intentionally private and assignment-scoped. The request
-- ledger stores the exact response for retry idempotency. The audit ledger
-- stores no destination, recipient, or other task snapshot data.
create table private.delivery_assignment_requests (
  actor_id uuid not null,
  request_id uuid not null,
  order_id uuid not null,
  shipper_id uuid not null,
  expected_task_id uuid,
  expected_shipper_id uuid,
  payload_hash text not null,
  result jsonb not null,
  created_at timestamptz not null default now(),
  primary key (actor_id, request_id),
  constraint delivery_assignment_requests_hash_nonblank
    check (btrim(payload_hash) <> ''),
  constraint delivery_assignment_requests_result_object
    check (jsonb_typeof(result) = 'object')
);

create table private.delivery_assignment_audits (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null,
  actor_id uuid not null,
  order_id uuid not null,
  task_id uuid not null,
  old_shipper_id uuid,
  new_shipper_id uuid not null,
  action text not null,
  created_at timestamptz not null default now(),
  constraint delivery_assignment_audits_action_valid
    check (action in ('assigned', 'reassigned')),
  constraint delivery_assignment_audits_shipper_changed
    check (action = 'assigned' or old_shipper_id is distinct from new_shipper_id)
);

alter table private.delivery_assignment_requests enable row level security;
alter table private.delivery_assignment_requests force row level security;
alter table private.delivery_assignment_audits enable row level security;
alter table private.delivery_assignment_audits force row level security;

create policy delivery_assignment_requests_writer_read
  on private.delivery_assignment_requests
  for select to sports_store_delivery_writer
  using (current_user = 'sports_store_delivery_writer');
create policy delivery_assignment_requests_writer_insert
  on private.delivery_assignment_requests
  for insert to sports_store_delivery_writer
  with check (current_user = 'sports_store_delivery_writer');
create policy delivery_assignment_audits_writer_insert
  on private.delivery_assignment_audits
  for insert to sports_store_delivery_writer
  with check (current_user = 'sports_store_delivery_writer');

-- Append-only means the function has no UPDATE/DELETE path, and the trigger
-- also protects the private audit/request rows if a future definer function is
-- accidentally granted table access.
create function private.reject_delivery_assignment_ledger_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'P03.3 assignment ledgers are append-only'
    using errcode = '55000';
end;
$$;

create trigger delivery_assignment_requests_append_only
before update or delete on private.delivery_assignment_requests
for each row execute function private.reject_delivery_assignment_ledger_mutation();
create trigger delivery_assignment_audits_append_only
before update or delete on private.delivery_assignment_audits
for each row execute function private.reject_delivery_assignment_ledger_mutation();

-- The writer can see only the minimum source columns needed by the function.
-- There are no authenticated INSERT/UPDATE grants added by this migration.
grant select (id, role) on public.profiles to sports_store_delivery_writer;
-- PostgreSQL requires a minimal UPDATE column privilege for a locking SELECT
-- (FOR SHARE) on this relation. The matching policy below has WITH CHECK
-- false, so this is lock-only privilege: the writer cannot mutate profiles.
grant update (id) on public.profiles to sports_store_delivery_writer;
grant select (
  id, status, recipient_name, recipient_phone, address_detail, latitude,
  longitude, total_cod_vnd, delivery_attempt_count
) on public.orders to sports_store_delivery_writer;
grant update (status, updated_at) on public.orders
  to sports_store_delivery_writer;
grant select (
  id, order_id, kind, assigned_shipper_id, assigned_by, status,
  attempt_number, destination_name, destination_phone, destination_address,
  destination_latitude, destination_longitude, amount_to_collect_vnd,
  assigned_at, accepted_at, started_at, completed_at, failure_reason,
  cancel_reason
) on public.delivery_tasks to sports_store_delivery_writer;
grant insert (
  id, order_id, kind, assigned_shipper_id, assigned_by, status, attempt_number,
  destination_name, destination_phone, destination_address,
  destination_latitude, destination_longitude, amount_to_collect_vnd,
  assigned_at
) on public.delivery_tasks to sports_store_delivery_writer;
grant update (assigned_shipper_id, assigned_by, status, assigned_at, updated_at)
  on public.delivery_tasks to sports_store_delivery_writer;
grant select (order_id, task_id, attempt_number, result)
  on public.delivery_attempts to sports_store_delivery_writer;
grant select (
  order_id, shipper_id, status, expected_amount_vnd, collected_amount_vnd,
  received_amount_vnd, collected_at, collected_by, handed_over_at,
  received_at, received_by
) on public.cod_collections to sports_store_delivery_writer;
grant insert (order_id, shipper_id, status, expected_amount_vnd)
  on public.cod_collections to sports_store_delivery_writer;
grant update (shipper_id, status, expected_amount_vnd, updated_at)
  on public.cod_collections to sports_store_delivery_writer;
grant select on private.delivery_assignment_requests
  to sports_store_delivery_writer;
grant insert on private.delivery_assignment_requests
  to sports_store_delivery_writer;
grant insert on private.delivery_assignment_audits
  to sports_store_delivery_writer;

-- RLS is an additional server-side gate for the dedicated writer. It checks
-- the server-managed profile through the existing SECURITY DEFINER helper;
-- JWT role claims and user metadata are not consulted.
create policy delivery_assignment_writer_profiles
  on public.profiles
  for select to sports_store_delivery_writer
  using (
    id = (select auth.uid())
    or role = 'shipper'::public.user_role
  );
create policy delivery_assignment_writer_profiles_lock_only
  on public.profiles
  for update to sports_store_delivery_writer
  using ((select private.current_app_role()) in ('manager', 'shipper'))
  with check (false);

create policy delivery_assignment_writer_orders_read
  on public.orders
  for select to sports_store_delivery_writer
  using ((select private.current_app_role()) = 'manager');
create policy delivery_assignment_writer_orders_update
  on public.orders
  for update to sports_store_delivery_writer
  using ((select private.current_app_role()) = 'manager')
  with check ((select private.current_app_role()) = 'manager');

create policy delivery_assignment_writer_tasks_read
  on public.delivery_tasks
  for select to sports_store_delivery_writer
  using ((select private.current_app_role()) = 'manager');
create policy delivery_assignment_writer_tasks_insert
  on public.delivery_tasks
  for insert to sports_store_delivery_writer
  with check ((select private.current_app_role()) = 'manager');
create policy delivery_assignment_writer_tasks_update
  on public.delivery_tasks
  for update to sports_store_delivery_writer
  using ((select private.current_app_role()) = 'manager')
  with check ((select private.current_app_role()) = 'manager');

create policy delivery_assignment_writer_attempts_read
  on public.delivery_attempts
  for select to sports_store_delivery_writer
  using ((select private.current_app_role()) = 'manager');

create policy delivery_assignment_writer_cod_read
  on public.cod_collections
  for select to sports_store_delivery_writer
  using ((select private.current_app_role()) = 'manager');
create policy delivery_assignment_writer_cod_insert
  on public.cod_collections
  for insert to sports_store_delivery_writer
  with check ((select private.current_app_role()) = 'manager');
create policy delivery_assignment_writer_cod_update
  on public.cod_collections
  for update to sports_store_delivery_writer
  using ((select private.current_app_role()) = 'manager')
  with check ((select private.current_app_role()) = 'manager');

create or replace function public.assign_delivery_task(
  p_order_id uuid,
  p_shipper_id uuid,
  p_request_id uuid,
  p_expected_task_id uuid default null,
  p_expected_shipper_id uuid default null
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
  l_existing private.delivery_assignment_requests%rowtype;
  l_order_status public.order_status;
  l_order_total bigint;
  l_attempt_count smallint;
  l_recipient_name text;
  l_recipient_phone text;
  l_address text;
  l_latitude numeric(9, 6);
  l_longitude numeric(9, 6);
  l_active_id uuid;
  l_active_status public.delivery_task_status;
  l_active_shipper uuid;
  l_active_assigned_at timestamptz;
  l_active_amount bigint;
  l_active_name text;
  l_active_phone text;
  l_active_address text;
  l_active_latitude numeric(9, 6);
  l_active_longitude numeric(9, 6);
  l_expected_found boolean := false;
  l_expected_status public.delivery_task_status;
  l_expected_shipper uuid;
  l_expected_accepted_at timestamptz;
  l_expected_started_at timestamptz;
  l_has_custody boolean := false;
  l_has_attempt boolean := false;
  l_has_terminal_attempt boolean := false;
  l_task_id uuid;
  l_assigned_at timestamptz;
  l_action text;
  l_old_shipper uuid;
  l_cod_exists boolean := false;
  l_cod_status public.cod_status;
  l_cod_shipper uuid;
  l_cod_expected bigint;
  l_cod_collected bigint;
  l_cod_received bigint;
  l_cod_collected_at timestamptz;
  l_cod_collected_by uuid;
  l_cod_handed_over_at timestamptz;
  l_cod_received_at timestamptz;
  l_cod_received_by uuid;
  l_cod_needs_write boolean := false;
  l_now timestamptz := statement_timestamp();
  l_result jsonb;
  l_task_row record;
begin
  l_actor_id := (select auth.uid());
  if l_actor_id is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;

  if p_order_id is null or p_shipper_id is null or p_request_id is null
     or (p_expected_task_id is null and p_expected_shipper_id is not null) then
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

  -- Serialize request replay before taking any business-row locks. The
  -- function touches one order per call, so the request key is sufficient to
  -- avoid cross-order retry deadlocks while preserving order-row locking.
  perform pg_advisory_xact_lock(hashtextextended(
    'sports_store.assign_delivery_task:' || l_actor_id::text || ':'
      || p_request_id::text,
    0
  ));

  -- Recheck after the request-key wait. The shared profile lock also prevents
  -- a role change from committing while this assignment is in flight.
  select p.role::text
    into l_actor_role
  from public.profiles p
  where p.id = l_actor_id
  for share;
  if l_actor_role is distinct from 'manager' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;

  l_payload_hash := md5(jsonb_build_object(
    'order_id', p_order_id,
    'shipper_id', p_shipper_id,
    'request_id', p_request_id,
    'expected_task_id', p_expected_task_id,
    'expected_shipper_id', p_expected_shipper_id
  )::text);

  select *
    into l_existing
  from private.delivery_assignment_requests r
  where r.actor_id = l_actor_id
    and r.request_id = p_request_id;
  if found then
    if l_existing.payload_hash <> l_payload_hash
       or l_existing.order_id is distinct from p_order_id
       or l_existing.shipper_id is distinct from p_shipper_id
       or l_existing.expected_task_id is distinct from p_expected_task_id
       or l_existing.expected_shipper_id is distinct from p_expected_shipper_id then
      raise exception using
        errcode = 'PT409', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return l_existing.result;
  end if;

  -- The order is always the first business row lock. Every outbound task for
  -- the order is then locked in deterministic UUID order before COD.
  select o.status, o.total_cod_vnd, o.delivery_attempt_count,
         o.recipient_name, o.recipient_phone, o.address_detail,
         o.latitude, o.longitude
    into l_order_status, l_order_total, l_attempt_count,
         l_recipient_name, l_recipient_phone, l_address,
         l_latitude, l_longitude
  from public.orders o
  where o.id = p_order_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'ORDER_NOT_FOUND';
  end if;

  -- Lock and validate the target role under the same transaction. This keeps
  -- a concurrent server-side role change from racing assignment validation.
  perform 1
  from public.profiles p
  where p.id = p_shipper_id
    and p.role = 'shipper'::public.user_role
  for share;
  if not found then
    raise exception using errcode = 'PT409', message = 'INVALID_SHIPPER';
  end if;

  for l_task_row in
    select t.id, t.status, t.assigned_shipper_id, t.assigned_at,
           t.amount_to_collect_vnd, t.destination_name, t.destination_phone,
           t.destination_address, t.destination_latitude,
           t.destination_longitude,
           t.accepted_at, t.started_at, t.completed_at, t.failure_reason,
           t.cancel_reason, t.attempt_number
    from public.delivery_tasks t
    where t.order_id = p_order_id
      and t.kind = 'outbound'::public.delivery_task_kind
    order by t.id
    for update
  loop
    if p_expected_task_id is not null
       and l_task_row.id = p_expected_task_id then
      l_expected_found := true;
      l_expected_status := l_task_row.status;
      l_expected_shipper := l_task_row.assigned_shipper_id;
      l_expected_accepted_at := l_task_row.accepted_at;
      l_expected_started_at := l_task_row.started_at;
    end if;

    if l_task_row.status in (
      'pending_assignment'::public.delivery_task_status,
      'assigned'::public.delivery_task_status,
      'accepted'::public.delivery_task_status,
      'in_transit'::public.delivery_task_status
    ) then
      if l_active_id is not null then
        raise exception using errcode = 'PT409', message = 'TASK_CONFLICT';
      end if;
      l_active_id := l_task_row.id;
      l_active_status := l_task_row.status;
      l_active_shipper := l_task_row.assigned_shipper_id;
      l_active_assigned_at := l_task_row.assigned_at;
      l_active_amount := l_task_row.amount_to_collect_vnd;
      l_active_name := l_task_row.destination_name;
      l_active_phone := l_task_row.destination_phone;
      l_active_address := l_task_row.destination_address;
      l_active_latitude := l_task_row.destination_latitude;
      l_active_longitude := l_task_row.destination_longitude;
    end if;

    if l_task_row.accepted_at is not null
       or l_task_row.started_at is not null
       or l_task_row.completed_at is not null
       or l_task_row.failure_reason is not null
       or l_task_row.cancel_reason is not null then
      l_has_custody := true;
    end if;
    if l_task_row.attempt_number > 1
       or l_task_row.status in (
         'delivered'::public.delivery_task_status,
         'failed'::public.delivery_task_status,
         'returned_to_store'::public.delivery_task_status,
         'manager_action_required'::public.delivery_task_status
       ) then
      l_has_terminal_attempt := true;
    end if;
  end loop;

  select exists (
    select 1 from public.delivery_attempts a
    where a.order_id = p_order_id
  )
    into l_has_attempt;

  if l_attempt_count > 0 or l_has_attempt or l_has_terminal_attempt then
    raise exception using errcode = 'PT409', message = 'ATTEMPT_LIMIT';
  end if;
  if l_has_custody then
    raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
  end if;
  if l_active_id is not null
     and l_active_amount is distinct from l_order_total then
    raise exception using errcode = 'PT409', message = 'COD_CONFLICT';
  end if;
  if l_active_id is not null
     and (
       l_active_name is distinct from l_recipient_name
       or l_active_phone is distinct from l_recipient_phone
       or l_active_address is distinct from l_address
       or l_active_latitude is distinct from l_latitude
       or l_active_longitude is distinct from l_longitude
     ) then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;

  if l_active_id is not null then
    if p_expected_task_id is null then
      raise exception using errcode = 'PT409', message = 'TASK_CONFLICT';
    end if;
    if p_expected_task_id <> l_active_id then
      raise exception using errcode = 'PT409', message = 'STALE_ASSIGNMENT';
    end if;
    if not l_expected_found then
      raise exception using errcode = 'PT409', message = 'STALE_ASSIGNMENT';
    end if;
    if l_active_status in (
      'accepted'::public.delivery_task_status,
      'in_transit'::public.delivery_task_status
    ) or l_expected_accepted_at is not null
       or l_expected_started_at is not null then
      raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
    end if;
    if l_active_status = 'assigned'::public.delivery_task_status
       and l_order_status <> 'awaiting_pickup'::public.order_status then
      raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
    end if;
    if l_active_status = 'assigned'::public.delivery_task_status
       and l_active_assigned_at is null then
      raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
    end if;
    if l_active_status = 'pending_assignment'::public.delivery_task_status
       and l_order_status <> 'preparing'::public.order_status then
      raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
    end if;
    if l_active_status = 'pending_assignment'::public.delivery_task_status
       and l_active_shipper is not null then
      raise exception using errcode = 'PT409', message = 'STALE_ASSIGNMENT';
    end if;
    if l_active_shipper is distinct from p_expected_shipper_id then
      raise exception using errcode = 'PT409', message = 'STALE_ASSIGNMENT';
    end if;
    if l_active_shipper = p_shipper_id
       and l_active_status = 'assigned'::public.delivery_task_status then
      l_task_id := l_active_id;
      l_assigned_at := l_active_assigned_at;
      l_action := 'noop';
    else
      l_task_id := l_active_id;
      l_old_shipper := l_active_shipper;
      l_action := case
        when l_active_status = 'pending_assignment'::public.delivery_task_status
          then 'assigned'
        else 'reassigned'
      end;
    end if;
  else
    if p_expected_task_id is not null then
      if not l_expected_found then
        raise exception using errcode = 'PT409', message = 'STALE_ASSIGNMENT';
      end if;
      if l_expected_accepted_at is not null or l_expected_started_at is not null
         or l_expected_status in (
           'accepted'::public.delivery_task_status,
           'in_transit'::public.delivery_task_status,
           'delivered'::public.delivery_task_status,
           'failed'::public.delivery_task_status,
           'returned_to_store'::public.delivery_task_status,
           'manager_action_required'::public.delivery_task_status
         ) then
        raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
      end if;
      raise exception using errcode = 'PT409', message = 'STALE_ASSIGNMENT';
    end if;
    if l_order_status <> 'preparing'::public.order_status then
      raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
    end if;
    l_action := 'assigned';
  end if;

  -- COD is locked after order/tasks and may only be created or reconciled in
  -- the clean uncollected state. Historical custody is never repaired here.
  select c.status, c.shipper_id, c.expected_amount_vnd,
         c.collected_amount_vnd, c.received_amount_vnd,
         c.collected_at, c.collected_by, c.handed_over_at,
         c.received_at, c.received_by
    into l_cod_status, l_cod_shipper, l_cod_expected,
         l_cod_collected, l_cod_received, l_cod_collected_at,
         l_cod_collected_by, l_cod_handed_over_at, l_cod_received_at,
         l_cod_received_by
  from public.cod_collections c
  where c.order_id = p_order_id
  for update;
  l_cod_exists := found;
  if l_cod_exists then
    if l_cod_status <> 'uncollected'::public.cod_status
       or l_cod_collected <> 0
       or l_cod_received <> 0
       or l_cod_collected_at is not null
       or l_cod_collected_by is not null
       or l_cod_handed_over_at is not null
       or l_cod_received_at is not null
       or l_cod_received_by is not null then
      raise exception using errcode = 'PT409', message = 'COD_CONFLICT';
    end if;
    l_cod_needs_write := l_cod_shipper is distinct from p_shipper_id
      or l_cod_expected is distinct from l_order_total;
  else
    l_cod_needs_write := true;
  end if;

  if not l_cod_exists then
    insert into public.cod_collections (
      order_id, shipper_id, status, expected_amount_vnd
    ) values (
      p_order_id, p_shipper_id, 'uncollected', l_order_total
    );
  elsif l_cod_needs_write then
    update public.cod_collections
    set shipper_id = p_shipper_id,
        status = 'uncollected'::public.cod_status,
        expected_amount_vnd = l_order_total,
        updated_at = l_now
    where order_id = p_order_id;
  end if;

  if l_action <> 'noop' then
    if l_task_id is null then
      l_task_id := gen_random_uuid();
      insert into public.delivery_tasks (
        id, order_id, kind, assigned_shipper_id, assigned_by, status,
        attempt_number, destination_name, destination_phone,
        destination_address, destination_latitude, destination_longitude,
        amount_to_collect_vnd, assigned_at
      ) values (
        l_task_id, p_order_id, 'outbound', p_shipper_id, l_actor_id,
        'assigned', 1, l_recipient_name, l_recipient_phone, l_address,
        l_latitude, l_longitude, l_order_total, l_now
      );
    else
      update public.delivery_tasks
      set assigned_shipper_id = p_shipper_id,
          assigned_by = l_actor_id,
          status = 'assigned'::public.delivery_task_status,
          assigned_at = l_now,
          updated_at = l_now
      where id = l_task_id;
    end if;
    l_assigned_at := coalesce(l_assigned_at, l_now);

    if l_order_status = 'preparing'::public.order_status then
      update public.orders
      set status = 'awaiting_pickup'::public.order_status,
          updated_at = l_now
      where id = p_order_id;
    end if;

    insert into private.delivery_assignment_audits (
      request_id, actor_id, order_id, task_id, old_shipper_id,
      new_shipper_id, action, created_at
    ) values (
      p_request_id, l_actor_id, p_order_id, l_task_id, l_old_shipper,
      p_shipper_id, l_action, l_now
    );
  else
    l_assigned_at := l_active_assigned_at;
  end if;

  l_result := jsonb_build_object(
    'task_id', l_task_id,
    'order_id', p_order_id,
    'shipper_id', p_shipper_id,
    'task_status', 'assigned',
    'order_status', 'awaiting_pickup',
    'attempt_number', 1,
    'amount_to_collect_vnd', l_order_total,
    'expected_amount_vnd', l_order_total,
    'total_cod_vnd', l_order_total,
    'assigned_at', l_assigned_at,
    'request_id', p_request_id
  );

  insert into private.delivery_assignment_requests (
    actor_id, request_id, order_id, shipper_id, expected_task_id,
    expected_shipper_id, payload_hash, result, created_at
  ) values (
    l_actor_id, p_request_id, p_order_id, p_shipper_id, p_expected_task_id,
    p_expected_shipper_id, l_payload_hash, l_result, l_now
  );
  return l_result;
end;
$$;

grant create on schema public to sports_store_delivery_writer;
alter function public.assign_delivery_task(uuid, uuid, uuid, uuid, uuid)
  owner to sports_store_delivery_writer;
revoke create on schema public from sports_store_delivery_writer;
revoke all on function public.assign_delivery_task(uuid, uuid, uuid, uuid, uuid)
  from public, anon, service_role, sports_store_delivery_writer;
grant execute on function public.assign_delivery_task(uuid, uuid, uuid, uuid, uuid)
  to authenticated;

comment on function public.assign_delivery_task(uuid, uuid, uuid, uuid, uuid) is
  'P03.3 manager-only outbound assignment. First assignment moves preparing to awaiting_pickup; reassignment is CAS-protected before physical acceptance. COD is created/reconciled only while uncollected.';

notify pgrst, 'reload schema';

