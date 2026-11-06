-- P04.1 production outbound acceptance/start contract.
-- This migration deliberately excludes completion, failure, retry decisions,
-- cancellation RPCs, notifications, and task creation.

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'sports_store_outbound_writer') then
    create role sports_store_outbound_writer nologin noinherit nobypassrls;
    comment on role sports_store_outbound_writer is
      'sports_store P04.1 outbound accept/start writer; no-login, no-inherit, no-bypass-RLS';
  elsif not exists (
    select 1 from pg_roles r
    where r.rolname = 'sports_store_outbound_writer'
      and not r.rolcanlogin and not r.rolsuper and not r.rolbypassrls
      and not r.rolinherit and not r.rolcreaterole and not r.rolcreatedb
      and not r.rolreplication
      and shobj_description(r.oid, 'pg_authid') =
        'sports_store P04.1 outbound accept/start writer; no-login, no-inherit, no-bypass-RLS'
  ) then
    raise exception 'P04.1 outbound writer role already exists with unexpected configuration';
  end if;
end;
$$;

do $$
begin
  if exists (
    select 1 from pg_auth_members m
    join pg_roles granted on granted.oid = m.roleid
    join pg_roles member on member.oid = m.member
    where granted.rolname = 'sports_store_outbound_writer'
      and member.rolname <> 'postgres'
  ) then
    raise exception 'P04.1 outbound writer role has an unexpected membership';
  end if;
end;
$$;

grant sports_store_outbound_writer to postgres;
grant usage on schema public, auth, private to sports_store_outbound_writer;
grant execute on function auth.uid() to sports_store_outbound_writer;
grant execute on function private.current_app_role() to sports_store_outbound_writer;
grant create on schema public, private to sports_store_outbound_writer;

create table private.outbound_command_requests (
  actor_id uuid not null references public.profiles (id),
  request_id uuid not null,
  operation text not null,
  task_id uuid not null references public.delivery_tasks (id),
  order_id uuid not null references public.orders (id),
  payload_hash text not null,
  response jsonb not null,
  created_at timestamptz not null default statement_timestamp(),
  primary key (actor_id, request_id),
  constraint outbound_command_requests_operation_valid check (operation in ('accept', 'start')),
  constraint outbound_command_requests_hash_nonblank check (btrim(payload_hash) <> ''),
  constraint outbound_command_requests_response_object check (jsonb_typeof(response) = 'object')
);

create table private.outbound_dispatches (
  order_id uuid primary key references public.orders (id),
  initial_task_id uuid not null references public.delivery_tasks (id),
  holder_id uuid not null references public.profiles (id),
  event_id uuid not null unique references public.business_events (id),
  items_snapshot jsonb not null,
  dispatched_at timestamptz not null,
  constraint outbound_dispatches_initial_task_unique unique (initial_task_id),
  constraint outbound_dispatches_items_snapshot_valid check (
    jsonb_typeof(items_snapshot) = 'array' and jsonb_array_length(items_snapshot) > 0
  )
);

create table private.outbound_custody_acceptances (
  task_id uuid primary key references public.delivery_tasks (id),
  order_id uuid not null references public.orders (id),
  holder_id uuid not null references public.profiles (id),
  dispatch_event_id uuid not null references private.outbound_dispatches (event_id),
  accepted_at timestamptz not null,
  attempt_number smallint not null,
  constraint outbound_custody_order_attempt_unique unique (order_id, attempt_number),
  constraint outbound_custody_acceptances_attempt_valid check (attempt_number between 1 and 2)
);

alter table private.outbound_command_requests enable row level security;
alter table private.outbound_command_requests force row level security;
alter table private.outbound_dispatches enable row level security;
alter table private.outbound_dispatches force row level security;
alter table private.outbound_custody_acceptances enable row level security;
alter table private.outbound_custody_acceptances force row level security;

create policy outbound_command_requests_writer_read on private.outbound_command_requests
  for select to sports_store_outbound_writer
  using (current_user = 'sports_store_outbound_writer');
create policy outbound_command_requests_writer_insert on private.outbound_command_requests
  for insert to sports_store_outbound_writer
  with check (current_user = 'sports_store_outbound_writer');
create policy outbound_dispatches_writer_read on private.outbound_dispatches
  for select to sports_store_outbound_writer
  using (current_user = 'sports_store_outbound_writer');
create policy outbound_dispatches_writer_insert on private.outbound_dispatches
  for insert to sports_store_outbound_writer
  with check (current_user = 'sports_store_outbound_writer');
create policy outbound_custody_writer_read on private.outbound_custody_acceptances
  for select to sports_store_outbound_writer
  using (current_user = 'sports_store_outbound_writer');
create policy outbound_custody_writer_insert on private.outbound_custody_acceptances
  for insert to sports_store_outbound_writer
  with check (current_user = 'sports_store_outbound_writer');

revoke all on private.outbound_command_requests,
  private.outbound_dispatches,
  private.outbound_custody_acceptances
  from public, anon, authenticated, service_role;
grant select, insert on private.outbound_command_requests
  to sports_store_outbound_writer;
grant select, insert on private.outbound_dispatches
  to sports_store_outbound_writer;
grant select, insert on private.outbound_custody_acceptances
  to sports_store_outbound_writer;

create or replace function private.reject_outbound_ledger_mutation()
returns trigger language plpgsql security invoker set search_path = ''
as $$
begin
  raise exception 'P04.1 outbound ledgers are append-only' using errcode = '55000';
end;
$$;
revoke all on function private.reject_outbound_ledger_mutation()
  from public, anon, authenticated, service_role;
create trigger outbound_command_requests_append_only
before update or delete on private.outbound_command_requests
for each row execute function private.reject_outbound_ledger_mutation();
create trigger outbound_dispatches_append_only
before update or delete on private.outbound_dispatches
for each row execute function private.reject_outbound_ledger_mutation();
create trigger outbound_custody_append_only
before update or delete on private.outbound_custody_acceptances
for each row execute function private.reject_outbound_ledger_mutation();

-- Column grants are intentionally narrow. Lock-only UPDATE grants are paired
-- with false WITH CHECK policies below.
grant select (id, role) on public.profiles to sports_store_outbound_writer;
grant update (id) on public.profiles to sports_store_outbound_writer;
grant select (id, status, total_cod_vnd, delivery_attempt_count) on public.orders
  to sports_store_outbound_writer;
grant update (status, delivery_attempt_count, updated_at) on public.orders
  to sports_store_outbound_writer;
grant select (
  id, order_id, kind, assigned_shipper_id, status, attempt_number,
  amount_to_collect_vnd, assigned_at, accepted_at, started_at, completed_at,
  failure_reason, cancel_reason
) on public.delivery_tasks to sports_store_outbound_writer;
grant update (status, accepted_at, started_at, updated_at) on public.delivery_tasks
  to sports_store_outbound_writer;
grant select (
  id, order_id, variant_id, product_name, variant_label, attributes,
  unit_price_vnd, quantity, line_total_vnd
) on public.order_items to sports_store_outbound_writer;
grant update (id) on public.order_items to sports_store_outbound_writer;
grant select (id, on_hand, reserved, damaged) on public.product_variants
  to sports_store_outbound_writer;
grant update (on_hand, reserved, updated_at) on public.product_variants
  to sports_store_outbound_writer;
grant select (
  order_id, shipper_id, status, expected_amount_vnd, collected_amount_vnd,
  received_amount_vnd, collected_at, collected_by, handed_over_at,
  received_at, received_by
) on public.cod_collections to sports_store_outbound_writer;
grant update (order_id) on public.cod_collections to sports_store_outbound_writer;
grant select (
  id, task_id, order_id, attempt_number, task_kind, result, shipper_id,
  occurred_at, reason
) on public.delivery_attempts to sports_store_outbound_writer;
grant select (
  id, variant_id, order_id, return_request_id, event_id, kind,
  on_hand_delta, reserved_delta, damaged_delta, actor_id, reason, created_at
) on public.inventory_movements to sports_store_outbound_writer;
grant insert (
  variant_id, order_id, event_id, kind, on_hand_delta, reserved_delta,
  damaged_delta, actor_id, reason, created_at
) on public.inventory_movements to sports_store_outbound_writer;
grant insert (
  id, actor_id, subject_type, subject_id, from_state, to_state, reason,
  task_id, request_id, created_at
) on public.business_events to sports_store_outbound_writer;
grant select (id, subject_type, subject_id, task_id, incident_kind)
  on public.business_events to sports_store_outbound_writer;

create policy outbound_writer_profiles_read on public.profiles
  for select to sports_store_outbound_writer
  using (id = (select auth.uid()));
create policy outbound_writer_profiles_lock on public.profiles
  for update to sports_store_outbound_writer
  using (id = (select auth.uid())) with check (false);

create policy outbound_writer_orders_read on public.orders
  for select to sports_store_outbound_writer
  using (
    (select private.current_app_role()) = 'shipper'
    and exists (
      select 1 from public.delivery_tasks t
      where t.order_id = orders.id and t.kind = 'outbound'::public.delivery_task_kind
        and t.assigned_shipper_id = (select auth.uid())
    )
  );
create policy outbound_writer_orders_update on public.orders
  for update to sports_store_outbound_writer
  using (
    (select private.current_app_role()) = 'shipper'
    and exists (
      select 1 from public.delivery_tasks t
      where t.order_id = orders.id and t.kind = 'outbound'::public.delivery_task_kind
        and t.assigned_shipper_id = (select auth.uid())
    )
  )
  with check (
    (select private.current_app_role()) = 'shipper'
    and exists (
      select 1 from public.delivery_tasks t
      where t.order_id = orders.id and t.kind = 'outbound'::public.delivery_task_kind
        and t.assigned_shipper_id = (select auth.uid())
    )
  );

create policy outbound_writer_tasks_read on public.delivery_tasks
  for select to sports_store_outbound_writer
  using (
    (select private.current_app_role()) = 'shipper'
    and kind = 'outbound'::public.delivery_task_kind
    and (
      assigned_shipper_id = (select auth.uid())
      or exists (
        select 1 from private.outbound_dispatches d
        where d.order_id = delivery_tasks.order_id and d.holder_id = (select auth.uid())
      )
    )
  );
create policy outbound_writer_tasks_update on public.delivery_tasks
  for update to sports_store_outbound_writer
  using (
    (select private.current_app_role()) = 'shipper'
    and kind = 'outbound'::public.delivery_task_kind
    and assigned_shipper_id = (select auth.uid())
  )
  with check (
    (select private.current_app_role()) = 'shipper'
    and kind = 'outbound'::public.delivery_task_kind
    and assigned_shipper_id = (select auth.uid())
  );

-- Trigger guards run as the writer even when a manager-owned cancellation
-- statement fired them. This read policy is internal-only and lets the guard
-- fail closed for legacy accepted/started rows without a custody proof.
create policy outbound_writer_tasks_guard_read on public.delivery_tasks
  for select to sports_store_outbound_writer
  using (current_user = 'sports_store_outbound_writer'
         and kind = 'outbound'::public.delivery_task_kind);
create policy outbound_writer_tasks_lock on public.delivery_tasks
  for update to sports_store_outbound_writer
  using (current_user = 'sports_store_outbound_writer'
         and kind = 'outbound'::public.delivery_task_kind)
  with check (false);

create policy outbound_writer_order_items_read on public.order_items
  for select to sports_store_outbound_writer
  using (
    (select private.current_app_role()) = 'shipper'
    and exists (
      select 1 from public.delivery_tasks t
      where t.order_id = order_items.order_id and t.kind = 'outbound'::public.delivery_task_kind
        and t.assigned_shipper_id = (select auth.uid())
    )
  );
create policy outbound_writer_order_items_lock on public.order_items
  for update to sports_store_outbound_writer
  using (
    (select private.current_app_role()) = 'shipper'
    and exists (
      select 1 from public.delivery_tasks t
      where t.order_id = order_items.order_id
        and t.kind = 'outbound'::public.delivery_task_kind
        and t.assigned_shipper_id = (select auth.uid())
    )
  )
  with check (false);

create policy outbound_writer_variants_read on public.product_variants
  for select to sports_store_outbound_writer
  using (
    (select private.current_app_role()) = 'shipper'
    and exists (
      select 1 from public.order_items oi
      join public.delivery_tasks t on t.order_id = oi.order_id
      where oi.variant_id = product_variants.id
        and t.kind = 'outbound'::public.delivery_task_kind
        and t.assigned_shipper_id = (select auth.uid())
    )
  );
create policy outbound_writer_variants_update on public.product_variants
  for update to sports_store_outbound_writer
  using (
    (select private.current_app_role()) = 'shipper'
    and exists (
      select 1 from public.order_items oi
      join public.delivery_tasks t on t.order_id = oi.order_id
      where oi.variant_id = product_variants.id
        and t.kind = 'outbound'::public.delivery_task_kind
        and t.assigned_shipper_id = (select auth.uid())
    )
  )
  with check (
    (select private.current_app_role()) = 'shipper'
    and exists (
      select 1 from public.order_items oi
      join public.delivery_tasks t on t.order_id = oi.order_id
      where oi.variant_id = product_variants.id
        and t.kind = 'outbound'::public.delivery_task_kind
        and t.assigned_shipper_id = (select auth.uid())
    )
  );

create policy outbound_writer_cod_read on public.cod_collections
  for select to sports_store_outbound_writer
  using ((select private.current_app_role()) = 'shipper' and shipper_id = (select auth.uid()));
create policy outbound_writer_cod_lock on public.cod_collections
  for update to sports_store_outbound_writer
  using ((select private.current_app_role()) = 'shipper' and shipper_id = (select auth.uid()))
  with check (false);

create policy outbound_writer_attempts_read on public.delivery_attempts
  for select to sports_store_outbound_writer
  using ((select private.current_app_role()) = 'shipper' and shipper_id = (select auth.uid()));
create policy outbound_writer_attempts_guard_read on public.delivery_attempts
  for select to sports_store_outbound_writer
  using (current_user = 'sports_store_outbound_writer');

create policy outbound_writer_movements_read on public.inventory_movements
  for select to sports_store_outbound_writer
  using (
    (select private.current_app_role()) = 'shipper'
    and exists (
      select 1 from public.delivery_tasks t
      where t.order_id = inventory_movements.order_id
        and t.kind = 'outbound'::public.delivery_task_kind
        and t.assigned_shipper_id = (select auth.uid())
    )
  );
create policy outbound_writer_movements_insert on public.inventory_movements
  for insert to sports_store_outbound_writer
  with check (
    (select private.current_app_role()) = 'shipper'
    and kind = 'dispatch'::public.inventory_movement_kind
    and order_id is not null and return_request_id is null
    and actor_id = (select auth.uid())
    and on_hand_delta < 0 and reserved_delta < 0 and damaged_delta = 0
    and exists (
      select 1 from public.delivery_tasks t
      where t.order_id = inventory_movements.order_id
        and t.kind = 'outbound'::public.delivery_task_kind
        and t.assigned_shipper_id = (select auth.uid())
    )
  );

create policy outbound_writer_business_events_insert on public.business_events
  for insert to sports_store_outbound_writer
  with check (
    (select private.current_app_role()) = 'shipper'
    and actor_id = (select auth.uid()) and request_id = id
    and (
      (subject_type = 'order' and task_id is null)
      or (subject_type = 'delivery_task' and task_id = subject_id)
    )
  );
create policy outbound_writer_business_events_read on public.business_events
  for select to sports_store_outbound_writer
  using (
    current_user = 'sports_store_outbound_writer'
    and incident_kind in (
      'damaged'::public.delivery_incident_kind,
      'lost'::public.delivery_incident_kind
    )
  );
-- P04.1 trigger and proof helpers.

create or replace function private.guard_outbound_order_cancellation()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if old.status is distinct from new.status
     and new.status = 'cancelled'::public.order_status
     and (
       exists (select 1 from private.outbound_dispatches d where d.order_id = old.id)
       or exists (
         select 1 from private.outbound_custody_acceptances c where c.order_id = old.id
       )
       or exists (
         select 1 from public.delivery_tasks t
         where t.order_id = old.id
           and t.kind = 'outbound'::public.delivery_task_kind
           and (t.accepted_at is not null or t.started_at is not null)
       )
     ) then
    raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
  end if;
  return new;
end;
$$;
alter function private.guard_outbound_order_cancellation() owner to sports_store_outbound_writer;
revoke all on function private.guard_outbound_order_cancellation()
  from public, anon, authenticated, service_role;
create trigger orders_block_cancel_after_outbound_dispatch
before update of status on public.orders
for each row execute function private.guard_outbound_order_cancellation();

create or replace function private.guard_outbound_task_custody()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if old.kind = 'outbound'::public.delivery_task_kind
     and (
       old.accepted_at is not null
       or exists (select 1 from private.outbound_custody_acceptances c where c.task_id = old.id)
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
    raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
  end if;
  return new;
end;
$$;
alter function private.guard_outbound_task_custody() owner to sports_store_outbound_writer;
revoke all on function private.guard_outbound_task_custody()
  from public, anon, authenticated, service_role;
create trigger delivery_tasks_block_post_accept_mutation
before update of assigned_shipper_id, assigned_by, assigned_at, status
on public.delivery_tasks
for each row execute function private.guard_outbound_task_custody();

create or replace function private.outbound_items_snapshot(p_order_id uuid)
returns jsonb language sql security invoker set search_path = ''
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'order_item_id', oi.id,
        'variant_id', oi.variant_id,
        'product_name', oi.product_name,
        'variant_label', oi.variant_label,
        'attributes', oi.attributes,
        'unit_price_vnd', oi.unit_price_vnd,
        'quantity', oi.quantity,
        'line_total_vnd', oi.line_total_vnd
      ) order by oi.variant_id, oi.id
    ), '[]'::jsonb
  )
  from public.order_items oi where oi.order_id = p_order_id;
$$;
alter function private.outbound_items_snapshot(uuid) owner to sports_store_outbound_writer;
revoke all on function private.outbound_items_snapshot(uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.outbound_items_snapshot(uuid) to sports_store_outbound_writer;

create or replace function private.validate_outbound_reservation(
  p_order_id uuid, p_items_snapshot jsonb
)
returns void language plpgsql security invoker set search_path = ''
as $$
declare
  l_item record;
  l_snapshot jsonb;
  l_item_count bigint;
  l_variant_count bigint;
  l_movement_count bigint;
  l_reserved_sum bigint;
begin
  if p_order_id is null
     or jsonb_typeof(p_items_snapshot) <> 'array'
     or jsonb_array_length(p_items_snapshot) = 0 then
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
    from public.business_events e
    where e.incident_kind in (
      'damaged'::public.delivery_incident_kind,
      'lost'::public.delivery_incident_kind
    )
      and (
        (e.subject_type = 'order' and e.subject_id = p_order_id)
        or exists (
          select 1 from public.delivery_tasks t
          where t.id = e.task_id and t.order_id = p_order_id
        )
      )
  ) then
    raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
  end if;
  if exists (
    select 1 from public.inventory_movements m
    where m.order_id = p_order_id
      and (
        m.variant_id is null
        or m.variant_id not in (
          select oi.variant_id from public.order_items oi where oi.order_id = p_order_id
        )
        or m.kind not in (
          'reserve'::public.inventory_movement_kind,
          'release'::public.inventory_movement_kind
        )
        or m.return_request_id is not null
        or m.on_hand_delta <> 0
        or m.damaged_delta <> 0
        or (m.kind = 'reserve'::public.inventory_movement_kind and m.reserved_delta <= 0)
        or (m.kind = 'release'::public.inventory_movement_kind and m.reserved_delta >= 0)
      )
  ) then
    raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
  end if;
  for l_item in
    select oi.variant_id, oi.quantity
    from public.order_items oi where oi.order_id = p_order_id order by oi.variant_id
  loop
    select count(*), coalesce(sum(m.reserved_delta), 0)
      into l_movement_count, l_reserved_sum
    from public.inventory_movements m
    where m.order_id = p_order_id and m.variant_id = l_item.variant_id
      and m.kind in (
        'reserve'::public.inventory_movement_kind,
        'release'::public.inventory_movement_kind
      );
    if l_movement_count = 0 or l_reserved_sum <> l_item.quantity then
      raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
    end if;
  end loop;
end;
$$;
alter function private.validate_outbound_reservation(uuid, jsonb)
  owner to sports_store_outbound_writer;
revoke all on function private.validate_outbound_reservation(uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function private.validate_outbound_reservation(uuid, jsonb)
  to sports_store_outbound_writer;

create or replace function private.validate_outbound_dispatch_proof(
  p_order_id uuid, p_dispatch_event_id uuid, p_holder_id uuid, p_items_snapshot jsonb
)
returns void language plpgsql security invoker set search_path = ''
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
    from public.business_events e
    where e.incident_kind in (
      'damaged'::public.delivery_incident_kind,
      'lost'::public.delivery_incident_kind
    )
      and (
        (e.subject_type = 'order' and e.subject_id = p_order_id)
        or exists (
          select 1 from public.delivery_tasks t
          where t.id = e.task_id and t.order_id = p_order_id
        )
      )
  ) then
    raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
  end if;
  if exists (
    select 1 from public.inventory_movements m
    where m.order_id = p_order_id
      and (
        m.variant_id is null
        or m.variant_id not in (
          select oi.variant_id from public.order_items oi where oi.order_id = p_order_id
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
          or (m.kind = 'reserve'::public.inventory_movement_kind and m.reserved_delta <= 0)
          or (m.kind = 'release'::public.inventory_movement_kind and m.reserved_delta >= 0)
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
    select 1 from public.inventory_movements m
    where m.order_id = p_order_id
      and m.kind = 'dispatch'::public.inventory_movement_kind
      and (
        m.event_id is distinct from p_dispatch_event_id
        or m.actor_id is distinct from l_dispatch.holder_id
        or m.on_hand_delta >= 0 or m.reserved_delta >= 0 or m.damaged_delta <> 0
        or m.return_request_id is not null
        or m.variant_id not in (
          select oi.variant_id from public.order_items oi where oi.order_id = p_order_id
        )
      )
  ) then
    raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
  end if;
  for l_item in
    select oi.variant_id, oi.quantity
    from public.order_items oi where oi.order_id = p_order_id order by oi.variant_id
  loop
    select count(*), coalesce(sum(m.reserved_delta), 0)
      into l_movement_count, l_reserved_sum
    from public.inventory_movements m
    where m.order_id = p_order_id and m.variant_id = l_item.variant_id
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
    where m.order_id = p_order_id and m.variant_id = l_item.variant_id
      and m.kind = 'dispatch'::public.inventory_movement_kind;
    if l_movement_count <> 1 or l_on_hand_sum <> -l_item.quantity then
      raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
    end if;
    select m.* into l_dispatch_row
    from public.inventory_movements m
    where m.order_id = p_order_id and m.variant_id = l_item.variant_id
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
alter function private.validate_outbound_dispatch_proof(uuid, uuid, uuid, jsonb)
  owner to sports_store_outbound_writer;
revoke all on function private.validate_outbound_dispatch_proof(uuid, uuid, uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function private.validate_outbound_dispatch_proof(uuid, uuid, uuid, jsonb)
  to sports_store_outbound_writer;

create or replace function private.dispatch_outbound(
  p_order_id uuid,
  p_task_id uuid,
  p_holder_id uuid,
  p_dispatch_event_id uuid,
  p_items_snapshot jsonb,
  p_dispatched_at timestamptz
)
returns jsonb language plpgsql security invoker set search_path = ''
as $$
declare
  l_item record;
  l_balance record;
  l_snapshot jsonb;
begin
  l_snapshot := private.outbound_items_snapshot(p_order_id);
  if l_snapshot is distinct from p_items_snapshot then
    raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
  end if;
  perform private.validate_outbound_reservation(p_order_id, p_items_snapshot);
  if exists (select 1 from private.outbound_dispatches d where d.order_id = p_order_id)
     or exists (
       select 1 from public.inventory_movements m
       where m.order_id = p_order_id
         and m.kind = 'dispatch'::public.inventory_movement_kind
     ) then
    raise exception using errcode = 'PT409', message = 'DISPATCH_CONFLICT';
  end if;

  -- Lock every variant before the first stock or movement write.
  for l_item in
    select oi.variant_id, oi.quantity
    from public.order_items oi where oi.order_id = p_order_id order by oi.variant_id
  loop
    select v.id, v.on_hand, v.reserved, v.damaged into l_balance
    from public.product_variants v where v.id = l_item.variant_id for update;
    if not found
       or l_balance.on_hand < l_item.quantity
       or l_balance.reserved < l_item.quantity
       or l_balance.on_hand - l_item.quantity < 0
       or l_balance.reserved - l_item.quantity < 0 then
      raise exception using errcode = 'PT409', message = 'STOCK_CONFLICT';
    end if;
  end loop;

  for l_item in
    select oi.variant_id, oi.quantity
    from public.order_items oi where oi.order_id = p_order_id order by oi.variant_id
  loop
    update public.product_variants
    set on_hand = on_hand - l_item.quantity,
        reserved = reserved - l_item.quantity,
        updated_at = p_dispatched_at
    where id = l_item.variant_id;
    insert into public.inventory_movements (
      variant_id, order_id, event_id, kind, on_hand_delta, reserved_delta,
      damaged_delta, actor_id, reason, created_at
    ) values (
      l_item.variant_id, p_order_id, p_dispatch_event_id,
      'dispatch'::public.inventory_movement_kind,
      -l_item.quantity, -l_item.quantity, 0, p_holder_id,
      'outbound_dispatch', p_dispatched_at
    );
  end loop;

  insert into private.outbound_dispatches (
    order_id, initial_task_id, holder_id, event_id, items_snapshot, dispatched_at
  ) values (
    p_order_id, p_task_id, p_holder_id, p_dispatch_event_id,
    p_items_snapshot, p_dispatched_at
  );
  return jsonb_build_object(
    'order_id', p_order_id,
    'task_id', p_task_id,
    'dispatch_event_id', p_dispatch_event_id,
    'items_snapshot', p_items_snapshot,
    'dispatched_at', p_dispatched_at
  );
end;
$$;
alter function private.dispatch_outbound(uuid, uuid, uuid, uuid, jsonb, timestamptz)
  owner to sports_store_outbound_writer;
revoke all on function private.dispatch_outbound(uuid, uuid, uuid, uuid, jsonb, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function private.dispatch_outbound(uuid, uuid, uuid, uuid, jsonb, timestamptz)
  to sports_store_outbound_writer;

create or replace function public.accept_delivery_task(p_task_id uuid, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  l_actor_id uuid;
  l_actor_role text;
  l_payload_hash text;
  l_existing private.outbound_command_requests%rowtype;
  l_order_id uuid;
  l_order_status public.order_status;
  l_order_total bigint;
  l_attempt_count smallint;
  l_outbound_task_count bigint := 0;
  l_target_found boolean := false;
  l_target_status public.delivery_task_status;
  l_target_shipper uuid;
  l_target_attempt smallint;
  l_target_amount bigint;
  l_target_assigned_at timestamptz;
  l_target_accepted_at timestamptz;
  l_target_started_at timestamptz;
  l_target_completed_at timestamptz;
  l_target_failure_reason text;
  l_target_cancel_reason text;
  l_legacy_task_conflict boolean := false;
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
  l_items_snapshot jsonb;
  l_dispatch_event_id uuid;
  l_event_id uuid;
  l_response jsonb;
  l_now timestamptz := statement_timestamp();
  l_is_second boolean := false;
  l_previous_task_id uuid;
  l_previous_task_shipper uuid;
  l_previous_task_status public.delivery_task_status;
  l_previous_accepted_at timestamptz;
  l_previous_started_at timestamptz;
  l_previous_task_count bigint;
  l_previous_attempt_rows bigint;
  l_previous_attempt_task uuid;
  l_previous_attempt_shipper uuid;
  l_previous_attempt_number smallint;
  l_previous_result public.delivery_attempt_result;
  l_previous_custody private.outbound_custody_acceptances%rowtype;
  l_dispatch private.outbound_dispatches%rowtype;
  l_task_row record;
begin
  l_actor_id := (select auth.uid());
  if l_actor_id is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if p_task_id is null or p_request_id is null then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;

  select p.role::text into l_actor_role
  from public.profiles p where p.id = l_actor_id for share;
  if l_actor_role is distinct from 'shipper' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'sports_store.outbound.command:' || l_actor_id::text || ':' || p_request_id::text, 0
  ));
  select p.role::text into l_actor_role
  from public.profiles p where p.id = l_actor_id for share;
  if l_actor_role is distinct from 'shipper' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;

  l_payload_hash := md5(jsonb_build_object(
    'operation', 'accept', 'task_id', p_task_id, 'request_id', p_request_id
  )::text);
  select t.order_id into l_order_id
  from public.delivery_tasks t
  where t.id = p_task_id and t.kind = 'outbound'::public.delivery_task_kind
    and t.assigned_shipper_id = l_actor_id;
  if not found then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;

  select o.status, o.total_cod_vnd, o.delivery_attempt_count
    into l_order_status, l_order_total, l_attempt_count
  from public.orders o where o.id = l_order_id for update;
  if not found then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;

  for l_task_row in
    select t.id, t.status, t.assigned_shipper_id, t.attempt_number,
           t.amount_to_collect_vnd,
           t.assigned_at, t.accepted_at, t.started_at, t.completed_at,
           t.failure_reason, t.cancel_reason
    from public.delivery_tasks t
    where t.order_id = l_order_id and t.kind = 'outbound'::public.delivery_task_kind
    order by t.id for update
  loop
    l_outbound_task_count := l_outbound_task_count + 1;
    if l_task_row.id = p_task_id then
      l_target_found := true;
      l_target_status := l_task_row.status;
      l_target_shipper := l_task_row.assigned_shipper_id;
      l_target_attempt := l_task_row.attempt_number;
      l_target_amount := l_task_row.amount_to_collect_vnd;
      l_target_assigned_at := l_task_row.assigned_at;
      l_target_accepted_at := l_task_row.accepted_at;
      l_target_started_at := l_task_row.started_at;
      l_target_completed_at := l_task_row.completed_at;
      l_target_failure_reason := l_task_row.failure_reason;
      l_target_cancel_reason := l_task_row.cancel_reason;
    elsif l_task_row.accepted_at is not null
       or l_task_row.started_at is not null
       or l_task_row.completed_at is not null
       or l_task_row.failure_reason is not null
       or l_task_row.cancel_reason is not null
       or l_task_row.attempt_number > 1
       or l_task_row.status in (
         'accepted'::public.delivery_task_status,
         'in_transit'::public.delivery_task_status,
         'delivered'::public.delivery_task_status,
         'failed'::public.delivery_task_status,
         'returned_to_store'::public.delivery_task_status,
         'cancelled'::public.delivery_task_status,
         'manager_action_required'::public.delivery_task_status
       ) then
      l_legacy_task_conflict := true;
    end if;
  end loop;
  if not l_target_found or l_target_shipper is distinct from l_actor_id then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;

  -- Assignment timestamps can be produced earlier in the same top-level
  -- statement; use wall-clock time for the state precondition below.  This is
  -- refreshed again after COD/order-item/variant locks before writes.
  l_now := clock_timestamp();

  -- Replay is safe only after role, target assignment, order, and all-task
  -- locks have been rechecked.
  select r.* into l_existing
  from private.outbound_command_requests r
  where r.actor_id = l_actor_id and r.request_id = p_request_id;
  if found then
    if l_existing.operation <> 'accept'
       or l_existing.task_id is distinct from p_task_id
       or l_existing.order_id is distinct from l_order_id
       or l_existing.payload_hash <> l_payload_hash then
      raise exception using errcode = 'PT409', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return l_existing.response;
  end if;

  if l_order_status = 'cancelled'::public.order_status then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;

  if l_target_attempt = 1
     and l_target_status = 'assigned'::public.delivery_task_status
     and l_target_accepted_at is null and l_target_started_at is null
     and l_target_completed_at is null and l_target_failure_reason is null
     and l_target_cancel_reason is null and l_target_assigned_at is not null
     and l_target_assigned_at <= l_now
     and l_order_status = 'awaiting_pickup'::public.order_status
     and l_attempt_count = 0
     and l_outbound_task_count = 1 then
    if l_legacy_task_conflict
       or exists (select 1 from private.outbound_custody_acceptances c where c.order_id = l_order_id)
       or exists (select 1 from private.outbound_dispatches d where d.order_id = l_order_id)
       or exists (
         select 1 from public.inventory_movements m
         where m.order_id = l_order_id and m.kind = 'dispatch'::public.inventory_movement_kind
       )
       or exists (select 1 from public.delivery_attempts a where a.order_id = l_order_id) then
      raise exception using errcode = 'PT409', message = 'DISPATCH_CONFLICT';
    end if;
  elsif l_target_attempt = 2
     and l_target_status = 'assigned'::public.delivery_task_status
     and l_target_accepted_at is null and l_target_started_at is null
     and l_target_completed_at is null and l_target_failure_reason is null
     and l_target_cancel_reason is null and l_target_assigned_at is not null
     and l_target_assigned_at <= l_now
     and l_order_status = 'awaiting_pickup'::public.order_status
     and l_attempt_count = 1
     and l_outbound_task_count = 2 then
    l_is_second := true;
  else
    if l_target_accepted_at is not null
       and not exists (
         select 1 from private.outbound_custody_acceptances c where c.task_id = p_task_id
       ) then
      raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
    end if;
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;

  select c.status, c.shipper_id, c.expected_amount_vnd,
         c.collected_amount_vnd, c.received_amount_vnd,
         c.collected_at, c.collected_by, c.handed_over_at,
         c.received_at, c.received_by
    into l_cod_status, l_cod_shipper, l_cod_expected,
         l_cod_collected, l_cod_received, l_cod_collected_at,
         l_cod_collected_by, l_cod_handed_over_at, l_cod_received_at,
         l_cod_received_by
  from public.cod_collections c where c.order_id = l_order_id for update;
  if not found or l_target_amount <> l_order_total
     or l_cod_status <> 'uncollected'::public.cod_status
     or l_cod_shipper is distinct from l_actor_id or l_cod_expected <> l_order_total
     or l_cod_collected <> 0 or l_cod_received <> 0
     or l_cod_collected_at is not null or l_cod_collected_by is not null
     or l_cod_handed_over_at is not null or l_cod_received_at is not null
     or l_cod_received_by is not null then
    raise exception using errcode = 'PT409', message = 'COD_CONFLICT';
  end if;

  perform 1 from public.order_items oi
  where oi.order_id = l_order_id order by oi.variant_id, oi.id for update;
  perform 1 from public.product_variants v
  where v.id in (select oi.variant_id from public.order_items oi where oi.order_id = l_order_id)
  order by v.id for update;
  l_now := clock_timestamp();
  if l_target_assigned_at > l_now then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;
  l_items_snapshot := private.outbound_items_snapshot(l_order_id);
  if jsonb_typeof(l_items_snapshot) <> 'array' or jsonb_array_length(l_items_snapshot) = 0 then
    raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
  end if;

  if l_is_second then
    select count(*) into l_previous_task_count
    from public.delivery_tasks t
    where t.order_id = l_order_id and t.kind = 'outbound'::public.delivery_task_kind
      and t.attempt_number = 1;
    if l_previous_task_count <> 1 then
      raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
    end if;
    select t.id, t.assigned_shipper_id, t.status, t.accepted_at, t.started_at
      into l_previous_task_id, l_previous_task_shipper,
           l_previous_task_status, l_previous_accepted_at, l_previous_started_at
    from public.delivery_tasks t
    where t.order_id = l_order_id and t.kind = 'outbound'::public.delivery_task_kind
      and t.attempt_number = 1;
    if l_previous_task_status <> 'failed'::public.delivery_task_status
       or l_previous_task_shipper is distinct from l_actor_id
       or l_previous_accepted_at is null
       or l_previous_started_at is null
       or l_previous_accepted_at > l_now
       or l_previous_started_at > l_now then
      raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
    end if;
    select count(*) into l_previous_attempt_rows
    from public.delivery_attempts a where a.order_id = l_order_id;
    if l_previous_attempt_rows = 1 then
      select a.task_id, a.shipper_id, a.attempt_number, a.result
        into l_previous_attempt_task, l_previous_attempt_shipper,
             l_previous_attempt_number, l_previous_result
      from public.delivery_attempts a where a.order_id = l_order_id;
    end if;
    if l_previous_attempt_rows <> 1
       or l_previous_attempt_task is distinct from l_previous_task_id
       or l_previous_attempt_shipper is distinct from l_actor_id
       or l_previous_attempt_number <> 1
       or l_previous_result <> 'failed'::public.delivery_attempt_result then
      raise exception using errcode = 'PT409', message = 'ATTEMPT_LIMIT';
    end if;
    select d.* into l_dispatch
    from private.outbound_dispatches d where d.order_id = l_order_id;
    if not found
       or l_dispatch.holder_id is distinct from l_actor_id
       or l_dispatch.initial_task_id is distinct from l_previous_task_id
       or l_dispatch.dispatched_at > l_previous_accepted_at then
      raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
    end if;
    l_dispatch_event_id := l_dispatch.event_id;
    perform private.validate_outbound_dispatch_proof(
      l_order_id, l_dispatch_event_id, l_actor_id, l_items_snapshot
    );
    select c.* into l_previous_custody
    from private.outbound_custody_acceptances c
    where c.task_id = l_previous_task_id;
    if not found or l_previous_custody.order_id is distinct from l_order_id
       or l_previous_custody.holder_id is distinct from l_actor_id
       or l_previous_custody.dispatch_event_id is distinct from l_dispatch_event_id
       or l_previous_custody.attempt_number <> 1
       or l_previous_custody.accepted_at is distinct from l_previous_accepted_at then
      raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
    end if;
  else
    l_dispatch_event_id := pg_catalog.gen_random_uuid();
    insert into public.business_events (
      id, actor_id, subject_type, subject_id, from_state, to_state,
      reason, task_id, request_id, created_at
    ) values (
      l_dispatch_event_id, l_actor_id, 'order', l_order_id,
      'awaiting_pickup', 'awaiting_pickup', 'outbound_dispatched', null,
      l_dispatch_event_id, l_now
    );
    perform private.dispatch_outbound(
      l_order_id, p_task_id, l_actor_id, l_dispatch_event_id,
      l_items_snapshot, l_now
    );
  end if;

  l_event_id := pg_catalog.gen_random_uuid();
  insert into private.outbound_custody_acceptances (
    task_id, order_id, holder_id, dispatch_event_id, accepted_at, attempt_number
  ) values (
    p_task_id, l_order_id, l_actor_id, l_dispatch_event_id, l_now, l_target_attempt
  );
  update public.delivery_tasks
  set status = 'accepted'::public.delivery_task_status,
      accepted_at = l_now, updated_at = l_now
  where id = p_task_id;
  insert into public.business_events (
    id, actor_id, subject_type, subject_id, from_state, to_state,
    reason, task_id, request_id, created_at
  ) values (
    l_event_id, l_actor_id, 'delivery_task', p_task_id,
    'assigned', 'accepted', 'delivery_task_accepted', p_task_id,
    l_event_id, l_now
  );

  l_response := jsonb_build_object(
    'task_id', p_task_id, 'order_id', l_order_id, 'operation', 'accept',
    'task_status', 'accepted', 'order_status', l_order_status::text,
    'attempt_number', l_target_attempt, 'delivery_attempt_count', l_attempt_count,
    'accepted_at', l_now, 'started_at', null,
    'dispatch_event_id', l_dispatch_event_id, 'event_id', l_event_id,
    'request_id', p_request_id
  );
  insert into private.outbound_command_requests (
    actor_id, request_id, operation, task_id, order_id, payload_hash,
    response, created_at
  ) values (
    l_actor_id, p_request_id, 'accept', p_task_id, l_order_id,
    l_payload_hash, l_response, l_now
  );
  return l_response;
end;
$$;
alter function public.accept_delivery_task(uuid, uuid) owner to sports_store_outbound_writer;
revoke all on function public.accept_delivery_task(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.accept_delivery_task(uuid, uuid) to authenticated;

create or replace function public.start_delivery_task(p_task_id uuid, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  l_actor_id uuid;
  l_actor_role text;
  l_payload_hash text;
  l_existing private.outbound_command_requests%rowtype;
  l_order_id uuid;
  l_order_status public.order_status;
  l_order_total bigint;
  l_attempt_count smallint;
  l_next_attempt smallint;
  l_target_found boolean := false;
  l_target_status public.delivery_task_status;
  l_target_shipper uuid;
  l_target_attempt smallint;
  l_target_amount bigint;
  l_target_assigned_at timestamptz;
  l_target_accepted_at timestamptz;
  l_target_started_at timestamptz;
  l_target_completed_at timestamptz;
  l_target_failure_reason text;
  l_target_cancel_reason text;
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
  l_items_snapshot jsonb;
  l_dispatch_event_id uuid;
  l_event_id uuid;
  l_response jsonb;
  l_now timestamptz := statement_timestamp();
  l_custody private.outbound_custody_acceptances%rowtype;
  l_attempt_rows bigint;
  l_task_row record;
begin
  l_actor_id := (select auth.uid());
  if l_actor_id is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if p_task_id is null or p_request_id is null then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;
  select p.role::text into l_actor_role
  from public.profiles p where p.id = l_actor_id for share;
  if l_actor_role is distinct from 'shipper' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'sports_store.outbound.command:' || l_actor_id::text || ':' || p_request_id::text, 0
  ));
  select p.role::text into l_actor_role
  from public.profiles p where p.id = l_actor_id for share;
  if l_actor_role is distinct from 'shipper' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;

  l_payload_hash := md5(jsonb_build_object(
    'operation', 'start', 'task_id', p_task_id, 'request_id', p_request_id
  )::text);
  select t.order_id into l_order_id
  from public.delivery_tasks t
  where t.id = p_task_id and t.kind = 'outbound'::public.delivery_task_kind
    and t.assigned_shipper_id = l_actor_id;
  if not found then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;
  select o.status, o.total_cod_vnd, o.delivery_attempt_count
    into l_order_status, l_order_total, l_attempt_count
  from public.orders o where o.id = l_order_id for update;
  if not found then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;
  for l_task_row in
    select t.id, t.status, t.assigned_shipper_id, t.attempt_number,
           t.amount_to_collect_vnd,
           t.assigned_at, t.accepted_at, t.started_at, t.completed_at,
           t.failure_reason, t.cancel_reason
    from public.delivery_tasks t
    where t.order_id = l_order_id and t.kind = 'outbound'::public.delivery_task_kind
    order by t.id for update
  loop
    if l_task_row.id = p_task_id then
      l_target_found := true;
      l_target_status := l_task_row.status;
      l_target_shipper := l_task_row.assigned_shipper_id;
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
  if not l_target_found or l_target_shipper is distinct from l_actor_id then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;
  select r.* into l_existing
  from private.outbound_command_requests r
  where r.actor_id = l_actor_id and r.request_id = p_request_id;
  if found then
    if l_existing.operation <> 'start'
       or l_existing.task_id is distinct from p_task_id
       or l_existing.order_id is distinct from l_order_id
       or l_existing.payload_hash <> l_payload_hash then
      raise exception using errcode = 'PT409', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return l_existing.response;
  end if;
  if l_order_status = 'cancelled'::public.order_status then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;

  select c.status, c.shipper_id, c.expected_amount_vnd,
         c.collected_amount_vnd, c.received_amount_vnd,
         c.collected_at, c.collected_by, c.handed_over_at,
         c.received_at, c.received_by
    into l_cod_status, l_cod_shipper, l_cod_expected,
         l_cod_collected, l_cod_received, l_cod_collected_at,
         l_cod_collected_by, l_cod_handed_over_at, l_cod_received_at,
         l_cod_received_by
  from public.cod_collections c where c.order_id = l_order_id for update;
  if not found or l_target_amount <> l_order_total
     or l_cod_status <> 'uncollected'::public.cod_status
     or l_cod_shipper is distinct from l_actor_id or l_cod_expected <> l_order_total
     or l_cod_collected <> 0 or l_cod_received <> 0
     or l_cod_collected_at is not null or l_cod_collected_by is not null
     or l_cod_handed_over_at is not null or l_cod_received_at is not null
     or l_cod_received_by is not null then
    raise exception using errcode = 'PT409', message = 'COD_CONFLICT';
  end if;

  -- A test/transaction may have assigned and accepted the task earlier in
  -- this same top-level statement.  Use wall-clock time for timestamp
  -- coherence, then refresh again after variant locks before mutating.
  l_now := clock_timestamp();
  l_next_attempt := l_attempt_count + 1;
  if l_next_attempt > 2 then
    raise exception using errcode = 'PT409', message = 'ATTEMPT_LIMIT';
  end if;
  if l_next_attempt > 2
     or l_target_attempt <> l_next_attempt
     or l_target_status <> 'accepted'::public.delivery_task_status
     or l_target_accepted_at is null or l_target_started_at is not null
     or l_target_completed_at is not null or l_target_failure_reason is not null
     or l_target_cancel_reason is not null or l_target_assigned_at is null
     or l_target_assigned_at > l_target_accepted_at
     or l_target_accepted_at > l_now
     or l_target_amount <> l_order_total
     or l_order_status <> 'awaiting_pickup'::public.order_status then
    if l_target_accepted_at is not null
       and not exists (
         select 1 from private.outbound_custody_acceptances c where c.task_id = p_task_id
       ) then
      raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
    end if;
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;

  perform 1 from public.order_items oi
  where oi.order_id = l_order_id order by oi.variant_id, oi.id for update;
  perform 1 from public.product_variants v
  where v.id in (select oi.variant_id from public.order_items oi where oi.order_id = l_order_id)
  order by v.id for update;
  l_now := clock_timestamp();
  if l_target_accepted_at > l_now then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;
  l_items_snapshot := private.outbound_items_snapshot(l_order_id);
  if jsonb_typeof(l_items_snapshot) <> 'array' or jsonb_array_length(l_items_snapshot) = 0 then
    raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
  end if;
  select c.* into l_custody
  from private.outbound_custody_acceptances c where c.task_id = p_task_id;
  if not found or l_custody.order_id is distinct from l_order_id
     or l_custody.holder_id is distinct from l_actor_id
     or l_custody.attempt_number <> l_target_attempt
     or l_custody.accepted_at is distinct from l_target_accepted_at then
    raise exception using errcode = 'PT409', message = 'CUSTODY_UNRESOLVED';
  end if;
  l_dispatch_event_id := l_custody.dispatch_event_id;
  perform private.validate_outbound_dispatch_proof(
    l_order_id, l_dispatch_event_id, l_actor_id, l_items_snapshot
  );
  select count(*) into l_attempt_rows
  from public.delivery_attempts a where a.order_id = l_order_id;
  if l_target_attempt = 1 and l_attempt_rows <> 0 then
    raise exception using errcode = 'PT409', message = 'ATTEMPT_LIMIT';
  end if;
  if l_target_attempt = 2 and (
    l_attempt_rows <> 1
    or not exists (
      select 1
      from public.delivery_attempts a
      join public.delivery_tasks t on t.id = a.task_id
      where a.order_id = l_order_id
        and a.attempt_number = 1
        and a.task_kind = 'outbound'::public.delivery_task_kind
        and a.result = 'failed'::public.delivery_attempt_result
        and a.shipper_id = l_actor_id
        and t.order_id = l_order_id
        and t.kind = 'outbound'::public.delivery_task_kind
        and t.attempt_number = 1
        and t.status = 'failed'::public.delivery_task_status
        and t.assigned_shipper_id = l_actor_id
    )
  ) then
    raise exception using errcode = 'PT409', message = 'ATTEMPT_LIMIT';
  end if;

  l_event_id := pg_catalog.gen_random_uuid();
  update public.delivery_tasks
  set status = 'in_transit'::public.delivery_task_status,
      started_at = l_now, updated_at = l_now
  where id = p_task_id;
  update public.orders
  set status = 'delivering'::public.order_status,
      delivery_attempt_count = l_next_attempt, updated_at = l_now
  where id = l_order_id;
  insert into public.business_events (
    id, actor_id, subject_type, subject_id, from_state, to_state,
    reason, task_id, request_id, created_at
  ) values (
    l_event_id, l_actor_id, 'delivery_task', p_task_id,
    'accepted', 'in_transit', 'delivery_started', p_task_id,
    l_event_id, l_now
  );

  l_response := jsonb_build_object(
    'task_id', p_task_id, 'order_id', l_order_id, 'operation', 'start',
    'task_status', 'in_transit', 'order_status', 'delivering',
    'attempt_number', l_target_attempt, 'delivery_attempt_count', l_next_attempt,
    'accepted_at', l_target_accepted_at, 'started_at', l_now,
    'dispatch_event_id', l_dispatch_event_id, 'event_id', l_event_id,
    'request_id', p_request_id
  );
  insert into private.outbound_command_requests (
    actor_id, request_id, operation, task_id, order_id, payload_hash,
    response, created_at
  ) values (
    l_actor_id, p_request_id, 'start', p_task_id, l_order_id,
    l_payload_hash, l_response, l_now
  );
  return l_response;
end;
$$;
alter function public.start_delivery_task(uuid, uuid) owner to sports_store_outbound_writer;
revoke create on schema public, private from sports_store_outbound_writer;
revoke all on function public.start_delivery_task(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.start_delivery_task(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';
