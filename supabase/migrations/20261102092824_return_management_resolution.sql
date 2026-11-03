-- Quản lý yêu cầu trả hàng, giai đoạn 2: yêu cầu bổ sung + phản hồi của
-- khách, kiểm tra chấp nhận (nhập kho đúng một lần), ghi hoàn tiền có chứng từ,
-- từ chối sau kiểm tra có bằng chứng. Nhận hàng tại cửa hàng, giao lại miễn
-- phí và phân công giao lại dùng các RPC production có sẵn
-- (receive_customer_return, reject_return_after_inspection,
-- assign_redelivery_task); file này không sửa chúng.
--
-- Không đổi COD: hoàn tiền cho khách không giảm nghĩa vụ COD của shipper.

-- 1. Ledger accepts the new operations.
alter table private.return_management_requests
  drop constraint return_management_requests_operation_valid;
alter table private.return_management_requests
  add constraint return_management_requests_operation_valid check (operation in (
    'approve_return_collection', 'reject_return_request',
    'request_return_info', 'respond_return_info',
    'accept_inspected_return', 'record_return_refund', 'reject_inspected_return'
  ));

-- 2. Information requests (manager asks, customer answers once).
create table private.return_info_requests (
  id uuid primary key default gen_random_uuid(),
  return_request_id uuid not null references public.return_requests (id),
  message text not null,
  requested_by uuid not null references public.profiles (id),
  requested_at timestamptz not null,
  response_text text,
  response_video_path text,
  responded_at timestamptz,
  constraint return_info_requests_message_valid
    check (length(btrim(message)) between 5 and 500),
  constraint return_info_requests_response_bundle check (
    (responded_at is null and response_text is null and response_video_path is null)
    or (responded_at is not null and length(btrim(response_text)) between 10 and 1000)
  )
);
create unique index return_info_requests_one_open
  on private.return_info_requests (return_request_id) where responded_at is null;
create index return_info_requests_return_idx
  on private.return_info_requests (return_request_id, requested_at);
alter table private.return_info_requests enable row level security;
alter table private.return_info_requests force row level security;
revoke all on private.return_info_requests
  from public, anon, authenticated, service_role;
grant select, insert, update on private.return_info_requests
  to sports_store_return_management_writer;
create policy return_info_manager_all
  on private.return_info_requests for all to sports_store_return_management_writer
  using ((select private.current_app_role()) = 'manager')
  with check ((select private.current_app_role()) = 'manager'
              and requested_by = (select private.delivery_request_user_id()));
create policy return_info_customer_read
  on private.return_info_requests for select to sports_store_return_management_writer
  using (exists (select 1 from public.return_requests r
                 where r.id = return_request_id
                   and r.customer_id = (select private.delivery_request_user_id())));
create policy return_info_customer_answer
  on private.return_info_requests for update to sports_store_return_management_writer
  using (responded_at is null and exists (
           select 1 from public.return_requests r
           where r.id = return_request_id
             and r.customer_id = (select private.delivery_request_user_id())))
  with check (responded_at is not null);

-- 3. Postgres-owned helpers returning only booleans (hosted projects do not
-- let custom roles read storage / pickup ledgers).
create function private.storage_object_exists(p_bucket text, p_path text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return exists (select 1 from storage.objects o
                 where o.bucket_id = p_bucket and o.name = p_path);
end;
$$;
revoke all on function private.storage_object_exists(text, text)
  from public, anon, authenticated, service_role;
grant execute on function private.storage_object_exists(text, text)
  to sports_store_return_management_writer;

create function private.return_pickup_handover_reported(p_task_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select private.current_app_role()) = 'manager'
     and exists (select 1 from private.return_pickup_handover_reports h
                 where h.task_id = p_task_id)
$$;
revoke all on function private.return_pickup_handover_reported(uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.return_pickup_handover_reported(uuid)
  to authenticated;

-- Manager-only read of the information requests for one return.
create function private.manager_return_info_requests(p_return_request_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when (select private.current_app_role()) = 'manager' then
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'message', q.message,
        'requested_at', q.requested_at,
        'response_text', q.response_text,
        'response_video_path', q.response_video_path,
        'responded_at', q.responded_at
      ) order by q.requested_at, q.id)
      from private.return_info_requests q
      where q.return_request_id = p_return_request_id
    ), '[]'::jsonb)
  else '[]'::jsonb end
$$;
revoke all on function private.manager_return_info_requests(uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.manager_return_info_requests(uuid)
  to authenticated;

-- 4. Writer privileges for the new commands.
grant execute on function private.return_video_object_ready(text, uuid)
  to sports_store_return_management_writer;
grant execute on function
  public.reject_return_after_inspection(uuid, uuid, text)
  to sports_store_return_management_writer;
grant select (full_name) on public.profiles to sports_store_return_management_writer;
grant select (total_cod_vnd) on public.orders to sports_store_return_management_writer;
grant select (video_object_path, additional_video_paths, inspected_at,
  inspection_evidence_paths) on public.return_requests
  to sports_store_return_management_writer;
grant update (additional_video_paths, inspected_at, inspected_by,
  inspection_evidence_paths, refund_amount_vnd, refunded_by, refunded_at,
  transfer_evidence_path, refund_request_id) on public.return_requests
  to sports_store_return_management_writer;
grant select (variant_id, quantity_collected, sellable_quantity, damaged_quantity)
  on public.return_items to sports_store_return_management_writer;
grant update (sellable_quantity, damaged_quantity, updated_at)
  on public.return_items to sports_store_return_management_writer;
grant select (id, on_hand, damaged) on public.product_variants
  to sports_store_return_management_writer;
grant update (on_hand, damaged, updated_at) on public.product_variants
  to sports_store_return_management_writer;
grant insert (variant_id, order_id, return_request_id, event_id, kind,
  on_hand_delta, reserved_delta, damaged_delta, actor_id, reason, created_at)
  on public.inventory_movements to sports_store_return_management_writer;
grant insert (task_id, incident_kind) on public.business_events
  to sports_store_return_management_writer;

create policy return_management_writer_profiles_managers
  on public.profiles for select to sports_store_return_management_writer
  using (role = 'manager'::public.user_role);
create policy return_management_writer_returns_customer_read
  on public.return_requests for select to sports_store_return_management_writer
  using (customer_id = (select private.delivery_request_user_id()));
create policy return_management_writer_returns_customer_update
  on public.return_requests for update to sports_store_return_management_writer
  using (customer_id = (select private.delivery_request_user_id())
         and (select private.current_app_role()) = 'customer')
  with check (customer_id = (select private.delivery_request_user_id())
              and status in ('pending_review'::public.return_request_status,
                             'under_inspection'::public.return_request_status));
create policy return_management_writer_returns_resolution
  on public.return_requests for update to sports_store_return_management_writer
  using ((select private.current_app_role()) = 'manager')
  with check ((select private.current_app_role()) = 'manager'
              and status in ('under_inspection'::public.return_request_status,
                             'awaiting_refund'::public.return_request_status,
                             'refunded'::public.return_request_status));
create policy return_management_writer_items_update
  on public.return_items for update to sports_store_return_management_writer
  using ((select private.current_app_role()) = 'manager')
  with check ((select private.current_app_role()) = 'manager');
create policy return_management_writer_variants_read
  on public.product_variants for select to sports_store_return_management_writer
  using ((select private.current_app_role()) = 'manager');
create policy return_management_writer_variants_update
  on public.product_variants for update to sports_store_return_management_writer
  using ((select private.current_app_role()) = 'manager')
  with check ((select private.current_app_role()) = 'manager');
create policy return_management_writer_movements_insert
  on public.inventory_movements for insert to sports_store_return_management_writer
  with check (
    (select private.current_app_role()) = 'manager'
    and actor_id = (select private.delivery_request_user_id())
    and kind = 'return_received'::public.inventory_movement_kind
    and return_request_id is not null
    and reserved_delta = 0 and on_hand_delta >= 0 and damaged_delta >= 0
  );
create policy return_management_writer_events_resolution
  on public.business_events for insert to sports_store_return_management_writer
  with check (
    actor_id = (select private.delivery_request_user_id())
    and subject_type = 'return_request'
    and request_id = id
    and incident_kind is null
    and task_id is null
    and reason in ('return_info_requested', 'return_info_provided',
                   'return_inspection_accepted', 'return_refund_recorded')
  );
create policy return_management_writer_notifications_resolution
  on public.notifications for insert to sports_store_return_management_writer
  with check (
    subject_type = 'return_request'
    and title in ('Cửa hàng cần bạn bổ sung thông tin',
                  'Khách đã bổ sung thông tin trả hàng',
                  'Hàng trả đã được kiểm tra',
                  'Đã hoàn tiền yêu cầu trả hàng')
  );

-- 5. Shared ledger helpers.
create function private.return_management_replay(
  p_actor uuid, p_request_id uuid, p_operation text, p_hash text
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  l_existing private.return_management_requests%rowtype;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'sports_store.return_management:request:' || p_actor::text || ':'
      || p_request_id::text, 0));
  select * into l_existing from private.return_management_requests m
  where m.actor_id = p_actor and m.request_id = p_request_id;
  if not found then
    return null;
  end if;
  if l_existing.operation <> p_operation or l_existing.payload_hash <> p_hash then
    raise exception using errcode = 'PT409', message = 'IDEMPOTENCY_CONFLICT';
  end if;
  return l_existing.response;
end;
$$;
revoke all on function private.return_management_replay(uuid, uuid, text, text)
  from public, anon, authenticated, service_role;
grant execute on function private.return_management_replay(uuid, uuid, text, text)
  to sports_store_return_management_writer;

create function private.notify_return_managers(
  p_event uuid, p_return_id uuid, p_title text, p_body text
)
returns void
language sql
set search_path = ''
as $$
  insert into public.notifications (recipient_id, event_id, subject_type, subject_id, title, body)
  select p.id, p_event, 'return_request', p_return_id, p_title, p_body
  from public.profiles p where p.role = 'manager'::public.user_role
$$;
revoke all on function private.notify_return_managers(uuid, uuid, text, text)
  from public, anon, authenticated, service_role;
grant execute on function private.notify_return_managers(uuid, uuid, text, text)
  to sports_store_return_management_writer;

-- 6. Manager asks the customer for more information (no state change).
create function public.request_return_info(
  p_return_request_id uuid, p_request_id uuid, p_message text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  l_actor uuid := private.require_manager();
  l_message text := btrim(coalesce(p_message, ''));
  l_payload jsonb;
  l_hash text;
  l_replay jsonb;
  l_return record;
  l_event uuid;
  l_now timestamptz;
  l_response jsonb;
begin
  if p_return_request_id is null or p_request_id is null
     or length(l_message) < 5 or length(l_message) > 500 then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;
  l_payload := jsonb_build_object('operation', 'request_return_info',
    'return_request_id', p_return_request_id, 'message', l_message);
  l_hash := md5(l_payload::text);
  l_replay := private.return_management_replay(l_actor, p_request_id,
    'request_return_info', l_hash);
  if l_replay is not null then return l_replay; end if;

  select r.id, r.customer_id, r.status into l_return
  from public.return_requests r where r.id = p_return_request_id for update;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  if l_return.status not in ('pending_review'::public.return_request_status,
                             'under_inspection'::public.return_request_status)
     or exists (select 1 from private.return_info_requests q
                where q.return_request_id = p_return_request_id
                  and q.responded_at is null) then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;

  l_now := pg_catalog.clock_timestamp();
  insert into private.return_info_requests (return_request_id, message, requested_by, requested_at)
  values (p_return_request_id, l_message, l_actor, l_now);
  l_event := pg_catalog.gen_random_uuid();
  insert into public.business_events (id, actor_id, subject_type, subject_id,
    from_state, to_state, reason, request_id, created_at)
  values (l_event, l_actor, 'return_request', p_return_request_id,
    l_return.status::text, l_return.status::text, 'return_info_requested', l_event, l_now);
  insert into public.notifications (recipient_id, event_id, subject_type, subject_id, title, body)
  values (l_return.customer_id, l_event, 'return_request', p_return_request_id,
    'Cửa hàng cần bạn bổ sung thông tin',
    'Mở yêu cầu trả hàng để xem nội dung cần bổ sung.');

  l_response := jsonb_build_object('operation', 'request_return_info',
    'return_request_id', p_return_request_id, 'return_status', l_return.status,
    'requested_at', l_now, 'event_id', l_event, 'request_id', p_request_id);
  insert into private.return_management_requests (actor_id, request_id, operation,
    return_request_id, payload, payload_hash, response)
  values (l_actor, p_request_id, 'request_return_info', p_return_request_id,
    l_payload, l_hash, l_response);
  return l_response;
end;
$$;

-- 7. Customer reads the latest information request of an owned return.
create function public.get_my_return_info_request(p_return_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  l_actor uuid := (select private.delivery_request_user_id());
  l_row record;
begin
  if l_actor is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if (select private.current_app_role()) is distinct from 'customer' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;
  if p_return_id is null then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;
  if not exists (select 1 from public.return_requests r
                 where r.id = p_return_id and r.customer_id = l_actor) then
    raise exception using errcode = 'PT404', message = 'RETURN_NOT_FOUND';
  end if;
  select q.message, q.requested_at, q.responded_at into l_row
  from private.return_info_requests q
  where q.return_request_id = p_return_id
  order by q.requested_at desc, q.id desc limit 1;
  if not found then
    return jsonb_build_object('info_request', null);
  end if;
  return jsonb_build_object('info_request', jsonb_build_object(
    'message', l_row.message,
    'requested_at', l_row.requested_at,
    'responded_at', l_row.responded_at));
end;
$$;

-- 8. Customer answers the open request (text + optional extra video).
create function public.respond_return_info(
  p_return_id uuid, p_request_id uuid, p_description text,
  p_video_object_path text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  l_actor uuid := (select private.delivery_request_user_id());
  l_text text := regexp_replace(btrim(coalesce(p_description, '')), '\s+', ' ', 'g');
  l_video text := nullif(btrim(coalesce(p_video_object_path, '')), '');
  l_payload jsonb;
  l_hash text;
  l_replay jsonb;
  l_return record;
  l_info record;
  l_event uuid;
  l_now timestamptz;
  l_response jsonb;
begin
  if l_actor is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if (select private.current_app_role()) is distinct from 'customer' then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;
  if p_return_id is null or p_request_id is null
     or length(l_text) < 10 or length(l_text) > 1000 then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;
  l_payload := jsonb_build_object('operation', 'respond_return_info',
    'return_request_id', p_return_id, 'description', l_text, 'video', l_video);
  l_hash := md5(l_payload::text);
  l_replay := private.return_management_replay(l_actor, p_request_id,
    'respond_return_info', l_hash);
  if l_replay is not null then return l_replay; end if;

  select r.id, r.status into l_return
  from public.return_requests r
  where r.id = p_return_id and r.customer_id = l_actor for update;
  if not found then
    raise exception using errcode = 'PT404', message = 'RETURN_NOT_FOUND';
  end if;
  select q.id into l_info from private.return_info_requests q
  where q.return_request_id = p_return_id and q.responded_at is null
  for update;
  if not found or l_return.status not in (
       'pending_review'::public.return_request_status,
       'under_inspection'::public.return_request_status) then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;
  if l_video is not null then
    if l_video not like l_actor::text || '/' || p_return_id::text || '/%'
       and l_video not like l_actor::text || '/%' then
      raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
    end if;
    if not private.return_video_object_ready(l_video, l_actor) then
      raise exception using errcode = 'PT422', message = 'VIDEO_REQUIRED';
    end if;
    if exists (select 1 from public.return_requests r
               where r.video_object_path = l_video
                  or l_video = any(r.additional_video_paths)) then
      raise exception using errcode = 'PT409', message = 'VIDEO_ALREADY_USED';
    end if;
  end if;

  l_now := pg_catalog.clock_timestamp();
  update private.return_info_requests
  set response_text = l_text, response_video_path = l_video, responded_at = l_now
  where id = l_info.id;
  if l_video is not null then
    update public.return_requests
    set additional_video_paths = additional_video_paths || l_video,
        updated_at = l_now
    where id = p_return_id;
  end if;
  l_event := pg_catalog.gen_random_uuid();
  insert into public.business_events (id, actor_id, subject_type, subject_id,
    from_state, to_state, reason, request_id, created_at)
  values (l_event, l_actor, 'return_request', p_return_id,
    l_return.status::text, l_return.status::text, 'return_info_provided', l_event, l_now);
  perform private.notify_return_managers(l_event, p_return_id,
    'Khách đã bổ sung thông tin trả hàng',
    'Mở quản lý yêu cầu trả hàng để xem phần bổ sung.');

  l_response := jsonb_build_object('operation', 'respond_return_info',
    'return_request_id', p_return_id, 'return_status', l_return.status,
    'responded_at', l_now, 'event_id', l_event, 'request_id', p_request_id);
  insert into private.return_management_requests (actor_id, request_id, operation,
    return_request_id, payload, payload_hash, response)
  values (l_actor, p_request_id, 'respond_return_info', p_return_id,
    l_payload, l_hash, l_response);
  return l_response;
end;
$$;

-- 9. Inspection accepted: split received goods into sellable (restocked once)
-- and damaged (kept out of sellable stock). Not a refund record.
create function public.accept_inspected_return(
  p_return_request_id uuid, p_request_id uuid, p_items jsonb,
  p_evidence_paths text[] default '{}'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  l_actor uuid := private.require_manager();
  l_items jsonb;
  l_paths text[] := coalesce(p_evidence_paths, '{}');
  l_payload jsonb;
  l_hash text;
  l_replay jsonb;
  l_return record;
  l_row record;
  l_count int;
  l_event uuid;
  l_now timestamptz;
  l_response jsonb;
begin
  if p_return_request_id is null or p_request_id is null or p_items is null
     or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0
     or cardinality(l_paths) > 10
     or array_position(l_paths, null) is not null
     or exists (select 1 from unnest(l_paths) x where btrim(x) = '') then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;
  begin
    select jsonb_agg(jsonb_build_object(
             'return_item_id', (e ->> 'return_item_id')::uuid,
             'sellable_quantity', (e ->> 'sellable_quantity')::bigint,
             'damaged_quantity', (e ->> 'damaged_quantity')::bigint)
           order by (e ->> 'return_item_id')::uuid)
      into l_items
    from jsonb_array_elements(p_items) e
    where jsonb_typeof(e) = 'object' and (select count(*) from jsonb_object_keys(e)) = 3;
  exception when others then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end;
  if l_items is null or jsonb_array_length(l_items) <> jsonb_array_length(p_items)
     or exists (select 1 from jsonb_array_elements(l_items) e
                where e ->> 'return_item_id' is null
                   or (e ->> 'sellable_quantity')::bigint < 0
                   or (e ->> 'damaged_quantity')::bigint < 0)
     or (select count(distinct e ->> 'return_item_id') from jsonb_array_elements(l_items) e)
        <> jsonb_array_length(l_items) then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;
  l_payload := jsonb_build_object('operation', 'accept_inspected_return',
    'return_request_id', p_return_request_id, 'items', l_items,
    'evidence', to_jsonb(l_paths));
  l_hash := md5(l_payload::text);
  l_replay := private.return_management_replay(l_actor, p_request_id,
    'accept_inspected_return', l_hash);
  if l_replay is not null then return l_replay; end if;

  select r.id, r.order_id, r.customer_id, r.status into l_return
  from public.return_requests r where r.id = p_return_request_id for update;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  if l_return.status <> 'under_inspection'::public.return_request_status
     or exists (select 1 from private.return_info_requests q
                where q.return_request_id = p_return_request_id and q.responded_at is null) then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;
  if exists (select 1 from unnest(l_paths) p
             where not private.storage_object_exists('inspection-evidence', p)) then
    raise exception using errcode = 'PT422', message = 'EVIDENCE_REQUIRED';
  end if;

  -- Exact cover of every received line; sellable + damaged = received.
  select count(*) into l_count from public.return_items i
  where i.return_request_id = p_return_request_id;
  if l_count <> jsonb_array_length(l_items) then
    raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
  end if;
  l_now := pg_catalog.clock_timestamp();
  l_event := pg_catalog.gen_random_uuid();
  perform 1 from public.return_items i
  where i.return_request_id = p_return_request_id
  order by i.id for update;
  for l_row in
    select i.id, i.variant_id, i.quantity_collected, i.sellable_quantity,
           i.damaged_quantity,
           (e ->> 'sellable_quantity')::bigint as sellable,
           (e ->> 'damaged_quantity')::bigint as damaged
    from jsonb_array_elements(l_items) e
    left join public.return_items i
      on i.id = (e ->> 'return_item_id')::uuid
     and i.return_request_id = p_return_request_id
    order by i.variant_id, i.id
  loop
    if l_row.id is null or l_row.quantity_collected <= 0
       or l_row.sellable + l_row.damaged <> l_row.quantity_collected
       or l_row.sellable_quantity <> 0 or l_row.damaged_quantity <> 0
       or (l_row.variant_id is null and l_row.sellable > 0) then
      raise exception using errcode = 'PT409', message = 'ITEMS_MISMATCH';
    end if;
    update public.return_items
    set sellable_quantity = l_row.sellable, damaged_quantity = l_row.damaged,
        updated_at = l_now
    where id = l_row.id;
  end loop;
  -- One movement per variant (event + variant is unique).
  for l_row in
    select i.variant_id, sum(i.sellable_quantity) as sellable,
           sum(i.damaged_quantity) as damaged
    from public.return_items i
    where i.return_request_id = p_return_request_id and i.variant_id is not null
    group by i.variant_id
    order by i.variant_id
  loop
    continue when l_row.sellable = 0 and l_row.damaged = 0;
    perform 1 from public.product_variants v where v.id = l_row.variant_id for update;
    update public.product_variants
    set on_hand = on_hand + l_row.sellable,
        damaged = damaged + l_row.damaged,
        updated_at = l_now
    where id = l_row.variant_id;
    insert into public.inventory_movements (variant_id, order_id, return_request_id,
      event_id, kind, on_hand_delta, reserved_delta, damaged_delta, actor_id, reason, created_at)
    values (l_row.variant_id, l_return.order_id, p_return_request_id, l_event,
      'return_received'::public.inventory_movement_kind, l_row.sellable, 0,
      l_row.damaged, l_actor, 'return_inspection_accepted', l_now);
  end loop;

  update public.return_requests
  set status = 'awaiting_refund'::public.return_request_status,
      inspected_at = l_now, inspected_by = l_actor,
      inspection_evidence_paths = l_paths, updated_at = l_now
  where id = p_return_request_id;
  insert into public.business_events (id, actor_id, subject_type, subject_id,
    from_state, to_state, reason, request_id, created_at)
  values (l_event, l_actor, 'return_request', p_return_request_id,
    'under_inspection', 'awaiting_refund', 'return_inspection_accepted', l_event, l_now);
  insert into public.notifications (recipient_id, event_id, subject_type, subject_id, title, body)
  values (l_return.customer_id, l_event, 'return_request', p_return_request_id,
    'Hàng trả đã được kiểm tra',
    'Yêu cầu được chấp nhận. Cửa hàng sẽ chuyển khoản hoàn tiền và cập nhật chứng từ.');

  l_response := jsonb_build_object('operation', 'accept_inspected_return',
    'return_request_id', p_return_request_id, 'return_status', 'awaiting_refund',
    'inspected_at', l_now, 'event_id', l_event, 'request_id', p_request_id);
  insert into private.return_management_requests (actor_id, request_id, operation,
    return_request_id, payload, payload_hash, response)
  values (l_actor, p_request_id, 'accept_inspected_return', p_return_request_id,
    l_payload, l_hash, l_response);
  return l_response;
end;
$$;

-- 10. Record the refund the manager transferred outside the app.
create function public.record_return_refund(
  p_return_request_id uuid, p_request_id uuid, p_amount_vnd bigint,
  p_transferred_at timestamptz, p_evidence_path text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  l_actor uuid := private.require_manager();
  l_path text := nullif(btrim(coalesce(p_evidence_path, '')), '');
  l_payload jsonb;
  l_hash text;
  l_replay jsonb;
  l_return record;
  l_total bigint;
  l_event uuid;
  l_now timestamptz;
  l_response jsonb;
begin
  if p_return_request_id is null or p_request_id is null or p_amount_vnd is null
     or p_amount_vnd <= 0 or p_transferred_at is null or l_path is null then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;
  l_payload := jsonb_build_object('operation', 'record_return_refund',
    'return_request_id', p_return_request_id, 'amount_vnd', p_amount_vnd,
    'transferred_at', p_transferred_at, 'evidence', l_path);
  l_hash := md5(l_payload::text);
  l_replay := private.return_management_replay(l_actor, p_request_id,
    'record_return_refund', l_hash);
  if l_replay is not null then return l_replay; end if;

  select r.id, r.order_id, r.customer_id, r.status, r.inspected_at into l_return
  from public.return_requests r where r.id = p_return_request_id for update;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  if l_return.status <> 'awaiting_refund'::public.return_request_status then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;
  select o.total_cod_vnd into l_total from public.orders o where o.id = l_return.order_id;
  if p_amount_vnd <> l_total then
    raise exception using errcode = 'PT409', message = 'AMOUNT_MISMATCH';
  end if;
  l_now := pg_catalog.clock_timestamp();
  if p_transferred_at > l_now + interval '5 minutes'
     or p_transferred_at < l_return.inspected_at then
    raise exception using errcode = '22023', message = 'INVALID_TRANSFER_TIME';
  end if;
  if not private.storage_object_exists('refund-evidence', l_path) then
    raise exception using errcode = 'PT422', message = 'EVIDENCE_REQUIRED';
  end if;

  update public.return_requests
  set status = 'refunded'::public.return_request_status,
      refund_amount_vnd = p_amount_vnd, refunded_by = l_actor,
      refunded_at = p_transferred_at, transfer_evidence_path = l_path,
      refund_request_id = p_request_id, closed_at = l_now, updated_at = l_now
  where id = p_return_request_id;
  l_event := pg_catalog.gen_random_uuid();
  insert into public.business_events (id, actor_id, subject_type, subject_id,
    from_state, to_state, reason, request_id, created_at)
  values (l_event, l_actor, 'return_request', p_return_request_id,
    'awaiting_refund', 'refunded', 'return_refund_recorded', l_event, l_now);
  insert into public.notifications (recipient_id, event_id, subject_type, subject_id, title, body)
  values (l_return.customer_id, l_event, 'return_request', p_return_request_id,
    'Đã hoàn tiền yêu cầu trả hàng',
    'Cửa hàng đã chuyển khoản hoàn đủ tiền hàng và phí giao ban đầu.');

  l_response := jsonb_build_object('operation', 'record_return_refund',
    'return_request_id', p_return_request_id, 'return_status', 'refunded',
    'amount_vnd', p_amount_vnd, 'refunded_at', p_transferred_at,
    'event_id', l_event, 'request_id', p_request_id);
  insert into private.return_management_requests (actor_id, request_id, operation,
    return_request_id, payload, payload_hash, response)
  values (l_actor, p_request_id, 'record_return_refund', p_return_request_id,
    l_payload, l_hash, l_response);
  return l_response;
end;
$$;

-- 11. Reject after inspection with supporting evidence, then the production
-- primitive snapshots the goods for free redelivery.
create function public.reject_inspected_return(
  p_return_request_id uuid, p_request_id uuid, p_reason text,
  p_evidence_paths text[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  l_actor uuid := private.require_manager();
  l_reason text := btrim(coalesce(p_reason, ''));
  l_paths text[] := coalesce(p_evidence_paths, '{}');
  l_payload jsonb;
  l_hash text;
  l_replay jsonb;
  l_return record;
  l_inner jsonb;
  l_response jsonb;
begin
  if p_return_request_id is null or p_request_id is null
     or length(l_reason) < 5 or length(l_reason) > 500
     or cardinality(l_paths) = 0 or cardinality(l_paths) > 10
     or array_position(l_paths, null) is not null
     or exists (select 1 from unnest(l_paths) x where btrim(x) = '') then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;
  l_payload := jsonb_build_object('operation', 'reject_inspected_return',
    'return_request_id', p_return_request_id, 'reason', l_reason,
    'evidence', to_jsonb(l_paths));
  l_hash := md5(l_payload::text);
  l_replay := private.return_management_replay(l_actor, p_request_id,
    'reject_inspected_return', l_hash);
  if l_replay is not null then return l_replay; end if;

  select r.id, r.status into l_return
  from public.return_requests r where r.id = p_return_request_id for update;
  if not found then
    raise exception using errcode = '42501', message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;
  if l_return.status <> 'under_inspection'::public.return_request_status
     or exists (select 1 from private.return_info_requests q
                where q.return_request_id = p_return_request_id and q.responded_at is null) then
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;
  if exists (select 1 from unnest(l_paths) p
             where not private.storage_object_exists('inspection-evidence', p)) then
    raise exception using errcode = 'PT422', message = 'EVIDENCE_REQUIRED';
  end if;
  update public.return_requests
  set inspection_evidence_paths = l_paths
  where id = p_return_request_id;
  l_inner := public.reject_return_after_inspection(
    p_return_request_id,
    private.return_management_derived_uuid(p_request_id, 'reject_inspected'),
    l_reason);

  l_response := jsonb_build_object('operation', 'reject_inspected_return',
    'return_request_id', p_return_request_id,
    'return_status', coalesce(l_inner ->> 'return_status', 'awaiting_redelivery'),
    'event_id', l_inner ->> 'event_id', 'request_id', p_request_id);
  insert into private.return_management_requests (actor_id, request_id, operation,
    return_request_id, payload, payload_hash, response)
  values (l_actor, p_request_id, 'reject_inspected_return', p_return_request_id,
    l_payload, l_hash, l_response);
  return l_response;
end;
$$;

-- 12. Ownership/grants for the new commands.
grant create on schema public to sports_store_return_management_writer;
alter function public.request_return_info(uuid, uuid, text)
  owner to sports_store_return_management_writer;
alter function public.get_my_return_info_request(uuid)
  owner to sports_store_return_management_writer;
alter function public.respond_return_info(uuid, uuid, text, text)
  owner to sports_store_return_management_writer;
alter function public.accept_inspected_return(uuid, uuid, jsonb, text[])
  owner to sports_store_return_management_writer;
alter function public.record_return_refund(uuid, uuid, bigint, timestamptz, text)
  owner to sports_store_return_management_writer;
alter function public.reject_inspected_return(uuid, uuid, text, text[])
  owner to sports_store_return_management_writer;
revoke create on schema public from sports_store_return_management_writer;
revoke all on function
  public.request_return_info(uuid, uuid, text),
  public.get_my_return_info_request(uuid),
  public.respond_return_info(uuid, uuid, text, text),
  public.accept_inspected_return(uuid, uuid, jsonb, text[]),
  public.record_return_refund(uuid, uuid, bigint, timestamptz, text),
  public.reject_inspected_return(uuid, uuid, text, text[])
  from public, anon;
grant execute on function
  public.request_return_info(uuid, uuid, text),
  public.get_my_return_info_request(uuid),
  public.respond_return_info(uuid, uuid, text, text),
  public.accept_inspected_return(uuid, uuid, jsonb, text[]),
  public.record_return_refund(uuid, uuid, bigint, timestamptz, text),
  public.reject_inspected_return(uuid, uuid, text, text[])
  to authenticated;

-- 13. Detail read gains info requests, evidence, refund, redelivery and the
-- handover flag (same signature; replaces the phase-1 body).
create or replace function public.get_manager_return_request(p_return_request_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  l_return public.return_requests%rowtype;
  l_order public.orders%rowtype;
  l_customer jsonb;
  l_pickup jsonb;
  l_redelivery jsonb;
begin
  perform private.require_manager();
  if p_return_request_id is null then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;
  select r.* into l_return from public.return_requests r
  where r.id = p_return_request_id;
  if not found then
    raise exception using errcode = 'PT404', message = 'RETURN_NOT_FOUND';
  end if;
  select o.* into strict l_order from public.orders o where o.id = l_return.order_id;

  select jsonb_build_object(
    'name', coalesce(nullif(btrim(p.full_name), ''), 'Khách hàng'),
    'phone', nullif(btrim(p.phone), '')
  ) into l_customer
  from public.profiles p where p.id = l_return.customer_id;

  select jsonb_build_object(
    'task_id', t.id, 'status', t.status, 'shipper_id', t.assigned_shipper_id,
    'shipper_name', coalesce(nullif(btrim(sp.full_name), ''), 'Shipper'),
    'shipper_phone', nullif(btrim(sp.phone), ''),
    'assigned_at', t.assigned_at, 'completed_at', t.completed_at,
    'failure_reason', t.failure_reason,
    'handover_reported', private.return_pickup_handover_reported(t.id)
  ) into l_pickup
  from public.delivery_tasks t
  left join public.profiles sp on sp.id = t.assigned_shipper_id
  where t.return_request_id = l_return.id
    and t.kind = 'return_pickup'::public.delivery_task_kind
  order by t.created_at desc, t.id
  limit 1;

  select jsonb_build_object(
    'task_id', t.id, 'status', t.status, 'shipper_id', t.assigned_shipper_id,
    'shipper_name', coalesce(nullif(btrim(sp.full_name), ''), 'Shipper'),
    'shipper_phone', nullif(btrim(sp.phone), ''),
    'assigned_at', t.assigned_at, 'completed_at', t.completed_at,
    'failure_reason', t.failure_reason,
    'handover_reported', false
  ) into l_redelivery
  from public.delivery_tasks t
  left join public.profiles sp on sp.id = t.assigned_shipper_id
  where t.return_request_id = l_return.id
    and t.kind = 'redelivery'::public.delivery_task_kind
  order by t.created_at desc, t.id
  limit 1;

  return jsonb_build_object(
    'return_id', l_return.id,
    'order_id', l_return.order_id,
    'status', l_return.status,
    'reason', l_return.reason,
    'description', l_return.description,
    'submitted_at', l_return.submitted_at,
    'decision_reason', l_return.decision_reason,
    'decision_at', l_return.decision_at,
    'inspection_started_at', l_return.inspection_started_at,
    'inspected_at', l_return.inspected_at,
    'closed_at', l_return.closed_at,
    'customer', coalesce(l_customer, jsonb_build_object('name', 'Khách hàng', 'phone', null)),
    'recipient', jsonb_build_object(
      'name', l_order.recipient_name,
      'phone', l_order.recipient_phone,
      'address', l_order.address_detail
    ),
    'delivered_at', l_order.delivered_at,
    'subtotal_vnd', l_order.subtotal_vnd,
    'delivery_fee_vnd', l_order.delivery_fee_vnd,
    'total_vnd', l_order.total_cod_vnd,
    'order_items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'order_item_id', oi.id, 'product_name', oi.product_name,
        'variant_label', oi.variant_label, 'quantity', oi.quantity,
        'unit_price_vnd', oi.unit_price_vnd, 'line_total_vnd', oi.line_total_vnd,
        'image_url', oi.product_image_url
      ) order by oi.created_at, oi.id)
      from public.order_items oi where oi.order_id = l_return.order_id
    ), '[]'::jsonb),
    'return_items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'return_item_id', i.id, 'order_item_id', i.order_item_id,
        'name', i.actual_item_name,
        'quantity_to_collect', i.quantity_to_collect,
        'quantity_collected', i.quantity_collected,
        'sellable_quantity', i.sellable_quantity,
        'damaged_quantity', i.damaged_quantity
      ) order by i.id)
      from public.return_items i where i.return_request_id = l_return.id
    ), '[]'::jsonb),
    'video_paths', to_jsonb(array[l_return.video_object_path] || l_return.additional_video_paths),
    'inspection_evidence_paths', to_jsonb(l_return.inspection_evidence_paths),
    'bank', case when l_return.bank_name is null then null else jsonb_build_object(
      'bank_name', l_return.bank_name,
      'account_number', l_return.account_number,
      'account_holder', l_return.account_holder
    ) end,
    'refund', case when l_return.refunded_at is null then null else jsonb_build_object(
      'amount_vnd', l_return.refund_amount_vnd,
      'refunded_at', l_return.refunded_at,
      'evidence_path', l_return.transfer_evidence_path
    ) end,
    'info_requests', private.manager_return_info_requests(l_return.id),
    'pickup_task', l_pickup,
    'redelivery_task', l_redelivery,
    'shippers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'shipper_id', p.id,
        'name', coalesce(nullif(btrim(p.full_name), ''), 'Shipper'),
        'phone', nullif(btrim(p.phone), '')
      ) order by p.full_name nulls last, p.id)
      from public.profiles p where p.role = 'shipper'::public.user_role
    ), '[]'::jsonb),
    'server_now', pg_catalog.now()
  );
end;
$$;
