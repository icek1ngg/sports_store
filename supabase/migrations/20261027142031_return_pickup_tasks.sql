-- P08.1 production return-pickup assignment and collection.
--
-- This migration owns only the manager/shipper return-pickup boundary.  It
-- never creates or approves a return request, receives returned goods, makes
-- an inspection/refund decision, performs redelivery, changes COD/inventory,
-- or writes delivery_attempts.  A manager can assign only an already-approved
-- return request (the approval provenance is the server-managed decision
-- metadata on return_requests).  The approved return_items plan is copied to
-- a private, append-only task snapshot before the task is exposed to a
-- shipper.  Shipper collection is one atomic full-plan operation: all planned
-- quantities are collected, accepted_at and started_at are the same server
-- timestamp, and the return request moves to returning_to_store.

-- SECURITY DEFINER wrappers use a restricted NOLOGIN/NOBYPASSRLS owner.  The
-- role never receives access to the managed auth schema; identity is obtained
-- only through the existing private identity bridge.
do $$
begin
  if not exists (
    select 1 from pg_roles
    where rolname = 'sports_store_return_pickup_writer'
  ) then
    create role sports_store_return_pickup_writer
      nologin noinherit nobypassrls;
    comment on role sports_store_return_pickup_writer is
      'sports_store P08.1 return-pickup writer; no-login, no-inherit, no-bypass-RLS';
  elsif not exists (
    select 1
    from pg_roles r
    where r.rolname = 'sports_store_return_pickup_writer'
      and not r.rolcanlogin
      and not r.rolsuper
      and not r.rolbypassrls
      and not r.rolinherit
      and not r.rolcreaterole
      and not r.rolcreatedb
      and not r.rolreplication
      and shobj_description(r.oid, 'pg_authid') =
        'sports_store P08.1 return-pickup writer; no-login, no-inherit, no-bypass-RLS'
  ) then
    raise exception
      'P08.1 return-pickup writer role already exists with unexpected configuration';
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
    where granted.rolname = 'sports_store_return_pickup_writer'
      and member.rolname <> 'postgres'
  ) then
    raise exception 'P08.1 return-pickup writer role has unexpected membership';
  end if;
end;
$$;

grant sports_store_return_pickup_writer to postgres;
grant usage on schema public, private
  to sports_store_return_pickup_writer;
grant execute on function private.delivery_request_user_id(),
  private.current_app_role()
  to sports_store_return_pickup_writer;
grant create on schema public, private
  to sports_store_return_pickup_writer;

-- The request ledger stores the canonical client payload and exact ACK.  The
-- key is actor-scoped, while every business event gets its own server UUID.
-- The ledger is never a client-readable Data API object.
create table private.return_pickup_requests (
  actor_id uuid not null references public.profiles (id),
  request_id uuid not null,
  operation text not null,
  return_request_id uuid not null references public.return_requests (id),
  order_id uuid not null references public.orders (id),
  task_id uuid not null references public.delivery_tasks (id),
  shipper_id uuid,
  expected_task_id uuid,
  expected_shipper_id uuid,
  payload jsonb not null,
  payload_hash text not null,
  response jsonb not null,
  created_at timestamptz not null default statement_timestamp(),
  primary key (actor_id, request_id),
  constraint return_pickup_requests_operation_valid
    check (operation in (
      'assign_return_pickup_task',
      'collect_return_items',
      'fail_return_pickup_task'
    )),
  constraint return_pickup_requests_payload_object
    check (jsonb_typeof(payload) = 'object'),
  constraint return_pickup_requests_hash_nonblank
    check (btrim(payload_hash) <> ''),
  constraint return_pickup_requests_response_object
    check (jsonb_typeof(response) = 'object')
);

-- One immutable approved-plan copy per task item.  A task made by the RPC
-- always receives these rows in the same transaction as delivery_tasks INSERT.
create table private.return_pickup_task_items (
  task_id uuid not null references public.delivery_tasks (id),
  return_request_id uuid not null references public.return_requests (id),
  order_id uuid not null references public.orders (id),
  return_item_id uuid not null references public.return_items (id),
  actual_item_name text not null,
  quantity_to_collect bigint not null,
  created_at timestamptz not null default statement_timestamp(),
  primary key (task_id, return_item_id),
  constraint return_pickup_task_items_name_nonblank
    check (btrim(actual_item_name) <> ''),
  constraint return_pickup_task_items_quantity_positive
    check (quantity_to_collect > 0),
  constraint return_pickup_task_items_task_kind
    check (task_id is not null)
);

-- Collection is a custody fact, not a manager receipt.  `items` is the exact
-- canonical full-plan payload received from the shipper and is immutable.
create table private.return_pickup_custody (
  task_id uuid primary key references public.delivery_tasks (id),
  return_request_id uuid not null references public.return_requests (id),
  order_id uuid not null references public.orders (id),
  shipper_id uuid not null references public.profiles (id),
  accepted_at timestamptz not null,
  started_at timestamptz not null,
  event_id uuid not null unique references public.business_events (id),
  items jsonb not null,
  created_at timestamptz not null default statement_timestamp(),
  constraint return_pickup_custody_times_equal
    check (accepted_at = started_at),
  constraint return_pickup_custody_items_valid
    check (jsonb_typeof(items) = 'array' and jsonb_array_length(items) > 0)
);

create table private.return_pickup_assignment_audits (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null,
  actor_id uuid not null references public.profiles (id),
  return_request_id uuid not null references public.return_requests (id),
  order_id uuid not null references public.orders (id),
  task_id uuid not null references public.delivery_tasks (id),
  old_shipper_id uuid,
  new_shipper_id uuid not null references public.profiles (id),
  action text not null,
  created_at timestamptz not null default statement_timestamp(),
  constraint return_pickup_assignment_action_valid
    check (action in ('assigned', 'reassigned')),
  constraint return_pickup_assignment_shipper_changed
    check (action = 'assigned' or old_shipper_id is distinct from new_shipper_id)
);

create table private.return_pickup_failure_results (
  task_id uuid primary key references public.delivery_tasks (id),
  return_request_id uuid not null references public.return_requests (id),
  order_id uuid not null references public.orders (id),
  actor_id uuid not null references public.profiles (id),
  event_id uuid not null unique references public.business_events (id),
  request_id uuid not null,
  reason_code text not null,
  description text,
  failed_at timestamptz not null,
  response jsonb not null,
  constraint return_pickup_failure_reason_valid
    check (reason_code in (
      'unreachable', 'reschedule', 'bad_address', 'refusal', 'other'
    )),
  constraint return_pickup_failure_description_nonblank
    check (description is null or btrim(description) <> ''),
  constraint return_pickup_failure_other_description_required
    check (reason_code <> 'other'
      or (description is not null and btrim(description) <> '')),
  constraint return_pickup_failure_response_object
    check (jsonb_typeof(response) = 'object'),
  constraint return_pickup_failure_actor_request_unique
    unique (actor_id, request_id)
);

alter table private.return_pickup_requests enable row level security;
alter table private.return_pickup_requests force row level security;
alter table private.return_pickup_task_items enable row level security;
alter table private.return_pickup_task_items force row level security;
alter table private.return_pickup_custody enable row level security;
alter table private.return_pickup_custody force row level security;
alter table private.return_pickup_assignment_audits enable row level security;
alter table private.return_pickup_assignment_audits force row level security;
alter table private.return_pickup_failure_results enable row level security;
alter table private.return_pickup_failure_results force row level security;

revoke all on private.return_pickup_requests,
  private.return_pickup_task_items,
  private.return_pickup_custody,
  private.return_pickup_assignment_audits,
  private.return_pickup_failure_results
  from public, anon, authenticated, service_role;

grant select, insert on private.return_pickup_requests,
  private.return_pickup_task_items,
  private.return_pickup_custody,
  private.return_pickup_failure_results
  to sports_store_return_pickup_writer;
grant insert on private.return_pickup_assignment_audits
  to sports_store_return_pickup_writer;

create policy return_pickup_requests_writer_read
  on private.return_pickup_requests for select
  to sports_store_return_pickup_writer
  using (current_user = 'sports_store_return_pickup_writer');
create policy return_pickup_requests_writer_insert
  on private.return_pickup_requests for insert
  to sports_store_return_pickup_writer
  with check (current_user = 'sports_store_return_pickup_writer');
create policy return_pickup_task_items_writer_read
  on private.return_pickup_task_items for select
  to sports_store_return_pickup_writer
  using (current_user = 'sports_store_return_pickup_writer');
create policy return_pickup_task_items_writer_insert
  on private.return_pickup_task_items for insert
  to sports_store_return_pickup_writer
  with check (current_user = 'sports_store_return_pickup_writer');
create policy return_pickup_custody_writer_read
  on private.return_pickup_custody for select
  to sports_store_return_pickup_writer
  using (current_user = 'sports_store_return_pickup_writer');
create policy return_pickup_custody_writer_insert
  on private.return_pickup_custody for insert
  to sports_store_return_pickup_writer
  with check (current_user = 'sports_store_return_pickup_writer');
create policy return_pickup_assignment_audit_writer_insert
  on private.return_pickup_assignment_audits for insert
  to sports_store_return_pickup_writer
  with check (current_user = 'sports_store_return_pickup_writer');
create policy return_pickup_failure_writer_read
  on private.return_pickup_failure_results for select
  to sports_store_return_pickup_writer
  using (current_user = 'sports_store_return_pickup_writer');
create policy return_pickup_failure_writer_insert
  on private.return_pickup_failure_results for insert
  to sports_store_return_pickup_writer
  with check (current_user = 'sports_store_return_pickup_writer');

-- The append-only guards protect the private ledgers even if another internal
-- function is accidentally granted table UPDATE/DELETE in a future migration.
create function private.reject_return_pickup_ledger_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'P08.1 return-pickup ledgers are append-only'
    using errcode = '55000';
end;
$$;
revoke all on function private.reject_return_pickup_ledger_mutation()
  from public, anon, authenticated, service_role;

create trigger return_pickup_requests_append_only
before update or delete on private.return_pickup_requests
for each row execute function private.reject_return_pickup_ledger_mutation();
create trigger return_pickup_task_items_append_only
before update or delete on private.return_pickup_task_items
for each row execute function private.reject_return_pickup_ledger_mutation();
create trigger return_pickup_custody_append_only
before update or delete on private.return_pickup_custody
for each row execute function private.reject_return_pickup_ledger_mutation();
create trigger return_pickup_assignment_audits_append_only
before update or delete on private.return_pickup_assignment_audits
for each row execute function private.reject_return_pickup_ledger_mutation();
create trigger return_pickup_failure_append_only
before update or delete on private.return_pickup_failure_results
for each row execute function private.reject_return_pickup_ledger_mutation();

-- A snapshot is not allowed to drift while any return-pickup task is active or
-- has custody.  Inspection may still update quantity_collected/sellable/
-- damaged_quantity after the task reaches the separate receipt boundary.
create function private.guard_return_pickup_plan_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  l_old_request uuid;
  l_new_request uuid;
begin
  if tg_op <> 'INSERT' then l_old_request := old.return_request_id; end if;
  if tg_op <> 'DELETE' then l_new_request := new.return_request_id; end if;
  -- Serialize the approval item-set check with assignment before inspecting
  -- committed snapshots. FK checks alone happen after BEFORE INSERT and
  -- cannot prevent an insert from passing against an uncommitted snapshot.
  perform r.id from public.return_requests r
  where r.id in (l_old_request,l_new_request)
  order by r.id for update;
  if tg_op <> 'UPDATE'
     or old.return_request_id is distinct from new.return_request_id
     or old.order_id is distinct from new.order_id
     or old.order_item_id is distinct from new.order_item_id
     or old.actual_item_name is distinct from new.actual_item_name
     or old.variant_id is distinct from new.variant_id
     or old.quantity_to_collect is distinct from new.quantity_to_collect then
    if exists (
      select 1
      from private.return_pickup_task_items s
      where s.return_request_id in (l_old_request,l_new_request)
    ) or exists (
      select 1 from private.return_pickup_custody c
      where c.return_request_id in (l_old_request,l_new_request)
    ) then
      raise exception using errcode = 'PT409', message = 'PLAN_IMMUTABLE';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function private.guard_return_pickup_plan_mutation()
  from public, anon, authenticated, service_role;
create trigger return_items_plan_immutable
before insert or delete or update of return_request_id, order_id, order_item_id,
  actual_item_name, variant_id, quantity_to_collect
on public.return_items
for each row execute function private.guard_return_pickup_plan_mutation();

-- Internal writer column ACLs.  UPDATE privileges used solely for FOR UPDATE
-- row locks are paired with false WITH CHECK policies below where the function
-- does not change the relation.
grant select (id, role) on public.profiles
  to sports_store_return_pickup_writer;
grant update (id) on public.profiles
  to sports_store_return_pickup_writer;
grant select (
  id, status, recipient_name, recipient_phone, address_detail, latitude,
  longitude
) on public.orders to sports_store_return_pickup_writer;
grant update (id) on public.orders
  to sports_store_return_pickup_writer;
grant select (
  id, order_id, customer_id, status, decided_by, decision_at
) on public.return_requests to sports_store_return_pickup_writer;
grant update (id, status, updated_at) on public.return_requests
  to sports_store_return_pickup_writer;
grant select (
  id, order_id, return_request_id, kind, assigned_shipper_id, assigned_by,
  status, attempt_number, destination_name, destination_phone,
  destination_address, destination_latitude, destination_longitude,
  amount_to_collect_vnd, assigned_at, accepted_at, started_at, completed_at,
  failure_reason, cancel_reason, created_at
) on public.delivery_tasks to sports_store_return_pickup_writer;
grant insert (
  id, order_id, return_request_id, kind, assigned_shipper_id, assigned_by,
  status, attempt_number, destination_name, destination_phone,
  destination_address, destination_latitude, destination_longitude,
  amount_to_collect_vnd, assigned_at
) on public.delivery_tasks to sports_store_return_pickup_writer;
grant update (
  assigned_shipper_id, assigned_by, status, assigned_at, accepted_at,
  started_at, completed_at, failure_reason, updated_at
) on public.delivery_tasks to sports_store_return_pickup_writer;
-- SELECT ... FOR UPDATE requires an UPDATE privilege; id is lock-only and is
-- not included in any RPC mutation SET list.
grant update (id) on public.delivery_tasks
  to sports_store_return_pickup_writer;
grant select (
  id, return_request_id, order_id, actual_item_name, quantity_to_collect,
  quantity_collected, sellable_quantity, damaged_quantity
) on public.return_items to sports_store_return_pickup_writer;
grant update (quantity_collected, updated_at) on public.return_items
  to sports_store_return_pickup_writer;
grant insert (
  id, actor_id, subject_type, subject_id, from_state, to_state, reason,
  task_id, request_id, created_at
) on public.business_events to sports_store_return_pickup_writer;
grant select (id, actor_id, subject_id, task_id, incident_kind, request_id)
  on public.business_events to sports_store_return_pickup_writer;
grant insert (
  id, recipient_id, event_id, subject_type, subject_id, title, body, created_at
) on public.notifications to sports_store_return_pickup_writer;

-- Writer RLS is deliberately narrower than the existing manager/customer
-- policies.  The RPCs repeat identity/role checks after each advisory wait;
-- these policies remain the table-level backstop.
create policy return_pickup_writer_profiles_read
  on public.profiles for select
  to sports_store_return_pickup_writer
  using (
    current_user = 'sports_store_return_pickup_writer'
    and (
      id = (select private.delivery_request_user_id())
      or role in (
        'shipper'::public.user_role,
        'manager'::public.user_role
      )
    )
  );
create policy return_pickup_writer_profiles_lock
  on public.profiles for update
  to sports_store_return_pickup_writer
  using (
    current_user = 'sports_store_return_pickup_writer'
    and role in (
      'manager'::public.user_role,
      'shipper'::public.user_role
    )
  )
  with check (false);

create policy return_pickup_writer_orders_read
  on public.orders for select
  to sports_store_return_pickup_writer
  using (
    current_user = 'sports_store_return_pickup_writer'
    and (
      (select private.current_app_role()) = 'manager'
      or (select private.current_app_role()) = 'shipper'
    )
  );
create policy return_pickup_writer_orders_lock
  on public.orders for update
  to sports_store_return_pickup_writer
  using (id is not null)
  with check (false);

create policy return_pickup_writer_returns_read
  on public.return_requests for select
  to sports_store_return_pickup_writer
  using (
    current_user = 'sports_store_return_pickup_writer'
    and (
      (select private.current_app_role()) = 'manager'
      or (select private.current_app_role()) = 'shipper'
    )
  );
create policy return_pickup_writer_returns_update
  on public.return_requests for update
  to sports_store_return_pickup_writer
  using (
    current_user = 'sports_store_return_pickup_writer'
    and (
      (select private.current_app_role()) = 'manager'
      or (select private.current_app_role()) = 'shipper'
    )
  )
  with check (
    current_user = 'sports_store_return_pickup_writer'
    and (
      ((select private.current_app_role()) = 'manager'
        and status = 'awaiting_return_pickup'::public.return_request_status)
      or (
        (select private.current_app_role()) = 'shipper'
        and status = 'returning_to_store'::public.return_request_status
      )
    )
  );

create policy return_pickup_writer_tasks_read
  on public.delivery_tasks for select
  to sports_store_return_pickup_writer
  using (
    current_user = 'sports_store_return_pickup_writer'
    and kind = 'return_pickup'::public.delivery_task_kind
    and (
      (select private.current_app_role()) = 'manager'
      or assigned_shipper_id = (select private.delivery_request_user_id())
    )
  );
create policy return_pickup_writer_tasks_insert
  on public.delivery_tasks for insert
  to sports_store_return_pickup_writer
  with check (
    current_user = 'sports_store_return_pickup_writer'
    and (select private.current_app_role()) = 'manager'
    and kind = 'return_pickup'::public.delivery_task_kind
    and status = 'assigned'::public.delivery_task_status
    and attempt_number = 1
    and amount_to_collect_vnd = 0
    and accepted_at is null
    and started_at is null
    and completed_at is null
    and failure_reason is null
    and cancel_reason is null
  );
create policy return_pickup_writer_tasks_update
  on public.delivery_tasks for update
  to sports_store_return_pickup_writer
  using (
    current_user = 'sports_store_return_pickup_writer'
    and kind = 'return_pickup'::public.delivery_task_kind
    and (
      ((select private.current_app_role()) = 'manager')
      or assigned_shipper_id = (select private.delivery_request_user_id())
    )
  )
  with check (
    current_user = 'sports_store_return_pickup_writer'
    and kind = 'return_pickup'::public.delivery_task_kind
    and attempt_number = 1
    and amount_to_collect_vnd = 0
    and (
      (
        (select private.current_app_role()) = 'manager'
        and status = 'assigned'::public.delivery_task_status
        and accepted_at is null
        and started_at is null
        and completed_at is null
        and failure_reason is null
        and cancel_reason is null
      )
      or (
        assigned_shipper_id = (select private.delivery_request_user_id())
        and status in (
          'in_transit'::public.delivery_task_status,
          'failed'::public.delivery_task_status
        )
      )
    )
  );

create policy return_pickup_writer_items_read
  on public.return_items for select
  to sports_store_return_pickup_writer
  using (
    current_user = 'sports_store_return_pickup_writer'
    and (
      (select private.current_app_role()) = 'manager'
      or (select private.current_app_role()) = 'shipper'
    )
  );
create policy return_pickup_writer_items_update
  on public.return_items for update
  to sports_store_return_pickup_writer
  using (
    current_user = 'sports_store_return_pickup_writer'
    and (select private.current_app_role()) = 'shipper'
  )
  with check (
    current_user = 'sports_store_return_pickup_writer'
    and (select private.current_app_role()) = 'shipper'
    and quantity_collected between 0 and quantity_to_collect
  );

-- Assignment validates and locks the approved plan but never changes an item.
-- PostgreSQL still requires UPDATE privilege/policy for FOR UPDATE, so keep a
-- manager-only lock policy with an always-false check expression.
create policy return_pickup_writer_items_manager_lock
  on public.return_items for update
  to sports_store_return_pickup_writer
  using (
    current_user = 'sports_store_return_pickup_writer'
    and (select private.current_app_role()) = 'manager'
  )
  with check (false);

create policy return_pickup_writer_events_insert
  on public.business_events for insert
  to sports_store_return_pickup_writer
  with check (
    current_user = 'sports_store_return_pickup_writer'
    and actor_id = (select private.delivery_request_user_id())
    and subject_type = 'delivery_task'
    and subject_id = task_id
    and task_id is not null
    and incident_kind is null
    and request_id = id
    and reason in (
      'return_pickup_assigned',
      'return_pickup_reassigned',
      'return_pickup_collected',
      'return_pickup_failed'
    )
  );
create policy return_pickup_writer_events_read
  on public.business_events for select
  to sports_store_return_pickup_writer
  using (
    current_user = 'sports_store_return_pickup_writer'
    and actor_id = (select private.delivery_request_user_id())
    and subject_type = 'delivery_task'
    and reason = 'return_pickup_failed'
  );

create policy return_pickup_writer_notifications_insert
  on public.notifications for insert
  to sports_store_return_pickup_writer
  with check (
    current_user = 'sports_store_return_pickup_writer'
    and subject_type = 'delivery_task'
    and title = 'Lấy hàng trả thất bại'
    and body = 'Một nhiệm vụ lấy hàng trả thất bại cần được xử lý.'
    and exists (
      select 1
      from public.delivery_tasks t
      join public.profiles recipient on recipient.id = notifications.recipient_id
      join public.business_events e on e.id = notifications.event_id
      where t.id = notifications.subject_id
        and e.id = notifications.event_id
        and e.subject_id = t.id
        and recipient.role = 'manager'::public.user_role
        and e.actor_id = (select private.delivery_request_user_id())
    )
  );

-- Canonical input parser shared by collect and the request payload.  It keeps
-- the existing two-key JSON contract and rejects duplicates, extra keys,
-- malformed UUIDs, non-integral/negative quantities and unsorted arrays.
create function private.normalize_return_pickup_items(p_items jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  l_element jsonb;
  l_id_text text;
  l_quantity_text text;
  l_previous uuid;
  l_id uuid;
  l_quantity bigint;
  l_count bigint;
  l_distinct_count bigint;
  l_canonical jsonb;
begin
  if p_items is null
     or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;

  for l_element in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(l_element) <> 'object'
       or (select count(*) from jsonb_object_keys(l_element)) <> 2
       or not (l_element ? 'return_item_id')
       or not (l_element ? 'quantity')
       or jsonb_typeof(l_element -> 'return_item_id') <> 'string'
       or jsonb_typeof(l_element -> 'quantity') <> 'number' then
      raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
    end if;
    l_id_text := l_element ->> 'return_item_id';
    l_quantity_text := l_element ->> 'quantity';
    if l_id_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or l_quantity_text !~ '^[0-9]+$'
       or length(l_quantity_text) > 10 then
      raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
    end if;
    l_id := l_id_text::uuid;
    l_quantity := l_quantity_text::bigint;
    if l_quantity < 1 or l_quantity > 2147483647 then
      raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
    end if;
    if l_previous is not null and l_id <= l_previous then
      raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
    end if;
    l_previous := l_id;
  end loop;

  select count(*), count(distinct (e ->> 'return_item_id')::uuid)
    into l_count, l_distinct_count
  from jsonb_array_elements(p_items) as a(e);
  if l_count <> l_distinct_count then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;

  select jsonb_agg(
           jsonb_build_object(
             'return_item_id', (e ->> 'return_item_id')::uuid,
             'quantity', (e ->> 'quantity')::bigint
           ) order by (e ->> 'return_item_id')::uuid
         )
    into l_canonical
  from jsonb_array_elements(p_items) as a(e);
  return l_canonical;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
end;
$$;
alter function private.normalize_return_pickup_items(jsonb)
  owner to sports_store_return_pickup_writer;
revoke all on function private.normalize_return_pickup_items(jsonb)
  from public, anon, authenticated, service_role;
grant execute on function private.normalize_return_pickup_items(jsonb)
  to sports_store_return_pickup_writer;

-- A deterministic plan representation is used both at assignment and at
-- collection; it never reads live quantities after a task has a snapshot.
create function private.return_pickup_plan_json(p_task_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'return_item_id', i.return_item_id,
        'quantity', i.quantity_to_collect
      ) order by i.return_item_id
    ),
    '[]'::jsonb
  )
  from private.return_pickup_task_items i
  where i.task_id = p_task_id;
$$;
alter function private.return_pickup_plan_json(uuid)
  owner to sports_store_return_pickup_writer;
revoke all on function private.return_pickup_plan_json(uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.return_pickup_plan_json(uuid)
  to sports_store_return_pickup_writer;

create function public.assign_return_pickup_task(
  p_return_request_id uuid,
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
  l_actor_id uuid := (select private.delivery_request_user_id());
  l_actor_role text;
  l_order_id uuid;
  l_order_status public.order_status;
  l_recipient_name text;
  l_recipient_phone text;
  l_address text;
  l_latitude numeric(9,6);
  l_longitude numeric(9,6);
  l_return_id uuid;
  l_return_order_id uuid;
  l_return_status public.return_request_status;
  l_decided_by uuid;
  l_decision_at timestamptz;
  l_task_row record;
  l_profile record;
  l_existing private.return_pickup_requests%rowtype;
  l_active_id uuid;
  l_active_status public.delivery_task_status;
  l_active_shipper_id uuid;
  l_active_assigned_at timestamptz;
  l_active_accepted_at timestamptz;
  l_active_started_at timestamptz;
  l_active_completed_at timestamptz;
  l_active_failure_reason text;
  l_active_cancel_reason text;
  l_active_found boolean := false;
  l_latest_failed_found boolean := false;
  l_latest_failed_id uuid;
  l_latest_failed_shipper_id uuid;
  l_latest_failed_at timestamptz;
  l_expected_found boolean := false;
  l_expected_status public.delivery_task_status;
  l_expected_shipper_id uuid;
  l_item_count bigint := 0;
  l_all_item_count bigint := 0;
  l_snapshot_count bigint := 0;
  l_live_plan jsonb;
  l_snapshot_plan jsonb;
  l_payload jsonb;
  l_payload_hash text;
  l_task_id uuid;
  l_assigned_at timestamptz;
  l_now timestamptz := pg_catalog.clock_timestamp();
  l_action text;
  l_old_shipper_id uuid;
  l_needs_snapshot boolean := false;
  l_event_id uuid;
  l_response jsonb;
  l_actor_found boolean := false;
  l_shipper_found boolean := false;
  l_approver_found boolean := false;
  l_approval_role text;
  l_item record;
begin
  if l_actor_id is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if p_return_request_id is null
     or p_shipper_id is null
     or p_request_id is null
     or (p_expected_task_id is null and p_expected_shipper_id is not null) then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.return_pickup:request:' || l_actor_id::text || ':'
      || p_request_id::text, 0));
  select p.role::text into l_actor_role
  from public.profiles p where p.id = l_actor_id;
  if l_actor_role is distinct from 'manager' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;

  select r.order_id into l_order_id
  from public.return_requests r where r.id = p_return_request_id;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.complete_outbound_delivery:order:' || l_order_id::text, 0));

  select o.status, o.recipient_name, o.recipient_phone, o.address_detail,
         o.latitude, o.longitude
    into l_order_status, l_recipient_name, l_recipient_phone, l_address,
         l_latitude, l_longitude
  from public.orders o where o.id = l_order_id for update;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;

  select r.id, r.order_id, r.status, r.decided_by, r.decision_at
    into l_return_id, l_return_order_id, l_return_status, l_decided_by,
         l_decision_at
  from public.return_requests r
  where r.id = p_return_request_id
  for update;
  if not found or l_return_order_id is distinct from l_order_id then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;

  for l_task_row in
    select t.id, t.order_id, t.return_request_id, t.kind,
           t.assigned_shipper_id, t.status, t.attempt_number,
           t.amount_to_collect_vnd, t.assigned_at, t.accepted_at,
           t.started_at, t.completed_at, t.failure_reason, t.cancel_reason,
           t.created_at
    from public.delivery_tasks t
    where t.return_request_id = p_return_request_id
    order by t.id
    for update
  loop
    if l_task_row.order_id is distinct from l_order_id
       or l_task_row.kind <> 'return_pickup'::public.delivery_task_kind
       or l_task_row.attempt_number <> 1
       or l_task_row.amount_to_collect_vnd <> 0 then
      raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
    end if;
    if p_expected_task_id is not null
       and l_task_row.id = p_expected_task_id then
      l_expected_found := true;
      l_expected_status := l_task_row.status;
      l_expected_shipper_id := l_task_row.assigned_shipper_id;
    end if;
    if l_task_row.status = 'failed'::public.delivery_task_status
       and (
         not l_latest_failed_found
         or coalesce(l_task_row.completed_at, l_task_row.created_at)
              > l_latest_failed_at
         or (
           coalesce(l_task_row.completed_at, l_task_row.created_at)
             = l_latest_failed_at
           and l_task_row.id > l_latest_failed_id
         )
       ) then
      l_latest_failed_found := true;
      l_latest_failed_id := l_task_row.id;
      l_latest_failed_shipper_id := l_task_row.assigned_shipper_id;
      l_latest_failed_at := coalesce(l_task_row.completed_at, l_task_row.created_at);
    end if;
    if l_task_row.status in (
      'pending_assignment'::public.delivery_task_status,
      'assigned'::public.delivery_task_status,
      'accepted'::public.delivery_task_status,
      'in_transit'::public.delivery_task_status,
      'manager_action_required'::public.delivery_task_status
    ) then
      if l_active_found then
        raise exception using errcode = 'PT409', message = 'TASK_CONFLICT';
      end if;
      l_active_found := true;
      l_active_id := l_task_row.id;
      l_active_status := l_task_row.status;
      l_active_shipper_id := l_task_row.assigned_shipper_id;
      l_active_assigned_at := l_task_row.assigned_at;
      l_active_accepted_at := l_task_row.accepted_at;
      l_active_started_at := l_task_row.started_at;
      l_active_completed_at := l_task_row.completed_at;
      l_active_failure_reason := l_task_row.failure_reason;
      l_active_cancel_reason := l_task_row.cancel_reason;
    end if;
  end loop;

  -- Lock snapshot rows before live return_items.  New tasks have no rows yet;
  -- their rows are inserted only after the task row exists.
  for l_task_row in
    select i.task_id, i.return_item_id
    from private.return_pickup_task_items i
    where i.return_request_id = p_return_request_id
    order by i.task_id, i.return_item_id
  loop
    null;
  end loop;
  for l_item in
    select i.id, i.order_id, i.actual_item_name, i.quantity_to_collect,
           i.quantity_collected, i.sellable_quantity, i.damaged_quantity
    from public.return_items i
    where i.return_request_id = p_return_request_id
    order by i.id
    for update
  loop
    l_all_item_count := l_all_item_count + 1;
    if l_item.order_id is distinct from l_order_id
       or l_item.quantity_to_collect <= 0 then
      raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
    end if;
  end loop;
  if l_all_item_count = 0 then
    raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
  end if;

  -- A task created by an older workflow has no immutable approved-plan
  -- snapshot.  Do not silently adopt its live return_items rows as a new
  -- assignment: only this RPC may create a pickup task, and every such task
  -- must be pinned before it is exposed to a shipper.
  if l_active_found then
    select count(*) into l_snapshot_count
    from private.return_pickup_task_items i
    where i.task_id = l_active_id;
    if l_snapshot_count = 0 then
      raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
    end if;
  end if;

  -- Lock actor, target shipper and the historical approving manager in UUID
  -- order.  Approval is server provenance, not a client-writable status.
  for l_profile in
    select p.id, p.role::text
    from public.profiles p
    where p.id in (l_actor_id, p_shipper_id, l_decided_by)
    order by p.id
    for share
  loop
    if l_profile.id = l_actor_id then
      l_actor_found := true;
      l_actor_role := l_profile.role;
    end if;
    if l_profile.id = p_shipper_id then
      l_shipper_found := true;
      if l_profile.role <> 'shipper' then
        raise exception using errcode = 'PT409', message = 'INVALID_SHIPPER';
      end if;
    end if;
    if l_decided_by is not null and l_profile.id = l_decided_by then
      l_approver_found := true;
      l_approval_role := l_profile.role;
    end if;
  end loop;
  if not l_actor_found or l_actor_role is distinct from 'manager' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;
  if not l_shipper_found then
    raise exception using errcode = 'PT409', message = 'INVALID_SHIPPER';
  end if;

  select coalesce(
           jsonb_agg(
             jsonb_build_object('return_item_id', i.id,
                                'quantity', i.quantity_to_collect)
             order by i.id), '[]'::jsonb), count(*)
    into l_live_plan, l_item_count
  from public.return_items i
  where i.return_request_id = p_return_request_id
    and i.order_id = l_order_id;
  if l_item_count <> l_all_item_count then
    raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
  end if;

  l_payload := jsonb_build_object(
    'operation', 'assign_return_pickup_task',
    'return_request_id', p_return_request_id,
    'shipper_id', p_shipper_id,
    'request_id', p_request_id,
    'expected_task_id', p_expected_task_id,
    'expected_shipper_id', p_expected_shipper_id,
    'plan', l_live_plan
  );
  l_payload_hash := md5(l_payload::text);

  select r.* into l_existing
  from private.return_pickup_requests r
  where r.actor_id = l_actor_id and r.request_id = p_request_id;
  if found then
    if l_existing.operation <> 'assign_return_pickup_task'
       or l_existing.return_request_id is distinct from p_return_request_id
       or l_existing.shipper_id is distinct from p_shipper_id
       or l_existing.expected_task_id is distinct from p_expected_task_id
       or l_existing.expected_shipper_id is distinct from p_expected_shipper_id
       or l_existing.payload_hash <> l_payload_hash
       or l_existing.payload is distinct from l_payload then
      raise exception using errcode = 'PT409', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return l_existing.response;
  end if;

  if l_return_status <> 'awaiting_return_pickup'::public.return_request_status
     or l_order_status <> 'delivered'::public.order_status
     or l_decided_by is null
     or l_decision_at is null
     or l_decision_at > l_now
     or not l_approver_found
     or l_approval_role is distinct from 'manager' then
    raise exception using errcode = 'PT409', message = 'APPROVAL_UNRESOLVED';
  end if;
  if exists (
    select 1 from public.return_items i
    where i.return_request_id = p_return_request_id
      and (i.quantity_collected <> 0
        or i.sellable_quantity <> 0
        or i.damaged_quantity <> 0
        or i.quantity_to_collect > 2147483647)
  ) then
    raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
  end if;

  if l_active_found then
    if l_active_status in (
      'accepted'::public.delivery_task_status,
      'in_transit'::public.delivery_task_status,
      'manager_action_required'::public.delivery_task_status
    )
       or l_active_accepted_at is not null
       or l_active_started_at is not null
       or exists (
         select 1 from private.return_pickup_custody c
         where c.task_id = l_active_id
       ) then
      raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
    end if;
    if not l_expected_found
       or p_expected_task_id is distinct from l_active_id
       or p_expected_shipper_id is distinct from l_active_shipper_id then
      raise exception using errcode = 'PT409', message = 'STALE_ASSIGNMENT';
    end if;
    if l_active_status = 'pending_assignment'::public.delivery_task_status then
      if l_active_shipper_id is not null
         or l_active_assigned_at is not null
         or p_expected_shipper_id is not null then
        raise exception using errcode = 'PT409', message = 'STALE_ASSIGNMENT';
      end if;
      l_task_id := l_active_id;
      l_action := 'assigned';
      l_old_shipper_id := null;
    elsif l_active_status = 'assigned'::public.delivery_task_status then
      if l_active_shipper_id is null
         or l_active_assigned_at is null
         or l_active_completed_at is not null
         or l_active_failure_reason is not null
         or l_active_cancel_reason is not null then
        raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
      end if;
      l_task_id := l_active_id;
      if l_active_shipper_id = p_shipper_id then
        l_action := 'noop';
      else
        l_action := 'reassigned';
        l_old_shipper_id := l_active_shipper_id;
      end if;
    else
      raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
    end if;
  else
    if l_latest_failed_found then
      if p_expected_task_id is null
         or p_expected_task_id is distinct from l_latest_failed_id
         or p_expected_shipper_id is distinct from l_latest_failed_shipper_id then
        raise exception using errcode = 'PT409', message = 'STALE_ASSIGNMENT';
      end if;
      if exists (
        select 1 from private.return_pickup_custody c
        where c.task_id = l_latest_failed_id
      ) then
        raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
      end if;
    elsif p_expected_task_id is not null then
      if not l_expected_found then
        raise exception using errcode = 'PT409', message = 'STALE_ASSIGNMENT';
      end if;
      -- A failed pickup remains an immutable CAS anchor.  The next manager
      -- call may create another task (without an attempt cap), but must name
      -- the exact failed task and its prior assignee.
      if l_expected_status <> 'failed'::public.delivery_task_status
         or l_expected_shipper_id is null
         or p_expected_shipper_id is distinct from l_expected_shipper_id
         or exists (
           select 1 from private.return_pickup_custody c
           where c.task_id = p_expected_task_id
         ) then
        raise exception using errcode = 'PT409', message = 'STALE_ASSIGNMENT';
      end if;
    end if;
    l_task_id := pg_catalog.gen_random_uuid();
    l_action := 'assigned';
    l_needs_snapshot := true;
  end if;

  select count(*) into l_snapshot_count
  from private.return_pickup_task_items i
  where i.task_id = l_task_id;
  if l_snapshot_count = 0 then
    if l_active_found then
      -- Existing tasks without an approved task snapshot are not silently
      -- adopted. Their read compatibility is not proof of an approved plan.
      raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
    end if;
    l_needs_snapshot := true;
  else
    l_snapshot_plan := private.return_pickup_plan_json(l_task_id);
    if l_snapshot_plan is distinct from l_live_plan then
      raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
    end if;
  end if;

  if l_action = 'assigned' and not l_active_found then
    l_assigned_at := l_now;
    insert into public.delivery_tasks (
      id, order_id, return_request_id, kind, assigned_shipper_id, assigned_by,
      status, attempt_number, destination_name, destination_phone,
      destination_address, destination_latitude, destination_longitude,
      amount_to_collect_vnd, assigned_at
    ) values (
      l_task_id, l_order_id, p_return_request_id,
      'return_pickup'::public.delivery_task_kind, p_shipper_id, l_actor_id,
      'assigned'::public.delivery_task_status, 1,
      l_recipient_name, l_recipient_phone, l_address, l_latitude, l_longitude,
      0, l_now
    );
  elsif l_action in ('assigned', 'reassigned') then
    l_assigned_at := l_now;
    update public.delivery_tasks
    set assigned_shipper_id = p_shipper_id,
        assigned_by = l_actor_id,
        status = 'assigned'::public.delivery_task_status,
        assigned_at = l_now,
        updated_at = l_now
    where id = l_task_id;
  else
    l_assigned_at := l_active_assigned_at;
  end if;

  if l_needs_snapshot then
    for l_item in
      select i.id, i.actual_item_name, i.quantity_to_collect
      from public.return_items i
      where i.return_request_id = p_return_request_id
        and i.order_id = l_order_id
      order by i.id
    loop
      insert into private.return_pickup_task_items (
        task_id, return_request_id, order_id, return_item_id,
        actual_item_name, quantity_to_collect
      ) values (
        l_task_id, p_return_request_id, l_order_id, l_item.id,
        l_item.actual_item_name, l_item.quantity_to_collect
      );
    end loop;
  end if;

  if l_action <> 'noop' then
    l_event_id := pg_catalog.gen_random_uuid();
    l_response := pg_catalog.jsonb_build_object(
      'task_id', l_task_id,
      'return_request_id', p_return_request_id,
      'order_id', l_order_id,
      'shipper_id', p_shipper_id,
      'operation', 'assign_return_pickup_task',
      'action', l_action,
      'task_status', 'assigned',
      'return_status', 'awaiting_return_pickup',
      'attempt_number', 1,
      'amount_to_collect_vnd', 0,
      'assigned_at', l_assigned_at,
      'event_id', l_event_id,
      'request_id', p_request_id
    );
    insert into public.business_events (
      id, actor_id, subject_type, subject_id, from_state, to_state,
      reason, task_id, request_id, created_at
    ) values (
      l_event_id, l_actor_id, 'delivery_task', l_task_id,
      case when l_action = 'reassigned' then 'assigned'
           else 'pending_assignment' end,
      'assigned',
      case when l_action = 'reassigned'
        then 'return_pickup_reassigned' else 'return_pickup_assigned' end,
      l_task_id, l_event_id, l_now
    );
  else
    l_response := pg_catalog.jsonb_build_object(
      'task_id', l_task_id,
      'return_request_id', p_return_request_id,
      'order_id', l_order_id,
      'shipper_id', p_shipper_id,
      'operation', 'assign_return_pickup_task',
      'action', 'noop',
      'task_status', 'assigned',
      'return_status', 'awaiting_return_pickup',
      'attempt_number', 1,
      'amount_to_collect_vnd', 0,
      'assigned_at', l_assigned_at,
      'event_id', null,
      'request_id', p_request_id
    );
  end if;

  if l_action <> 'noop' then
    insert into private.return_pickup_assignment_audits (
      request_id, actor_id, return_request_id, order_id, task_id,
      old_shipper_id, new_shipper_id, action, created_at
    ) values (
      p_request_id, l_actor_id, p_return_request_id, l_order_id, l_task_id,
      l_old_shipper_id, p_shipper_id, l_action, l_now
    );
  end if;
  insert into private.return_pickup_requests (
    actor_id, request_id, operation, return_request_id, order_id, task_id,
    shipper_id, expected_task_id, expected_shipper_id, payload, payload_hash,
    response, created_at
  ) values (
    l_actor_id, p_request_id, 'assign_return_pickup_task',
    p_return_request_id, l_order_id, l_task_id, p_shipper_id,
    p_expected_task_id, p_expected_shipper_id, l_payload, l_payload_hash,
    l_response, l_now
  );
  return l_response;
end;
$$;

alter function public.assign_return_pickup_task(uuid, uuid, uuid, uuid, uuid)
  owner to sports_store_return_pickup_writer;

create function public.collect_return_items(
  p_task_id uuid,
  p_request_id uuid,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  l_actor_id uuid := (select private.delivery_request_user_id());
  l_actor_role text;
  l_order_id uuid;
  l_return_request_id uuid;
  l_order_status public.order_status;
  l_return_status public.return_request_status;
  l_task_row record;
  l_profile record;
  l_existing private.return_pickup_requests%rowtype;
  l_items jsonb;
  l_plan jsonb;
  l_live_plan jsonb;
  l_payload jsonb;
  l_payload_hash text;
  l_target_found boolean := false;
  l_target_kind public.delivery_task_kind;
  l_target_shipper_id uuid;
  l_target_status public.delivery_task_status;
  l_target_attempt smallint;
  l_target_amount bigint;
  l_target_assigned_at timestamptz;
  l_target_accepted_at timestamptz;
  l_target_started_at timestamptz;
  l_target_completed_at timestamptz;
  l_target_failure_reason text;
  l_target_cancel_reason text;
  l_item_count bigint := 0;
  l_snapshot_count bigint := 0;
  l_all_item_count bigint := 0;
  l_now timestamptz := pg_catalog.clock_timestamp();
  l_event_id uuid;
  l_response jsonb;
  l_item record;
  l_input record;
begin
  if l_actor_id is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if p_task_id is null or p_request_id is null or p_items is null then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;
  l_items := private.normalize_return_pickup_items(p_items);

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.return_pickup:request:' || l_actor_id::text || ':'
      || p_request_id::text, 0));
  select p.role::text into l_actor_role
  from public.profiles p where p.id = l_actor_id;
  if l_actor_role is distinct from 'shipper' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;

  select t.order_id, t.return_request_id
    into l_order_id, l_return_request_id
  from public.delivery_tasks t
  where t.id = p_task_id
    and t.assigned_shipper_id = l_actor_id;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.complete_outbound_delivery:order:' || l_order_id::text, 0));

  select o.status into l_order_status
  from public.orders o where o.id = l_order_id for update;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  select r.status into l_return_status
  from public.return_requests r
  where r.id = l_return_request_id and r.order_id = l_order_id
  for update;
  if not found then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;

  for l_task_row in
    select t.id, t.order_id, t.return_request_id, t.kind,
           t.assigned_shipper_id, t.status, t.attempt_number,
           t.amount_to_collect_vnd, t.assigned_at, t.accepted_at,
           t.started_at, t.completed_at, t.failure_reason, t.cancel_reason
    from public.delivery_tasks t
    where t.return_request_id = l_return_request_id
    order by t.id
    for update
  loop
    if l_task_row.order_id is distinct from l_order_id
       or l_task_row.kind <> 'return_pickup'::public.delivery_task_kind then
      raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
    end if;
    if l_task_row.id = p_task_id then
      l_target_found := true;
      l_target_kind := l_task_row.kind;
      l_target_shipper_id := l_task_row.assigned_shipper_id;
      l_target_status := l_task_row.status;
      l_target_attempt := l_task_row.attempt_number;
      l_target_amount := l_task_row.amount_to_collect_vnd;
      l_target_assigned_at := l_task_row.assigned_at;
      l_target_accepted_at := l_task_row.accepted_at;
      l_target_started_at := l_task_row.started_at;
      l_target_completed_at := l_task_row.completed_at;
      l_target_failure_reason := l_task_row.failure_reason;
      l_target_cancel_reason := l_task_row.cancel_reason;
    end if;
  end loop;
  if not l_target_found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;

  for l_task_row in
    select i.task_id, i.return_item_id
    from private.return_pickup_task_items i
    where i.task_id = p_task_id
    order by i.return_item_id
  loop
    l_snapshot_count := l_snapshot_count + 1;
  end loop;
  for l_item in
    select i.id, i.order_id, i.quantity_to_collect, i.quantity_collected,
           i.sellable_quantity, i.damaged_quantity
    from public.return_items i
    where i.return_request_id = l_return_request_id
    order by i.id
    for update
  loop
    l_all_item_count := l_all_item_count + 1;
    if l_item.order_id is distinct from l_order_id then
      raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
    end if;
  end loop;

  select p.role::text into l_actor_role
  from public.profiles p where p.id = l_actor_id for share;
  if l_actor_role is distinct from 'shipper' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;
  l_payload := jsonb_build_object(
    'operation', 'collect_return_items',
    'task_id', p_task_id,
    'request_id', p_request_id,
    'items', l_items
  );
  l_payload_hash := md5(l_payload::text);
  select r.* into l_existing
  from private.return_pickup_requests r
  where r.actor_id = l_actor_id and r.request_id = p_request_id;
  if found then
    if l_existing.operation <> 'collect_return_items'
       or l_existing.task_id is distinct from p_task_id
       or l_existing.return_request_id is distinct from l_return_request_id
       or l_existing.payload_hash <> l_payload_hash
       or l_existing.payload is distinct from l_payload then
      raise exception using errcode = 'PT409', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return l_existing.response;
  end if;

  if l_order_status <> 'delivered'::public.order_status then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;
  if l_target_kind <> 'return_pickup'::public.delivery_task_kind
     or l_target_shipper_id is distinct from l_actor_id then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  if l_return_status <> 'awaiting_return_pickup'::public.return_request_status
     or l_target_status <> 'assigned'::public.delivery_task_status
     or l_target_attempt <> 1
     or l_target_amount <> 0
     or l_target_assigned_at is null
     or l_target_accepted_at is not null
     or l_target_started_at is not null
     or l_target_completed_at is not null
     or l_target_failure_reason is not null
     or l_target_cancel_reason is not null then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;
  if l_snapshot_count = 0 then
    raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
  end if;

  l_plan := private.return_pickup_plan_json(p_task_id);
  if l_plan is distinct from l_items then
    raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
  end if;
  select coalesce(
           jsonb_agg(
             jsonb_build_object('return_item_id', i.id,
                                'quantity', i.quantity_to_collect)
             order by i.id), '[]'::jsonb), count(*)
    into l_live_plan, l_item_count
  from public.return_items i
  where i.return_request_id = l_return_request_id
    and i.order_id = l_order_id;
  if l_item_count <> l_all_item_count
     or l_live_plan is distinct from l_plan
     or l_item_count <> l_snapshot_count then
    raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
  end if;
  if exists (
    select 1 from public.return_items i
    where i.return_request_id = l_return_request_id
      and (i.quantity_collected <> 0
        or i.sellable_quantity <> 0
        or i.damaged_quantity <> 0)
  ) then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;

  l_now := pg_catalog.clock_timestamp();
  update public.delivery_tasks
  set status = 'in_transit'::public.delivery_task_status,
      accepted_at = l_now,
      started_at = l_now,
      updated_at = l_now
  where id = p_task_id;
  update public.return_requests
  set status = 'returning_to_store'::public.return_request_status,
      updated_at = l_now
  where id = l_return_request_id;

  -- Exact full-plan collection is atomic with the task/request transition.
  -- No inventory movement, COD row, refund row or delivery_attempts row is
  -- touched by this operation.
  for l_input in
    select (e ->> 'return_item_id')::uuid as return_item_id,
           (e ->> 'quantity')::bigint as quantity
    from jsonb_array_elements(l_items) as a(e)
  loop
    update public.return_items
    set quantity_collected = l_input.quantity,
        updated_at = l_now
    where id = l_input.return_item_id
      and return_request_id = l_return_request_id
      and order_id = l_order_id;
    if not found then
      raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
    end if;
  end loop;

  l_event_id := pg_catalog.gen_random_uuid();
  insert into public.business_events (
    id, actor_id, subject_type, subject_id, from_state, to_state,
    reason, task_id, request_id, created_at
  ) values (
    l_event_id, l_actor_id, 'delivery_task', p_task_id,
    'assigned', 'in_transit', 'return_pickup_collected',
    p_task_id, l_event_id, l_now
  );
  insert into private.return_pickup_custody (
    task_id, return_request_id, order_id, shipper_id,
    accepted_at, started_at, event_id, items, created_at
  ) values (
    p_task_id, l_return_request_id, l_order_id, l_actor_id,
    l_now, l_now, l_event_id, l_items, l_now
  );
  l_response := pg_catalog.jsonb_build_object(
    'task_id', p_task_id,
    'return_request_id', l_return_request_id,
    'order_id', l_order_id,
    'operation', 'collect_return_items',
    'task_status', 'in_transit',
    'return_status', 'returning_to_store',
    'accepted_at', l_now,
    'started_at', l_now,
    'occurred_at', l_now,
    'event_id', l_event_id,
    'request_id', p_request_id
  );
  insert into private.return_pickup_requests (
    actor_id, request_id, operation, return_request_id, order_id, task_id,
    shipper_id, payload, payload_hash, response, created_at
  ) values (
    l_actor_id, p_request_id, 'collect_return_items', l_return_request_id,
    l_order_id, p_task_id, l_actor_id, l_payload, l_payload_hash,
    l_response, l_now
  );
  return l_response;
end;
$$;

alter function public.collect_return_items(uuid, uuid, jsonb)
  owner to sports_store_return_pickup_writer;

create function public.fail_return_pickup_task(
  p_task_id uuid,
  p_request_id uuid,
  p_reason_code text,
  p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  l_actor_id uuid := (select private.delivery_request_user_id());
  l_actor_role text;
  l_reason_code text;
  l_description text;
  l_order_id uuid;
  l_return_request_id uuid;
  l_order_status public.order_status;
  l_return_status public.return_request_status;
  l_task_row record;
  l_profile record;
  l_existing private.return_pickup_requests%rowtype;
  l_payload jsonb;
  l_payload_hash text;
  l_target_found boolean := false;
  l_target_kind public.delivery_task_kind;
  l_target_shipper_id uuid;
  l_target_status public.delivery_task_status;
  l_target_attempt smallint;
  l_target_amount bigint;
  l_target_assigned_at timestamptz;
  l_target_accepted_at timestamptz;
  l_target_started_at timestamptz;
  l_target_completed_at timestamptz;
  l_target_failure_reason text;
  l_target_cancel_reason text;
  l_snapshot_count bigint := 0;
  l_item_count bigint := 0;
  l_all_item_count bigint := 0;
  l_snapshot_plan jsonb;
  l_live_plan jsonb;
  l_now timestamptz := pg_catalog.clock_timestamp();
  l_event_id uuid;
  l_response jsonb;
begin
  if l_actor_id is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  l_reason_code := nullif(
    pg_catalog.regexp_replace(coalesce(p_reason_code, ''),
      '^[[:space:]]+|[[:space:]]+$', '', 'g'), '');
  l_description := nullif(
    pg_catalog.regexp_replace(coalesce(p_description, ''),
      '^[[:space:]]+|[[:space:]]+$', '', 'g'), '');
  if p_task_id is null
     or p_request_id is null
     or l_reason_code is null
     or l_reason_code not in (
       'unreachable', 'reschedule', 'bad_address', 'refusal', 'other'
     )
     or (l_reason_code = 'other' and l_description is null) then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.return_pickup:request:' || l_actor_id::text || ':'
      || p_request_id::text, 0));
  select p.role::text into l_actor_role
  from public.profiles p where p.id = l_actor_id;
  if l_actor_role is distinct from 'shipper' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;
  select t.order_id, t.return_request_id
    into l_order_id, l_return_request_id
  from public.delivery_tasks t
  where t.id = p_task_id
    and t.assigned_shipper_id = l_actor_id;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.complete_outbound_delivery:order:' || l_order_id::text, 0));

  select o.status into l_order_status
  from public.orders o where o.id = l_order_id for update;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  select r.status into l_return_status
  from public.return_requests r
  where r.id = l_return_request_id and r.order_id = l_order_id
  for update;
  if not found then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;

  for l_task_row in
    select t.id, t.order_id, t.return_request_id, t.kind,
           t.assigned_shipper_id, t.status, t.attempt_number,
           t.amount_to_collect_vnd, t.assigned_at, t.accepted_at,
           t.started_at, t.completed_at, t.failure_reason, t.cancel_reason
    from public.delivery_tasks t
    where t.return_request_id = l_return_request_id
    order by t.id
    for update
  loop
    if l_task_row.order_id is distinct from l_order_id
       or l_task_row.kind <> 'return_pickup'::public.delivery_task_kind then
      raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
    end if;
    if l_task_row.id = p_task_id then
      l_target_found := true;
      l_target_kind := l_task_row.kind;
      l_target_shipper_id := l_task_row.assigned_shipper_id;
      l_target_status := l_task_row.status;
      l_target_attempt := l_task_row.attempt_number;
      l_target_amount := l_task_row.amount_to_collect_vnd;
      l_target_assigned_at := l_task_row.assigned_at;
      l_target_accepted_at := l_task_row.accepted_at;
      l_target_started_at := l_task_row.started_at;
      l_target_completed_at := l_task_row.completed_at;
      l_target_failure_reason := l_task_row.failure_reason;
      l_target_cancel_reason := l_task_row.cancel_reason;
    end if;
  end loop;
  if not l_target_found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;

  for l_task_row in
    select i.task_id, i.return_item_id
    from private.return_pickup_task_items i
    where i.task_id = p_task_id
    order by i.return_item_id
  loop
    l_snapshot_count := l_snapshot_count + 1;
  end loop;
  perform 1 from public.return_items i
  where i.return_request_id = l_return_request_id;

  select p.role::text into l_actor_role
  from public.profiles p where p.id = l_actor_id for share;
  if l_actor_role is distinct from 'shipper' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;
  l_payload := jsonb_build_object(
    'operation', 'fail_return_pickup_task',
    'task_id', p_task_id,
    'request_id', p_request_id,
    'reason_code', l_reason_code,
    'description', l_description
  );
  l_payload_hash := md5(l_payload::text);
  select r.* into l_existing
  from private.return_pickup_requests r
  where r.actor_id = l_actor_id and r.request_id = p_request_id;
  if found then
    if l_existing.operation <> 'fail_return_pickup_task'
       or l_existing.task_id is distinct from p_task_id
       or l_existing.return_request_id is distinct from l_return_request_id
       or l_existing.payload_hash <> l_payload_hash
       or l_existing.payload is distinct from l_payload then
      raise exception using errcode = 'PT409', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return l_existing.response;
  end if;

  -- Re-check all pre-custody evidence only for a new request.  Exact ledger
  -- replay above must remain an ACK even after the task has moved on.
  if l_order_status <> 'delivered'::public.order_status then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;
  if exists (
    select 1 from private.return_pickup_custody c
    where c.task_id = p_task_id
  ) then
    raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
  end if;
  if l_snapshot_count = 0 then
    raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
  end if;
  l_snapshot_plan := private.return_pickup_plan_json(p_task_id);
  select coalesce(
           jsonb_agg(
             jsonb_build_object('return_item_id', i.id,
                                'quantity', i.quantity_to_collect)
             order by i.id), '[]'::jsonb), count(*)
    into l_live_plan, l_item_count
  from public.return_items i
  where i.return_request_id = l_return_request_id
    and i.order_id = l_order_id;
  select count(*) into l_all_item_count
  from public.return_items i
  where i.return_request_id = l_return_request_id;
  if l_item_count <> l_snapshot_count
     or l_all_item_count <> l_item_count
     or l_live_plan is distinct from l_snapshot_plan then
    raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
  end if;
  if exists (
    select 1 from public.return_items i
    where i.return_request_id = l_return_request_id
      and (i.quantity_collected <> 0
        or i.sellable_quantity <> 0
        or i.damaged_quantity <> 0)
  ) then
    raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
  end if;

  if l_target_kind <> 'return_pickup'::public.delivery_task_kind
     or l_target_shipper_id is distinct from l_actor_id then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  if l_return_status <> 'awaiting_return_pickup'::public.return_request_status
     or l_target_status <> 'assigned'::public.delivery_task_status
     or l_target_attempt <> 1
     or l_target_amount <> 0
     or l_target_assigned_at is null
     or l_target_accepted_at is not null
     or l_target_started_at is not null
     or l_target_completed_at is not null
     or l_target_failure_reason is not null
     or l_target_cancel_reason is not null then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;
  if l_snapshot_count = 0 then
    raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
  end if;

  l_now := pg_catalog.clock_timestamp();
  update public.delivery_tasks
  set status = 'failed'::public.delivery_task_status,
      completed_at = l_now,
      failure_reason = l_reason_code
        || case when l_description is null then '' else ': ' || l_description end,
      updated_at = l_now
  where id = p_task_id;

  l_event_id := pg_catalog.gen_random_uuid();
  insert into public.business_events (
    id, actor_id, subject_type, subject_id, from_state, to_state,
    reason, task_id, request_id, created_at
  ) values (
    l_event_id, l_actor_id, 'delivery_task', p_task_id,
    'assigned', 'failed', 'return_pickup_failed',
    p_task_id, l_event_id, l_now
  );
  for l_profile in
    select p.id from public.profiles p
    where p.role = 'manager'::public.user_role order by p.id
  loop
    insert into public.notifications (
      id, recipient_id, event_id, subject_type, subject_id,
      title, body, created_at
    ) values (
      pg_catalog.gen_random_uuid(), l_profile.id, l_event_id,
      'delivery_task', p_task_id,
      'Lấy hàng trả thất bại',
      'Một nhiệm vụ lấy hàng trả thất bại cần được xử lý.',
      l_now
    );
  end loop;
  l_response := pg_catalog.jsonb_build_object(
    'task_id', p_task_id,
    'return_request_id', l_return_request_id,
    'order_id', l_order_id,
    'operation', 'fail_return_pickup_task',
    'task_status', 'failed',
    'return_status', 'awaiting_return_pickup',
    'reason_code', l_reason_code,
    'description', l_description,
    'failed_at', l_now,
    'occurred_at', l_now,
    'event_id', l_event_id,
    'request_id', p_request_id
  );
  insert into private.return_pickup_failure_results (
    task_id, return_request_id, order_id, actor_id, event_id,
    request_id, reason_code, description, failed_at, response
  ) values (
    p_task_id, l_return_request_id, l_order_id, l_actor_id, l_event_id,
    p_request_id, l_reason_code, l_description, l_now, l_response
  );
  insert into private.return_pickup_requests (
    actor_id, request_id, operation, return_request_id, order_id, task_id,
    shipper_id, payload, payload_hash, response, created_at
  ) values (
    l_actor_id, p_request_id, 'fail_return_pickup_task', l_return_request_id,
    l_order_id, p_task_id, l_actor_id, l_payload, l_payload_hash,
    l_response, l_now
  );
  return l_response;
end;
$$;

alter function public.fail_return_pickup_task(uuid, uuid, text, text)
  owner to sports_store_return_pickup_writer;

-- The shipper projection reads only the immutable task plan for new pickup
-- tasks.  Historical tasks created before P08.1 may not have a private
-- snapshot, so their existing live return_items projection remains available
-- as a compatibility branch; a task created by the RPC always takes the
-- snapshot branch and can never silently fall back.
grant usage on schema private to sports_store_delivery_reader;
grant execute on function private.delivery_request_user_id()
  to sports_store_delivery_reader;
grant select (
  task_id, return_request_id, order_id, return_item_id,
  actual_item_name, quantity_to_collect
) on private.return_pickup_task_items
  to sports_store_delivery_reader;
grant select (task_id, items) on private.return_pickup_custody
  to sports_store_delivery_reader;

create policy return_pickup_task_items_delivery_reader
  on private.return_pickup_task_items for select
  to sports_store_delivery_reader
  using (
    current_user = 'sports_store_delivery_reader'
    and exists (
      select 1
      from public.delivery_tasks t
      where t.id = return_pickup_task_items.task_id
        and t.kind = 'return_pickup'::public.delivery_task_kind
        and t.status in (
          'assigned'::public.delivery_task_status,
          'accepted'::public.delivery_task_status,
          'in_transit'::public.delivery_task_status
        )
        and t.assigned_shipper_id = (select private.delivery_request_user_id())
    )
  );
create policy return_pickup_custody_delivery_reader
  on private.return_pickup_custody for select
  to sports_store_delivery_reader
  using (
    current_user = 'sports_store_delivery_reader'
    and exists (
      select 1
      from public.delivery_tasks t
      where t.id = return_pickup_custody.task_id
        and t.kind = 'return_pickup'::public.delivery_task_kind
        and t.status in (
          'assigned'::public.delivery_task_status,
          'accepted'::public.delivery_task_status,
          'in_transit'::public.delivery_task_status
        )
        and t.assigned_shipper_id = (select private.delivery_request_user_id())
    )
  );

create or replace function public.read_my_delivery_task_items(p_task_id uuid)
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
  with actor as (
    select private.delivery_request_user_id() as id
  ), current_tasks as (
    select t.id, t.order_id, t.return_request_id, t.kind, t.status
    from public.delivery_tasks t
    cross join actor a
    where t.id = p_task_id
      and t.assigned_shipper_id = a.id
      and t.status in (
        'assigned'::public.delivery_task_status,
        'accepted'::public.delivery_task_status,
        'in_transit'::public.delivery_task_status
      )
      and exists (
        select 1
        from public.profiles p
        where p.id = a.id and p.role = 'shipper'::public.user_role
      )
  ), outbound_items as (
    select i.id, 'order_snapshot'::text, i.product_name, i.variant_label,
      i.attributes, i.quantity, null::bigint, i.unit_price_vnd,
      i.line_total_vnd
    from current_tasks t
    join public.order_items i on i.order_id = t.order_id
    where t.kind = 'outbound'::public.delivery_task_kind
  ), snapshot_items as (
    select s.return_item_id, 'return_plan'::text, s.actual_item_name,
      null::text, null::jsonb, s.quantity_to_collect,
      coalesce((
        select (entry ->> 'quantity')::bigint
        from jsonb_array_elements(coalesce(c.items, '[]'::jsonb)) as item(entry)
        where (entry ->> 'return_item_id')::uuid = s.return_item_id
      ), 0::bigint),
      null::bigint, null::bigint
    from current_tasks t
    join private.return_pickup_task_items s on s.task_id = t.id
    left join private.return_pickup_custody c on c.task_id = t.id
    where t.kind = 'return_pickup'::public.delivery_task_kind
  ), legacy_items as (
    select i.id, 'return_plan'::text, i.actual_item_name,
      null::text, null::jsonb, i.quantity_to_collect, i.quantity_collected,
      null::bigint, null::bigint
    from current_tasks t
    join public.return_items i on i.return_request_id = t.return_request_id
    where t.kind = 'return_pickup'::public.delivery_task_kind
      and not exists (
        select 1
        from private.return_pickup_task_items s
        where s.task_id = t.id
      )
  )
  select * from outbound_items
  union all
  select * from snapshot_items
  union all
  select * from legacy_items
  order by 1;
$$;

alter function public.read_my_delivery_task_items(uuid)
  owner to sports_store_delivery_reader;
revoke all on function public.read_my_delivery_task_items(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.read_my_delivery_task_items(uuid)
  to authenticated;

comment on function public.read_my_delivery_task_items(uuid) is
  'P08.1 task-scoped shipper item projection; new pickup tasks read immutable approved snapshots, legacy tasks retain compatibility fallback.';

-- Keep migration-created writer capabilities internal; client roles receive
-- only the three public RPC EXECUTE grants below.
revoke create on schema public, private
  from sports_store_return_pickup_writer;
revoke all on function public.assign_return_pickup_task(uuid, uuid, uuid, uuid, uuid)
  from public, anon, service_role;
revoke all on function public.collect_return_items(uuid, uuid, jsonb)
  from public, anon, service_role;
revoke all on function public.fail_return_pickup_task(uuid, uuid, text, text)
  from public, anon, service_role;
grant execute on function public.assign_return_pickup_task(uuid, uuid, uuid, uuid, uuid)
  to authenticated;
grant execute on function public.collect_return_items(uuid, uuid, jsonb)
  to authenticated;
grant execute on function public.fail_return_pickup_task(uuid, uuid, text, text)
  to authenticated;

comment on function public.assign_return_pickup_task(uuid, uuid, uuid, uuid, uuid) is
  'P08.1 manager-only assignment/reassignment of an approved return pickup; pins the exact plan and never mutates COD, inventory, refunds or delivery attempts.';
comment on function public.collect_return_items(uuid, uuid, jsonb) is
  'P08.1 shipper-only atomic full approved-plan collection; records custody and moves the return request to returning_to_store.';
comment on function public.fail_return_pickup_task(uuid, uuid, text, text) is
  'P08.1 shipper-only pre-custody failure; leaves the return awaiting pickup and records a generic manager notification.';

notify pgrst, 'reload schema';

