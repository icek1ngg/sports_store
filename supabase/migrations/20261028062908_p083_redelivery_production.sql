-- P08.3 production return receipt, inspection release and free redelivery.
--
-- The P08.1/P08.2 pickup writer remains the only internal writer role.  This
-- migration adds a separate, append-only redelivery ledger and immutable
-- snapshots.  No operation below mutates COD, inventory or delivery_attempts.
-- Receipt/inspection proofs are intentionally private; shippers only receive
-- a task-scoped immutable item plan through the existing read projection.

do $$
begin
  if not exists (
    select 1 from pg_roles
    where rolname = 'sports_store_return_pickup_writer'
  ) then
    raise exception
      'P08.3 requires the restricted P08.1 return-pickup writer role';
  end if;
  if not exists (
    select 1 from pg_roles r
    where r.rolname = 'sports_store_return_pickup_writer'
      and not r.rolcanlogin and not r.rolsuper and not r.rolbypassrls
      and not r.rolinherit and not r.rolcreaterole and not r.rolcreatedb
      and not r.rolreplication
      and shobj_description(r.oid, 'pg_authid') =
        'sports_store P08.1 return-pickup writer; no-login, no-inherit, no-bypass-RLS'
  ) then
    raise exception 'P08.3 return-pickup writer has unexpected configuration';
  end if;
end;
$$;

grant usage on schema public, private
  to sports_store_return_pickup_writer;
grant execute on function private.delivery_request_user_id(),
  private.current_app_role(),
  private.normalize_return_pickup_items(jsonb)
  to sports_store_return_pickup_writer;
grant create on schema public, private
  to sports_store_return_pickup_writer;

-- One actor/request namespace covers every P08.3 operation.  Payload and ACK
-- are canonical JSON, so a same-key replay can be returned only after the
-- current caller has been re-authorized.
create table private.redelivery_requests (
  actor_id uuid not null references public.profiles (id),
  request_id uuid not null,
  operation text not null,
  order_id uuid not null references public.orders (id),
  return_request_id uuid not null references public.return_requests (id),
  task_id uuid references public.delivery_tasks (id),
  shipper_id uuid references public.profiles (id),
  payload jsonb not null,
  payload_hash text not null,
  response jsonb not null,
  created_at timestamptz not null default statement_timestamp(),
  primary key (actor_id, request_id),
  constraint redelivery_requests_operation_valid check (operation in (
    'approve_return_pickup_plan',
    'receive_customer_return',
    'reject_return_after_inspection',
    'assign_redelivery_task',
    'accept_redelivery_task',
    'start_redelivery_task',
    'complete_redelivery',
    'fail_redelivery_task'
  )),
  constraint redelivery_requests_payload_object
    check (jsonb_typeof(payload) = 'object'),
  constraint redelivery_requests_payload_hash_nonblank
    check (btrim(payload_hash) <> ''),
  constraint redelivery_requests_response_object
    check (jsonb_typeof(response) = 'object')
);

-- Manager receipt is separate from the shipper handover report.  The row is
-- immutable and is accepted only when its item array exactly equals the
-- already-recorded pickup custody and handover report.
create table private.redelivery_return_receipts (
  return_request_id uuid primary key references public.return_requests (id),
  pickup_task_id uuid not null unique references public.delivery_tasks (id),
  order_id uuid not null references public.orders (id),
  manager_id uuid not null references public.profiles (id),
  request_id uuid not null,
  event_id uuid not null unique references public.business_events (id),
  items jsonb not null,
  received_at timestamptz not null,
  response jsonb not null,
  constraint redelivery_receipts_items_valid check (
    jsonb_typeof(items) = 'array' and jsonb_array_length(items) > 0
  ),
  constraint redelivery_receipts_response_object
    check (jsonb_typeof(response) = 'object')
);

-- Inspection rejection is immutable.  The reason is manager-entered text,
-- while the actual redelivery quantities come only from receipt custody.
create table private.redelivery_inspection_results (
  return_request_id uuid primary key references public.return_requests (id),
  order_id uuid not null references public.orders (id),
  manager_id uuid not null references public.profiles (id),
  receipt_event_id uuid not null references public.business_events (id),
  request_id uuid not null,
  event_id uuid not null unique references public.business_events (id),
  rejection_reason text not null,
  inspected_at timestamptz not null,
  response jsonb not null,
  constraint redelivery_inspection_reason_nonblank
    check (btrim(rejection_reason) <> ''),
  constraint redelivery_inspection_response_object
    check (jsonb_typeof(response) = 'object')
);

-- The release plan is a server-created snapshot of every item actually
-- received.  No client can supply or alter a redelivery quantity.
create table private.redelivery_release_plan_items (
  return_request_id uuid not null references public.return_requests (id),
  order_id uuid not null references public.orders (id),
  return_item_id uuid not null references public.return_items (id),
  actual_item_name text not null,
  variant_id uuid references public.product_variants (id),
  variant_label text,
  attributes jsonb not null default '{}'::jsonb,
  quantity_received bigint not null,
  quantity_to_redeliver bigint not null,
  receipt_event_id uuid not null references public.business_events (id),
  inspection_event_id uuid not null references public.business_events (id),
  created_at timestamptz not null default statement_timestamp(),
  primary key (return_request_id, return_item_id),
  constraint redelivery_release_name_nonblank check (btrim(actual_item_name) <> ''),
  constraint redelivery_release_attributes_object
    check (jsonb_typeof(attributes) = 'object'),
  constraint redelivery_release_quantity_positive check (
    quantity_received > 0 and quantity_to_redeliver > 0
  ),
  constraint redelivery_release_full_received_plan check (
    quantity_received = quantity_to_redeliver
  )
);

-- A task owns its own immutable, private item snapshot.  This prevents a
-- later return-item edit from changing what a shipper is authorized to carry.
create table private.redelivery_task_items (
  task_id uuid not null references public.delivery_tasks (id),
  return_request_id uuid not null references public.return_requests (id),
  order_id uuid not null references public.orders (id),
  return_item_id uuid not null references public.return_items (id),
  actual_item_name text not null,
  variant_id uuid references public.product_variants (id),
  variant_label text,
  attributes jsonb not null default '{}'::jsonb,
  quantity bigint not null,
  created_at timestamptz not null default statement_timestamp(),
  primary key (task_id, return_item_id),
  constraint redelivery_task_item_name_nonblank check (btrim(actual_item_name) <> ''),
  constraint redelivery_task_item_attributes_object
    check (jsonb_typeof(attributes) = 'object'),
  constraint redelivery_task_item_quantity_positive check (quantity > 0)
);

-- Accept is deliberately separate from start.  Accept records the shipper's
-- full physical receipt/custody proof; start records transport commencement.
create table private.redelivery_acceptances (
  task_id uuid primary key references public.delivery_tasks (id),
  return_request_id uuid not null references public.return_requests (id),
  order_id uuid not null references public.orders (id),
  shipper_id uuid not null references public.profiles (id),
  request_id uuid not null,
  event_id uuid not null unique references public.business_events (id),
  items jsonb not null,
  accepted_at timestamptz not null,
  response jsonb not null,
  constraint redelivery_accept_items_valid check (
    jsonb_typeof(items) = 'array' and jsonb_array_length(items) > 0
  ),
  constraint redelivery_accept_response_object
    check (jsonb_typeof(response) = 'object')
);

create table private.redelivery_custody (
  task_id uuid primary key references public.delivery_tasks (id),
  return_request_id uuid not null references public.return_requests (id),
  order_id uuid not null references public.orders (id),
  shipper_id uuid not null references public.profiles (id),
  accepted_at timestamptz not null,
  started_at timestamptz,
  event_id uuid not null unique references public.business_events (id),
  items jsonb not null,
  response jsonb not null,
  constraint redelivery_custody_times_ordered check (
    started_at is null or started_at >= accepted_at
  ),
  constraint redelivery_custody_items_valid check (
    jsonb_typeof(items) = 'array' and jsonb_array_length(items) > 0
  ),
  constraint redelivery_custody_response_object
    check (jsonb_typeof(response) = 'object')
);

create table private.redelivery_starts (
  task_id uuid primary key references public.delivery_tasks (id),
  return_request_id uuid not null references public.return_requests (id),
  order_id uuid not null references public.orders (id),
  shipper_id uuid not null references public.profiles (id),
  accepted_at timestamptz not null,
  started_at timestamptz not null,
  event_id uuid not null unique references public.business_events (id),
  response jsonb not null,
  constraint redelivery_start_times_ordered check (started_at >= accepted_at),
  constraint redelivery_start_response_object
    check (jsonb_typeof(response) = 'object')
);

create table private.redelivery_outcomes (
  task_id uuid primary key references public.delivery_tasks (id),
  return_request_id uuid not null references public.return_requests (id),
  order_id uuid not null references public.orders (id),
  shipper_id uuid not null references public.profiles (id),
  outcome text not null check (outcome in ('completed', 'failed')),
  request_id uuid not null,
  event_id uuid not null unique references public.business_events (id),
  reason_code text,
  description text,
  occurred_at timestamptz not null,
  response jsonb not null,
  constraint redelivery_outcome_reason_valid check (
    outcome = 'completed'
    or reason_code in ('unreachable', 'reschedule', 'bad_address', 'refusal', 'other')
  ),
  constraint redelivery_outcome_other_description check (
    outcome = 'completed'
    or reason_code <> 'other'
    or (description is not null and btrim(description) <> '')
  ),
  constraint redelivery_outcome_response_object
    check (jsonb_typeof(response) = 'object')
);

create index redelivery_task_items_request_idx
  on private.redelivery_task_items (return_request_id, task_id);
create index redelivery_release_plan_order_idx
  on private.redelivery_release_plan_items (order_id, return_request_id);

alter table private.redelivery_requests enable row level security;
alter table private.redelivery_requests force row level security;
alter table private.redelivery_return_receipts enable row level security;
alter table private.redelivery_return_receipts force row level security;
alter table private.redelivery_inspection_results enable row level security;
alter table private.redelivery_inspection_results force row level security;
alter table private.redelivery_release_plan_items enable row level security;
alter table private.redelivery_release_plan_items force row level security;
alter table private.redelivery_task_items enable row level security;
alter table private.redelivery_task_items force row level security;
alter table private.redelivery_acceptances enable row level security;
alter table private.redelivery_acceptances force row level security;
alter table private.redelivery_custody enable row level security;
alter table private.redelivery_custody force row level security;
alter table private.redelivery_starts enable row level security;
alter table private.redelivery_starts force row level security;
alter table private.redelivery_outcomes enable row level security;
alter table private.redelivery_outcomes force row level security;

revoke all on private.redelivery_requests,
  private.redelivery_return_receipts,
  private.redelivery_inspection_results,
  private.redelivery_release_plan_items,
  private.redelivery_task_items,
  private.redelivery_acceptances,
  private.redelivery_custody,
  private.redelivery_starts,
  private.redelivery_outcomes
  from public, anon, authenticated, service_role;
grant select, insert on private.redelivery_requests,
  private.redelivery_return_receipts,
  private.redelivery_inspection_results,
  private.redelivery_release_plan_items,
  private.redelivery_task_items,
  private.redelivery_acceptances,
  private.redelivery_custody,
  private.redelivery_starts,
  private.redelivery_outcomes
  to sports_store_return_pickup_writer;

create policy redelivery_requests_writer_read on private.redelivery_requests
  for select to sports_store_return_pickup_writer
  using (current_user = 'sports_store_return_pickup_writer');
create policy redelivery_requests_writer_insert on private.redelivery_requests
  for insert to sports_store_return_pickup_writer
  with check (current_user = 'sports_store_return_pickup_writer');

create policy redelivery_receipts_writer_read on private.redelivery_return_receipts
  for select to sports_store_return_pickup_writer
  using (current_user = 'sports_store_return_pickup_writer');
create policy redelivery_receipts_writer_insert on private.redelivery_return_receipts
  for insert to sports_store_return_pickup_writer
  with check (
    current_user = 'sports_store_return_pickup_writer'
    and manager_id = (select private.delivery_request_user_id())
  );
create policy redelivery_inspections_writer_read on private.redelivery_inspection_results
  for select to sports_store_return_pickup_writer
  using (current_user = 'sports_store_return_pickup_writer');
create policy redelivery_inspections_writer_insert on private.redelivery_inspection_results
  for insert to sports_store_return_pickup_writer
  with check (
    current_user = 'sports_store_return_pickup_writer'
    and manager_id = (select private.delivery_request_user_id())
  );
create policy redelivery_release_writer_read on private.redelivery_release_plan_items
  for select to sports_store_return_pickup_writer
  using (current_user = 'sports_store_return_pickup_writer');
create policy redelivery_release_writer_insert on private.redelivery_release_plan_items
  for insert to sports_store_return_pickup_writer
  with check (current_user = 'sports_store_return_pickup_writer');
create policy redelivery_task_items_writer_read on private.redelivery_task_items
  for select to sports_store_return_pickup_writer
  using (current_user = 'sports_store_return_pickup_writer');
create policy redelivery_task_items_writer_insert on private.redelivery_task_items
  for insert to sports_store_return_pickup_writer
  with check (current_user = 'sports_store_return_pickup_writer');
create policy redelivery_acceptances_writer_read on private.redelivery_acceptances
  for select to sports_store_return_pickup_writer
  using (current_user = 'sports_store_return_pickup_writer');
create policy redelivery_acceptances_writer_insert on private.redelivery_acceptances
  for insert to sports_store_return_pickup_writer
  with check (
    current_user = 'sports_store_return_pickup_writer'
    and shipper_id = (select private.delivery_request_user_id())
  );
create policy redelivery_custody_writer_read on private.redelivery_custody
  for select to sports_store_return_pickup_writer
  using (current_user = 'sports_store_return_pickup_writer');
create policy redelivery_custody_writer_insert on private.redelivery_custody
  for insert to sports_store_return_pickup_writer
  with check (
    current_user = 'sports_store_return_pickup_writer'
    and shipper_id = (select private.delivery_request_user_id())
  );
create policy redelivery_starts_writer_read on private.redelivery_starts
  for select to sports_store_return_pickup_writer
  using (current_user = 'sports_store_return_pickup_writer');
create policy redelivery_starts_writer_insert on private.redelivery_starts
  for insert to sports_store_return_pickup_writer
  with check (
    current_user = 'sports_store_return_pickup_writer'
    and shipper_id = (select private.delivery_request_user_id())
  );
create policy redelivery_outcomes_writer_read on private.redelivery_outcomes
  for select to sports_store_return_pickup_writer
  using (current_user = 'sports_store_return_pickup_writer');
create policy redelivery_outcomes_writer_insert on private.redelivery_outcomes
  for insert to sports_store_return_pickup_writer
  with check (
    current_user = 'sports_store_return_pickup_writer'
    and shipper_id = (select private.delivery_request_user_id())
  );

-- The delivery reader can expose only active assigned redelivery task items.
grant usage on schema private to sports_store_delivery_reader;
grant select (
  task_id, return_request_id, order_id, return_item_id, actual_item_name,
  variant_label, attributes, quantity
) on private.redelivery_task_items to sports_store_delivery_reader;
create policy redelivery_task_items_reader_read on private.redelivery_task_items
  for select to sports_store_delivery_reader
  using (
    current_user = 'sports_store_delivery_reader'
    and exists (
      select 1 from public.delivery_tasks t
      where t.id = redelivery_task_items.task_id
        and t.kind = 'redelivery'::public.delivery_task_kind
        and t.status in (
          'assigned'::public.delivery_task_status,
          'accepted'::public.delivery_task_status,
          'in_transit'::public.delivery_task_status
        )
        and t.assigned_shipper_id = (select private.delivery_request_user_id())
    )
  );

create function private.reject_redelivery_immutable_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'P08.3 redelivery proof/snapshot ledgers are append-only'
    using errcode = '55000', message = 'IMMUTABLE_REDELIVERY_RECORD';
end;
$$;
alter function private.reject_redelivery_immutable_mutation()
  owner to sports_store_return_pickup_writer;
revoke all on function private.reject_redelivery_immutable_mutation()
  from public, anon, authenticated, service_role;
do $$
declare
  l_table text;
begin
  foreach l_table in array array[
    'redelivery_requests', 'redelivery_return_receipts',
    'redelivery_inspection_results', 'redelivery_release_plan_items',
    'redelivery_task_items', 'redelivery_acceptances',
    'redelivery_custody', 'redelivery_starts', 'redelivery_outcomes'
  ] loop
    execute format(
      'create trigger %I before update or delete on private.%I '
      'for each row execute function private.reject_redelivery_immutable_mutation()',
      l_table || '_append_only', l_table
    );
  end loop;
end;
$$;

-- Internal column ACLs.  UPDATE(id) is used only to acquire row locks; every
-- actual state mutation below is restricted to the explicit state columns.
grant select (id, role) on public.profiles
  to sports_store_return_pickup_writer;
grant select (
  id, customer_id, status, recipient_name, recipient_phone, address_detail,
  latitude, longitude
) on public.orders to sports_store_return_pickup_writer;
grant update (id) on public.orders to sports_store_return_pickup_writer;
grant select (
  id, order_id, customer_id, request_id, status, decided_by, decision_at,
  inspection_started_at, inspected_at, inspected_by, closed_at
) on public.return_requests to sports_store_return_pickup_writer;
grant update (
  id, status, decision_reason, decision_at, decided_by,
  inspection_started_at, inspected_at, inspected_by, closed_at, updated_at
) on public.return_requests to sports_store_return_pickup_writer;
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
grant update (id) on public.delivery_tasks to sports_store_return_pickup_writer;
grant select (
  id, return_request_id, order_id, order_item_id, actual_item_name,
  variant_id, quantity_to_collect, quantity_collected, sellable_quantity,
  damaged_quantity
) on public.return_items to sports_store_return_pickup_writer;
grant update (id) on public.return_items to sports_store_return_pickup_writer;
grant select (id, label, attributes) on public.product_variants
  to sports_store_return_pickup_writer;
grant insert (
  id, actor_id, subject_type, subject_id, from_state, to_state, reason,
  task_id, request_id, created_at
) on public.business_events to sports_store_return_pickup_writer;
grant insert (
  id, recipient_id, event_id, subject_type, subject_id, title, body, created_at
) on public.notifications to sports_store_return_pickup_writer;

-- P08.1 policies intentionally mention only return_pickup.  These additional
-- policies keep the same restricted writer backstop for redelivery rows.
create policy redelivery_writer_returns_update on public.return_requests
  for update to sports_store_return_pickup_writer
  using (
    current_user = 'sports_store_return_pickup_writer'
    and (
      (select private.current_app_role()) = 'manager'
      or (
        (select private.current_app_role()) = 'shipper'
        and exists (
          select 1 from public.delivery_tasks t
          where t.return_request_id = return_requests.id
            and t.kind = 'redelivery'::public.delivery_task_kind
            and t.assigned_shipper_id = (select private.delivery_request_user_id())
        )
      )
    )
  )
  with check (
    current_user = 'sports_store_return_pickup_writer'
    and (
      ((select private.current_app_role()) = 'manager'
        and status in (
          'awaiting_return_pickup'::public.return_request_status,
          'under_inspection'::public.return_request_status,
          'awaiting_redelivery'::public.return_request_status
        ))
      or (
        (select private.current_app_role()) = 'shipper'
        and status = 'manager_action_required'::public.return_request_status
      )
    )
  );

create policy redelivery_writer_tasks_read on public.delivery_tasks
  for select to sports_store_return_pickup_writer
  using (
    current_user = 'sports_store_return_pickup_writer'
    and kind = 'redelivery'::public.delivery_task_kind
    and (
      (select private.current_app_role()) = 'manager'
      or assigned_shipper_id = (select private.delivery_request_user_id())
    )
  );
create policy redelivery_writer_tasks_insert on public.delivery_tasks
  for insert to sports_store_return_pickup_writer
  with check (
    current_user = 'sports_store_return_pickup_writer'
    and (select private.current_app_role()) = 'manager'
    and kind = 'redelivery'::public.delivery_task_kind
    and status = 'assigned'::public.delivery_task_status
    and attempt_number = 1
    and amount_to_collect_vnd = 0
    and accepted_at is null and started_at is null and completed_at is null
    and failure_reason is null and cancel_reason is null
  );
create policy redelivery_writer_tasks_update on public.delivery_tasks
  for update to sports_store_return_pickup_writer
  using (
    current_user = 'sports_store_return_pickup_writer'
    and kind = 'redelivery'::public.delivery_task_kind
    and (
      (select private.current_app_role()) = 'manager'
      or assigned_shipper_id = (select private.delivery_request_user_id())
    )
  )
  with check (
    current_user = 'sports_store_return_pickup_writer'
    and kind = 'redelivery'::public.delivery_task_kind
    and attempt_number = 1 and amount_to_collect_vnd = 0
    and (
      (
        (select private.current_app_role()) = 'manager'
        and status = 'assigned'::public.delivery_task_status
        and accepted_at is null and started_at is null and completed_at is null
        and failure_reason is null and cancel_reason is null
      )
      or (
        assigned_shipper_id = (select private.delivery_request_user_id())
        and status in (
          'accepted'::public.delivery_task_status,
          'in_transit'::public.delivery_task_status,
          'delivered'::public.delivery_task_status,
          'manager_action_required'::public.delivery_task_status
        )
      )
    )
  );

create policy redelivery_writer_variant_read on public.product_variants
  for select to sports_store_return_pickup_writer
  using (
    current_user = 'sports_store_return_pickup_writer'
    and (select private.current_app_role()) in ('manager', 'shipper')
  );

create policy redelivery_writer_events_insert on public.business_events
  for insert to sports_store_return_pickup_writer
  with check (
    current_user = 'sports_store_return_pickup_writer'
    and actor_id = (select private.delivery_request_user_id())
    and request_id = id
    and incident_kind is null
    and reason in (
      'return_pickup_approved', 'return_customer_received',
      'return_rejected_after_inspection', 'redelivery_assigned',
      'redelivery_accepted', 'redelivery_started',
      'redelivery_completed', 'redelivery_failed'
    )
    and (
      (
        subject_type = 'delivery_task' and subject_id = task_id
        and task_id is not null
      )
      or (
        subject_type = 'return_request' and subject_id is not null
        and task_id is null
      )
    )
  );

create policy redelivery_writer_events_read on public.business_events
for select to sports_store_return_pickup_writer
using (current_user='sports_store_return_pickup_writer'
  and actor_id=private.delivery_request_user_id()
  and reason in ('return_pickup_approved','return_customer_received',
    'return_rejected_after_inspection','redelivery_assigned','redelivery_accepted',
    'redelivery_started','redelivery_completed','redelivery_failed'));

create policy redelivery_writer_notifications_insert
  on public.notifications for insert to sports_store_return_pickup_writer
  with check (
    current_user = 'sports_store_return_pickup_writer'
    and subject_type in ('delivery_task', 'return_request')
    and title in (
      'Nhiệm vụ giao lại mới', 'Giao lại đã hoàn tất',
      'Giao lại cần cửa hàng xử lý'
    )
    and body in (
      'Bạn được phân công một nhiệm vụ giao lại.',
      'Nhiệm vụ giao lại đã hoàn tất.',
      'Nhiệm vụ giao lại cần được cửa hàng xử lý.'
    )
    and exists (
      select 1
      from public.business_events e
      where e.id = notifications.event_id
        and e.actor_id = (select private.delivery_request_user_id())
        and e.reason in (
          'redelivery_assigned', 'redelivery_completed', 'redelivery_failed'
        )
    )
    and (
      exists (
        select 1
        from public.delivery_tasks t
        where t.id = notifications.subject_id
          and notifications.subject_type = 'delivery_task'
          and t.kind = 'redelivery'::public.delivery_task_kind
          and title = 'Nhiệm vụ giao lại mới'
          and recipient_id = t.assigned_shipper_id
      )
      or exists (
        select 1
        from public.orders o
        where o.id = (
          select t.order_id from public.delivery_tasks t
          where t.id = notifications.subject_id
            and notifications.subject_type = 'delivery_task'
        )
        and recipient_id = o.customer_id
        and title <> 'Nhiệm vụ giao lại mới'
      )
      or exists (
        select 1 from public.profiles p
        where p.id = recipient_id
          and p.role = 'manager'::public.user_role
          and title <> 'Nhiệm vụ giao lại mới'
      )
    )
  );

create function private.redelivery_plan_json(p_task_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object('return_item_id', i.return_item_id,
                         'quantity', i.quantity)
      order by i.return_item_id
    ), '[]'::jsonb
  )
  from private.redelivery_task_items i
  where i.task_id = p_task_id;
$$;
alter function private.redelivery_plan_json(uuid)
  owner to sports_store_return_pickup_writer;
revoke all on function private.redelivery_plan_json(uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.redelivery_plan_json(uuid)
  to sports_store_return_pickup_writer;

create function private.redelivery_release_plan_json(p_return_request_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object('return_item_id', i.return_item_id,
                         'quantity', i.quantity_to_redeliver)
      order by i.return_item_id
    ), '[]'::jsonb
  )
  from private.redelivery_release_plan_items i
  where i.return_request_id = p_return_request_id;
$$;
alter function private.redelivery_release_plan_json(uuid)
  owner to sports_store_return_pickup_writer;
revoke all on function private.redelivery_release_plan_json(uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.redelivery_release_plan_json(uuid)
  to sports_store_return_pickup_writer;

-- Approval is intentionally narrow: it can only approve the exact current
-- customer-submitted return_items plan.  It cannot add, remove or re-quantity
-- an item, and is kept separate from the inspection/release decision.
create function public.approve_return_pickup_plan(
  p_return_request_id uuid,
  p_request_id uuid,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  l_actor uuid := (select private.delivery_request_user_id());
  l_role text;
  l_order_id uuid;
  l_order_status public.order_status;
  l_customer_id uuid;
  l_return public.return_requests%rowtype;
  l_existing private.redelivery_requests%rowtype;
  l_items jsonb;
  l_live jsonb;
  l_payload jsonb;
  l_hash text;
  l_event uuid;
  l_now timestamptz;
  l_response jsonb;
  l_count bigint := 0;
  l_all_count bigint := 0;
  l_item record;
begin
  if l_actor is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if p_return_request_id is null or p_request_id is null or p_items is null then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;
  l_items := private.normalize_return_pickup_items(p_items);

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.redelivery:request:' || l_actor::text || ':'
      || p_request_id::text, 0));
  select r.order_id into l_order_id
  from public.return_requests r where r.id = p_return_request_id;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.complete_outbound_delivery:order:' || l_order_id::text, 0));
  select o.status, o.customer_id into l_order_status, l_customer_id
  from public.orders o where o.id = l_order_id for update;
  select (jsonb_populate_record(null::public.return_requests,jsonb_build_object('id',r.id,'order_id',r.order_id,'customer_id',r.customer_id,'request_id',r.request_id,'status',r.status,'decided_by',r.decided_by,'decision_at',r.decision_at,'inspection_started_at',r.inspection_started_at,'inspected_at',r.inspected_at,'inspected_by',r.inspected_by,'closed_at',r.closed_at))).* into l_return
  from public.return_requests r
  where r.id = p_return_request_id and r.order_id = l_order_id
  for update;
  if not found or l_return.customer_id is distinct from l_customer_id then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  perform 1 from public.delivery_tasks t
  where t.return_request_id = p_return_request_id
  order by t.id for update;
  for l_item in
    select i.id, i.order_id, i.quantity_to_collect, i.quantity_collected,
           i.sellable_quantity, i.damaged_quantity
    from public.return_items i
    where i.return_request_id = p_return_request_id
    order by i.id for update of i
  loop
    l_all_count := l_all_count + 1;
    if l_item.order_id is distinct from l_order_id
       or l_item.quantity_to_collect <= 0
       or l_item.quantity_collected <> 0
       or l_item.sellable_quantity <> 0
       or l_item.damaged_quantity <> 0 then
      raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
    end if;
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object(
           'return_item_id', i.id, 'quantity', i.quantity_to_collect
         ) order by i.id), '[]'::jsonb), count(*)
    into l_live, l_count
  from public.return_items i
  where i.return_request_id = p_return_request_id
    and i.order_id = l_order_id;
  select role::text into l_role from public.profiles
  where id = l_actor for share;
  if l_role is distinct from 'manager' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;
  l_payload := jsonb_build_object(
    'operation', 'approve_return_pickup_plan',
    'return_request_id', p_return_request_id,
    'request_id', p_request_id,
    'items', l_items
  );
  l_hash := md5(l_payload::text);
  select r.* into l_existing from private.redelivery_requests r
  where r.actor_id = l_actor and r.request_id = p_request_id ;
  if found then
    if l_existing.operation <> 'approve_return_pickup_plan'
       or l_existing.return_request_id is distinct from p_return_request_id
       or l_existing.payload_hash <> l_hash
       or l_existing.payload is distinct from l_payload then
      raise exception using errcode = 'PT409', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return l_existing.response;
  end if;
  if l_order_status is distinct from 'delivered'::public.order_status
     or l_return.status is distinct from 'pending_review'::public.return_request_status
     or l_count = 0
     or l_count <> l_all_count
     or l_items is distinct from l_live then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;
  l_now := pg_catalog.clock_timestamp();
  update public.return_requests
  set status = 'awaiting_return_pickup'::public.return_request_status,
      decision_reason = 'approved_for_return_pickup',
      decision_at = l_now,
      decided_by = l_actor,
      updated_at = l_now
  where id = p_return_request_id;
  l_event := pg_catalog.gen_random_uuid();
  insert into public.business_events (
    id, actor_id, subject_type, subject_id, from_state, to_state,
    reason, request_id, created_at
  ) values (
    l_event, l_actor, 'return_request', p_return_request_id,
    'pending_review', 'awaiting_return_pickup', 'return_pickup_approved',
    l_event, l_now
  );
  l_response := pg_catalog.jsonb_build_object(
    'operation', 'approve_return_pickup_plan',
    'order_id', l_order_id, 'return_request_id', p_return_request_id,
    'return_status', 'awaiting_return_pickup', 'approved_at', l_now,
    'event_id', l_event, 'occurred_at', l_now, 'request_id', p_request_id
  );
  insert into private.redelivery_requests (
    actor_id, request_id, operation, order_id, return_request_id,
    payload, payload_hash, response, created_at
  ) values (
    l_actor, p_request_id, 'approve_return_pickup_plan', l_order_id,
    p_return_request_id, l_payload, l_hash, l_response, l_now
  );
  return l_response;
end;
$$;
alter function public.approve_return_pickup_plan(uuid, uuid, jsonb)
  owner to sports_store_return_pickup_writer;

create function public.receive_customer_return(
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
  l_actor uuid := (select private.delivery_request_user_id());
  l_role text;
  l_order_id uuid;
  l_customer_id uuid;
  l_order_status public.order_status;
  l_return public.return_requests%rowtype;
  l_task public.delivery_tasks%rowtype;
  l_custody private.return_pickup_custody%rowtype;
  l_handover private.return_pickup_handover_reports%rowtype;
  l_receipt private.redelivery_return_receipts%rowtype;
  l_existing private.redelivery_requests%rowtype;
  l_items jsonb;
  l_payload jsonb;
  l_hash text;
  l_event uuid;
  l_now timestamptz;
  l_response jsonb;
  l_live jsonb;
  l_count bigint := 0;
  l_all_count bigint := 0;
  l_row record;
begin
  if l_actor is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if p_task_id is null or p_request_id is null or p_items is null then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;
  l_items := private.normalize_return_pickup_items(p_items);

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.redelivery:request:' || l_actor::text || ':'
      || p_request_id::text, 0));
  select t.order_id into l_order_id
  from public.delivery_tasks t
  where t.id = p_task_id and t.kind = 'return_pickup'::public.delivery_task_kind;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.complete_outbound_delivery:order:' || l_order_id::text, 0));
  select o.status, o.customer_id into l_order_status, l_customer_id
  from public.orders o where o.id = l_order_id for update;
  select (jsonb_populate_record(null::public.return_requests,jsonb_build_object('id',r.id,'order_id',r.order_id,'customer_id',r.customer_id,'request_id',r.request_id,'status',r.status,'decided_by',r.decided_by,'decision_at',r.decision_at,'inspection_started_at',r.inspection_started_at,'inspected_at',r.inspected_at,'inspected_by',r.inspected_by,'closed_at',r.closed_at))).* into l_return
  from public.return_requests r
  where r.id = (select return_request_id from public.delivery_tasks where id = p_task_id)
    and r.order_id = l_order_id for update;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  select t.* into l_task from public.delivery_tasks t
  where t.id = p_task_id and t.order_id = l_order_id
    and t.return_request_id = l_return.id
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  perform 1 from public.delivery_tasks t
  where t.return_request_id = l_return.id order by t.id for update;
  for l_row in
    select i.id, i.order_id, i.quantity_to_collect, i.quantity_collected,
           i.sellable_quantity, i.damaged_quantity
    from public.return_items i
    where i.return_request_id = l_return.id order by i.id for update of i
  loop
    l_all_count := l_all_count + 1;
    if l_row.order_id is distinct from l_order_id
       or l_row.quantity_collected <> l_row.quantity_to_collect
       or l_row.quantity_collected <= 0
       or l_row.sellable_quantity <> 0
       or l_row.damaged_quantity <> 0 then
      raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
    end if;
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object(
           'return_item_id', i.id, 'quantity', i.quantity_collected
         ) order by i.id), '[]'::jsonb), count(*)
    into l_live, l_count
  from public.return_items i
  where i.return_request_id = l_return.id and i.order_id = l_order_id;
  select * into l_custody from private.return_pickup_custody c
  where c.task_id = p_task_id;
  select * into l_handover from private.return_pickup_handover_reports h
  where h.task_id = p_task_id;
  select role::text into l_role from public.profiles
  where id = l_actor for share;
  if l_role is distinct from 'manager' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;
  l_payload := jsonb_build_object(
    'operation', 'receive_customer_return', 'task_id', p_task_id,
    'request_id', p_request_id, 'items', l_items
  );
  l_hash := md5(l_payload::text);
  select r.* into l_existing from private.redelivery_requests r
  where r.actor_id = l_actor and r.request_id = p_request_id ;
  if found then
    if l_existing.operation <> 'receive_customer_return'
       or l_existing.task_id is distinct from p_task_id
       or l_existing.return_request_id is distinct from l_return.id
       or l_existing.payload_hash <> l_hash
       or l_existing.payload is distinct from l_payload then
      raise exception using errcode = 'PT409', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return l_existing.response;
  end if;
  if l_order_status is distinct from 'delivered'::public.order_status
     or l_return.customer_id is distinct from l_customer_id
     or l_task.kind <> 'return_pickup'::public.delivery_task_kind
     or l_task.status <> 'in_transit'::public.delivery_task_status
     or l_task.attempt_number <> 1 or l_task.amount_to_collect_vnd <> 0
     or l_task.completed_at is not null
     or l_return.status <> 'returning_to_store'::public.return_request_status
     or l_count = 0 or l_count <> l_all_count
     or l_items is distinct from l_live
     or l_custody.task_id is null
     or l_custody.order_id is distinct from l_order_id
     or l_custody.return_request_id is distinct from l_return.id
     or l_custody.accepted_at is distinct from l_task.accepted_at
     or l_custody.started_at is distinct from l_task.started_at
     or l_custody.accepted_at is distinct from l_custody.started_at
     or l_handover.task_id is null
     or l_handover.return_request_id is distinct from l_return.id
     or l_handover.order_id is distinct from l_order_id
     or l_handover.items is distinct from l_items
     or l_custody.items is distinct from l_items then
    raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
  end if;
  if exists (
    select 1 from private.redelivery_return_receipts x
    where x.return_request_id = l_return.id
  ) then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;
  l_now := pg_catalog.clock_timestamp();
  update public.delivery_tasks
  set status = 'returned_to_store'::public.delivery_task_status,
      completed_at = l_now, updated_at = l_now
  where id = p_task_id;
  update public.return_requests
  set status = 'under_inspection'::public.return_request_status,
      inspection_started_at = l_now, updated_at = l_now
  where id = l_return.id;
  l_event := pg_catalog.gen_random_uuid();
  insert into public.business_events (
    id, actor_id, subject_type, subject_id, from_state, to_state,
    reason, task_id, request_id, created_at
  ) values (
    l_event, l_actor, 'delivery_task', p_task_id,
    'in_transit', 'returned_to_store', 'return_customer_received',
    p_task_id, l_event, l_now
  );
  l_response := pg_catalog.jsonb_build_object(
    'operation', 'receive_customer_return', 'task_id', p_task_id,
    'order_id', l_order_id, 'return_request_id', l_return.id,
    'task_status', 'returned_to_store', 'return_status', 'under_inspection',
    'received_at', l_now, 'event_id', l_event,
    'occurred_at', l_now, 'request_id', p_request_id
  );
  insert into private.redelivery_return_receipts (
    return_request_id, pickup_task_id, order_id, manager_id, request_id,
    event_id, items, received_at, response
  ) values (
    l_return.id, p_task_id, l_order_id, l_actor, p_request_id,
    l_event, l_items, l_now, l_response
  );
  insert into private.redelivery_requests (
    actor_id, request_id, operation, order_id, return_request_id, task_id,
    payload, payload_hash, response, created_at
  ) values (
    l_actor, p_request_id, 'receive_customer_return', l_order_id,
    l_return.id, p_task_id, l_payload, l_hash, l_response, l_now
  );
  return l_response;
end;
$$;
alter function public.receive_customer_return(uuid, uuid, jsonb)
  owner to sports_store_return_pickup_writer;

create function public.reject_return_after_inspection(
  p_return_request_id uuid,
  p_request_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  l_actor uuid := (select private.delivery_request_user_id());
  l_role text;
  l_order_id uuid;
  l_customer_id uuid;
  l_order_status public.order_status;
  l_return public.return_requests%rowtype;
  l_receipt private.redelivery_return_receipts%rowtype;
  l_pickup public.delivery_tasks%rowtype;
  l_existing private.redelivery_requests%rowtype;
  l_reason text;
  l_payload jsonb;
  l_hash text;
  l_event uuid;
  l_now timestamptz;
  l_response jsonb;
  l_receipt_plan jsonb;
  l_live jsonb;
  l_count bigint := 0;
  l_all_count bigint := 0;
  l_item record;
begin
  if l_actor is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  l_reason := nullif(
    pg_catalog.regexp_replace(coalesce(p_reason, ''),
      '^[[:space:]]+|[[:space:]]+$', '', 'g'), '');
  if p_return_request_id is null or p_request_id is null
     or l_reason is null or char_length(l_reason) > 2000 then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.redelivery:request:' || l_actor::text || ':'
      || p_request_id::text, 0));
  select r.order_id into l_order_id
  from public.return_requests r where r.id = p_return_request_id;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.complete_outbound_delivery:order:' || l_order_id::text, 0));
  select o.status, o.customer_id into l_order_status, l_customer_id
  from public.orders o where o.id = l_order_id for update;
  select (jsonb_populate_record(null::public.return_requests,jsonb_build_object('id',r.id,'order_id',r.order_id,'customer_id',r.customer_id,'request_id',r.request_id,'status',r.status,'decided_by',r.decided_by,'decision_at',r.decision_at,'inspection_started_at',r.inspection_started_at,'inspected_at',r.inspected_at,'inspected_by',r.inspected_by,'closed_at',r.closed_at))).* into l_return
  from public.return_requests r
  where r.id = p_return_request_id and r.order_id = l_order_id for update;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  perform 1 from public.delivery_tasks t
  where t.return_request_id = p_return_request_id order by t.id for update;
  select rr.* into l_receipt
  from private.redelivery_return_receipts rr
  where rr.return_request_id = p_return_request_id;
  if l_receipt.return_request_id is not null then
    select t.* into l_pickup from public.delivery_tasks t
    where t.id = l_receipt.pickup_task_id for update;
  end if;
  for l_item in
    select i.id, i.order_id, i.actual_item_name, i.variant_id,
           i.quantity_to_collect, i.quantity_collected,
           i.sellable_quantity, i.damaged_quantity,
           v.label as variant_label, v.attributes
    from public.return_items i
    left join public.product_variants v on v.id = i.variant_id
    where i.return_request_id = p_return_request_id
    order by i.id for update of i
  loop
    l_all_count := l_all_count + 1;
    if l_item.order_id is distinct from l_order_id
       or l_item.quantity_collected <= 0
       or l_item.quantity_collected <> l_item.quantity_to_collect
       or l_item.sellable_quantity <> 0
       or l_item.damaged_quantity <> 0 then
      raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
    end if;
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object(
           'return_item_id', i.id, 'quantity', i.quantity_collected
         ) order by i.id), '[]'::jsonb), count(*)
    into l_live, l_count
  from public.return_items i
  where i.return_request_id = p_return_request_id
    and i.order_id = l_order_id;
  select role::text into l_role from public.profiles
  where id = l_actor for share;
  if l_role is distinct from 'manager' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;
  l_payload := jsonb_build_object(
    'operation', 'reject_return_after_inspection',
    'return_request_id', p_return_request_id,
    'request_id', p_request_id, 'reason', l_reason
  );
  l_hash := md5(l_payload::text);
  select r.* into l_existing from private.redelivery_requests r
  where r.actor_id = l_actor and r.request_id = p_request_id ;
  if found then
    if l_existing.operation <> 'reject_return_after_inspection'
       or l_existing.return_request_id is distinct from p_return_request_id
       or l_existing.payload_hash <> l_hash
       or l_existing.payload is distinct from l_payload then
      raise exception using errcode = 'PT409', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return l_existing.response;
  end if;
  if l_order_status is distinct from 'delivered'::public.order_status
     or l_return.customer_id is distinct from l_customer_id
     or l_return.status is distinct from 'under_inspection'::public.return_request_status
     or l_return.inspection_started_at is null
     or l_count = 0 or l_count <> l_all_count
     or l_receipt.return_request_id is null
     or l_receipt.order_id is distinct from l_order_id
     or l_receipt.items is distinct from l_live
     or l_pickup.id is null
     or l_pickup.kind <> 'return_pickup'::public.delivery_task_kind
     or l_pickup.status <> 'returned_to_store'::public.delivery_task_status
     or l_pickup.completed_at is null then
    raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
  end if;
  if exists (
    select 1 from private.redelivery_inspection_results x
    where x.return_request_id = p_return_request_id
  ) or exists (
    select 1 from private.redelivery_release_plan_items x
    where x.return_request_id = p_return_request_id
  ) then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;
  l_now := pg_catalog.clock_timestamp();
  update public.return_requests
  set status = 'awaiting_redelivery'::public.return_request_status,
      inspected_at = l_now, inspected_by = l_actor, closed_at = null,
      updated_at = l_now
  where id = p_return_request_id;
  l_event := pg_catalog.gen_random_uuid();
  insert into public.business_events (
    id, actor_id, subject_type, subject_id, from_state, to_state,
    reason, request_id, created_at
  ) values (
    l_event, l_actor, 'return_request', p_return_request_id,
    'under_inspection', 'awaiting_redelivery',
    'return_rejected_after_inspection', l_event, l_now
  );
  for l_item in
    select i.id, i.order_id, i.actual_item_name, i.variant_id,
           i.quantity_collected, v.label as variant_label,
           coalesce(v.attributes, '{}'::jsonb) as attributes
    from public.return_items i
    left join public.product_variants v on v.id = i.variant_id
    where i.return_request_id = p_return_request_id
      and i.order_id = l_order_id order by i.id
  loop
    insert into private.redelivery_release_plan_items (
      return_request_id, order_id, return_item_id, actual_item_name,
      variant_id, variant_label, attributes, quantity_received,
      quantity_to_redeliver, receipt_event_id, inspection_event_id, created_at
    ) values (
      p_return_request_id, l_order_id, l_item.id, l_item.actual_item_name,
      l_item.variant_id, l_item.variant_label, l_item.attributes,
      l_item.quantity_collected, l_item.quantity_collected,
      l_receipt.event_id, l_event, l_now
    );
  end loop;
  l_response := pg_catalog.jsonb_build_object(
    'operation', 'reject_return_after_inspection',
    'order_id', l_order_id, 'return_request_id', p_return_request_id,
    'return_status', 'awaiting_redelivery', 'reason', l_reason,
    'inspected_at', l_now, 'closed_at', null,
    'plan', private.redelivery_release_plan_json(null::uuid),
    'event_id', l_event, 'occurred_at', l_now, 'request_id', p_request_id
  );
  -- Build the plan after inserts; the helper takes a request id, not a task id.
  l_response := jsonb_set(
    l_response, '{plan}', private.redelivery_release_plan_json(p_return_request_id)
  );
  insert into private.redelivery_inspection_results (
    return_request_id, order_id, manager_id, receipt_event_id, request_id,
    event_id, rejection_reason, inspected_at, response
  ) values (
    p_return_request_id, l_order_id, l_actor, l_receipt.event_id, p_request_id,
    l_event, l_reason, l_now, l_response
  );
  insert into private.redelivery_requests (
    actor_id, request_id, operation, order_id, return_request_id,
    payload, payload_hash, response, created_at
  ) values (
    l_actor, p_request_id, 'reject_return_after_inspection', l_order_id,
    p_return_request_id, l_payload, l_hash, l_response, l_now
  );
  return l_response;
end;
$$;
alter function public.reject_return_after_inspection(uuid, uuid, text)
  owner to sports_store_return_pickup_writer;

create function public.assign_redelivery_task(
  p_return_request_id uuid,
  p_shipper_id uuid,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  l_actor uuid := (select private.delivery_request_user_id());
  l_role text;
  l_shipper_role text;
  l_order_id uuid;
  l_customer_id uuid;
  l_order_status public.order_status;
  l_return public.return_requests%rowtype;
  l_task public.delivery_tasks%rowtype;
  l_existing private.redelivery_requests%rowtype;
  l_plan jsonb;
  l_payload jsonb;
  l_hash text;
  l_task_id uuid;
  l_event uuid;
  l_now timestamptz;
  l_response jsonb;
  l_item record;
begin
  if l_actor is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if p_return_request_id is null or p_shipper_id is null or p_request_id is null then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.redelivery:request:' || l_actor::text || ':'
      || p_request_id::text, 0));
  select r.order_id into l_order_id
  from public.return_requests r where r.id = p_return_request_id;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.complete_outbound_delivery:order:' || l_order_id::text, 0));
  select o.status, o.customer_id, o.recipient_name, o.recipient_phone,
         o.address_detail, o.latitude, o.longitude
    into l_order_status, l_customer_id, l_task.destination_name,
         l_task.destination_phone, l_task.destination_address,
         l_task.destination_latitude, l_task.destination_longitude
  from public.orders o where o.id = l_order_id for update;
  select (jsonb_populate_record(null::public.return_requests,jsonb_build_object('id',r.id,'order_id',r.order_id,'customer_id',r.customer_id,'request_id',r.request_id,'status',r.status,'decided_by',r.decided_by,'decision_at',r.decision_at,'inspection_started_at',r.inspection_started_at,'inspected_at',r.inspected_at,'inspected_by',r.inspected_by,'closed_at',r.closed_at))).* into l_return from public.return_requests r
  where r.id = p_return_request_id and r.order_id = l_order_id for update;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  perform 1 from public.delivery_tasks t
  where t.return_request_id = p_return_request_id order by t.id for update;
  select role::text into l_role from public.profiles where id = l_actor for share;
  select role::text into l_shipper_role from public.profiles
  where id = p_shipper_id for share;
  if l_role is distinct from 'manager' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;
  if l_shipper_role is distinct from 'shipper' then
    raise exception using errcode = 'PT409', message = 'INVALID_SHIPPER';
  end if;
  l_plan := private.redelivery_release_plan_json(p_return_request_id);
  l_payload := jsonb_build_object(
    'operation', 'assign_redelivery_task',
    'return_request_id', p_return_request_id,
    'shipper_id', p_shipper_id, 'request_id', p_request_id
  );
  l_hash := md5(l_payload::text);
  select r.* into l_existing from private.redelivery_requests r
  where r.actor_id = l_actor and r.request_id = p_request_id ;
  if found then
    if l_existing.operation <> 'assign_redelivery_task'
       or l_existing.return_request_id is distinct from p_return_request_id
       or l_existing.shipper_id is distinct from p_shipper_id
       or l_existing.payload_hash <> l_hash
       or l_existing.payload is distinct from l_payload then
      raise exception using errcode = 'PT409', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return l_existing.response;
  end if;
  if l_order_status is distinct from 'delivered'::public.order_status
     or l_return.customer_id is distinct from l_customer_id
     or l_return.status is distinct from 'awaiting_redelivery'::public.return_request_status
     or l_plan = '[]'::jsonb
     or not exists (
       select 1 from private.redelivery_inspection_results x
       where x.return_request_id = p_return_request_id
     )
     or not exists (
       select 1 from private.redelivery_return_receipts x
       where x.return_request_id = p_return_request_id
     ) then
    raise exception using errcode = 'PT409', message = 'DEPENDENCY_NOT_READY';
  end if;
  if exists (
    select 1 from public.delivery_tasks t
    where t.return_request_id = p_return_request_id
      and t.kind = 'redelivery'::public.delivery_task_kind
      and t.status in (
        'pending_assignment'::public.delivery_task_status,
        'assigned'::public.delivery_task_status,
        'accepted'::public.delivery_task_status,
        'in_transit'::public.delivery_task_status,
        'manager_action_required'::public.delivery_task_status
      )
  ) then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;
  if exists (
    select 1 from public.delivery_tasks t
    where t.return_request_id = p_return_request_id
      and t.kind = 'return_pickup'::public.delivery_task_kind
      and t.status not in (
        'returned_to_store'::public.delivery_task_status,
        'failed'::public.delivery_task_status,
        'cancelled'::public.delivery_task_status
      )
  ) then
    raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
  end if;
  l_task_id := pg_catalog.gen_random_uuid();
  l_now := pg_catalog.clock_timestamp();
  insert into public.delivery_tasks (
    id, order_id, return_request_id, kind, assigned_shipper_id, assigned_by,
    status, attempt_number, destination_name, destination_phone,
    destination_address, destination_latitude, destination_longitude,
    amount_to_collect_vnd, assigned_at
  ) values (
    l_task_id, l_order_id, p_return_request_id,
    'redelivery'::public.delivery_task_kind, p_shipper_id, l_actor,
    'assigned'::public.delivery_task_status, 1,
    l_task.destination_name, l_task.destination_phone,
    l_task.destination_address, l_task.destination_latitude,
    l_task.destination_longitude, 0, l_now
  );
  for l_item in
    select i.return_item_id, i.actual_item_name, i.variant_id,
           i.variant_label, i.attributes, i.quantity_to_redeliver as quantity
    from private.redelivery_release_plan_items i
    where i.return_request_id = p_return_request_id
      and i.order_id = l_order_id order by i.return_item_id
  loop
    insert into private.redelivery_task_items (
      task_id, return_request_id, order_id, return_item_id, actual_item_name,
      variant_id, variant_label, attributes, quantity, created_at
    ) values (
      l_task_id, p_return_request_id, l_order_id, l_item.return_item_id,
      l_item.actual_item_name, l_item.variant_id, l_item.variant_label,
      l_item.attributes, l_item.quantity, l_now
    );
  end loop;
  l_event := pg_catalog.gen_random_uuid();
  insert into public.business_events (
    id, actor_id, subject_type, subject_id, from_state, to_state,
    reason, task_id, request_id, created_at
  ) values (
    l_event, l_actor, 'delivery_task', l_task_id,
    'pending_assignment', 'assigned', 'redelivery_assigned',
    l_task_id, l_event, l_now
  );
  insert into public.notifications (
    id, recipient_id, event_id, subject_type, subject_id, title, body, created_at
  ) values (
    pg_catalog.gen_random_uuid(), p_shipper_id, l_event, 'delivery_task', l_task_id,
    'Nhiệm vụ giao lại mới', 'Bạn được phân công một nhiệm vụ giao lại.', l_now
  );
  l_response := pg_catalog.jsonb_build_object(
    'operation', 'assign_redelivery_task', 'task_id', l_task_id,
    'order_id', l_order_id, 'return_request_id', p_return_request_id,
    'kind', 'redelivery', 'task_status', 'assigned',
    'return_status', 'awaiting_redelivery',
    'assigned_shipper_id', p_shipper_id, 'attempt_number', 1,
    'amount_to_collect_vnd', 0, 'assigned_at', l_now,
    'event_id', l_event, 'occurred_at', l_now, 'request_id', p_request_id
  );
  insert into private.redelivery_requests (
    actor_id, request_id, operation, order_id, return_request_id,
    task_id, shipper_id, payload, payload_hash, response, created_at
  ) values (
    l_actor, p_request_id, 'assign_redelivery_task', l_order_id,
    p_return_request_id, l_task_id, p_shipper_id, l_payload, l_hash,
    l_response, l_now
  );
  return l_response;
end;
$$;
alter function public.assign_redelivery_task(uuid, uuid, uuid)
  owner to sports_store_return_pickup_writer;

create function public.accept_redelivery_task(
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
  l_actor uuid := (select private.delivery_request_user_id());
  l_role text;
  l_order_id uuid;
  l_return_id uuid;
  l_customer_id uuid;
  l_order_status public.order_status;
  l_return_status public.return_request_status;
  l_task public.delivery_tasks%rowtype;
  l_existing private.redelivery_requests%rowtype;
  l_items jsonb;
  l_plan jsonb;
  l_payload jsonb;
  l_hash text;
  l_event uuid;
  l_now timestamptz;
  l_response jsonb;
begin
  if l_actor is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if p_task_id is null or p_request_id is null or p_items is null then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;
  l_items := private.normalize_return_pickup_items(p_items);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.redelivery:request:' || l_actor::text || ':'
      || p_request_id::text, 0));
  select t.order_id, t.return_request_id into l_order_id, l_return_id
  from public.delivery_tasks t
  where t.id = p_task_id and t.kind = 'redelivery'::public.delivery_task_kind
    and t.assigned_shipper_id = l_actor;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.complete_outbound_delivery:order:' || l_order_id::text, 0));
  select o.status, o.customer_id into l_order_status, l_customer_id
  from public.orders o where o.id = l_order_id for update;
  select r.status into l_return_status from public.return_requests r
  where r.id = l_return_id and r.order_id = l_order_id for update;
  select t.* into l_task from public.delivery_tasks t
  where t.id = p_task_id for update;
  perform 1 from public.delivery_tasks t
  where t.return_request_id = l_return_id order by t.id for update;
  select role::text into l_role from public.profiles where id = l_actor for share;
  if l_role is distinct from 'shipper' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;
  l_plan := private.redelivery_plan_json(p_task_id);
  l_payload := jsonb_build_object(
    'operation', 'accept_redelivery_task', 'task_id', p_task_id,
    'request_id', p_request_id, 'items', l_items
  );
  l_hash := md5(l_payload::text);
  select r.* into l_existing from private.redelivery_requests r
  where r.actor_id = l_actor and r.request_id = p_request_id ;
  if found then
    if l_existing.operation <> 'accept_redelivery_task'
       or l_existing.task_id is distinct from p_task_id
       or l_existing.return_request_id is distinct from l_return_id
       or l_existing.payload_hash <> l_hash
       or l_existing.payload is distinct from l_payload then
      raise exception using errcode = 'PT409', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return l_existing.response;
  end if;
  if l_order_status is distinct from 'delivered'::public.order_status
     or l_customer_id is null
     or l_return_status is distinct from 'awaiting_redelivery'::public.return_request_status
     or l_task.assigned_shipper_id is distinct from l_actor
     or l_task.status is distinct from 'assigned'::public.delivery_task_status
     or l_task.attempt_number <> 1 or l_task.amount_to_collect_vnd <> 0
     or l_task.assigned_at is null or l_task.accepted_at is not null
     or l_task.started_at is not null or l_task.completed_at is not null
     or l_task.failure_reason is not null or l_plan = '[]'::jsonb
     or l_items is distinct from l_plan
     or exists (select 1 from private.redelivery_acceptances a where a.task_id = p_task_id)
     or exists (select 1 from private.redelivery_custody c where c.task_id = p_task_id)
  then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;
  l_now := pg_catalog.clock_timestamp();
  update public.delivery_tasks
  set status = 'accepted'::public.delivery_task_status,
      accepted_at = l_now, updated_at = l_now
  where id = p_task_id;
  l_event := pg_catalog.gen_random_uuid();
  insert into public.business_events (
    id, actor_id, subject_type, subject_id, from_state, to_state,
    reason, task_id, request_id, created_at
  ) values (
    l_event, l_actor, 'delivery_task', p_task_id,
    'assigned', 'accepted', 'redelivery_accepted', p_task_id, l_event, l_now
  );
  l_response := pg_catalog.jsonb_build_object(
    'operation', 'accept_redelivery_task', 'task_id', p_task_id,
    'order_id', l_order_id, 'return_request_id', l_return_id,
    'kind', 'redelivery', 'task_status', 'accepted',
    'return_status', 'awaiting_redelivery', 'accepted_at', l_now,
    'started_at', null, 'amount_to_collect_vnd', 0,
    'event_id', l_event, 'occurred_at', l_now, 'request_id', p_request_id
  );
  insert into private.redelivery_acceptances (
    task_id, return_request_id, order_id, shipper_id, request_id,
    event_id, items, accepted_at, response
  ) values (
    p_task_id, l_return_id, l_order_id, l_actor, p_request_id,
    l_event, l_items, l_now, l_response
  );
  -- Acceptance is the physical receipt: custody is immutable from this point.
  insert into private.redelivery_custody (
    task_id, return_request_id, order_id, shipper_id,
    accepted_at, started_at, event_id, items, response
  ) values (
    p_task_id, l_return_id, l_order_id, l_actor,
    l_now, null, l_event, l_items, l_response
  );
  insert into private.redelivery_requests (
    actor_id, request_id, operation, order_id, return_request_id, task_id,
    shipper_id, payload, payload_hash, response, created_at
  ) values (
    l_actor, p_request_id, 'accept_redelivery_task', l_order_id, l_return_id,
    p_task_id, l_actor, l_payload, l_hash, l_response, l_now
  );
  return l_response;
end;
$$;
alter function public.accept_redelivery_task(uuid, uuid, jsonb)
  owner to sports_store_return_pickup_writer;

create function public.start_redelivery_task(
  p_task_id uuid,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  l_actor uuid := (select private.delivery_request_user_id());
  l_role text;
  l_order_id uuid;
  l_return_id uuid;
  l_order_status public.order_status;
  l_return_status public.return_request_status;
  l_task public.delivery_tasks%rowtype;
  l_accept private.redelivery_acceptances%rowtype;
  l_custody private.redelivery_custody%rowtype;
  l_existing private.redelivery_requests%rowtype;
  l_plan jsonb;
  l_payload jsonb;
  l_hash text;
  l_event uuid;
  l_now timestamptz;
  l_response jsonb;
begin
  if l_actor is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if p_task_id is null or p_request_id is null then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.redelivery:request:' || l_actor::text || ':'
      || p_request_id::text, 0));
  select t.order_id, t.return_request_id into l_order_id, l_return_id
  from public.delivery_tasks t
  where t.id = p_task_id and t.kind = 'redelivery'::public.delivery_task_kind
    and t.assigned_shipper_id = l_actor;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.complete_outbound_delivery:order:' || l_order_id::text, 0));
  select status into l_order_status from public.orders
  where id = l_order_id for update;
  select status into l_return_status from public.return_requests
  where id = l_return_id and order_id = l_order_id for update;
  select t.* into l_task from public.delivery_tasks t
  where t.id = p_task_id for update;
  perform 1 from public.delivery_tasks t
  where t.return_request_id = l_return_id order by t.id for update;
  select role::text into l_role from public.profiles where id = l_actor for share;
  if l_role is distinct from 'shipper' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;
  select a.* into l_accept from private.redelivery_acceptances a
  where a.task_id = p_task_id;
  select c.* into l_custody from private.redelivery_custody c
  where c.task_id = p_task_id;
  l_plan := private.redelivery_plan_json(p_task_id);
  l_payload := jsonb_build_object(
    'operation', 'start_redelivery_task', 'task_id', p_task_id,
    'request_id', p_request_id
  );
  l_hash := md5(l_payload::text);
  select r.* into l_existing from private.redelivery_requests r
  where r.actor_id = l_actor and r.request_id = p_request_id ;
  if found then
    if l_existing.operation <> 'start_redelivery_task'
       or l_existing.task_id is distinct from p_task_id
       or l_existing.return_request_id is distinct from l_return_id
       or l_existing.payload_hash <> l_hash
       or l_existing.payload is distinct from l_payload then
      raise exception using errcode = 'PT409', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return l_existing.response;
  end if;
  if l_order_status is distinct from 'delivered'::public.order_status
     or l_return_status is distinct from 'awaiting_redelivery'::public.return_request_status
     or l_task.assigned_shipper_id is distinct from l_actor
     or l_task.status is distinct from 'accepted'::public.delivery_task_status
     or l_task.accepted_at is null or l_task.started_at is not null
     or l_task.completed_at is not null or l_task.amount_to_collect_vnd <> 0
     or l_accept.task_id is null or l_accept.shipper_id is distinct from l_actor
     or l_accept.accepted_at is distinct from l_task.accepted_at
     or l_accept.items is distinct from l_plan
     or l_custody.task_id is null or l_custody.started_at is not null
     or l_custody.accepted_at is distinct from l_task.accepted_at
     or l_custody.items is distinct from l_plan then
    raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
  end if;
  l_now := pg_catalog.clock_timestamp();
  update public.delivery_tasks
  set status = 'in_transit'::public.delivery_task_status,
      started_at = l_now, updated_at = l_now
  where id = p_task_id;
  l_event := pg_catalog.gen_random_uuid();
  insert into public.business_events (
    id, actor_id, subject_type, subject_id, from_state, to_state,
    reason, task_id, request_id, created_at
  ) values (
    l_event, l_actor, 'delivery_task', p_task_id,
    'accepted', 'in_transit', 'redelivery_started', p_task_id, l_event, l_now
  );
  l_response := pg_catalog.jsonb_build_object(
    'operation', 'start_redelivery_task', 'task_id', p_task_id,
    'order_id', l_order_id, 'return_request_id', l_return_id,
    'kind', 'redelivery', 'task_status', 'in_transit',
    'return_status', 'awaiting_redelivery', 'accepted_at', l_task.accepted_at,
    'started_at', l_now, 'amount_to_collect_vnd', 0,
    'event_id', l_event, 'occurred_at', l_now, 'request_id', p_request_id
  );
  insert into private.redelivery_starts (
    task_id, return_request_id, order_id, shipper_id, accepted_at,
    started_at, event_id, response
  ) values (
    p_task_id, l_return_id, l_order_id, l_actor, l_task.accepted_at,
    l_now, l_event, l_response
  );
  insert into private.redelivery_requests (
    actor_id, request_id, operation, order_id, return_request_id, task_id,
    shipper_id, payload, payload_hash, response, created_at
  ) values (
    l_actor, p_request_id, 'start_redelivery_task', l_order_id, l_return_id,
    p_task_id, l_actor, l_payload, l_hash, l_response, l_now
  );
  return l_response;
end;
$$;
alter function public.start_redelivery_task(uuid, uuid)
  owner to sports_store_return_pickup_writer;

-- A shared internal outcome writer serializes opposing results on the order.
create function private.finish_redelivery(
  p_task_id uuid, p_request_id uuid, p_success boolean,
  p_received_all_items boolean, p_reason_code text, p_description text
) returns jsonb language plpgsql security invoker set search_path = '' as $$
#variable_conflict use_column
declare
  a uuid := private.delivery_request_user_id();
  t public.delivery_tasks%rowtype;
  r public.return_requests%rowtype;
  c private.redelivery_custody%rowtype;
  s private.redelivery_starts%rowtype;
  prior private.redelivery_requests%rowtype;
  oid uuid; rid uuid; os public.order_status; role_name text;
  payload jsonb; plan jsonb; result jsonb; ev uuid; ts timestamptz;
  op text; reason text := nullif(btrim(p_description),''); recipient uuid;
begin
  if a is null then raise exception using errcode='42501',message='AUTH_REQUIRED'; end if;
  if p_task_id is null or p_request_id is null or p_success is null then
    raise exception using errcode='22023',message='INVALID_ARGUMENT'; end if;
  if p_success then
    if p_received_all_items is distinct from true then
      raise exception using errcode='22023',message='ITEMS_MISMATCH'; end if;
    op := 'complete_redelivery';
  else
    if p_reason_code is null or p_reason_code not in
      ('unreachable','reschedule','bad_address','refusal','other')
      or (p_reason_code='other' and reason is null) or length(reason)>2000 then
      raise exception using errcode='22023',message='INVALID_ARGUMENT'; end if;
    op := 'fail_redelivery_task';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'sports_store.redelivery:request:'||a::text||':'||p_request_id::text,0));
  select order_id,return_request_id into oid,rid from public.delivery_tasks
    where id=p_task_id and kind='redelivery' and assigned_shipper_id=a;
  if not found then raise exception using errcode='42501',message='NOT_FOUND_OR_FORBIDDEN'; end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'sports_store.complete_outbound_delivery:order:'||oid::text,0));
  select status into os from public.orders where id=oid for update;
  select (jsonb_populate_record(null::public.return_requests,jsonb_build_object('id',r.id,'order_id',r.order_id,'customer_id',r.customer_id,'request_id',r.request_id,'status',r.status,'decided_by',r.decided_by,'decision_at',r.decision_at,'inspection_started_at',r.inspection_started_at,'inspected_at',r.inspected_at,'inspected_by',r.inspected_by,'closed_at',r.closed_at))).* into r from public.return_requests r where r.id=rid and r.order_id=oid for update;
  perform 1 from public.delivery_tasks where return_request_id=rid order by id for update;
  select * into t from public.delivery_tasks where id=p_task_id;
  select role::text into role_name from public.profiles where id=a for share;
  if role_name is distinct from 'shipper' or t.assigned_shipper_id is distinct from a then
    raise exception using errcode='42501',message='PERMISSION_DENIED'; end if;
  select * into c from private.redelivery_custody where task_id=p_task_id;
  select * into s from private.redelivery_starts where task_id=p_task_id;
  plan := private.redelivery_plan_json(p_task_id);
  if c.task_id is null or s.task_id is null or c.shipper_id is distinct from a
    or s.shipper_id is distinct from a or c.order_id is distinct from oid
    or c.return_request_id is distinct from rid or c.accepted_at is distinct from t.accepted_at
    or s.accepted_at is distinct from t.accepted_at or s.started_at is distinct from t.started_at
    or c.items is distinct from plan or jsonb_array_length(plan)=0 then
    raise exception using errcode='PT409',message='CUSTODY_UNRESOLVED'; end if;
  payload := jsonb_build_object('operation',op,'task_id',p_task_id,
    'received_all_items',case when p_success then true else null end,
    'reason_code',case when p_success then null else p_reason_code end,
    'description',case when p_success then null else reason end);
  select * into prior from private.redelivery_requests
    where actor_id=a and request_id=p_request_id ;
  if found then
    if prior.operation<>op or prior.task_id is distinct from p_task_id
      or prior.payload is distinct from payload then
      raise exception using errcode='PT409',message='IDEMPOTENCY_CONFLICT'; end if;
    return prior.response;
  end if;
  if os is distinct from 'delivered' or r.status is distinct from 'awaiting_redelivery'
    or r.closed_at is not null or t.status is distinct from 'in_transit'
    or t.completed_at is not null or t.attempt_number<>1 or t.amount_to_collect_vnd<>0
    or exists(select 1 from private.redelivery_outcomes where task_id=p_task_id) then
    raise exception using errcode='PT409',message='STATE_CONFLICT'; end if;
  ts:=clock_timestamp(); ev:=gen_random_uuid();
  update public.delivery_tasks set status=case when p_success then 'delivered'::public.delivery_task_status
      else 'manager_action_required'::public.delivery_task_status end,
    completed_at=case when p_success then ts else null end,
    failure_reason=case when p_success then null else p_reason_code||coalesce(': '||reason,'') end,
    updated_at=ts where id=p_task_id;
  update public.return_requests set status=case when p_success then 'rejected_after_inspection'::public.return_request_status
      else 'manager_action_required'::public.return_request_status end,
    closed_at=case when p_success then ts else null end,updated_at=ts where id=rid;
  insert into public.business_events(id,actor_id,subject_type,subject_id,from_state,to_state,reason,task_id,request_id,created_at)
    values(ev,a,'delivery_task',p_task_id,'in_transit',case when p_success then 'delivered' else 'manager_action_required' end,
      case when p_success then 'redelivery_completed' else 'redelivery_failed' end,p_task_id,ev,ts);
  for recipient in select id from public.profiles where role='manager'
    union select customer_id from public.orders where id=oid loop
    insert into public.notifications(id,recipient_id,event_id,subject_type,subject_id,title,body,created_at)
      values(gen_random_uuid(),recipient,ev,'delivery_task',p_task_id,
        case when p_success then 'Giao lại đã hoàn tất' else 'Giao lại cần cửa hàng xử lý' end,
        case when p_success then 'Nhiệm vụ giao lại đã hoàn tất.' else 'Nhiệm vụ giao lại cần được cửa hàng xử lý.' end,ts);
  end loop;
  result:=jsonb_build_object('task_id',p_task_id,'order_id',oid,'return_request_id',rid,
    'operation',op,'task_status',case when p_success then 'delivered' else 'manager_action_required' end,
    'return_status',case when p_success then 'rejected_after_inspection' else 'manager_action_required' end,
    'event_id',ev,'request_id',p_request_id,'occurred_at',ts);
  if p_success then result:=result||jsonb_build_object('completed_at',ts,'closed_at',ts);
  else result:=result||jsonb_build_object('reason_code',p_reason_code,'description',reason,'failed_at',ts,'custody_open',true); end if;
  insert into private.redelivery_outcomes(task_id,return_request_id,order_id,shipper_id,outcome,
    request_id,event_id,reason_code,description,occurred_at,response)
    values(p_task_id,rid,oid,a,case when p_success then 'completed' else 'failed' end,p_request_id,ev,
      case when p_success then null else p_reason_code end,case when p_success then null else reason end,ts,result);
  insert into private.redelivery_requests(actor_id,request_id,operation,order_id,return_request_id,task_id,
    shipper_id,payload,payload_hash,response,created_at)
    values(a,p_request_id,op,oid,rid,p_task_id,a,payload,md5(payload::text),result,ts);
  return result;
end; $$;
alter function private.finish_redelivery(uuid,uuid,boolean,boolean,text,text) owner to sports_store_return_pickup_writer;
revoke all on function private.finish_redelivery(uuid,uuid,boolean,boolean,text,text) from public,anon,authenticated,service_role;

create function public.complete_redelivery(p_task_id uuid,p_request_id uuid,p_received_all_items boolean)
returns jsonb language sql security definer set search_path='' as $$
  select private.finish_redelivery(p_task_id,p_request_id,true,p_received_all_items,null,null);
$$;
alter function public.complete_redelivery(uuid,uuid,boolean) owner to sports_store_return_pickup_writer;
create function public.fail_redelivery_task(p_task_id uuid,p_request_id uuid,p_reason_code text,p_description text default null)
returns jsonb language sql security definer set search_path='' as $$
  select private.finish_redelivery(p_task_id,p_request_id,false,null,p_reason_code,p_description);
$$;
alter function public.fail_redelivery_task(uuid,uuid,text,text) owner to sports_store_return_pickup_writer;

-- Success is terminal only after redelivery, never at inspection rejection.
drop policy redelivery_writer_returns_update on public.return_requests;
create policy redelivery_writer_returns_update on public.return_requests for update
to sports_store_return_pickup_writer using (
  current_user='sports_store_return_pickup_writer' and (
    private.current_app_role()='manager' or exists(select 1 from public.delivery_tasks t
      where t.return_request_id=return_requests.id and t.kind='redelivery'
        and t.assigned_shipper_id=private.delivery_request_user_id())))
with check (current_user='sports_store_return_pickup_writer' and (
  (private.current_app_role()='manager' and status in ('awaiting_return_pickup','under_inspection','awaiting_redelivery'))
  or (private.current_app_role()='shipper' and status in ('manager_action_required','rejected_after_inspection'))));

do $$ declare signature text; begin
  foreach signature in array array[
    'approve_return_pickup_plan(uuid,uuid,jsonb)',
    'receive_customer_return(uuid,uuid,jsonb)',
    'reject_return_after_inspection(uuid,uuid,text)',
    'assign_redelivery_task(uuid,uuid,uuid)',
    'accept_redelivery_task(uuid,uuid,jsonb)',
    'start_redelivery_task(uuid,uuid)',
    'complete_redelivery(uuid,uuid,boolean)',
    'fail_redelivery_task(uuid,uuid,text,text)'
  ] loop
    execute 'revoke all on function public.'||signature||' from public,anon,authenticated,service_role';
    execute 'grant execute on function public.'||signature||' to authenticated';
  end loop;
end; $$;
revoke create on schema public,private from sports_store_return_pickup_writer;
notify pgrst,'reload schema';

-- Only the existing task-authorized reader can see immutable redelivery items.
grant select(task_id,return_request_id,order_id,return_item_id,actual_item_name,
  variant_label,attributes,quantity) on private.redelivery_task_items to sports_store_delivery_reader;
do $$ declare def text; begin
  def:=pg_get_functiondef('public.read_my_delivery_tasks(uuid)'::regprocedure);
  if position('unavailable_redelivery_plan' in def)=0 then
    raise exception 'Unexpected delivery read definition'; end if;
  def:=replace(def, 'else ''unavailable_redelivery_plan''',
    'when t.kind = ''redelivery'' and exists(select 1 from private.redelivery_task_items rs where rs.task_id=t.id) then ''return_plan'' else ''unavailable_redelivery_plan''');
  execute def;
  def:=pg_get_functiondef('public.read_my_delivery_task_items(uuid)'::regprocedure);
  if position('order by 1;' in def)=0 then raise exception 'Unexpected item projection'; end if;
  def:=replace(def,'order by 1;',
    'union all select s.return_item_id, ''return_plan''::text, s.actual_item_name,
      s.variant_label,s.attributes,s.quantity,s.quantity,null::bigint,null::bigint
      from current_tasks t join private.redelivery_task_items s on s.task_id=t.id
      and s.order_id=t.order_id and s.return_request_id=t.return_request_id
      where t.kind=''redelivery'' order by 1;');
  execute def;
end; $$;
notify pgrst,'reload schema';

grant select(updated_at) on public.delivery_tasks to sports_store_return_pickup_writer;
create policy redelivery_manager_pickup_receipt on public.delivery_tasks for update
to sports_store_return_pickup_writer
using (current_user='sports_store_return_pickup_writer'
  and private.current_app_role()='manager' and kind='return_pickup'
  and status='in_transit' and exists(select 1 from private.return_pickup_handover_reports h
    where h.task_id=delivery_tasks.id and h.order_id=delivery_tasks.order_id))
with check (current_user='sports_store_return_pickup_writer'
  and private.current_app_role()='manager' and kind='return_pickup'
  and status='returned_to_store' and completed_at is not null
  and exists(select 1 from private.return_pickup_handover_reports h where h.task_id=delivery_tasks.id));
