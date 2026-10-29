-- P06.3 manager-only COD receipt transaction.
--
-- This migration deliberately owns only confirm_cod_received. It does not
-- change order state, delivery tasks, attempts, inventory, returns, or refund
-- amounts. The API caller supplies only the order, the manager's attested
-- amount, and a stable retry key; identity, holder, timestamps and expected
-- amount are server-derived.

-- Keep this writer separate from P03.3 assignment. It must never be granted
-- to an API role or used as a generic table-writing role.
do $$
begin
  if not exists (
    select 1 from pg_roles where rolname = 'sports_store_cod_receipt_writer'
  ) then
    create role sports_store_cod_receipt_writer
      nologin noinherit nobypassrls nocreatedb nocreaterole noreplication;
    comment on role sports_store_cod_receipt_writer is
      'sports_store P06.3 COD receipt writer; no-login, no-inherit, no-bypass-RLS';
  elsif not exists (
    select 1
    from pg_roles r
    where r.rolname = 'sports_store_cod_receipt_writer'
      and not r.rolcanlogin
      and not r.rolsuper
      and not r.rolbypassrls
      and not r.rolinherit
      and not r.rolcreaterole
      and not r.rolcreatedb
      and not r.rolreplication
      and shobj_description(r.oid, 'pg_authid') =
        'sports_store P06.3 COD receipt writer; no-login, no-inherit, no-bypass-RLS'
  ) then
    raise exception
      'P06.3 COD receipt writer role already exists with unexpected configuration';
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
    where granted.rolname = 'sports_store_cod_receipt_writer'
      and member.rolname <> 'postgres'
  ) then
    raise exception 'P06.3 COD receipt writer role has unexpected membership';
  end if;
end;
$$;

grant sports_store_cod_receipt_writer to postgres;
grant usage on schema public, auth, private
  to sports_store_cod_receipt_writer;
grant execute on function auth.uid()
  to sports_store_cod_receipt_writer;
grant execute on function private.current_app_role()
  to sports_store_cod_receipt_writer;

-- One successful receipt per order is an explicit ledger invariant. The
-- actor/request primary key makes same-manager retries replayable, while the
-- order unique key prevents a new request from receiving the same COD twice.
create table private.cod_receipt_requests (
  actor_id uuid not null,
  request_id uuid not null,
  operation text not null,
  order_id uuid not null,
  received_amount_vnd bigint not null,
  payload_hash text not null,
  response jsonb not null,
  created_at timestamptz not null default now(),
  primary key (actor_id, request_id),
  constraint cod_receipt_requests_operation_valid
    check (operation = 'confirm_cod_received'),
  constraint cod_receipt_requests_amount_positive
    check (received_amount_vnd > 0),
  constraint cod_receipt_requests_payload_hash_nonblank
    check (btrim(payload_hash) <> ''),
  constraint cod_receipt_requests_response_object
    check (jsonb_typeof(response) = 'object'),
  constraint cod_receipt_requests_order_unique unique (order_id)
);

alter table private.cod_receipt_requests enable row level security;
alter table private.cod_receipt_requests force row level security;

create policy cod_receipt_requests_writer_read
  on private.cod_receipt_requests
  for select to sports_store_cod_receipt_writer
  using (current_user = 'sports_store_cod_receipt_writer');
create policy cod_receipt_requests_writer_insert
  on private.cod_receipt_requests
  for insert to sports_store_cod_receipt_writer
  with check (current_user = 'sports_store_cod_receipt_writer');

create function private.reject_cod_receipt_ledger_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'P06.3 COD receipt ledger is append-only'
    using errcode = '55000';
end;
$$;

create trigger cod_receipt_requests_append_only
before update or delete on private.cod_receipt_requests
for each row execute function private.reject_cod_receipt_ledger_mutation();

grant select, insert on private.cod_receipt_requests
  to sports_store_cod_receipt_writer;

-- Lock-only profile/order privileges use an impossible WITH CHECK policy, as
-- in the P03.3 writer. The function still rechecks the server-managed role
-- after the request advisory lock and before replay or any side effect.
grant select (id, role) on public.profiles
  to sports_store_cod_receipt_writer;
grant update (id) on public.profiles
  to sports_store_cod_receipt_writer;

grant select (id) on public.orders
  to sports_store_cod_receipt_writer;
grant update (id) on public.orders
  to sports_store_cod_receipt_writer;

grant select (
  order_id, shipper_id, status, expected_amount_vnd,
  collected_amount_vnd, received_amount_vnd, collected_at, collected_by,
  handed_over_at, received_at, received_by
) on public.cod_collections to sports_store_cod_receipt_writer;
grant update (
  status, received_amount_vnd, handed_over_at, received_at, received_by,
  updated_at
) on public.cod_collections to sports_store_cod_receipt_writer;

grant insert (
  id, actor_id, subject_type, subject_id, from_state, to_state, reason,
  request_id, created_at
) on public.business_events to sports_store_cod_receipt_writer;
grant insert (
  id, recipient_id, event_id, subject_type, subject_id, title, body, created_at
) on public.notifications to sports_store_cod_receipt_writer;

-- Every policy below is scoped to the function owner. No authenticated grant
-- is added, and the owner is NOBYPASSRLS so these checks remain meaningful.
create policy cod_receipt_writer_profiles_read
  on public.profiles
  for select to sports_store_cod_receipt_writer
  using (id = (select auth.uid()));
create policy cod_receipt_writer_profiles_lock_only
  on public.profiles
  for update to sports_store_cod_receipt_writer
  using ((select private.current_app_role()) = 'manager')
  with check (false);

create policy cod_receipt_writer_orders_read
  on public.orders
  for select to sports_store_cod_receipt_writer
  using ((select private.current_app_role()) = 'manager');
create policy cod_receipt_writer_orders_lock_only
  on public.orders
  for update to sports_store_cod_receipt_writer
  using ((select private.current_app_role()) = 'manager')
  with check (false);

create policy cod_receipt_writer_cod_read
  on public.cod_collections
  for select to sports_store_cod_receipt_writer
  using ((select private.current_app_role()) = 'manager');
create policy cod_receipt_writer_cod_update
  on public.cod_collections
  for update to sports_store_cod_receipt_writer
  using ((select private.current_app_role()) = 'manager')
  with check ((select private.current_app_role()) = 'manager');

create policy cod_receipt_writer_events_insert
  on public.business_events
  for insert to sports_store_cod_receipt_writer
  with check (
    (select private.current_app_role()) = 'manager'
    and actor_id = (select auth.uid())
    and subject_type = 'cod_collection'
    and subject_id is not null
    and from_state = 'collected'
    and to_state = 'received'
    and incident_kind is null
    and task_id is null
    and request_id = id
    and reason = 'manager_confirmed_cod_received'
  );

create policy cod_receipt_writer_notifications_insert
  on public.notifications
  for insert to sports_store_cod_receipt_writer
  with check (
    (select private.current_app_role()) = 'manager'
    and subject_type = 'cod_collection'
    and title = 'Cửa hàng đã nhận COD'
    and body = 'Cửa hàng đã xác nhận nhận đủ tiền COD.'
    and exists (
      select 1
      from public.cod_collections c
      where c.order_id = subject_id
        and c.status = 'received'::public.cod_status
        and c.shipper_id = recipient_id
        and c.received_by = (select auth.uid())
    )
  );

create or replace function public.confirm_cod_received(
  p_order_id uuid,
  p_received_amount_vnd bigint,
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
  l_holder_id uuid;
  l_collected_by uuid;
  l_payload_hash text;
  l_existing private.cod_receipt_requests%rowtype;
  l_order_id uuid;
  l_cod record;
  l_event_id uuid;
  l_notification_id uuid;
  l_now timestamptz;
  l_result jsonb;
begin
  l_actor_id := (select auth.uid());
  if l_actor_id is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;

  if p_order_id is null
     or p_received_amount_vnd is null
     or p_request_id is null
     or p_received_amount_vnd <= 0 then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;

  -- Lock the manager profile before using its role. This is the only source
  -- of authorization; JWT claims and user metadata are not trusted.
  select p.role::text
    into l_actor_role
  from public.profiles p
  where p.id = l_actor_id
  for share;
  if l_actor_role is distinct from 'manager' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;

  -- Serialize retries for one actor/request and all contenders for one
  -- order. The request lock makes mismatch handling deterministic; the order
  -- lock is taken before the required order -> COD row locks below.
  perform pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.confirm_cod_received:request:' || l_actor_id::text || ':'
      || p_request_id::text,
    0
  ));

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
    'received_amount_vnd', p_received_amount_vnd
  )::text);

  select *
    into l_existing
  from private.cod_receipt_requests r
  where r.actor_id = l_actor_id
    and r.request_id = p_request_id;
  if found then
    if l_existing.operation <> 'confirm_cod_received'
       or l_existing.order_id is distinct from p_order_id
       or l_existing.received_amount_vnd is distinct from p_received_amount_vnd
       or l_existing.payload_hash <> l_payload_hash then
      raise exception using
        errcode = 'PT409', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return l_existing.response;
  end if;

  perform pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.confirm_cod_received:order:' || p_order_id::text,
    0
  ));

  -- Business locks are always order first, COD second. Do not read a mutable
  -- order total here: cod_collections.expected_amount_vnd is authoritative
  -- for the existing COD obligation and is validated against its own state.
  select o.id
    into l_order_id
  from public.orders o
  where o.id = p_order_id
  for update;
  if not found then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;

  -- A different request cannot confirm an order already present in the
  -- successful ledger, even if a caller races after the order lock.
  select *
    into l_existing
  from private.cod_receipt_requests r
  where r.order_id = p_order_id;
  if found then
    if l_existing.actor_id = l_actor_id
       and l_existing.request_id = p_request_id
       and l_existing.payload_hash = l_payload_hash
       and l_existing.received_amount_vnd = p_received_amount_vnd then
      return l_existing.response;
    end if;
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;

  select c.order_id, c.shipper_id, c.status, c.expected_amount_vnd,
         c.collected_amount_vnd, c.received_amount_vnd, c.collected_at,
         c.collected_by, c.handed_over_at, c.received_at, c.received_by
    into l_cod
  from public.cod_collections c
  where c.order_id = p_order_id
  for update;
  if not found then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;

  if l_cod.status <> 'collected'::public.cod_status
     or l_cod.received_amount_vnd <> 0
     or l_cod.received_at is not null
     or l_cod.received_by is not null
     or l_cod.handed_over_at is not null then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;

  if l_cod.expected_amount_vnd <= 0
     or l_cod.collected_amount_vnd <> l_cod.expected_amount_vnd
     or p_received_amount_vnd <> l_cod.expected_amount_vnd then
    raise exception using errcode = 'PT409', message = 'AMOUNT_MISMATCH';
  end if;

  l_holder_id := l_cod.shipper_id;
  l_collected_by := l_cod.collected_by;
  if l_holder_id is null
     or l_collected_by is null
     or l_cod.collected_at is null
     or l_holder_id is distinct from l_collected_by then
    raise exception using errcode = 'PT409', message = 'CORRUPT_COD_STATE';
  end if;

  -- Capture the physical receipt timestamp only after both business rows are
  -- locked. A future collected_at is corrupt data, not a reason to backdate
  -- the store receipt.
  l_now := pg_catalog.clock_timestamp();
  if l_cod.collected_at > l_now then
    raise exception using errcode = 'PT409', message = 'CORRUPT_COD_STATE';
  end if;

  update public.cod_collections
  set status = 'received'::public.cod_status,
      received_amount_vnd = p_received_amount_vnd,
      handed_over_at = l_now,
      received_at = l_now,
      received_by = l_actor_id,
      updated_at = l_now
  where order_id = p_order_id;

  l_event_id := pg_catalog.gen_random_uuid();
  insert into public.business_events (
    id, actor_id, subject_type, subject_id, from_state, to_state,
    reason, request_id, created_at
  ) values (
    l_event_id, l_actor_id, 'cod_collection', p_order_id,
    'collected', 'received', 'manager_confirmed_cod_received', l_event_id,
    l_now
  );

  l_notification_id := pg_catalog.gen_random_uuid();
  insert into public.notifications (
    id, recipient_id, event_id, subject_type, subject_id, title, body, created_at
  ) values (
    l_notification_id, l_holder_id, l_event_id, 'cod_collection', p_order_id,
    'Cửa hàng đã nhận COD',
    'Cửa hàng đã xác nhận nhận đủ tiền COD.',
    l_now
  );

  l_result := jsonb_build_object(
    'order_id', p_order_id,
    'status', 'received',
    'received_amount_vnd', p_received_amount_vnd,
    'received_by', l_actor_id,
    'received_at', l_now,
    'handed_over_at', l_now,
    'event_id', l_event_id,
    'notification_id', l_notification_id
  );

  insert into private.cod_receipt_requests (
    actor_id, request_id, operation, order_id, received_amount_vnd,
    payload_hash, response, created_at
  ) values (
    l_actor_id, p_request_id, 'confirm_cod_received', p_order_id,
    p_received_amount_vnd, l_payload_hash, l_result, l_now
  );

  return l_result;
end;
$$;

grant create on schema public to sports_store_cod_receipt_writer;
alter function public.confirm_cod_received(uuid, bigint, uuid)
  owner to sports_store_cod_receipt_writer;
revoke create on schema public from sports_store_cod_receipt_writer;
revoke all on function public.confirm_cod_received(uuid, bigint, uuid)
  from public, anon, service_role, sports_store_cod_receipt_writer;
grant execute on function public.confirm_cod_received(uuid, bigint, uuid)
  to authenticated;

comment on function public.confirm_cod_received(uuid, bigint, uuid) is
  'P06.3 manager-only atomic COD receipt; exact collected amount, one order ledger row, shipper-holder notification, no refund offset.';

notify pgrst, 'reload schema';
