-- P03.1 authorized task-detail projection contract.
-- TEST FIXTURE ONLY. The runner executes this in an isolated, rolled-back
-- transaction. It is not a Supabase seed or a deployment script.

begin;
set constraints all deferred;

create or replace function pg_temp.set_detail_claims(
  p_user_id uuid,
  p_claimed_role text default 'authenticated'
) returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', p_user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', p_user_id::text,
      'role', p_claimed_role,
      'aud', p_claimed_role
    )::text,
    true
  );
end;
$$;

create or replace function pg_temp.clear_detail_claims()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
end;
$$;

create or replace function pg_temp.assert_detail(
  p_label text,
  p_condition boolean
) returns void
language plpgsql
as $$
begin
  if coalesce(p_condition, false) is not true then
    raise exception 'delivery task detail test failed: %', p_label;
  end if;
end;
$$;

create or replace function pg_temp.assert_detail_error(
  p_label text,
  p_sql text,
  p_state text,
  p_message text default null
) returns void
language plpgsql
as $$
declare
  l_state text;
  l_message text;
begin
  begin
    execute p_sql;
  exception
    when others then
      get stacked diagnostics
        l_state = returned_sqlstate,
        l_message = message_text;
  end;

  if l_state is distinct from p_state then
    raise exception
      'delivery task detail test failed: % (expected SQLSTATE %, got %: %)',
      p_label, p_state, coalesce(l_state, 'success'), coalesce(l_message, '');
  end if;
  if p_message is not null and l_message is distinct from p_message then
    raise exception
      'delivery task detail test failed: % (expected message %, got %)',
      p_label, p_message, coalesce(l_message, '');
  end if;
end;
$$;

-- Fixture identities. Server-managed profiles, rather than editable JWT
-- claims, determine who is a shipper.
insert into auth.users (id, email)
values
  ('11000000-0000-0000-0000-000000000001'::uuid, 'detail-customer-a@example.invalid'),
  ('11000000-0000-0000-0000-000000000002'::uuid, 'detail-customer-b@example.invalid'),
  ('11000000-0000-0000-0000-000000000003'::uuid, 'detail-manager@example.invalid'),
  ('11000000-0000-0000-0000-000000000004'::uuid, 'detail-shipper-a@example.invalid'),
  ('11000000-0000-0000-0000-000000000005'::uuid, 'detail-shipper-b@example.invalid');

update public.profiles
set full_name = case id
  when '11000000-0000-0000-0000-000000000001'::uuid then 'Detail Customer A'
  when '11000000-0000-0000-0000-000000000002'::uuid then 'Detail Customer B'
  when '11000000-0000-0000-0000-000000000003'::uuid then 'Detail Manager'
  when '11000000-0000-0000-0000-000000000004'::uuid then 'Detail Shipper A'
  when '11000000-0000-0000-0000-000000000005'::uuid then 'Detail Shipper B'
end,
role = case
  when id in (
    '11000000-0000-0000-0000-000000000004'::uuid,
    '11000000-0000-0000-0000-000000000005'::uuid
  ) then 'shipper'::public.user_role
  when id = '11000000-0000-0000-0000-000000000003'::uuid
    then 'manager'::public.user_role
  else 'customer'::public.user_role
end
where id in (
  '11000000-0000-0000-0000-000000000001'::uuid,
  '11000000-0000-0000-0000-000000000002'::uuid,
  '11000000-0000-0000-0000-000000000003'::uuid,
  '11000000-0000-0000-0000-000000000004'::uuid,
  '11000000-0000-0000-0000-000000000005'::uuid
);

insert into public.categories (id, code, name)
values ('21000000-0000-0000-0000-000000000001'::uuid, 'detail', 'Detail fixtures');

insert into public.products (id, category_id, name, description, image_path)
values (
  '31000000-0000-0000-0000-000000000001'::uuid,
  '21000000-0000-0000-0000-000000000001'::uuid,
  'Detail product',
  'This description must never cross the shipper detail projection.',
  'private/product-image-secret.png'
);

-- 1001 variants/items deliberately exercise complete server-side aggregation;
-- the old Dart list adapter's 200-row page limit and PostgREST max_rows 1000
-- must not truncate this API.
insert into public.product_variants (
  id, product_id, sku, label, attributes, price_vnd
)
select
  ('41000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  '31000000-0000-0000-0000-000000000001'::uuid,
  format('DETAIL-%03s', n),
  format('Variant %s', n),
  jsonb_build_object('fixture', n),
  1000 + n
from generate_series(1, 1001) as numbers(n);

insert into public.orders (
  id, customer_id, request_id, status, recipient_name, recipient_phone,
  address_detail, latitude, longitude, subtotal_vnd, delivery_fee_vnd
)
select
  ('61000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  '11000000-0000-0000-0000-000000000001'::uuid,
  ('a6000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  case when n in (3, 8) then 'awaiting_redelivery'::public.order_status
       else 'delivered'::public.order_status end,
  case when n = 1 then 'Detail Recipient' else format('Recipient %s', n) end,
  format('09000004%02s', n),
  format('Detail address %s, Ha Noi', n),
  21.030000 + n / 100000.0,
  105.800000 + n / 100000.0,
  530000,
  30000
from generate_series(1, 8) as numbers(n);

insert into public.order_items (
  id, order_id, product_id, variant_id, product_name, variant_label,
  attributes, unit_price_vnd, quantity
)
select
  ('51000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  '61000000-0000-0000-0000-000000000001'::uuid,
  '31000000-0000-0000-0000-000000000001'::uuid,
  ('41000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  format('Snapshot item %s', n),
  format('Variant %s', n),
  jsonb_build_object('fixture', n),
  1000 + n,
  1
from generate_series(1, 1001) as numbers(n);

insert into public.return_requests (
  id, order_id, customer_id, request_id, status, reason, description,
  video_object_path
)
values
  (
    '91000000-0000-0000-0000-000000000002'::uuid,
    '61000000-0000-0000-0000-000000000002'::uuid,
    '11000000-0000-0000-0000-000000000001'::uuid,
    'a7000000-0000-0000-0000-000000000002'::uuid,
    'awaiting_return_pickup', 'defective', 'Return detail fixture',
    'private/return-video-secret.mp4'
  ),
  (
    '91000000-0000-0000-0000-000000000003'::uuid,
    '61000000-0000-0000-0000-000000000003'::uuid,
    '11000000-0000-0000-0000-000000000001'::uuid,
    'a7000000-0000-0000-0000-000000000003'::uuid,
    'awaiting_redelivery', 'wrong_item', 'Redelivery detail fixture',
    'private/redelivery-video-secret.mp4'
  );

insert into public.return_items (
  id, return_request_id, order_id, actual_item_name, quantity_to_collect,
  quantity_collected
)
values
  (
    '92000000-0000-0000-0000-000000000001'::uuid,
    '91000000-0000-0000-0000-000000000002'::uuid,
    '61000000-0000-0000-0000-000000000002'::uuid,
    'Returned jersey', 2, 1
  ),
  (
    '92000000-0000-0000-0000-000000000002'::uuid,
    '91000000-0000-0000-0000-000000000002'::uuid,
    '61000000-0000-0000-0000-000000000002'::uuid,
    'Returned shorts', 1, 0
  );

-- Sensitive evidence/refund fields exist in the merged return-request schema
-- but are not a source for this API.
update public.return_requests
set inspection_evidence_paths = array['private/inspection-video-secret.mp4'],
    additional_video_paths = array['private/evidence-video-secret.mp4'],
    bank_name = 'Secret Bank',
    account_number = 'SECRET-ACCOUNT',
    account_holder = 'Secret Holder',
    refund_amount_vnd = 1000,
    refunded_by = '11000000-0000-0000-0000-000000000003'::uuid,
    refunded_at = now(),
    transfer_evidence_path = 'private/refund-bank-evidence-secret.pdf',
    refund_request_id = 'a8000000-0000-0000-0000-000000000002'::uuid
where id = '91000000-0000-0000-0000-000000000002'::uuid;

insert into public.delivery_tasks (
  id, order_id, return_request_id, kind, assigned_shipper_id, assigned_by,
  status, attempt_number, destination_name, destination_phone,
  destination_address, destination_latitude, destination_longitude,
  amount_to_collect_vnd, assigned_at, accepted_at, started_at, completed_at,
  created_at, updated_at
)
values
  (
    '81000000-0000-0000-0000-000000000001'::uuid,
    '61000000-0000-0000-0000-000000000001'::uuid,
    null, 'outbound',
    '11000000-0000-0000-0000-000000000004'::uuid,
    '11000000-0000-0000-0000-000000000003'::uuid,
    'in_transit', 1, 'Detail Recipient', '0900000401',
    'Detail address 1, Ha Noi', 21.031000, 105.801000, 560000,
    now() - interval '5 minutes', now() - interval '4 minutes',
    now() - interval '3 minutes', null, now() - interval '5 minutes',
    now() - interval '3 minutes'
  ),
  (
    '81000000-0000-0000-0000-000000000002'::uuid,
    '61000000-0000-0000-0000-000000000002'::uuid,
    '91000000-0000-0000-0000-000000000002'::uuid, 'return_pickup',
    '11000000-0000-0000-0000-000000000004'::uuid,
    '11000000-0000-0000-0000-000000000003'::uuid,
    'assigned', 1, 'Pickup Recipient', '0900000402',
    'Detail address 2, Ha Noi', 21.032000, 105.802000, 0,
    now() - interval '4 minutes', null, null, null,
    now() - interval '4 minutes', now() - interval '4 minutes'
  ),
  (
    '81000000-0000-0000-0000-000000000003'::uuid,
    '61000000-0000-0000-0000-000000000003'::uuid,
    '91000000-0000-0000-0000-000000000003'::uuid, 'redelivery',
    '11000000-0000-0000-0000-000000000004'::uuid,
    '11000000-0000-0000-0000-000000000003'::uuid,
    'accepted', 1, 'Redelivery Recipient', '0900000403',
    'Detail address 3, Ha Noi', 21.033000, 105.803000, 0,
    now() - interval '3 minutes', now() - interval '2 minutes', null, null,
    now() - interval '3 minutes', now() - interval '2 minutes'
  ),
  (
    '81000000-0000-0000-0000-000000000004'::uuid,
    '61000000-0000-0000-0000-000000000001'::uuid,
    null, 'outbound',
    '11000000-0000-0000-0000-000000000004'::uuid,
    '11000000-0000-0000-0000-000000000003'::uuid,
    'delivered', 1, 'History Recipient', '0900000404',
    'History address, Ha Noi', 21.034000, 105.804000, 560000,
    now() - interval '10 minutes', now() - interval '9 minutes',
    now() - interval '8 minutes', now() - interval '7 minutes',
    now() - interval '10 minutes', now() - interval '7 minutes'
  ),
  (
    '81000000-0000-0000-0000-000000000005'::uuid,
    '61000000-0000-0000-0000-000000000005'::uuid,
    null, 'outbound',
    '11000000-0000-0000-0000-000000000004'::uuid,
    '11000000-0000-0000-0000-000000000003'::uuid,
    'failed', 1, 'Restricted Recipient', '0900000405',
    'Restricted address, Ha Noi', 21.035000, 105.805000, 560000,
    now() - interval '9 minutes', null, null, now() - interval '8 minutes',
    now() - interval '9 minutes', now() - interval '8 minutes'
  ),
  (
    '81000000-0000-0000-0000-000000000006'::uuid,
    '61000000-0000-0000-0000-000000000006'::uuid,
    null, 'outbound',
    '11000000-0000-0000-0000-000000000004'::uuid,
    '11000000-0000-0000-0000-000000000003'::uuid,
    'cancelled', 1, 'Cancelled Recipient', '0900000406',
    'Cancelled address, Ha Noi', 21.036000, 105.806000, 560000,
    now() - interval '8 minutes', null, null, now() - interval '7 minutes',
    now() - interval '8 minutes', now() - interval '7 minutes'
  ),
  (
    '81000000-0000-0000-0000-000000000007'::uuid,
    '61000000-0000-0000-0000-000000000007'::uuid,
    null, 'outbound',
    '11000000-0000-0000-0000-000000000005'::uuid,
    '11000000-0000-0000-0000-000000000003'::uuid,
    'assigned', 1, 'Foreign Recipient', '0900000407',
    'Foreign address, Ha Noi', 21.037000, 105.807000, 560000,
    now() - interval '7 minutes', null, null, null,
    now() - interval '7 minutes', now() - interval '7 minutes'
  ),
  (
    '81000000-0000-0000-0000-000000000008'::uuid,
    '61000000-0000-0000-0000-000000000008'::uuid,
    null, 'outbound',
    '11000000-0000-0000-0000-000000000004'::uuid,
    '11000000-0000-0000-0000-000000000003'::uuid,
    'assigned', 2, 'Reassigned Recipient', '0900000408',
    'Reassigned address, Ha Noi', 21.038000, 105.808000, 560000,
    now() - interval '6 minutes', null, null, null,
    now() - interval '6 minutes', now() - interval '6 minutes'
  );

-- Current outbound projection: exact P01.1 task shape, authoritative COD,
-- optional lifecycle values, and all 1001 item rows in item_id order.
set local role authenticated;
select pg_temp.set_detail_claims(
  '11000000-0000-0000-0000-000000000004'::uuid
);

do $$
declare
  l_function oid := 'public.get_my_delivery_task(uuid)'::regprocedure;
  l_reader oid := 'sports_store_delivery_reader'::regrole;
  l_owner text;
  l_security_definer boolean;
  l_volatility "char";
  l_config text[];
begin
  select
    p.proowner::regrole::text,
    p.prosecdef,
    p.provolatile,
    p.proconfig
  into l_owner, l_security_definer, l_volatility, l_config
  from pg_proc p
  where p.oid = l_function;

  perform pg_temp.assert_detail('detail function exists', l_owner is not null);
  perform pg_temp.assert_detail(
    'detail owner is the existing locked reader role',
    l_owner = 'sports_store_delivery_reader'
  );
  perform pg_temp.assert_detail(
    'detail function is SECURITY DEFINER and STABLE',
    l_security_definer and l_volatility = 's'
  );
  perform pg_temp.assert_detail(
    'detail function locks search_path to empty',
    l_config = array['search_path=""']
  );
  perform pg_temp.assert_detail(
    'authenticated is the only API grantee',
    has_function_privilege('authenticated', l_function, 'EXECUTE')
    and not has_function_privilege('anon', l_function, 'EXECUTE')
    and not has_function_privilege('service_role', l_function, 'EXECUTE')
    and not exists (
      select 1
      from aclexplode((select p.proacl from pg_proc p where p.oid = l_function)) a
      where a.grantee = 0
        and a.privilege_type = 'EXECUTE'
    )
  );
  perform pg_temp.assert_detail(
    'reader role remains NOLOGIN NOINHERIT and NOBYPASSRLS',
    (select not r.rolcanlogin
            and not r.rolinherit
            and not r.rolbypassrls
            and not r.rolsuper
            and not r.rolcreaterole
            and not r.rolcreatedb
            and not r.rolreplication
       from pg_roles r
       where r.oid = l_reader)
  );
  perform pg_temp.assert_detail(
    'reader membership remains only the existing postgres owner grant',
    (select count(*) from pg_auth_members m where m.roleid = l_reader) = 1
    and exists (
      select 1
      from pg_auth_members m
      where m.roleid = l_reader
        and m.member = 'postgres'::regrole
    )
    and not exists (
      select 1
      from pg_auth_members m
      join pg_roles granted on granted.oid = m.roleid
      where m.member = l_reader
        and granted.rolbypassrls
    )
  );
end;
$$;

do $$
declare
  l_detail jsonb;
  l_task jsonb;
  l_items jsonb;
begin
  l_detail := public.get_my_delivery_task(
    '81000000-0000-0000-0000-000000000001'::uuid
  );
  l_task := l_detail -> 'task';
  l_items := l_detail -> 'items';
  perform pg_temp.assert_detail('outer shape has exactly five keys',
    (select count(*) from jsonb_object_keys(l_detail)) = 5
    and l_detail ?& array['task', 'items', 'notes', 'notes_source', 'as_of']);
  perform pg_temp.assert_detail('task has exactly the P01.1 projection keys',
    (select count(*) from jsonb_object_keys(l_task)) = 18
    and l_task ?& array[
      'task_id', 'kind', 'status', 'attempt_number', 'snapshot_scope',
      'order_id', 'return_request_id', 'amount_to_collect_vnd',
      'destination_name', 'destination_phone', 'destination_address',
      'destination_latitude', 'destination_longitude', 'assigned_at',
      'accepted_at', 'started_at', 'completed_at', 'item_source'
    ]);
  perform pg_temp.assert_detail('server-authoritative current task values',
    l_task ->> 'task_id' = '81000000-0000-0000-0000-000000000001'
    and l_task ->> 'kind' = 'outbound'
    and l_task ->> 'status' = 'in_transit'
    and (l_task ->> 'attempt_number')::int = 1
    and l_task ->> 'snapshot_scope' = 'current'
    and l_task ->> 'amount_to_collect_vnd' = '560000'
    and l_task ->> 'item_source' = 'order_snapshot');
  perform pg_temp.assert_detail('optional lifecycle values are preserved',
    l_task ->> 'accepted_at' is not null
    and l_task ->> 'started_at' is not null
    and l_task ->> 'completed_at' is null);
  perform pg_temp.assert_detail('notes are explicit unavailable-schema nulls',
    l_detail -> 'notes' = 'null'::jsonb
    and l_detail ->> 'notes_source' = 'unavailable_schema'
    and jsonb_typeof(l_detail -> 'as_of') = 'string');
  perform pg_temp.assert_detail('all 1001 item rows are aggregated beyond API max_rows',
    jsonb_array_length(l_items) = 1001
    and l_items -> 0 ->> 'item_id' = '51000000-0000-0000-0000-000000000001'
    and l_items -> 1000 ->> 'item_id' = '51000000-0000-0000-0000-000000001001');
  perform pg_temp.assert_detail('item shape and snapshot values are exact',
    (select count(*) from jsonb_object_keys(l_items -> 0)) = 9
    and (l_items -> 0) ?& array[
      'item_id', 'item_source', 'product_name', 'variant_label', 'attributes',
      'quantity', 'quantity_collected', 'unit_price_vnd', 'line_total_vnd'
    ]
    and l_items -> 0 ->> 'item_source' = 'order_snapshot'
    and l_items -> 0 ->> 'product_name' = 'Snapshot item 1'
    and (l_items -> 0 ->> 'quantity')::int = 1
    and (l_items -> 0 ->> 'unit_price_vnd')::int = 1001);
  perform pg_temp.assert_detail('sensitive sources are absent',
    l_detail::text !~* '(video|bank|refund|storage|product-image|secret)');
end;
$$;

do $$
declare
  l_detail jsonb;
begin
  l_detail := public.get_my_delivery_task(
    '81000000-0000-0000-0000-000000000002'::uuid
  );
  perform pg_temp.assert_detail('return-pickup task uses return-plan items',
    (l_detail -> 'task' ->> 'item_source') = 'return_plan'
    and jsonb_array_length(l_detail -> 'items') = 2
    and l_detail -> 'items' -> 0 ->> 'item_source' = 'return_plan'
    and l_detail -> 'items' -> 0 ->> 'product_name' = 'Returned jersey'
    and l_detail -> 'items' -> 0 ->> 'unit_price_vnd' is null
    and (l_detail -> 'items' -> 0 ->> 'quantity_collected')::int = 1);
end;
$$;

do $$
declare
  l_detail jsonb;
begin
  l_detail := public.get_my_delivery_task(
    '81000000-0000-0000-0000-000000000003'::uuid
  );
  perform pg_temp.assert_detail('redelivery preserves unavailable plan and []',
    l_detail -> 'task' ->> 'kind' = 'redelivery'
    and l_detail -> 'task' ->> 'item_source' = 'unavailable_redelivery_plan'
    and jsonb_array_length(l_detail -> 'items') = 0);
end;
$$;

do $$
declare
  l_detail jsonb;
begin
  l_detail := public.get_my_delivery_task(
    '81000000-0000-0000-0000-000000000004'::uuid
  );
  perform pg_temp.assert_detail('historical snapshot is masked',
    l_detail -> 'task' ->> 'snapshot_scope' = 'history'
    and l_detail -> 'task' ->> 'order_id' is null
    and l_detail -> 'task' ->> 'destination_name' is null
    and l_detail -> 'task' ->> 'item_source' = 'unavailable'
    and jsonb_array_length(l_detail -> 'items') = 0
    and l_detail::text !~* '(video|bank|refund|storage|private|evidence|account)');
  l_detail := public.get_my_delivery_task(
    '81000000-0000-0000-0000-000000000005'::uuid
  );
  perform pg_temp.assert_detail('restricted snapshot has no PII',
    l_detail -> 'task' ->> 'snapshot_scope' = 'restricted'
    and (select count(*) from jsonb_object_keys(l_detail -> 'task')) = 18
    and l_detail -> 'task' ?& array[
      'task_id', 'kind', 'status', 'attempt_number', 'snapshot_scope', 'item_source'
    ]
    and l_detail -> 'task' ->> 'destination_name' is null
    and jsonb_array_length(l_detail -> 'items') = 0
    and l_detail::text !~* '(video|bank|refund|storage|private|evidence|account)');
end;
$$;

-- The same safe error covers nonexistent, foreign and reassigned tasks.
select pg_temp.assert_detail_error(
  'foreign task is not distinguishable',
  'select public.get_my_delivery_task(''81000000-0000-0000-0000-000000000007''::uuid)',
  'P0002',
  'NOT_FOUND_OR_FORBIDDEN'
);
select pg_temp.assert_detail_error(
  'nonexistent task is not distinguishable',
  'select public.get_my_delivery_task(''ffffffff-ffff-ffff-ffff-ffffffffffff''::uuid)',
  'P0002',
  'NOT_FOUND_OR_FORBIDDEN'
);
select pg_temp.assert_detail_error(
  'null task id is invalid',
  'select public.get_my_delivery_task(null::uuid)',
  '22023',
  'INVALID_ARGUMENT'
);

-- Reassignment is checked on every fetch. A's old assignment cannot unlock the
-- new task scope; B can read only after the server-side assignment changes.
reset role;
update public.delivery_tasks
set assigned_shipper_id = '11000000-0000-0000-0000-000000000005'::uuid,
    assigned_at = clock_timestamp(),
    updated_at = clock_timestamp()
where id = '81000000-0000-0000-0000-000000000008'::uuid;
set local role authenticated;
select pg_temp.set_detail_claims(
  '11000000-0000-0000-0000-000000000004'::uuid
);
select pg_temp.assert_detail_error(
  'old shipper loses reassigned task',
  'select public.get_my_delivery_task(''81000000-0000-0000-0000-000000000008''::uuid)',
  'P0002',
  'NOT_FOUND_OR_FORBIDDEN'
);
select pg_temp.set_detail_claims(
  '11000000-0000-0000-0000-000000000005'::uuid
);
do $$
declare l_detail jsonb;
begin
  l_detail := public.get_my_delivery_task(
    '81000000-0000-0000-0000-000000000008'::uuid
  );
  perform pg_temp.assert_detail('new shipper sees reassigned task',
    l_detail -> 'task' ->> 'task_id' = '81000000-0000-0000-0000-000000000008'
    and l_detail -> 'task' ->> 'snapshot_scope' = 'current');
end;
$$;

-- A cancellation changes a previously current task into a masked historical
-- snapshot; its 1001 order items remain inaccessible.
reset role;
update public.delivery_tasks
set status = 'cancelled', completed_at = clock_timestamp(), updated_at = clock_timestamp()
where id = '81000000-0000-0000-0000-000000000001'::uuid;
set local role authenticated;
select pg_temp.set_detail_claims(
  '11000000-0000-0000-0000-000000000004'::uuid
);
do $$
declare l_detail jsonb;
begin
  l_detail := public.get_my_delivery_task(
    '81000000-0000-0000-0000-000000000001'::uuid
  );
  perform pg_temp.assert_detail('cancelled task no longer exposes current data',
    l_detail -> 'task' ->> 'snapshot_scope' = 'history'
    and l_detail -> 'task' ->> 'order_id' is null
    and jsonb_array_length(l_detail -> 'items') = 0);
end;
$$;

-- Anonymous/non-shipper roles are rejected before any projection data is
-- visible, even when the JWT role claim is forged.
set local role anon;
select pg_temp.clear_detail_claims();
select pg_temp.assert_detail_error(
  'anonymous caller denied',
  'select public.get_my_delivery_task(''81000000-0000-0000-0000-000000000002''::uuid)',
  '42501'
);
set local role authenticated;
select pg_temp.set_detail_claims(
  '11000000-0000-0000-0000-000000000001'::uuid,
  'shipper'
);
select pg_temp.assert_detail_error(
  'customer with forged shipper claim denied',
  'select public.get_my_delivery_task(''81000000-0000-0000-0000-000000000002''::uuid)',
  '42501',
  'DELIVERY_TASK_FORBIDDEN'
);
select pg_temp.set_detail_claims(
  '11000000-0000-0000-0000-000000000003'::uuid
);
select pg_temp.assert_detail_error(
  'manager caller denied',
  'select public.get_my_delivery_task(''81000000-0000-0000-0000-000000000002''::uuid)',
  '42501',
  'DELIVERY_TASK_FORBIDDEN'
);

reset role;
select 'delivery_task_detail.sql: PASS' as result,
       'fixtures rolled back by final statement' as fixture_scope;
rollback;
