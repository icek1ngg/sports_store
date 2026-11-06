-- P06.1 COD list projection contract.
-- TEST FIXTURE ONLY.  The runner executes this in an isolated, rolled-back
-- transaction; it is not seed data and never targets a cloud project.

begin;
set constraints all deferred;

create or replace function pg_temp.set_cod_claims(p_user_id uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', p_user_id::text, 'role', 'authenticated', 'aud', 'authenticated')::text,
    true
  );
end;
$$;

create or replace function pg_temp.clear_cod_claims()
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
end;
$$;

create or replace function pg_temp.assert_cod(p_label text, p_condition boolean)
returns void language plpgsql as $$
begin
  if coalesce(p_condition, false) is not true then
    raise exception 'COD list test failed: %', p_label;
  end if;
end;
$$;

create or replace function pg_temp.assert_cod_error(
  p_label text, p_sql text, p_state text
) returns void language plpgsql as $$
declare
  l_state text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics l_state = returned_sqlstate;
  end;
  if l_state is distinct from p_state then
    raise exception 'COD list test failed: % (expected %, got %)',
      p_label, p_state, coalesce(l_state, 'success');
  end if;
end;
$$;

insert into auth.users (id, email) values
  ('16000000-0000-0000-0000-000000000001'::uuid, 'cod-customer@example.invalid'),
  ('16000000-0000-0000-0000-000000000002'::uuid, 'cod-manager@example.invalid'),
  ('16000000-0000-0000-0000-000000000003'::uuid, 'cod-shipper-a@example.invalid'),
  ('16000000-0000-0000-0000-000000000004'::uuid, 'cod-shipper-b@example.invalid');

update public.profiles
set role = case id
  when '16000000-0000-0000-0000-000000000002'::uuid then 'manager'::public.user_role
  when '16000000-0000-0000-0000-000000000003'::uuid then 'shipper'::public.user_role
  when '16000000-0000-0000-0000-000000000004'::uuid then 'shipper'::public.user_role
  else 'customer'::public.user_role
end
where id in (
  '16000000-0000-0000-0000-000000000001'::uuid,
  '16000000-0000-0000-0000-000000000002'::uuid,
  '16000000-0000-0000-0000-000000000003'::uuid,
  '16000000-0000-0000-0000-000000000004'::uuid
);

insert into public.orders (
  id, customer_id, request_id, status, recipient_name, recipient_phone,
  address_detail, latitude, longitude, subtotal_vnd, delivery_fee_vnd
)
select
  ('66000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  '16000000-0000-0000-0000-000000000001'::uuid,
  ('a6000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  'delivered', format('COD recipient %s', n), format('09000006%02s', n),
  format('COD address %s, Ha Noi', n), 21.03, 105.8, 520000, 30000
from generate_series(1, 5) as numbers(n);

insert into public.return_requests (
  id, order_id, customer_id, request_id, status, reason, description,
  video_object_path
)
values (
  '96000000-0000-0000-0000-000000000005'::uuid,
  '66000000-0000-0000-0000-000000000005'::uuid,
  '16000000-0000-0000-0000-000000000001'::uuid,
  'a9600000-0000-0000-0000-000000000005'::uuid,
  'awaiting_refund', 'defective', 'COD must remain payable during refund workflow',
  'cod/return-proof-005.mp4'
);

insert into public.cod_collections (
  order_id, shipper_id, status, expected_amount_vnd, collected_amount_vnd,
  received_amount_vnd, collected_by, received_by, collected_at, received_at,
  created_at, updated_at
)
values
  ('66000000-0000-0000-0000-000000000001'::uuid,
   '16000000-0000-0000-0000-000000000003'::uuid, 'collected', 550000, 550000, 0,
   '16000000-0000-0000-0000-000000000003'::uuid, null, now() - interval '5 minutes', null,
   now() - interval '4 minutes', now() - interval '5 minutes'),
  ('66000000-0000-0000-0000-000000000002'::uuid,
   '16000000-0000-0000-0000-000000000003'::uuid, 'uncollected', 550000, 0, 0,
   null, null, null, null, now() - interval '4 minutes', now() - interval '4 minutes'),
  ('66000000-0000-0000-0000-000000000003'::uuid,
   '16000000-0000-0000-0000-000000000004'::uuid, 'collected', 550000, 550000, 0,
   '16000000-0000-0000-0000-000000000004'::uuid, null, now() - interval '3 minutes', null,
   now() - interval '3 minutes', now() - interval '3 minutes'),
  ('66000000-0000-0000-0000-000000000004'::uuid,
   '16000000-0000-0000-0000-000000000003'::uuid, 'received', 550000, 550000, 550000,
   '16000000-0000-0000-0000-000000000003'::uuid,
   '16000000-0000-0000-0000-000000000002'::uuid,
   now() - interval '2 minutes', now() - interval '1 minute',
   now() - interval '2 minutes', now() - interval '1 minute'),
  ('66000000-0000-0000-0000-000000000005'::uuid,
   '16000000-0000-0000-0000-000000000003'::uuid, 'collected', 550000, 550000, 0,
   '16000000-0000-0000-0000-000000000003'::uuid, null, now() - interval '30 seconds', null,
   now() - interval '30 seconds', now() - interval '30 seconds');

create temporary table cod_before_refund as
select to_jsonb(c) as snapshot from public.cod_collections c
where c.order_id = '66000000-0000-0000-0000-000000000005'::uuid;
grant select on cod_before_refund to authenticated;

update public.return_requests
set status = 'refunded'::public.return_request_status,
    refund_amount_vnd = 550000,
    refunded_by = '16000000-0000-0000-0000-000000000002'::uuid,
    refunded_at = now(),
    transfer_evidence_path = 'refunds/cod-proof-005.pdf',
    refund_request_id = 'a9700000-0000-0000-0000-000000000005'::uuid,
    closed_at = now()
where id = '96000000-0000-0000-0000-000000000005'::uuid;

-- The return/refund workflow does not alter the COD obligation.  This is a
-- seed invariant checked again through the shipper projection below.

-- From this point all reads and RPC calls execute as the Data API role.  The
-- fixture remains connected as postgres only so it can seed and roll back.
set local role authenticated;
select pg_temp.set_cod_claims('16000000-0000-0000-0000-000000000003'::uuid);

select pg_temp.assert_cod('refund preserves every COD column and full obligation',
  (select to_jsonb(c) = (select snapshot from cod_before_refund)
   from public.cod_collections c
   where c.order_id = '66000000-0000-0000-0000-000000000005'::uuid)
  and (public.list_cod_collections(null,
    '66000000-0000-0000-0000-000000000005'::uuid)->>'outstanding_vnd')::bigint = 550000
);

select pg_temp.assert_cod('base RLS shipper isolation',
  (select count(*) = 4 from public.cod_collections)
  and (select count(*) = 0 from public.cod_collections
       where shipper_id = '16000000-0000-0000-0000-000000000004'::uuid)
);

-- Shipper A sees only its four obligations.  The 550,000 VND example is kept
-- intact; uncollected is excluded from outstanding and received is excluded.
with response as (
  select public.list_cod_collections() as body
)
select pg_temp.assert_cod('shipper isolation',
  (body->'items')::jsonb @> jsonb_build_array(
    jsonb_build_object('order_id', '66000000-0000-0000-0000-000000000001')
  )
  and jsonb_array_length(body->'items') = 4
  and (body->>'outstanding_vnd')::bigint = 1100000
  and (body->'counts'->>'all')::integer = 4
  and (body->'counts'->>'uncollected')::integer = 1
  and (body->'counts'->>'collected')::integer = 2
  and (body->'counts'->>'received')::integer = 1
) from response;

do $$
declare
  l_cursor text;
  l_page jsonb;
  l_ids uuid[] := '{}'::uuid[];
  l_id uuid;
begin
  loop
    l_page := public.list_cod_collections(null, null, null, 1, l_cursor);
    if jsonb_array_length(l_page->'items') <> 1
       or (l_page->>'filtered_total')::integer <> 4
       or (l_page->>'outstanding_vnd')::bigint <> 1100000 then
      raise exception 'COD pagination changed full-dataset counts/totals';
    end if;
    l_id := (l_page->'items'->0->>'order_id')::uuid;
    if l_id = any(l_ids) then raise exception 'COD pagination duplicate'; end if;
    l_ids := array_append(l_ids, l_id);
    l_cursor := l_page->>'next_cursor';
    exit when l_cursor is null;
    if cardinality(l_ids) > 4 then raise exception 'COD pagination did not terminate'; end if;
  end loop;
  perform pg_temp.assert_cod('all pages and tied timestamp UUID ordering',
    cardinality(l_ids) = 4
    and l_ids[3] = '66000000-0000-0000-0000-000000000002'::uuid
    and l_ids[4] = '66000000-0000-0000-0000-000000000001'::uuid);
end;
$$;

select pg_temp.assert_cod_error('shipper cross-scope filter denied',
  $$select public.list_cod_collections('16000000-0000-0000-0000-000000000004'::uuid)$$,
  '42501');

select pg_temp.assert_cod_error('empty status filter rejected',
  $$select public.list_cod_collections(null, null, '{}'::public.cod_status[])$$,
  '22023');

select pg_temp.assert_cod_error('null status filter element rejected',
  $$select public.list_cod_collections(null, null, array[null::public.cod_status])$$,
  '22023');

select pg_temp.assert_cod_error('zero limit rejected',
  $$select public.list_cod_collections(null, null, null, 0, null)$$,
  '22023');
select pg_temp.assert_cod_error('limit above maximum rejected',
  $$select public.list_cod_collections(null, null, null, 101, null)$$,
  '22023');
select pg_temp.assert_cod_error('malformed cursor rejected',
  $$select public.list_cod_collections(null, null, null, 20, 'not-base64')$$,
  '22023');

do $$
declare
  l_state text;
  l_cursor text := replace(encode(convert_to(
    '{"v":null,"uid":"16000000-0000-0000-0000-000000000003",'
      || '"filter":"x","created_at":"2026-01-01T00:00:00Z",'
      || '"order_id":"66000000-0000-0000-0000-000000000001"}',
    'UTF8'), 'base64'), E'\n', '');
begin
  begin
    perform public.list_cod_collections(null, null, null, 20, l_cursor);
  exception when others then
    get stacked diagnostics l_state = returned_sqlstate;
  end;
  if l_state is distinct from '22023' then
    raise exception 'COD list test failed: cursor wrong type accepted (got %)',
      coalesce(l_state, 'success');
  end if;
end;
$$;

do $$
declare
  l_cursor text;
  l_state text;
begin
  l_cursor := (
    public.list_cod_collections(null, null, null, 1, null)->>'next_cursor'
  );
  l_state := null;
  perform pg_temp.set_cod_claims('16000000-0000-0000-0000-000000000004'::uuid);
  begin
    perform public.list_cod_collections(null, null, null, 1, l_cursor);
  exception when others then
    get stacked diagnostics l_state = returned_sqlstate;
  end;
  if l_state is distinct from '22023' then
    raise exception 'COD list test failed: cursor is not user-bound (got %)',
      coalesce(l_state, 'success');
  end if;
  perform pg_temp.set_cod_claims('16000000-0000-0000-0000-000000000003'::uuid);

  l_cursor := (
    public.list_cod_collections(null, null, null, 1, null)->>'next_cursor'
  );
  l_state := null;
  begin
    perform public.list_cod_collections(
      null, null, array['collected'::public.cod_status], 1, l_cursor
    );
  exception when others then
    get stacked diagnostics l_state = returned_sqlstate;
  end;
  if l_state is distinct from '22023' then
    raise exception 'COD list test failed: cursor is not filter-bound (got %)',
      coalesce(l_state, 'success');
  end if;
end;
$$;

-- Status filtering affects page rows/filtered_total only; counts and
-- outstanding remain over the complete shipper scope.
with response as (
  select public.list_cod_collections(
    null, null, array['collected'::public.cod_status], 20, null
  ) as body
)
select pg_temp.assert_cod('status filter keeps full totals',
  jsonb_array_length(body->'items') = 2
  and (body->>'filtered_total')::integer = 2
  and (body->'counts'->>'all')::integer = 4
  and (body->>'outstanding_vnd')::bigint = 1100000
) from response;

select pg_temp.assert_cod('received-only tab keeps outstanding from other collected rows',
  (select jsonb_array_length(body->'items') = 1
      and body->'items'->0->>'status' = 'received'
      and (body->>'filtered_total')::integer = 1
      and (body->>'outstanding_vnd')::bigint = 1100000
   from (select public.list_cod_collections(null, null,
     array['received'::public.cod_status]) as body) response)
);

with ordered as (
  select public.list_cod_collections(
    null, null,
    array['received'::public.cod_status, 'collected'::public.cod_status,
      'collected'::public.cod_status],
    20, null
  ) as body
), canonical as (
  select public.list_cod_collections(
    null, null,
    array['collected'::public.cod_status, 'received'::public.cod_status],
    20, null
  ) as body
)
select pg_temp.assert_cod('status filter canonicalization',
  (select body->'items' from ordered) = (select body->'items' from canonical)
  and (select body->>'filtered_total' from ordered)
      = (select body->>'filtered_total' from canonical)
);

-- Keyset pagination returns one item and a bound cursor; the next request has
-- the same scope/filter and advances without overlap.
with first_page as (
  select public.list_cod_collections(null, null, null, 1, null) as body
), second_page as (
  select public.list_cod_collections(
    null, null, null, 20, body->>'next_cursor'
  ) as body
  from first_page
)
select pg_temp.assert_cod('keyset cursor advances',
  (select body->>'next_cursor' is not null from first_page)
  and jsonb_array_length((select body->'items' from first_page)) = 1
  and jsonb_array_length((select body->'items' from second_page)) = 3
  and (select (body->>'filtered_total')::integer from second_page) = 4
  and (select (body->>'outstanding_vnd')::bigint from second_page) = 1100000
  and (select (body->'counts'->>'all')::integer from second_page) = 4
  and (select (body->'items'->0->>'order_id') from first_page)
      <> (select (body->'items'->0->>'order_id') from second_page)
);

reset role;
do $$
declare
  l_cursor text;
  l_state text;
begin
  perform pg_temp.set_cod_claims('16000000-0000-0000-0000-000000000003'::uuid);
  l_cursor := (public.list_cod_collections(null, null, null, 1, null)->>'next_cursor');
  update public.profiles
  set role = 'manager'::public.user_role
  where id = '16000000-0000-0000-0000-000000000003'::uuid;
  begin
    perform public.list_cod_collections(null, null, null, 1, l_cursor);
  exception when others then
    get stacked diagnostics l_state = returned_sqlstate;
  end;
  if l_state is distinct from '22023' then
    raise exception 'COD list test failed: cursor is not role-bound (got %)',
      coalesce(l_state, 'success');
  end if;
  update public.profiles
  set role = 'shipper'::public.user_role
  where id = '16000000-0000-0000-0000-000000000003'::uuid;
end;
$$;
set local role authenticated;

select pg_temp.set_cod_claims('16000000-0000-0000-0000-000000000004'::uuid);
select pg_temp.assert_cod('shipper B isolation',
  (select jsonb_array_length(body->'items') = 1
      and (body->>'outstanding_vnd')::bigint = 550000
   from (select public.list_cod_collections() as body) result)
);
select pg_temp.assert_cod('shipper order filter cannot reveal other owner',
  (select jsonb_array_length(body->'items') = 0
      and (body->>'filtered_total')::integer = 0
   from (select public.list_cod_collections(
     null, '66000000-0000-0000-0000-000000000001'::uuid, null, 20, null
   ) as body) result)
);

select pg_temp.set_cod_claims('16000000-0000-0000-0000-000000000002'::uuid);
with response as (
  select public.list_cod_collections() as body
)
select pg_temp.assert_cod('manager global scope',
  jsonb_array_length(body->'items') = 5
  and (body->>'filtered_total')::integer = 5
  and (body->'counts'->>'all')::integer = 5
  and (body->'counts'->>'uncollected')::integer = 1
  and (body->'counts'->>'collected')::integer = 3
  and (body->'counts'->>'received')::integer = 1
  and (body->>'outstanding_vnd')::bigint = 1650000
) from response;
with response as (
  select public.list_cod_collections(
    '16000000-0000-0000-0000-000000000003'::uuid,
    '66000000-0000-0000-0000-000000000001'::uuid,
    null, 20, null
  ) as body
)
select pg_temp.assert_cod('manager shipper/order filters',
  jsonb_array_length(body->'items') = 1
  and body->'items'->0->>'order_code_source' = 'order_uuid'
  and body->'items'->0->>'order_code' = '66000000-0000-0000-0000-000000000001'
  and (body->'items'->0->>'expected_amount_vnd')::bigint = 550000
) from response;

select pg_temp.set_cod_claims('16000000-0000-0000-0000-000000000001'::uuid);
select pg_temp.assert_cod_error('customer endpoint denied',
  $$select public.list_cod_collections()$$, '42501');

select pg_temp.clear_cod_claims();
reset role;
set local role anon;
select pg_temp.assert_cod_error('anonymous endpoint denied',
  $$select public.list_cod_collections()$$, '42501');
reset role;

select pg_temp.clear_cod_claims();
select 'cod_collection_list.sql: PASS' as result;
rollback;
