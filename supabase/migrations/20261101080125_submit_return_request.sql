-- MH13 customer return request: read context + atomic submission.
--
-- Owns only return creation. It never approves a return, creates return_items
-- (the pickup plan is decided by the manager in MH15), changes the delivered
-- order, COD, inventory or refund state. The client supplies the order, a
-- stable retry key, reason, description, an already-uploaded private video
-- path and refund bank details. Identity, ownership, the 7-day window
-- (measured at submission on the server clock), video presence and the
-- one-active-return rule are all enforced here.

-- 1. Restricted NOLOGIN/NOBYPASSRLS owner for the SECURITY DEFINER command.
do $$
begin
  if not exists (
    select 1 from pg_roles where rolname = 'sports_store_return_request_writer'
  ) then
    create role sports_store_return_request_writer
      nologin noinherit nobypassrls nocreatedb nocreaterole noreplication;
    comment on role sports_store_return_request_writer is
      'sports_store MH13 return-request writer; no-login, no-inherit, no-bypass-RLS';
  elsif not exists (
    select 1
    from pg_roles r
    where r.rolname = 'sports_store_return_request_writer'
      and not r.rolcanlogin
      and not r.rolsuper
      and not r.rolbypassrls
      and not r.rolinherit
      and not r.rolcreaterole
      and not r.rolcreatedb
      and not r.rolreplication
      and shobj_description(r.oid, 'pg_authid') =
        'sports_store MH13 return-request writer; no-login, no-inherit, no-bypass-RLS'
  ) then
    raise exception
      'MH13 return-request writer role already exists with unexpected configuration';
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
    where granted.rolname = 'sports_store_return_request_writer'
      and member.rolname <> 'postgres'
  ) then
    raise exception 'MH13 return-request writer role has unexpected membership';
  end if;
end;
$$;

grant sports_store_return_request_writer to postgres;
grant usage on schema public, private to sports_store_return_request_writer;
grant execute on function private.delivery_request_user_id(),
  private.current_app_role()
  to sports_store_return_request_writer;

-- 2. Storage check through a postgres-owned helper (hosted projects do not let
-- custom roles read the managed storage schema). Returns only a boolean.
create function private.return_video_object_ready(
  p_object_path text,
  p_owner_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  -- plpgsql defers column resolution to call time (hosted storage.objects has
  -- owner_id/metadata; minimal SQL fixtures for other suites do not).
  return exists (
    select 1
    from storage.objects o
    where o.bucket_id = 'return-videos'
      and o.name = p_object_path
      and o.owner_id = p_owner_id::text
      and coalesce(o.metadata ->> 'mimetype', '') like 'video/%'
      and coalesce((o.metadata ->> 'size')::bigint, 0) between 1 and 104857600
  );
end;
$$;
revoke all on function private.return_video_object_ready(text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.return_video_object_ready(text, uuid)
  to sports_store_return_request_writer;

-- 3. Minimal column privileges + policies scoped to the writer role.
grant select (id, role) on public.profiles
  to sports_store_return_request_writer;
grant select (id, customer_id, status, delivered_at) on public.orders
  to sports_store_return_request_writer;
-- Lock-only: FOR UPDATE needs an UPDATE privilege; the policy forbids writes.
grant update (id) on public.orders to sports_store_return_request_writer;
grant select (
  id, order_id, customer_id, request_id, status, reason, description,
  video_object_path, submitted_at, bank_name, account_number, account_holder
) on public.return_requests to sports_store_return_request_writer;
grant insert (
  id, order_id, customer_id, request_id, status, reason, description,
  video_object_path, submitted_at, bank_name, account_number, account_holder,
  created_at, updated_at
) on public.return_requests to sports_store_return_request_writer;
grant insert (
  id, actor_id, subject_type, subject_id, from_state, to_state, reason,
  request_id, created_at
) on public.business_events to sports_store_return_request_writer;
grant insert (
  id, recipient_id, event_id, subject_type, subject_id, title, body, created_at
) on public.notifications to sports_store_return_request_writer;

create policy return_request_writer_profiles_read
  on public.profiles
  for select to sports_store_return_request_writer
  using (
    id = (select private.delivery_request_user_id())
    or role = 'manager'::public.user_role
  );

create policy return_request_writer_orders_read
  on public.orders
  for select to sports_store_return_request_writer
  using (customer_id = (select private.delivery_request_user_id()));
create policy return_request_writer_orders_lock_only
  on public.orders
  for update to sports_store_return_request_writer
  using (customer_id = (select private.delivery_request_user_id()))
  with check (false);

create policy return_request_writer_returns_read
  on public.return_requests
  for select to sports_store_return_request_writer
  using (customer_id = (select private.delivery_request_user_id()));
create policy return_request_writer_returns_insert
  on public.return_requests
  for insert to sports_store_return_request_writer
  with check (
    customer_id = (select private.delivery_request_user_id())
    and (select private.current_app_role()) = 'customer'
    and status = 'pending_review'::public.return_request_status
  );

create policy return_request_writer_events_insert
  on public.business_events
  for insert to sports_store_return_request_writer
  with check (
    actor_id = (select private.delivery_request_user_id())
    and subject_type = 'return_request'
    and from_state is null
    and to_state = 'pending_review'
    and request_id = id
    and incident_kind is null
    and task_id is null
    and exists (
      select 1 from public.return_requests r
      where r.id = subject_id
        and r.customer_id = (select private.delivery_request_user_id())
    )
  );

create policy return_request_writer_notifications_insert
  on public.notifications
  for insert to sports_store_return_request_writer
  with check (
    subject_type = 'return_request'
    and title = 'Yêu cầu trả hàng mới'
    and exists (
      select 1 from public.profiles p
      where p.id = recipient_id and p.role = 'manager'::public.user_role
    )
    and exists (
      select 1 from public.return_requests r
      where r.id = subject_id
        and r.customer_id = (select private.delivery_request_user_id())
    )
  );

-- 4. Read context for MH13 step 1 (SECURITY INVOKER: caller RLS applies).
create function public.get_return_request_context(p_order_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  l_uid uuid := auth.uid();
  l_now timestamptz := pg_catalog.now();
  l_order record;
  l_active record;
  l_deadline timestamptz;
  l_reason text;
  l_items jsonb;
begin
  if l_uid is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if p_order_id is null then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;
  if (select private.current_app_role()) is distinct from 'customer' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;

  select o.id, o.status::text as status, o.delivered_at, o.subtotal_vnd,
         o.delivery_fee_vnd, o.total_cod_vnd
    into l_order
  from public.orders o
  where o.id = p_order_id and o.customer_id = l_uid;
  if not found then
    raise exception using errcode = 'PT404', message = 'ORDER_NOT_FOUND';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'order_item_id', i.id,
           'product_name', i.product_name,
           'variant_label', i.variant_label,
           'quantity', i.quantity,
           'unit_price_vnd', i.unit_price_vnd,
           'line_total_vnd', i.line_total_vnd,
           'product_image_url', i.product_image_url
         ) order by i.created_at, i.id), '[]'::jsonb)
    into l_items
  from public.order_items i
  where i.order_id = p_order_id;

  select r.id, r.status::text as status, r.submitted_at
    into l_active
  from public.return_requests r
  where r.order_id = p_order_id
    and r.customer_id = l_uid
    and r.status in (
      'pending_review', 'awaiting_return_pickup', 'returning_to_store',
      'under_inspection', 'awaiting_refund', 'awaiting_redelivery',
      'redelivery_failed', 'manager_action_required'
    )
  limit 1;

  l_deadline := l_order.delivered_at + interval '7 days';
  l_reason := case
    when l_order.status <> 'delivered' or l_order.delivered_at is null
      then 'not_delivered'
    when l_active.id is not null then 'active_return_exists'
    when l_now > l_deadline then 'return_window_expired'
    else null
  end;

  return jsonb_build_object(
    'order_id', l_order.id,
    'order_status', l_order.status,
    'delivered_at', l_order.delivered_at,
    'subtotal_vnd', l_order.subtotal_vnd,
    'delivery_fee_vnd', l_order.delivery_fee_vnd,
    'total_paid_vnd', l_order.total_cod_vnd,
    'items', l_items,
    'server_now', l_now,
    'return_deadline', l_deadline,
    'can_submit_return', l_reason is null,
    'eligibility_reason', l_reason,
    'active_return', case when l_active.id is null then null
      else jsonb_build_object(
        'return_request_id', l_active.id,
        'status', l_active.status,
        'submitted_at', l_active.submitted_at
      ) end
  );
end;
$$;
revoke all on function public.get_return_request_context(uuid)
  from public, anon, service_role;
grant execute on function public.get_return_request_context(uuid)
  to authenticated;

-- 5. Atomic, idempotent submission.
create function public.submit_return_request(
  p_order_id uuid,
  p_request_id uuid,
  p_reason text,
  p_description text,
  p_video_object_path text,
  p_bank_name text,
  p_account_number text,
  p_account_holder text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  l_uid uuid;
  l_reason public.return_reason;
  l_description text;
  l_bank_name text;
  l_account_number text;
  l_account_holder text;
  l_existing record;
  l_order record;
  l_now timestamptz;
  l_return_id uuid;
  l_event_id uuid;
begin
  l_uid := (select private.delivery_request_user_id());
  if l_uid is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;

  -- Canonicalize before comparing replays so whitespace-only differences do
  -- not create a conflict.
  l_description := pg_catalog.regexp_replace(
    pg_catalog.btrim(coalesce(p_description, '')), '\s+', ' ', 'g');
  l_bank_name := pg_catalog.regexp_replace(
    pg_catalog.btrim(coalesce(p_bank_name, '')), '\s+', ' ', 'g');
  l_account_holder := pg_catalog.upper(pg_catalog.regexp_replace(
    pg_catalog.btrim(coalesce(p_account_holder, '')), '\s+', ' ', 'g'));
  l_account_number := pg_catalog.regexp_replace(
    coalesce(p_account_number, ''), '\s', '', 'g');

  if p_order_id is null
     or p_request_id is null
     or p_reason is null
     or p_reason not in ('defective', 'wrong_item', 'missing_items')
     or pg_catalog.char_length(l_description) not between 10 and 1000
     or pg_catalog.char_length(l_bank_name) not between 2 and 100
     or pg_catalog.char_length(l_account_holder) not between 2 and 100
     or l_account_number !~ '^[0-9]{6,20}$'
     or p_video_object_path is null then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;
  l_reason := p_reason::public.return_reason;

  if (select private.current_app_role()) is distinct from 'customer' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.submit_return_request:request:' || l_uid::text || ':'
      || p_request_id::text, 0));

  -- Replay: the (customer_id, request_id) unique key is the ledger.
  select r.id, r.order_id, r.status::text as status, r.reason::text as reason,
         r.description, r.video_object_path, r.submitted_at, r.bank_name,
         r.account_number, r.account_holder
    into l_existing
  from public.return_requests r
  where r.customer_id = l_uid and r.request_id = p_request_id;
  if found then
    if l_existing.order_id is distinct from p_order_id
       or l_existing.reason is distinct from p_reason
       or l_existing.description is distinct from l_description
       or l_existing.video_object_path is distinct from p_video_object_path
       or l_existing.bank_name is distinct from l_bank_name
       or l_existing.account_number is distinct from l_account_number
       or l_existing.account_holder is distinct from l_account_holder then
      raise exception using errcode = 'PT409', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object(
      'return_request_id', l_existing.id,
      'order_id', l_existing.order_id,
      'request_id', p_request_id,
      'status', l_existing.status,
      'reason', l_existing.reason,
      'submitted_at', l_existing.submitted_at,
      'replayed', true
    );
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.submit_return_request:order:' || p_order_id::text, 0));

  select o.id, o.status::text as status, o.delivered_at
    into l_order
  from public.orders o
  where o.id = p_order_id and o.customer_id = l_uid
  for update;
  if not found then
    raise exception using errcode = 'PT404', message = 'ORDER_NOT_FOUND';
  end if;
  if l_order.status <> 'delivered' or l_order.delivered_at is null then
    raise exception using errcode = 'PT409', message = 'ORDER_NOT_DELIVERED';
  end if;

  l_now := pg_catalog.clock_timestamp();
  if l_now > l_order.delivered_at + interval '7 days' then
    raise exception using errcode = 'PT409', message = 'RETURN_WINDOW_EXPIRED';
  end if;

  if exists (
    select 1 from public.return_requests r
    where r.order_id = p_order_id
      and r.status in (
        'pending_review', 'awaiting_return_pickup', 'returning_to_store',
        'under_inspection', 'awaiting_refund', 'awaiting_redelivery',
        'redelivery_failed', 'manager_action_required'
      )
  ) then
    raise exception using errcode = 'PT409', message = 'ACTIVE_RETURN_EXISTS';
  end if;

  -- <customer UUID>/<order UUID>/<file>, uploaded by this customer, video/*.
  if p_video_object_path !~ (
       '^' || l_uid::text || '/' || p_order_id::text || '/[A-Za-z0-9._-]{1,120}$')
     or p_video_object_path like '%..%'
     or not (select private.return_video_object_ready(p_video_object_path, l_uid)) then
    raise exception using errcode = 'PT422', message = 'VIDEO_REQUIRED';
  end if;
  if exists (
    select 1 from public.return_requests r
    where r.customer_id = l_uid and r.video_object_path = p_video_object_path
  ) then
    raise exception using errcode = 'PT409', message = 'VIDEO_ALREADY_USED';
  end if;

  l_return_id := pg_catalog.gen_random_uuid();
  begin
    insert into public.return_requests (
      id, order_id, customer_id, request_id, status, reason, description,
      video_object_path, submitted_at, bank_name, account_number,
      account_holder, created_at, updated_at
    ) values (
      l_return_id, p_order_id, l_uid, p_request_id,
      'pending_review'::public.return_request_status, l_reason, l_description,
      p_video_object_path, l_now, l_bank_name, l_account_number,
      l_account_holder, l_now, l_now
    );
  exception when unique_violation then
    raise exception using errcode = 'PT409', message = 'ACTIVE_RETURN_EXISTS';
  end;

  l_event_id := pg_catalog.gen_random_uuid();
  insert into public.business_events (
    id, actor_id, subject_type, subject_id, from_state, to_state, reason,
    request_id, created_at
  ) values (
    l_event_id, l_uid, 'return_request', l_return_id, null, 'pending_review',
    p_reason, l_event_id, l_now
  );

  insert into public.notifications (
    id, recipient_id, event_id, subject_type, subject_id, title, body,
    created_at
  )
  select pg_catalog.gen_random_uuid(), p.id, l_event_id, 'return_request',
         l_return_id, 'Yêu cầu trả hàng mới',
         'Khách hàng vừa gửi yêu cầu trả hàng cho một đơn đã giao.', l_now
  from public.profiles p
  where p.role = 'manager'::public.user_role;

  return jsonb_build_object(
    'return_request_id', l_return_id,
    'order_id', p_order_id,
    'request_id', p_request_id,
    'status', 'pending_review',
    'reason', p_reason,
    'submitted_at', l_now,
    'replayed', false
  );
end;
$$;

grant create on schema public to sports_store_return_request_writer;
alter function public.submit_return_request(
  uuid, uuid, text, text, text, text, text, text
) owner to sports_store_return_request_writer;
revoke create on schema public from sports_store_return_request_writer;
revoke all on function public.submit_return_request(
  uuid, uuid, text, text, text, text, text, text
) from public, anon, service_role, sports_store_return_request_writer;
grant execute on function public.submit_return_request(
  uuid, uuid, text, text, text, text, text, text
) to authenticated;

comment on function public.get_return_request_context(uuid) is
  'MH13 customer-only read: order snapshot, server time, 7-day deadline and eligibility under caller RLS.';
comment on function public.submit_return_request(
  uuid, uuid, text, text, text, text, text, text
) is
  'MH13 customer-only atomic return submission: ownership, delivered + 7-day window at submission, uploaded private video, one active return per order, idempotent by request_id, manager notifications.';

notify pgrst, 'reload schema';
