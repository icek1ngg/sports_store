-- P07.4 production shipper reports.
--
-- This migration records a shipper's report of an outbound handover or a
-- delivery incident. A report is an append-only audit fact: it never changes
-- an order, task, COD row, inventory row, delivery result, or return receipt.
-- Manager receipt/inspection remains a separate operation.

do $$
begin
  if not exists (
    select 1 from pg_roles
    where rolname = 'sports_store_outbound_reporting_writer'
  ) then
    create role sports_store_outbound_reporting_writer
      nologin noinherit nobypassrls;
    comment on role sports_store_outbound_reporting_writer is
      'sports_store P07.4 outbound handover/incident report writer; no-login, no-inherit, no-bypass-RLS';
  elsif not exists (
    select 1 from pg_roles r
    where r.rolname = 'sports_store_outbound_reporting_writer'
      and not r.rolcanlogin
      and not r.rolsuper
      and not r.rolbypassrls
      and not r.rolinherit
      and not r.rolcreaterole
      and not r.rolcreatedb
      and not r.rolreplication
      and shobj_description(r.oid, 'pg_authid') =
        'sports_store P07.4 outbound handover/incident report writer; no-login, no-inherit, no-bypass-RLS'
  ) then
    raise exception
      'P07.4 outbound reporting writer role already exists with unexpected configuration';
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
    where granted.rolname = 'sports_store_outbound_reporting_writer'
      and member.rolname <> 'postgres'
  ) then
    raise exception 'P07.4 outbound reporting writer role has unexpected membership';
  end if;
end;
$$;

grant sports_store_outbound_reporting_writer to postgres;

-- The identity bridge is the only Auth dependency. The internal role is not
-- granted USAGE on the managed auth schema.
grant usage on schema public, private
  to sports_store_outbound_reporting_writer;
grant execute on function private.delivery_request_user_id()
  to sports_store_outbound_reporting_writer;
grant execute on function private.outbound_items_snapshot(uuid),private.current_app_role()
  to sports_store_outbound_reporting_writer;
grant create on schema public, private
  to sports_store_outbound_reporting_writer;

-- One request ledger is shared by both public operations. The client request
-- UUID is scoped by actor and is never copied into business_events.request_id;
-- every event below gets its own server UUID.
create table private.outbound_reporting_requests (
  actor_id uuid not null references public.profiles (id),
  request_id uuid not null,
  operation text not null,
  task_id uuid not null references public.delivery_tasks (id),
  order_id uuid not null references public.orders (id),
  payload jsonb not null,
  payload_hash text not null,
  response jsonb not null,
  created_at timestamptz not null default statement_timestamp(),
  primary key (actor_id, request_id),
  constraint outbound_reporting_requests_operation_valid
    check (operation in ('report_store_handover', 'report_delivery_incident')),
  constraint outbound_reporting_requests_payload_object
    check (jsonb_typeof(payload) = 'object'),
  constraint outbound_reporting_requests_hash_nonblank
    check (btrim(payload_hash) <> ''),
  constraint outbound_reporting_requests_response_object
    check (jsonb_typeof(response) = 'object')
);

-- A return-to-store handover is reported at most once for an order's return
-- cycle. Incidents intentionally have no task/order uniqueness constraint:
-- several distinct incident keys may be reported while custody is valid.
create table private.outbound_handover_reports (
  order_id uuid primary key references public.orders (id),
  task_id uuid not null references public.delivery_tasks (id),
  holder_id uuid not null references public.profiles (id),
  request_id uuid not null,
  event_id uuid not null unique references public.business_events (id),
  items jsonb not null,
  reported_at timestamptz not null,
  constraint outbound_handover_reports_items_valid
    check (jsonb_typeof(items) = 'array' and jsonb_array_length(items) > 0)
);

alter table private.outbound_reporting_requests enable row level security;
alter table private.outbound_reporting_requests force row level security;
alter table private.outbound_handover_reports enable row level security;
alter table private.outbound_handover_reports force row level security;

revoke all on private.outbound_reporting_requests,
  private.outbound_handover_reports
  from public, anon, authenticated, service_role;
grant select, insert on private.outbound_reporting_requests,
  private.outbound_handover_reports
  to sports_store_outbound_reporting_writer;

create policy outbound_reporting_requests_read
  on private.outbound_reporting_requests
  for select to sports_store_outbound_reporting_writer
  using (current_user = 'sports_store_outbound_reporting_writer');
create policy outbound_reporting_requests_insert
  on private.outbound_reporting_requests
  for insert to sports_store_outbound_reporting_writer
  with check (current_user = 'sports_store_outbound_reporting_writer');
create policy outbound_handover_reports_read
  on private.outbound_handover_reports
  for select to sports_store_outbound_reporting_writer
  using (current_user = 'sports_store_outbound_reporting_writer');
create policy outbound_handover_reports_insert
  on private.outbound_handover_reports
  for insert to sports_store_outbound_reporting_writer
  with check (current_user = 'sports_store_outbound_reporting_writer');

create or replace function private.reject_outbound_reporting_ledger_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'P07.4 reporting ledgers are append-only' using errcode = '55000';
end;
$$;
revoke all on function private.reject_outbound_reporting_ledger_mutation()
  from public, anon, authenticated, service_role;
create trigger outbound_reporting_requests_append_only
before update or delete on private.outbound_reporting_requests
for each row execute function private.reject_outbound_reporting_ledger_mutation();
create trigger outbound_handover_reports_append_only
before update or delete on private.outbound_handover_reports
for each row execute function private.reject_outbound_reporting_ledger_mutation();

-- Internal writer grants. UPDATE is limited to lock-only columns and every
-- corresponding policy has WITH CHECK (false), so no report path can mutate a
-- business state while still using FOR UPDATE to serialize with P04/P05/P07.
grant select (id, role) on public.profiles
  to sports_store_outbound_reporting_writer;
grant update (id) on public.profiles to sports_store_outbound_reporting_writer;
create policy outbound_reporting_profiles_lock on public.profiles
  for update to sports_store_outbound_reporting_writer
  using (id = (select private.delivery_request_user_id())) with check (false);
grant select (id, status, delivery_attempt_count) on public.orders
  to sports_store_outbound_reporting_writer;
grant update (id) on public.orders
  to sports_store_outbound_reporting_writer;
grant select (
  id, order_id, return_request_id, kind, assigned_shipper_id, status,
  attempt_number, assigned_at, accepted_at, started_at, completed_at,
  failure_reason, cancel_reason
) on public.delivery_tasks
  to sports_store_outbound_reporting_writer;
grant update (id) on public.delivery_tasks
  to sports_store_outbound_reporting_writer;
grant select (
  id, task_id, order_id, attempt_number, task_kind, result, shipper_id,
  occurred_at, reason
) on public.delivery_attempts
  to sports_store_outbound_reporting_writer;
grant select (order_id, shipper_id) on public.cod_collections
  to sports_store_outbound_reporting_writer;
grant update (order_id) on public.cod_collections
  to sports_store_outbound_reporting_writer;
grant select (
  id, order_id, variant_id, product_name, variant_label, attributes,
  unit_price_vnd, quantity, line_total_vnd
) on public.order_items
  to sports_store_outbound_reporting_writer;
grant select (
  id, variant_id, order_id, return_request_id, event_id, kind,
  on_hand_delta, reserved_delta, damaged_delta, actor_id, reason, created_at
) on public.inventory_movements
  to sports_store_outbound_reporting_writer;
grant select (
  id, actor_id, subject_type, subject_id, from_state, to_state, reason,
  task_id, incident_kind, request_id, created_at
) on public.business_events
  to sports_store_outbound_reporting_writer;
grant insert (
  id, actor_id, subject_type, subject_id, from_state, to_state, reason,
  task_id, incident_kind, request_id, created_at
) on public.business_events
  to sports_store_outbound_reporting_writer;
grant insert (
  id, recipient_id, event_id, subject_type, subject_id, title, body, created_at
) on public.notifications
  to sports_store_outbound_reporting_writer;
grant select on private.outbound_dispatches,
  private.outbound_custody_acceptances
  to sports_store_outbound_reporting_writer;

create policy outbound_reporting_profiles_read
  on public.profiles for select to sports_store_outbound_reporting_writer
  using (
    current_user = 'sports_store_outbound_reporting_writer'
    and (id = (select private.delivery_request_user_id())
      or role = 'manager'::public.user_role)
  );

create policy outbound_reporting_orders_read
  on public.orders for select to sports_store_outbound_reporting_writer
  using (
    current_user = 'sports_store_outbound_reporting_writer'
    and exists (
      select 1 from public.delivery_tasks t
      where t.order_id = orders.id
        and t.kind = 'outbound'::public.delivery_task_kind
        and t.assigned_shipper_id = (select private.delivery_request_user_id())
    )
  );
create policy outbound_reporting_orders_lock
  on public.orders for update to sports_store_outbound_reporting_writer
  using (
    current_user = 'sports_store_outbound_reporting_writer'
    and exists (
      select 1 from public.delivery_tasks t
      where t.order_id = orders.id
        and t.kind = 'outbound'::public.delivery_task_kind
        and t.assigned_shipper_id = (select private.delivery_request_user_id())
    )
  )
  with check (false);

-- Read all task kinds assigned to the current shipper long enough to return an
-- explicit UNSUPPORTED_TASK_KIND for pickup/redelivery instead of guessing a
-- future Sơn contract or leaking an unrelated task's existence.
create policy outbound_reporting_tasks_read
  on public.delivery_tasks for select to sports_store_outbound_reporting_writer
  using (
    current_user = 'sports_store_outbound_reporting_writer'
    and assigned_shipper_id = (select private.delivery_request_user_id())
  );
create policy outbound_reporting_tasks_lock
  on public.delivery_tasks for update to sports_store_outbound_reporting_writer
  using (
    current_user = 'sports_store_outbound_reporting_writer'
    and assigned_shipper_id = (select private.delivery_request_user_id())
  )
  with check (false);

create policy outbound_reporting_attempts_read
  on public.delivery_attempts for select to sports_store_outbound_reporting_writer
  using (
    current_user = 'sports_store_outbound_reporting_writer'
    and shipper_id = (select private.delivery_request_user_id())
  );

create policy outbound_reporting_cod_read
  on public.cod_collections for select to sports_store_outbound_reporting_writer
  using (
    current_user = 'sports_store_outbound_reporting_writer'
    and shipper_id = (select private.delivery_request_user_id())
  );
create policy outbound_reporting_cod_lock
  on public.cod_collections for update to sports_store_outbound_reporting_writer
  using (
    current_user = 'sports_store_outbound_reporting_writer'
    and shipper_id = (select private.delivery_request_user_id())
  )
  with check (false);

create policy outbound_reporting_order_items_read
  on public.order_items for select to sports_store_outbound_reporting_writer
  using (
    current_user = 'sports_store_outbound_reporting_writer'
    and exists (
      select 1 from public.delivery_tasks t
      where t.order_id = order_items.order_id
        and t.kind = 'outbound'::public.delivery_task_kind
        and t.assigned_shipper_id = (select private.delivery_request_user_id())
    )
  );
create policy outbound_reporting_movements_read
  on public.inventory_movements for select to sports_store_outbound_reporting_writer
  using (
    current_user = 'sports_store_outbound_reporting_writer'
    and exists (
      select 1 from public.delivery_tasks t
      where t.order_id = inventory_movements.order_id
        and t.kind = 'outbound'::public.delivery_task_kind
        and t.assigned_shipper_id = (select private.delivery_request_user_id())
    )
  );

create policy outbound_reporting_events_read
  on public.business_events for select to sports_store_outbound_reporting_writer
  using (current_user = 'sports_store_outbound_reporting_writer');
create policy outbound_reporting_events_insert
  on public.business_events for insert to sports_store_outbound_reporting_writer
  with check (
    current_user = 'sports_store_outbound_reporting_writer'
    and actor_id = (select private.delivery_request_user_id())
    and subject_type = 'delivery_task'
    and subject_id = task_id
    and task_id is not null
    and from_state is null
    and to_state is null
    and request_id = id
    and (
      (incident_kind is null and reason = 'store_handover_reported')
      or (incident_kind is not null and reason is not null and btrim(reason) <> '')
    )
  );

create policy outbound_reporting_notifications_insert
  on public.notifications for insert to sports_store_outbound_reporting_writer
  with check (
    current_user = 'sports_store_outbound_reporting_writer'
    and subject_type = 'delivery_task'
    and title in ('Đã báo bàn giao hàng', 'Có sự cố giao hàng')
    and body in (
      'Một nhiệm vụ giao hàng đã báo bàn giao về cửa hàng. Mở nhiệm vụ để xem chi tiết.',
      'Một nhiệm vụ giao hàng có sự cố cần được xử lý. Mở nhiệm vụ để xem chi tiết.'
    )
    and exists (
      select 1
      from public.delivery_tasks t
      join public.profiles recipient on recipient.id = notifications.recipient_id
      join public.business_events e on e.id = notifications.event_id
      where t.id = notifications.subject_id
        and e.id = notifications.event_id
        and e.subject_id = t.id
        and e.actor_id = (select private.delivery_request_user_id())
        and recipient.role = 'manager'::public.user_role
    )
  );

create policy outbound_reporting_dispatches_read
  on private.outbound_dispatches for select
  to sports_store_outbound_reporting_writer
  using (current_user = 'sports_store_outbound_reporting_writer');
create policy outbound_reporting_custody_read
  on private.outbound_custody_acceptances for select
  to sports_store_outbound_reporting_writer
  using (current_user = 'sports_store_outbound_reporting_writer');

-- Normalize and validate the public handover item contract. JSONB object key
-- order is canonicalized by PostgreSQL; array order is intentionally checked so
-- callers must send order_item_id ascending with exactly two keys per element.
create or replace function private.normalize_outbound_handover_items(p_items jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  l_element jsonb;
  l_order_item_id uuid;
  l_quantity bigint;
  l_id_text text;
  l_quantity_text text;
  l_canonical jsonb;
  l_count bigint;
  l_distinct_count bigint;
begin
  if p_items is null
     or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;

  for l_element in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(l_element) <> 'object'
       or (select count(*) from jsonb_object_keys(l_element)) <> 2
       or not (l_element ? 'order_item_id')
       or not (l_element ? 'quantity')
       or jsonb_typeof(l_element -> 'order_item_id') <> 'string'
       or jsonb_typeof(l_element -> 'quantity') <> 'number' then
      raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
    end if;
    l_id_text := l_element ->> 'order_item_id';
    l_quantity_text := l_element ->> 'quantity';
    if l_id_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or l_quantity_text !~ '^[0-9]+$'
       or length(l_quantity_text) > 10 then
      raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
    end if;
    l_order_item_id := l_id_text::uuid;
    l_quantity := l_quantity_text::bigint;
    if l_quantity < 1 or l_quantity > 2147483647 then
      raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
    end if;
  end loop;

  select count(*), count(distinct (e ->> 'order_item_id')::uuid)
    into l_count, l_distinct_count
  from jsonb_array_elements(p_items) as a(e);
  if l_count <> l_distinct_count then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;

  select jsonb_agg(
           jsonb_build_object(
             'order_item_id', (e ->> 'order_item_id')::uuid,
             'quantity', (e ->> 'quantity')::bigint
           )
           order by (e ->> 'order_item_id')::uuid
         )
    into l_canonical
  from jsonb_array_elements(p_items) as a(e);
  if l_canonical is distinct from p_items then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;
  return l_canonical;
end;
$$;

-- Project the immutable dispatch snapshot into the public handover shape.
create or replace function private.outbound_reporting_items_from_snapshot(
  p_items_snapshot jsonb
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'order_item_id', s.order_item_id,
        'quantity', s.quantity
      ) order by s.order_item_id
    ),
    '[]'::jsonb
  )
  from jsonb_to_recordset(p_items_snapshot) as s(
    order_item_id uuid,
    quantity bigint
  );
$$;

-- P04's validator intentionally rejects prior damaged/lost incidents because
-- it protects completion/start. Reporting must still prove the historical
-- dispatch without invoking that incident gate, so keep the existing validator
-- untouched and use this private reporting-only copy of its historical checks.
create or replace function private.validate_outbound_dispatch_proof_for_reporting(
  p_order_id uuid,
  p_dispatch_event_id uuid,
  p_holder_id uuid,
  p_items_snapshot jsonb
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  l_dispatch private.outbound_dispatches%rowtype;
  l_item record;
  l_snapshot jsonb;
  l_item_count bigint;
  l_variant_count bigint;
  l_dispatch_count bigint;
  l_movement_count bigint;
  l_reserved_sum bigint;
  l_on_hand_sum bigint;
  l_dispatch_row record;
begin
  select d.* into l_dispatch
  from private.outbound_dispatches d
  where d.order_id = p_order_id and d.event_id = p_dispatch_event_id;
  if not found
     or l_dispatch.holder_id is distinct from p_holder_id
     or l_dispatch.dispatched_at > clock_timestamp() then
    raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
  end if;
  if l_dispatch.items_snapshot is distinct from p_items_snapshot then
    raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
  end if;
  l_snapshot := private.outbound_items_snapshot(p_order_id);
  if l_snapshot is distinct from p_items_snapshot then
    raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
  end if;
  select count(*), count(distinct oi.variant_id)
    into l_item_count, l_variant_count
  from public.order_items oi where oi.order_id = p_order_id;
  if l_item_count = 0 or l_item_count <> l_variant_count then
    raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
  end if;

  if exists (
    select 1
    from public.inventory_movements m
    where m.order_id = p_order_id
      and (
        m.variant_id is null
        or m.variant_id not in (
          select oi.variant_id from public.order_items oi
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
  select count(*) into l_dispatch_count
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
        m.event_id is distinct from p_dispatch_event_id
        or m.actor_id is distinct from l_dispatch.holder_id
        or m.on_hand_delta >= 0
        or m.reserved_delta >= 0
        or m.damaged_delta <> 0
        or m.return_request_id is not null
        or m.variant_id not in (
          select oi.variant_id from public.order_items oi
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
    select m.* into l_dispatch_row
    from public.inventory_movements m
    where m.order_id = p_order_id
      and m.variant_id = l_item.variant_id
      and m.kind = 'dispatch'::public.inventory_movement_kind;
    if l_dispatch_row.event_id is distinct from p_dispatch_event_id
       or l_dispatch_row.reserved_delta <> -l_item.quantity
       or l_dispatch_row.on_hand_delta <> -l_item.quantity
       or l_dispatch_row.damaged_delta <> 0
       or l_dispatch_row.actor_id is distinct from l_dispatch.holder_id then
      raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
    end if;
  end loop;
end;
$$;

alter function private.normalize_outbound_handover_items(jsonb)
  owner to sports_store_outbound_reporting_writer;
alter function private.outbound_reporting_items_from_snapshot(jsonb)
  owner to sports_store_outbound_reporting_writer;
alter function private.validate_outbound_dispatch_proof_for_reporting(uuid, uuid, uuid, jsonb)
  owner to sports_store_outbound_reporting_writer;
revoke all on function private.normalize_outbound_handover_items(jsonb),
  private.outbound_reporting_items_from_snapshot(jsonb),
  private.validate_outbound_dispatch_proof_for_reporting(uuid, uuid, uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function private.normalize_outbound_handover_items(jsonb),
  private.outbound_reporting_items_from_snapshot(jsonb),
  private.validate_outbound_dispatch_proof_for_reporting(uuid, uuid, uuid, jsonb)
  to sports_store_outbound_reporting_writer;

-- Shared state/custody proof. The caller has already acquired the request
-- advisory lock, the shared order advisory lock, the order row lock, every
-- outbound task lock in UUID order, and the COD row lock.
create or replace function private.validate_outbound_report_context(
  p_task_id uuid,
  p_operation text
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  l_actor_id uuid := (select private.delivery_request_user_id());
  l_order_id uuid;
  l_order_status public.order_status;
  l_delivery_attempt_count smallint;
  l_target record;
  l_task_one record;
  l_task_two record;
  l_task_one_found boolean := false;
  l_task_two_found boolean := false;
  l_task_count bigint := 0;
  l_target_custody private.outbound_custody_acceptances%rowtype;
  l_task_one_custody private.outbound_custody_acceptances%rowtype;
  l_target_custody_found boolean := false;
  l_task_one_custody_found boolean := false;
  l_custody private.outbound_custody_acceptances%rowtype;
  l_dispatch private.outbound_dispatches%rowtype;
  l_dispatch_found boolean := false;
  l_expected_items jsonb;
  l_attempt_result public.delivery_attempt_result;
  l_attempt_task_id uuid;
  l_attempt_shipper_id uuid;
  l_holder_id uuid;
  l_original_task_id uuid;
  l_now timestamptz := clock_timestamp();
begin
  if p_operation not in ('report_store_handover', 'report_delivery_incident') then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;

  select t.id,t.order_id,t.kind,t.status,t.assigned_shipper_id,t.attempt_number,t.assigned_at,t.accepted_at,t.started_at,t.completed_at,t.failure_reason,t.cancel_reason into l_target
  from public.delivery_tasks t
  where t.id = p_task_id
    and t.kind = 'outbound'::public.delivery_task_kind
    and t.assigned_shipper_id = l_actor_id;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  l_order_id := l_target.order_id;

  select o.status, o.delivery_attempt_count
    into l_order_status, l_delivery_attempt_count
  from public.orders o
  where o.id = l_order_id;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;

  select t.id,t.order_id,t.kind,t.status,t.assigned_shipper_id,t.attempt_number,t.assigned_at,t.accepted_at,t.started_at,t.completed_at,t.failure_reason,t.cancel_reason into l_task_one
  from public.delivery_tasks t
  where t.order_id = l_order_id
    and t.kind = 'outbound'::public.delivery_task_kind
    and t.attempt_number = 1;
  l_task_one_found := found;
  select t.id,t.order_id,t.kind,t.status,t.assigned_shipper_id,t.attempt_number,t.assigned_at,t.accepted_at,t.started_at,t.completed_at,t.failure_reason,t.cancel_reason into l_task_two
  from public.delivery_tasks t
  where t.order_id = l_order_id
    and t.kind = 'outbound'::public.delivery_task_kind
    and t.attempt_number = 2;
  l_task_two_found := found;
  select count(*) into l_task_count
  from public.delivery_tasks t
  where t.order_id = l_order_id
    and t.kind = 'outbound'::public.delivery_task_kind;

  if p_operation = 'report_store_handover' then
    if l_order_status <> 'awaiting_store_return'::public.order_status then
      raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
    end if;
    if l_task_two_found
       and l_task_two.status = 'cancelled'::public.delivery_task_status
       and l_task_two.cancel_reason = 'manager_return_to_store' then
      if l_target.id is distinct from l_task_two.id
         or not l_task_one_found
         or l_task_one.status <> 'failed'::public.delivery_task_status
         or l_task_one.assigned_shipper_id is distinct from l_actor_id
         or l_task_one.accepted_at is null
         or l_task_one.started_at is null
         or l_task_one.completed_at is null
         or l_task_two.assigned_shipper_id is distinct from l_actor_id
         or l_task_two.attempt_number <> 2
         or l_task_two.started_at is not null
         or l_task_two.completed_at is null
         or l_task_two.failure_reason is not null
         or l_delivery_attempt_count <> 1
         or l_task_count <> 2 then
        raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
      end if;
    elsif l_target.status = 'failed'::public.delivery_task_status then
      if l_target.attempt_number = 1 then
        if not l_task_one_found
           or l_task_count <> 1
           or l_delivery_attempt_count <> 1
           or l_target.id is distinct from l_task_one.id then
          raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
        end if;
      elsif l_target.attempt_number = 2 then
        if not l_task_one_found
           or not l_task_two_found
           or l_task_count <> 2
           or l_delivery_attempt_count <> 2
           or l_task_one.status <> 'failed'::public.delivery_task_status
           or l_task_one.assigned_shipper_id is distinct from l_actor_id
           or l_target.id is distinct from l_task_two.id then
          raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
        end if;
      else
        raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
      end if;
      if l_target.assigned_shipper_id is distinct from l_actor_id
         or l_target.accepted_at is null
         or l_target.started_at is null
         or l_target.completed_at is null
         or l_target.failure_reason is null
         or btrim(l_target.failure_reason) = ''
         or l_target.cancel_reason is not null then
        raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
      end if;
    else
      raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
    end if;
  else
    if l_target.status = 'accepted'::public.delivery_task_status then
      if l_target.accepted_at is null
         or l_target.started_at is not null
         or l_target.completed_at is not null
         or l_target.failure_reason is not null
         or l_target.cancel_reason is not null
         or l_target.assigned_shipper_id is distinct from l_actor_id
         or l_target.accepted_at > l_now
         or (l_target.attempt_number = 1 and (
           l_order_status <> 'awaiting_pickup'::public.order_status
           or l_delivery_attempt_count <> 0
           or l_task_count <> 1
         ))
         or (l_target.attempt_number = 2 and (
           l_order_status <> 'awaiting_pickup'::public.order_status
           or l_delivery_attempt_count <> 1
           or l_task_count <> 2
           or not l_task_one_found
           or l_task_one.status <> 'failed'::public.delivery_task_status
           or l_task_one.assigned_shipper_id is distinct from l_actor_id
         ))
         or l_target.attempt_number not in (1, 2) then
        raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
      end if;
    elsif l_target.status = 'in_transit'::public.delivery_task_status then
      if l_target.accepted_at is null
         or l_target.started_at is null
         or l_target.completed_at is not null
         or l_target.failure_reason is not null
         or l_target.cancel_reason is not null
         or l_target.assigned_shipper_id is distinct from l_actor_id
         or l_target.accepted_at > l_now
         or l_target.started_at > l_now
         or (l_target.attempt_number = 1 and (
           l_order_status <> 'delivering'::public.order_status
           or l_delivery_attempt_count <> 1
           or l_task_count <> 1
         ))
         or (l_target.attempt_number = 2 and (
           l_order_status <> 'delivering'::public.order_status
           or l_delivery_attempt_count <> 2
           or l_task_count <> 2
           or not l_task_one_found
           or l_task_one.status <> 'failed'::public.delivery_task_status
           or l_task_one.assigned_shipper_id is distinct from l_actor_id
         ))
         or l_target.attempt_number not in (1, 2) then
        raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
      end if;
    elsif l_target.status = 'failed'::public.delivery_task_status then
      if l_target.accepted_at is null
         or l_target.started_at is null
         or l_target.completed_at is null
         or l_target.failure_reason is null
         or btrim(l_target.failure_reason) = ''
         or l_target.cancel_reason is not null
         or l_target.assigned_shipper_id is distinct from l_actor_id
         or l_target.completed_at > l_now
         or (l_target.attempt_number = 1 and (
           l_delivery_attempt_count <> 1
           or l_order_status not in (
             'awaiting_redelivery'::public.order_status,
             'awaiting_store_return'::public.order_status
           )
         ))
         or (l_target.attempt_number = 2 and (
           l_delivery_attempt_count <> 2
           or l_order_status <> 'awaiting_store_return'::public.order_status
           or not l_task_one_found
           or l_task_one.status <> 'failed'::public.delivery_task_status
           or l_task_one.assigned_shipper_id is distinct from l_actor_id
         ))
         or l_target.attempt_number not in (1, 2) then
        raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
      end if;
    elsif l_target.status = 'cancelled'::public.delivery_task_status
      and l_target.attempt_number = 2
      and l_target.cancel_reason = 'manager_return_to_store'
      and l_order_status = 'awaiting_store_return'::public.order_status
      and l_delivery_attempt_count = 1
      and l_task_count = 2
      and l_task_two_found
      and l_target.id = l_task_two.id
      and l_task_two.assigned_shipper_id = l_actor_id
      and l_task_two.started_at is null
      and l_task_two.completed_at is not null
      and l_task_two.failure_reason is null
      and l_task_one_found
      and l_task_one.status = 'failed'::public.delivery_task_status
      and l_task_one.assigned_shipper_id = l_actor_id then
      null;
    else
      raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
    end if;
  end if;

  -- A failed task must have an immutable failed-attempt row. Task 2 cancelled
  -- before accept has no result; its task-1 failed row is checked below.
  if l_target.status = 'failed'::public.delivery_task_status then
    select a.task_id, a.result, a.shipper_id
      into l_attempt_task_id, l_attempt_result, l_attempt_shipper_id
    from public.delivery_attempts a
    where a.task_id = l_target.id
      and a.order_id = l_order_id
      and a.attempt_number = l_target.attempt_number
      and a.task_kind = 'outbound'::public.delivery_task_kind;
    if not found
       or l_attempt_result <> 'failed'::public.delivery_attempt_result
       or l_attempt_shipper_id is distinct from l_actor_id then
      raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
    end if;
  end if;
  if l_task_one_found
     and l_task_one.status = 'failed'::public.delivery_task_status
     and (l_target.attempt_number = 2
       or l_target.status = 'cancelled'::public.delivery_task_status) then
    select a.task_id, a.result, a.shipper_id
      into l_attempt_task_id, l_attempt_result, l_attempt_shipper_id
    from public.delivery_attempts a
    where a.task_id = l_task_one.id
      and a.order_id = l_order_id
      and a.attempt_number = 1
      and a.task_kind = 'outbound'::public.delivery_task_kind;
    if not found
       or l_attempt_result <> 'failed'::public.delivery_attempt_result
       or l_attempt_shipper_id is distinct from l_actor_id then
      raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
    end if;
  end if;

  select c.* into l_target_custody
  from private.outbound_custody_acceptances c
  where c.task_id = l_target.id;
  l_target_custody_found := found;
  if l_task_one_found then
    select c.* into l_task_one_custody
    from private.outbound_custody_acceptances c
    where c.task_id = l_task_one.id;
    l_task_one_custody_found := found;
  end if;

  if l_target_custody_found then
    if l_target_custody.order_id is distinct from l_order_id
       or l_target_custody.holder_id is distinct from l_actor_id
       or l_target_custody.attempt_number is distinct from l_target.attempt_number
       or l_target.accepted_at is null
       or l_target_custody.accepted_at is distinct from l_target.accepted_at then
      raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
    end if;
    l_custody := l_target_custody;
  elsif l_target.status = 'cancelled'::public.delivery_task_status
        and l_target.attempt_number = 2 then
    -- Assigned task 2 can be cancelled before accept; its physical holder is
    -- still proven by the original dispatch/task-1 custody.
    if not l_task_one_custody_found then
      raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
    end if;
    l_custody := l_task_one_custody;
  else
    raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
  end if;

  if l_custody.order_id is distinct from l_order_id
     or l_custody.holder_id is distinct from l_actor_id
     or l_custody.accepted_at > l_now then
    raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
  end if;
  l_holder_id := l_custody.holder_id;
  l_original_task_id := l_task_one.id;

  select d.* into l_dispatch
  from private.outbound_dispatches d
  where d.order_id = l_order_id
    and d.event_id = l_custody.dispatch_event_id;
  l_dispatch_found := found;
  if not l_dispatch_found
     or l_dispatch.initial_task_id is distinct from l_original_task_id
     or l_dispatch.holder_id is distinct from l_holder_id
     or l_dispatch.dispatched_at > l_custody.accepted_at then
    raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
  end if;

  perform private.validate_outbound_dispatch_proof_for_reporting(
    l_order_id, l_dispatch.event_id, l_holder_id, l_dispatch.items_snapshot
  );
  l_expected_items := private.outbound_reporting_items_from_snapshot(
    l_dispatch.items_snapshot
  );

  if p_operation = 'report_store_handover'
     and exists (
       select 1
       from public.business_events e
       where e.incident_kind = 'lost'::public.delivery_incident_kind
         and (
           (e.subject_type = 'order' and e.subject_id = l_order_id)
           or exists (
             select 1 from public.delivery_tasks t
             where t.id = e.task_id and t.order_id = l_order_id
           )
         )
     ) then
    -- A lost incident prevents a full-goods claim until a manager resolves it.
    -- That resolution is intentionally outside P07.4.
    raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
  end if;

  return jsonb_build_object(
    'task_id', l_target.id,
    'order_id', l_order_id,
    'task_status', l_target.status::text,
    'order_status', l_order_status::text,
    'attempt_number', l_target.attempt_number,
    'holder_id', l_holder_id,
    'dispatch_event_id', l_dispatch.event_id,
    'items_snapshot', l_dispatch.items_snapshot,
    'expected_items', l_expected_items,
    'accepted_at', l_target.accepted_at,
    'started_at', l_target.started_at
  );
end;
$$;

alter function private.validate_outbound_report_context(uuid, text)
  owner to sports_store_outbound_reporting_writer;
revoke all on function private.validate_outbound_report_context(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function private.validate_outbound_report_context(uuid, text)
  to sports_store_outbound_reporting_writer;

-- Both operations enter one internal transaction implementation and share the
-- actor/request namespace. Public wrappers execute as the restricted writer.
create function private.execute_outbound_report(
  p_task_id uuid, p_request_id uuid, p_operation text, p_items jsonb,
  p_incident_kind public.delivery_incident_kind, p_reason text
) returns jsonb language plpgsql security invoker set search_path='' as $$
declare
  l_actor uuid := (select private.delivery_request_user_id());
  l_role text;
  l_order uuid;
  l_kind public.delivery_task_kind;
  l_items jsonb;
  l_reason text;
  l_payload jsonb;
  l_existing private.outbound_reporting_requests%rowtype;
  l_context jsonb;
  l_event uuid;
  l_now timestamptz;
  l_response jsonb;
  l_recipient record;
begin
  if l_actor is null then raise exception using errcode='42501',message='AUTH_REQUIRED'; end if;
  if p_task_id is null or p_request_id is null or p_operation not in
    ('report_store_handover','report_delivery_incident') then
    raise exception using errcode='22023',message='INVALID_ARGUMENT';
  end if;
  select role::text into l_role from public.profiles where id=l_actor for share;
  if l_role is distinct from 'shipper' then
    raise exception using errcode='42501',message='PERMISSION_DENIED';
  end if;
  if p_operation='report_store_handover' then
    l_items := private.normalize_outbound_handover_items(p_items);
  else
    l_reason := nullif(regexp_replace(coalesce(p_reason,''),'^[[:space:]]+|[[:space:]]+$','','g'),'');
    if p_incident_kind is null or l_reason is null then
      raise exception using errcode='22023',message='INVALID_ARGUMENT';
    end if;
  end if;
  l_payload := jsonb_build_object('operation',p_operation,'task_id',p_task_id,
    'items',l_items,'incident_kind',p_incident_kind,'reason',l_reason);
  perform pg_advisory_xact_lock(hashtextextended('sports_store.outbound.reporting:request:'||l_actor::text||':'||p_request_id::text,0));
  select role::text into l_role from public.profiles where id=l_actor for share;
  if l_role is distinct from 'shipper' then
    raise exception using errcode='42501',message='PERMISSION_DENIED';
  end if;
  select order_id,kind into l_order,l_kind from public.delivery_tasks
    where id=p_task_id and assigned_shipper_id=l_actor;
  if not found then raise exception using errcode='42501',message='NOT_FOUND_OR_FORBIDDEN'; end if;
  if l_kind <> 'outbound'::public.delivery_task_kind then
    raise exception using errcode='PT409',message='UNSUPPORTED_TASK_KIND';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('sports_store.complete_outbound_delivery:order:'||l_order::text,0));
  perform 1 from public.orders where id=l_order for update;
  if not found then raise exception using errcode='42501',message='NOT_FOUND_OR_FORBIDDEN'; end if;
  perform 1 from public.delivery_tasks where order_id=l_order and kind='outbound'
    order by id for update;
  perform 1 from public.delivery_tasks where id=p_task_id and assigned_shipper_id=l_actor;
  if not found then raise exception using errcode='42501',message='NOT_FOUND_OR_FORBIDDEN'; end if;
  perform 1 from public.cod_collections where order_id=l_order and shipper_id=l_actor for update;
  if not found then raise exception using errcode='PT409',message='CUSTODY_UNRESOLVED'; end if;
  -- Reauthorize historical holder evidence before replay, without demanding
  -- the original transient task state or absence of later damage reports.
  if not exists(select 1 from private.outbound_dispatches d
    join private.outbound_custody_acceptances c on c.task_id=d.initial_task_id
    where d.order_id=l_order and d.holder_id=l_actor and c.holder_id=l_actor
      and c.order_id=l_order and c.dispatch_event_id=d.event_id) then
    raise exception using errcode='PT409',message='CUSTODY_UNRESOLVED';
  end if;
  select * into l_existing from private.outbound_reporting_requests
    where actor_id=l_actor and request_id=p_request_id;
  if found then
    if l_existing.operation is distinct from p_operation or
      l_existing.task_id is distinct from p_task_id or l_existing.order_id is distinct from l_order or
      l_existing.payload is distinct from l_payload then
      raise exception using errcode='PT409',message='IDEMPOTENCY_CONFLICT';
    end if;
    return l_existing.response;
  end if;
  l_context := private.validate_outbound_report_context(p_task_id,p_operation);
  if p_operation='report_store_handover' then
    if exists(select 1 from private.outbound_handover_reports where order_id=l_order) then
      raise exception using errcode='PT409',message='STATE_CONFLICT';
    end if;
    if l_items is distinct from l_context->'expected_items' then
      raise exception using errcode='PT409',message='ITEMS_MISMATCH';
    end if;
  end if;
  l_event:=gen_random_uuid(); l_now:=clock_timestamp();
  l_response:=jsonb_build_object('task_id',p_task_id,'order_id',l_order,
    'operation',p_operation,'request_id',p_request_id,'event_id',l_event,
    'reported_at',l_now,'task_status',l_context->>'task_status',
    'order_status',l_context->>'order_status');
  insert into public.business_events(id,actor_id,subject_type,subject_id,task_id,
    from_state,to_state,reason,incident_kind,request_id,created_at)
  values(l_event,l_actor,'delivery_task',p_task_id,p_task_id,null,null,
    case when p_operation='report_store_handover' then 'store_handover_reported' else l_reason end,
    p_incident_kind,l_event,l_now);
  for l_recipient in select id from public.profiles where role='manager' order by id loop
    insert into public.notifications(id,recipient_id,event_id,subject_type,subject_id,title,body,created_at)
    values(gen_random_uuid(),l_recipient.id,l_event,'delivery_task',p_task_id,
      case when p_operation='report_store_handover' then 'Đã báo bàn giao hàng' else 'Có sự cố giao hàng' end,
      case when p_operation='report_store_handover'
        then 'Một nhiệm vụ giao hàng đã báo bàn giao về cửa hàng. Mở nhiệm vụ để xem chi tiết.'
        else 'Một nhiệm vụ giao hàng có sự cố cần được xử lý. Mở nhiệm vụ để xem chi tiết.' end,l_now);
  end loop;
  if p_operation='report_store_handover' then
    insert into private.outbound_handover_reports(order_id,task_id,holder_id,request_id,event_id,items,reported_at)
    values(l_order,p_task_id,l_actor,p_request_id,l_event,l_items,l_now);
  end if;
  insert into private.outbound_reporting_requests(actor_id,request_id,operation,task_id,order_id,payload,payload_hash,response,created_at)
  values(l_actor,p_request_id,p_operation,p_task_id,l_order,l_payload,md5(l_payload::text),l_response,l_now);
  return l_response;
end;
$$;
alter function private.execute_outbound_report(uuid,uuid,text,jsonb,public.delivery_incident_kind,text)
  owner to sports_store_outbound_reporting_writer;
revoke all on function private.execute_outbound_report(uuid,uuid,text,jsonb,public.delivery_incident_kind,text)
  from public,anon,authenticated,service_role;
grant execute on function private.execute_outbound_report(uuid,uuid,text,jsonb,public.delivery_incident_kind,text)
  to sports_store_outbound_reporting_writer;

create function public.report_store_handover(p_task_id uuid,p_request_id uuid,p_items jsonb)
returns jsonb language sql security definer set search_path='' as $$
  select private.execute_outbound_report(p_task_id,p_request_id,'report_store_handover',p_items,null,null);
$$;
create function public.report_delivery_incident(p_task_id uuid,p_request_id uuid,
  p_incident_kind public.delivery_incident_kind,p_reason text)
returns jsonb language sql security definer set search_path='' as $$
  select private.execute_outbound_report(p_task_id,p_request_id,'report_delivery_incident',null,p_incident_kind,p_reason);
$$;
alter function public.report_store_handover(uuid,uuid,jsonb) owner to sports_store_outbound_reporting_writer;
alter function public.report_delivery_incident(uuid,uuid,public.delivery_incident_kind,text) owner to sports_store_outbound_reporting_writer;
revoke all on function public.report_store_handover(uuid,uuid,jsonb),
  public.report_delivery_incident(uuid,uuid,public.delivery_incident_kind,text) from public,anon,service_role;
grant execute on function public.report_store_handover(uuid,uuid,jsonb),
  public.report_delivery_incident(uuid,uuid,public.delivery_incident_kind,text) to authenticated;
revoke create on schema public,private from sports_store_outbound_reporting_writer;
notify pgrst,'reload schema';
