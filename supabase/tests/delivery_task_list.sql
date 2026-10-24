-- P02.1 task-list query contract.
-- TEST FIXTURE ONLY.  The runner executes this in an isolated, rolled-back
-- transaction.  It is not a Supabase seed or a deployment script.

begin;
set constraints all deferred;

create or replace function pg_temp.set_list_claims(p_user_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', p_user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', p_user_id::text,
      'role', 'authenticated',
      'aud', 'authenticated'
    )::text,
    true
  );
end;
$$;

create or replace function pg_temp.clear_list_claims()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
end;
$$;

create or replace function pg_temp.assert_list(
  p_label text,
  p_condition boolean
) returns void
language plpgsql
as $$
begin
  if coalesce(p_condition, false) is not true then
    raise exception 'delivery task list test failed: %', p_label;
  end if;
end;
$$;

create or replace function pg_temp.assert_list_error(
  p_label text,
  p_sql text,
  p_state text
) returns void
language plpgsql
as $$
declare
  l_state text;
begin
  begin
    execute p_sql;
  exception
    when others then
      get stacked diagnostics l_state = returned_sqlstate;
  end;
  if l_state is distinct from p_state then
    raise exception
      'delivery task list test failed: % (expected %, got %)',
      p_label, p_state, coalesce(l_state, 'success');
  end if;
end;
$$;

-- Two customers, a manager and two server-provisioned shippers.  The
-- projection checks profiles.role, so the caller's editable JWT is irrelevant.
insert into auth.users (id, email) values
  ('12000000-0000-0000-0000-000000000001'::uuid, 'list-customer-a@example.invalid'),
  ('12000000-0000-0000-0000-000000000002'::uuid, 'list-customer-b@example.invalid'),
  ('12000000-0000-0000-0000-000000000003'::uuid, 'list-manager@example.invalid'),
  ('12000000-0000-0000-0000-000000000004'::uuid, 'list-shipper-a@example.invalid'),
  ('12000000-0000-0000-0000-000000000005'::uuid, 'list-shipper-b@example.invalid');

update public.profiles
set full_name = case id
  when '12000000-0000-0000-0000-000000000001'::uuid then 'List customer A'
  when '12000000-0000-0000-0000-000000000002'::uuid then 'List customer B'
  when '12000000-0000-0000-0000-000000000003'::uuid then 'List manager'
  when '12000000-0000-0000-0000-000000000004'::uuid then 'List shipper A'
  when '12000000-0000-0000-0000-000000000005'::uuid then 'List shipper B'
end,
role = case
  when id in (
    '12000000-0000-0000-0000-000000000004'::uuid,
    '12000000-0000-0000-0000-000000000005'::uuid
  ) then 'shipper'::public.user_role
  when id = '12000000-0000-0000-0000-000000000003'::uuid
    then 'manager'::public.user_role
  else 'customer'::public.user_role
end
where id in (
  '12000000-0000-0000-0000-000000000001'::uuid,
  '12000000-0000-0000-0000-000000000002'::uuid,
  '12000000-0000-0000-0000-000000000003'::uuid,
  '12000000-0000-0000-0000-000000000004'::uuid,
  '12000000-0000-0000-0000-000000000005'::uuid
);

insert into public.orders (
  id, customer_id, request_id, status, recipient_name, recipient_phone,
  address_detail, latitude, longitude, subtotal_vnd, delivery_fee_vnd
)
select
  ('62000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  case when n = 12 then
    '12000000-0000-0000-0000-000000000002'::uuid
  else
    '12000000-0000-0000-0000-000000000001'::uuid
  end,
  ('a6000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  'delivered',
  case when n = 1 then 'Recipient Alpha' else format('Recipient %s', n) end,
  format('09000002%02s', n),
  format('List address %s, Ha Noi', n),
  21.030000 + n / 100000.0,
  105.800000 + n / 100000.0,
  520000,
  30000
from generate_series(1, 12) as numbers(n);

insert into public.return_requests (
  id, order_id, customer_id, request_id, status, reason, description,
  video_object_path
)
values
  (
    '92000000-0000-0000-0000-000000000010'::uuid,
    '62000000-0000-0000-0000-000000000010'::uuid,
    '12000000-0000-0000-0000-000000000001'::uuid,
    'a7000000-0000-0000-0000-000000000010'::uuid,
    'awaiting_return_pickup', 'defective', 'List pickup fixture',
    'list/pickup/video.mp4'
  ),
  (
    '92000000-0000-0000-0000-000000000011'::uuid,
    '62000000-0000-0000-0000-000000000011'::uuid,
    '12000000-0000-0000-0000-000000000001'::uuid,
    'a7000000-0000-0000-0000-000000000011'::uuid,
    'awaiting_redelivery', 'wrong_item', 'List redelivery fixture',
    'list/redelivery/video.mp4'
  );

-- A has every state and kind needed by the list contract.  T01/T02 share a
-- created_at value so the UUID tie-breaker is exercised.  B starts with T12;
-- T09 is reassigned below to prove old/new scopes do not overlap.
insert into public.delivery_tasks (
  id, order_id, return_request_id, kind, assigned_shipper_id, assigned_by,
  status, attempt_number, destination_name, destination_phone,
  destination_address, destination_latitude, destination_longitude,
  amount_to_collect_vnd, assigned_at, completed_at, created_at, updated_at
)
values
  (
    '82000000-0000-0000-0000-000000000001'::uuid,
    '62000000-0000-0000-0000-000000000001'::uuid, null, 'outbound',
    '12000000-0000-0000-0000-000000000004'::uuid,
    '12000000-0000-0000-0000-000000000003'::uuid, 'assigned', 1,
    'Recipient Alpha', '0900000201', 'List address 1, Ha Noi', 21.031000,
    105.801000, 550000, now() - interval '1 minute', null,
    now() - interval '1 minute', now() - interval '1 minute'
  ),
  (
    '82000000-0000-0000-0000-000000000002'::uuid,
    '62000000-0000-0000-0000-000000000002'::uuid, null, 'outbound',
    '12000000-0000-0000-0000-000000000004'::uuid,
    '12000000-0000-0000-0000-000000000003'::uuid, 'accepted', 1,
    'Recipient Bravo', '0900000202', 'List address 2, Ha Noi', 21.032000,
    105.802000, 550000, now() - interval '2 minutes', null,
    now() - interval '1 minute', now() - interval '1 minute'
  ),
  (
    '82000000-0000-0000-0000-000000000003'::uuid,
    '62000000-0000-0000-0000-000000000003'::uuid, null, 'outbound',
    '12000000-0000-0000-0000-000000000004'::uuid,
    '12000000-0000-0000-0000-000000000003'::uuid, 'in_transit', 1,
    'Recipient Charlie', '0900000203', 'List address 3, Ha Noi', 21.033000,
    105.803000, 550000, now() - interval '3 minutes', null,
    now() - interval '2 minutes', now() - interval '2 minutes'
  ),
  (
    '82000000-0000-0000-0000-000000000004'::uuid,
    '62000000-0000-0000-0000-000000000004'::uuid, null, 'outbound',
    '12000000-0000-0000-0000-000000000004'::uuid,
    '12000000-0000-0000-0000-000000000003'::uuid, 'delivered', 1,
    'History Delivered', '0900000204', 'List address 4, Ha Noi', 21.034000,
    105.804000, 550000, now() - interval '4 minutes', now() - interval '3 minutes',
    now() - interval '3 minutes', now() - interval '3 minutes'
  ),
  (
    '82000000-0000-0000-0000-000000000005'::uuid,
    '62000000-0000-0000-0000-000000000005'::uuid, null, 'outbound',
    '12000000-0000-0000-0000-000000000004'::uuid,
    '12000000-0000-0000-0000-000000000003'::uuid, 'returned_to_store', 2,
    'History Returned', '0900000205', 'List address 5, Ha Noi', 21.035000,
    105.805000, 550000, now() - interval '5 minutes', now() - interval '4 minutes',
    now() - interval '4 minutes', now() - interval '4 minutes'
  ),
  (
    '82000000-0000-0000-0000-000000000006'::uuid,
    '62000000-0000-0000-0000-000000000006'::uuid, null, 'outbound',
    '12000000-0000-0000-0000-000000000004'::uuid,
    '12000000-0000-0000-0000-000000000003'::uuid, 'pending_assignment', 1,
    'Pending Assignment', '0900000206', 'List address 6, Ha Noi', 21.036000,
    105.806000, 550000, now() - interval '6 minutes', null,
    now() - interval '5 minutes', now() - interval '5 minutes'
  ),
  (
    '82000000-0000-0000-0000-000000000007'::uuid,
    '62000000-0000-0000-0000-000000000007'::uuid, null, 'outbound',
    '12000000-0000-0000-0000-000000000004'::uuid,
    '12000000-0000-0000-0000-000000000003'::uuid, 'failed', 1,
    'Failed Delivery', '0900000207', 'List address 7, Ha Noi', 21.037000,
    105.807000, 550000, now() - interval '7 minutes', now() - interval '6 minutes',
    now() - interval '6 minutes', now() - interval '6 minutes'
  ),
  (
    '82000000-0000-0000-0000-000000000008'::uuid,
    '62000000-0000-0000-0000-000000000008'::uuid, null, 'outbound',
    '12000000-0000-0000-0000-000000000004'::uuid,
    '12000000-0000-0000-0000-000000000003'::uuid, 'cancelled', 1,
    'Cancelled Delivery', '0900000208', 'List address 8, Ha Noi', 21.038000,
    105.808000, 550000, now() - interval '8 minutes', now() - interval '7 minutes',
    now() - interval '7 minutes', now() - interval '7 minutes'
  ),
  (
    '82000000-0000-0000-0000-000000000009'::uuid,
    '62000000-0000-0000-0000-000000000009'::uuid, null, 'outbound',
    '12000000-0000-0000-0000-000000000004'::uuid,
    '12000000-0000-0000-0000-000000000003'::uuid, 'manager_action_required', 2,
    'Manager Action', '0900000209', 'List address 9, Ha Noi', 21.039000,
    105.809000, 550000, now() - interval '9 minutes', null,
    now() - interval '8 minutes', now() - interval '8 minutes'
  ),
  (
    '82000000-0000-0000-0000-000000000010'::uuid,
    '62000000-0000-0000-0000-000000000010'::uuid,
    '92000000-0000-0000-0000-000000000010'::uuid, 'return_pickup',
    '12000000-0000-0000-0000-000000000004'::uuid,
    '12000000-0000-0000-0000-000000000003'::uuid, 'in_transit', 1,
    'Pickup Recipient', '0900000210', 'List address 10, Ha Noi', 21.040000,
    105.810000, 0, now() - interval '10 minutes', null,
    now() - interval '9 minutes', now() - interval '9 minutes'
  ),
  (
    '82000000-0000-0000-0000-000000000011'::uuid,
    '62000000-0000-0000-0000-000000000011'::uuid,
    '92000000-0000-0000-0000-000000000011'::uuid, 'redelivery',
    '12000000-0000-0000-0000-000000000004'::uuid,
    '12000000-0000-0000-0000-000000000003'::uuid, 'assigned', 1,
    'Redelivery Recipient', '0900000211', 'List address 11, Ha Noi', 21.041000,
    105.811000, 0, now() - interval '11 minutes', null,
    now() - interval '10 minutes', now() - interval '10 minutes'
  ),
  (
    '82000000-0000-0000-0000-000000000012'::uuid,
    '62000000-0000-0000-0000-000000000012'::uuid, null, 'outbound',
    '12000000-0000-0000-0000-000000000005'::uuid,
    '12000000-0000-0000-0000-000000000003'::uuid, 'assigned', 1,
    'Other Shipper Recipient', '0900000212', 'List address 12, Ha Noi', 21.042000,
    105.812000, 550000, now() - interval '1 minute', null,
    now() - interval '1 minute', now() - interval '1 minute'
  );

-- Anonymous and authenticated non-shippers cannot call the function or gain
-- access through a forged JWT role claim.
set local role anon;
select pg_temp.clear_list_claims();
select pg_temp.assert_list_error(
  'anonymous caller is denied',
  'select public.list_my_delivery_tasks()',
  '42501'
);

set local role authenticated;
select pg_temp.set_list_claims('12000000-0000-0000-0000-000000000001'::uuid);
select pg_temp.assert_list_error(
  'customer caller is denied',
  'select public.list_my_delivery_tasks()',
  '42501'
);

select pg_temp.set_list_claims('12000000-0000-0000-0000-000000000003'::uuid);
select pg_temp.assert_list_error(
  'manager caller is denied',
  'select public.list_my_delivery_tasks()',
  '42501'
);

select pg_temp.set_list_claims('12000000-0000-0000-0000-000000000004'::uuid);

do $$
declare
  l_page jsonb;
  l_second_page jsonb;
  l_ids text[];
  l_second_ids text[];
begin
  l_page := public.list_my_delivery_tasks(null, null, null, 2, null);
  perform pg_temp.assert_list('A full filtered_total is 11', (l_page->>'filtered_total')::int = 11);
  perform pg_temp.assert_list('A full counts include ungrouped states',
    (l_page->'counts'->>'waiting')::int = 3
    and (l_page->'counts'->>'in_transit')::int = 2
    and (l_page->'counts'->>'completed')::int = 2
    and (l_page->'counts'->>'ungrouped')::int = 4
  );
  perform pg_temp.assert_list('page is limited to two items', jsonb_array_length(l_page->'items') = 2);
  perform pg_temp.assert_list('next cursor exists for another page', l_page->>'next_cursor' is not null);
  perform pg_temp.assert_list('sort tie breaks by task UUID',
    (l_page->'items'->0->>'task_id') = '82000000-0000-0000-0000-000000000002'
    and (l_page->'items'->1->>'task_id') = '82000000-0000-0000-0000-000000000001'
  );
  perform pg_temp.assert_list('items contain only the P01.1 snapshot fields',
    not (l_page->'items'->0 ? 'created_at')
  );

  l_second_page := public.list_my_delivery_tasks(null, null, null, 2, l_page->>'next_cursor');
  select array_agg(item->>'task_id' order by ordinality)
    into l_ids
  from jsonb_array_elements(l_page->'items') with ordinality as page(item, ordinality);
  select array_agg(item->>'task_id' order by ordinality)
    into l_second_ids
  from jsonb_array_elements(l_second_page->'items') with ordinality as page(item, ordinality);
  perform pg_temp.assert_list('cursor page does not repeat a task',
    not (l_ids && l_second_ids)
  );
  perform pg_temp.assert_list('cursor page starts immediately after last row',
    l_second_ids = array[
      '82000000-0000-0000-0000-000000000003',
      '82000000-0000-0000-0000-000000000004'
    ]
  );

  l_page := public.list_my_delivery_tasks(null, 'waiting', null, 100, null);
  perform pg_temp.assert_list('waiting excludes pending and terminal states',
    (l_page->>'filtered_total')::int = 3
    and (l_page->'counts'->>'waiting')::int = 3
    and (l_page->'counts'->>'in_transit')::int = 2
    and (l_page->'counts'->>'completed')::int = 2
    and (l_page->'counts'->>'ungrouped')::int = 4
    and not exists (
      select 1
      from jsonb_array_elements(l_page->'items') as item
      where item->>'status' not in ('assigned', 'accepted')
    )
  );
  l_page := public.list_my_delivery_tasks(null, 'in_transit', null, 100, null);
  perform pg_temp.assert_list('in_transit group is explicit',
    (l_page->>'filtered_total')::int = 2
    and not exists (
      select 1
      from jsonb_array_elements(l_page->'items') as item
      where item->>'status' <> 'in_transit'
    )
  );
  l_page := public.list_my_delivery_tasks(null, 'completed', null, 100, null);
  perform pg_temp.assert_list('completed group excludes failed/cancelled',
    (l_page->>'filtered_total')::int = 2
    and not exists (
      select 1
      from jsonb_array_elements(l_page->'items') as item
      where item->>'status' not in ('delivered', 'returned_to_store')
    )
  );

  l_page := public.list_my_delivery_tasks('return_pickup', null, null, 100, null);
  perform pg_temp.assert_list('kind filter returns pickup only',
    (l_page->>'filtered_total')::int = 1
    and (l_page->'items'->0->>'kind') = 'return_pickup'
  );
  l_page := public.list_my_delivery_tasks('redelivery', 'waiting', null, 100, null);
  perform pg_temp.assert_list('kind and state filters compose',
    (l_page->>'filtered_total')::int = 1
    and (l_page->'items'->0->>'kind') = 'redelivery'
    and (l_page->'counts'->>'waiting')::int = 1
  );

  l_page := public.list_my_delivery_tasks(null, null, 'alpha', 100, null);
  perform pg_temp.assert_list('recipient search is case insensitive',
    (l_page->>'filtered_total')::int = 1
    and (l_page->'items'->0->>'task_id') = '82000000-0000-0000-0000-000000000001'
  );
  l_page := public.list_my_delivery_tasks(null, null, '62000000-0000-0000-0000-000000000001', 100, null);
  perform pg_temp.assert_list('UUID display search is supported', (l_page->>'filtered_total')::int = 1);
  l_page := public.list_my_delivery_tasks(null, null, E'\t  ReCiPiEnT \n', 2, null);
  perform pg_temp.assert_list('query trim matches Dart ASCII whitespace',
    (l_page->>'filtered_total')::int = 5
    and l_page->>'next_cursor' is not null
  );
  l_second_page := public.list_my_delivery_tasks(
    null, null, 'recipient', 2, l_page->>'next_cursor'
  );
  perform pg_temp.assert_list('normalized query resumes the same cursor',
    (l_second_page->>'filtered_total')::int = 5
    and jsonb_array_length(l_second_page->'items') = 2
  );
  perform pg_temp.assert_list_error(
    'cursor with leading ASCII whitespace is invalid',
    format(
      'select public.list_my_delivery_tasks(null, null, null, 2, %L)',
      ' ' || (l_page->>'next_cursor')
    ),
    '22023'
  );
  l_page := public.list_my_delivery_tasks(null, null, 'history delivered', 100, null);
  perform pg_temp.assert_list('masked history cannot be searched as an oracle',
    (l_page->>'filtered_total')::int = 0
  );
  l_page := public.list_my_delivery_tasks(null, null, '%', 100, null);
  perform pg_temp.assert_list('search metacharacters remain literal',
    (l_page->>'filtered_total')::int = 0
  );
  l_page := public.list_my_delivery_tasks(null, null, 'does-not-exist', 100, null);
  perform pg_temp.assert_list('empty search result has no cursor',
    (l_page->>'filtered_total')::int = 0
    and jsonb_array_length(l_page->'items') = 0
    and l_page->>'next_cursor' is null
  );

  perform pg_temp.assert_list_error(
    'zero limit is invalid',
    'select public.list_my_delivery_tasks(null, null, null, 0, null)',
    '22023'
  );
  perform pg_temp.assert_list_error(
    'unknown state group is invalid',
    'select public.list_my_delivery_tasks(null, ''failed'', null, 20, null)',
    '22023'
  );
  perform pg_temp.assert_list_error(
    'malformed cursor is invalid',
    'select public.list_my_delivery_tasks(null, null, null, 20, ''not-a-cursor'')',
    '22023'
  );
  perform pg_temp.assert_list_error(
    'cursor missing tuple fields is invalid',
    'select public.list_my_delivery_tasks(null, null, null, 20, ''e30='')',
    '22023'
  );
  perform pg_temp.assert_list_error(
    'overlong query is invalid',
    $sql$select public.list_my_delivery_tasks(null, null, repeat('x', 201), 20, null)$sql$,
    '22023'
  );
end;
$$;

do $$
declare
  l_page jsonb;
begin
  l_page := public.list_my_delivery_tasks(null, null, null, 2, null);
  perform pg_temp.assert_list_error(
    'cursor cannot cross filters',
    format(
      'select public.list_my_delivery_tasks(null, ''waiting'', null, 2, %L)',
      l_page->>'next_cursor'
    ),
    '22023'
  );
  perform pg_temp.assert_list_error(
    'cursor cannot cross search filters',
    format(
      'select public.list_my_delivery_tasks(null, null, ''alpha'', 2, %L)',
      l_page->>'next_cursor'
    ),
    '22023'
  );
  perform pg_temp.assert_list_error(
    'cursor cannot cross kind filters',
    format(
      'select public.list_my_delivery_tasks(''outbound'', null, null, 2, %L)',
      l_page->>'next_cursor'
    ),
    '22023'
  );
end;
$$;

do $$
declare
  l_cursor text;
begin
  l_cursor := replace(
    encode(
      convert_to(
        jsonb_build_object(
          'v', 1,
          'uid', null,
          'filter', null,
          'created_at', now(),
          'task_id', '82000000-0000-0000-0000-000000000001'::uuid
        )::text,
        'UTF8'
      ),
      'base64'
    ),
    E'\n',
    ''
  );
  perform pg_temp.assert_list_error(
    'cursor null uid/filter is invalid',
    format('select public.list_my_delivery_tasks(null, null, null, 2, %L)', l_cursor),
    '22023'
  );
end;
$$;

-- Walk every page to prove the keyset tuple advances from the last returned
-- row and never drops the look-ahead row or repeats a task.
do $$
declare
  l_page jsonb;
  l_cursor text;
  l_seen text[] := array[]::text[];
  l_ids text[];
  l_steps integer := 0;
begin
  loop
    l_page := public.list_my_delivery_tasks(null, null, null, 2, l_cursor);
    select array_agg(item->>'task_id' order by ordinality)
      into l_ids
    from jsonb_array_elements(l_page->'items') with ordinality as page(item, ordinality);
    l_seen := l_seen || coalesce(l_ids, array[]::text[]);
    l_steps := l_steps + 1;
    exit when l_page->>'next_cursor' is null;
    if l_steps > 10 then
      raise exception 'delivery task list test failed: cursor did not terminate';
    end if;
    l_cursor := l_page->>'next_cursor';
  end loop;
  perform pg_temp.assert_list('all 11 rows are reachable by cursor pages', cardinality(l_seen) = 11);
  perform pg_temp.assert_list('cursor pages contain no duplicate task IDs',
    cardinality(l_seen) = (select count(distinct id) from unnest(l_seen) as seen(id))
  );
end;
$$;

-- A cursor is bound to both the filter and auth.uid.  Reusing A's token as B
-- must fail before any rows are returned.
do $$
declare
  l_page jsonb;
begin
  l_page := public.list_my_delivery_tasks(null, null, null, 2, null);
  perform set_config('request.jwt.claim.sub', '12000000-0000-0000-0000-000000000005', true);
  perform pg_temp.assert_list_error(
    'cursor cannot cross accounts',
    format(
      'select public.list_my_delivery_tasks(null, null, null, 2, %L)',
      l_page->>'next_cursor'
    ),
    '22023'
  );
end;
$$;

-- Reassignment revokes A and exposes the task only to B.  The old caller does
-- not retain a historical row because this is an in-place assignment change.
reset role;
update public.delivery_tasks
set assigned_shipper_id = '12000000-0000-0000-0000-000000000005'::uuid,
    assigned_at = clock_timestamp()
where id = '82000000-0000-0000-0000-000000000009'::uuid;
set local role authenticated;
select pg_temp.set_list_claims('12000000-0000-0000-0000-000000000004'::uuid);
do $$
declare l_page jsonb;
begin
  l_page := public.list_my_delivery_tasks(null, null, null, 100, null);
  perform pg_temp.assert_list('reassigned task leaves old shipper list',
    not exists (
      select 1 from jsonb_array_elements(l_page->'items') as item
      where item->>'task_id' = '82000000-0000-0000-0000-000000000009'
    )
  );
end;
$$;

select pg_temp.set_list_claims('12000000-0000-0000-0000-000000000005'::uuid);
do $$
declare l_page jsonb;
begin
  l_page := public.list_my_delivery_tasks(null, null, null, 100, null);
  perform pg_temp.assert_list('new shipper sees reassigned task',
    (l_page->>'filtered_total')::int = 2
    and exists (
      select 1 from jsonb_array_elements(l_page->'items') as item
      where item->>'task_id' = '82000000-0000-0000-0000-000000000009'
    )
  );
end;
$$;

reset role;
select 'delivery_task_list.sql: PASS' as result,
       'fixtures rolled back by final statement' as fixture_scope;
rollback;
