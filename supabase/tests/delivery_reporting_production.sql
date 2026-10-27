-- P07.4 production store-handover/incident report contract.
--
-- This suite intentionally runs in one transaction and rolls back.  It uses
-- the real P03.3 assignment, P04.1 accept/start, P07.1 failure and P07.2
-- manager-return RPCs.  Only the rows required to provide their reservation,
-- COD and custody proofs are fixture-seeded here.  A report is not a receipt,
-- inspection, restock, compensation, COD action or delivery result.
begin;
set constraints all deferred;

create or replace function pg_temp.set_p074_claims(p_user_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
  perform set_config(
    'request.jwt.claims',
    case when p_user_id is null then '' else jsonb_build_object(
      'sub', p_user_id::text, 'role', 'authenticated', 'aud', 'authenticated'
    )::text end,
    true
  );
end;
$$;

create or replace function pg_temp.assert_p074(p_label text, p_ok boolean)
returns void language plpgsql as $$
begin
  if coalesce(p_ok, false) is not true then
    raise exception 'P07.4 production test failed: %', p_label;
  end if;
end;
$$;

create or replace function pg_temp.assert_p074_error(
  p_label text, p_sql text, p_state text, p_message text default null
)
returns void
language plpgsql
as $$
declare
  l_state text;
  l_message text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics
      l_state = returned_sqlstate,
      l_message = message_text;
  end;
  if l_state is distinct from p_state
     or (p_message is not null and l_message is distinct from p_message) then
    raise exception
      'P07.4 error % expected %/% got %/%', p_label, p_state,
      coalesce(p_message, '<any>'), coalesce(l_state, 'success'),
      coalesce(l_message, '');
  end if;
end;
$$;

create or replace function pg_temp.assert_p074_state(
  p_label text, p_sql text, p_state text
)
returns void
language plpgsql
as $$
declare
  l_state text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics l_state = returned_sqlstate;
  end;
  if l_state is distinct from p_state then
    raise exception 'P07.4 error % expected % got %', p_label, p_state,
      coalesce(l_state, 'success');
  end if;
end;
$$;

-- The RPCs and private reporting ledgers are an authenticated-only,
-- SECURITY DEFINER boundary.  Do not weaken this check by accepting a broad
-- owner, a client-readable ledger, or a SECURITY DEFINER search path.
do $$
declare
  l_proc record;
  l_owner record;
  l_private_count integer;
  l_private record;
begin
  for l_proc in
    select p.oid, p.prosecdef, p.proconfig,
           pg_get_userbyid(p.proowner) as owner_name,
           p.proname
    from pg_proc p
    where p.oid in (
      'public.report_store_handover(uuid,uuid,jsonb)'::regprocedure,
      'public.report_delivery_incident(uuid,uuid,public.delivery_incident_kind,text)'::regprocedure
    )
  loop
    if l_proc.prosecdef is not true
       or not (l_proc.proconfig @> array['search_path=""'])
       or l_proc.owner_name is null
       or l_proc.owner_name in ('postgres', 'supabase_admin') then
      raise exception 'P07.4 RPC % is not a narrowly owned SECURITY DEFINER',
        l_proc.proname;
    end if;
    select r.rolcanlogin, r.rolsuper, r.rolbypassrls, r.rolinherit,
           r.rolcreaterole, r.rolcreatedb, r.rolreplication
      into l_owner
    from pg_roles r where r.rolname = l_proc.owner_name;
    if not found or l_owner.rolcanlogin or l_owner.rolsuper
       or l_owner.rolbypassrls or l_owner.rolinherit
       or l_owner.rolcreaterole or l_owner.rolcreatedb
       or l_owner.rolreplication then
      raise exception 'P07.4 RPC % owner is unsafe', l_proc.proname;
    end if;
    if not has_function_privilege('authenticated', l_proc.oid, 'EXECUTE')
       or has_function_privilege('anon', l_proc.oid, 'EXECUTE')
       or has_function_privilege('service_role', l_proc.oid, 'EXECUTE')
       or has_function_privilege('public', l_proc.oid, 'EXECUTE') then
      raise exception 'P07.4 RPC % ACL is broader than authenticated',
        l_proc.proname;
    end if;
  end loop;

  -- The implementation may keep request/result rows in one or more private
  -- ledgers.  Identify them by their contract vocabulary, then require RLS
  -- and no client table privileges without coupling this test to a private
  -- table name that is not part of the public API.
  select count(*) into l_private_count
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'private' and c.relkind = 'r'
    and (
      c.relname ilike '%delivery%report%'
      or c.relname ilike '%handover%'
      or c.relname ilike '%incident%report%'
    );
  if l_private_count = 0 then
    raise exception 'P07.4 reporting ledger is missing';
  end if;
  for l_private in
    select c.relname, c.relrowsecurity, c.relforcerowsecurity
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'private' and c.relkind = 'r'
      and (
        c.relname ilike '%delivery%report%'
        or c.relname ilike '%handover%'
        or c.relname ilike '%incident%report%'
      )
  loop
    if not l_private.relrowsecurity or not l_private.relforcerowsecurity
       or has_table_privilege('authenticated', 'private.' || quote_ident(l_private.relname), 'SELECT,INSERT,UPDATE,DELETE')
       or has_table_privilege('anon', 'private.' || quote_ident(l_private.relname), 'SELECT,INSERT,UPDATE,DELETE')
       or has_table_privilege('service_role', 'private.' || quote_ident(l_private.relname), 'SELECT,INSERT,UPDATE,DELETE') then
      raise exception 'P07.4 reporting ledger % is not private/forced-RLS',
        l_private.relname;
    end if;
  end loop;
end;
$$;

create temp table p074_ids(name text primary key, id uuid not null) on commit drop;
create temp table p074_responses(name text primary key, response jsonb not null) on commit drop;
grant select,insert,update on p074_ids,p074_responses to authenticated;

-- All business fixtures use the normal Auth -> profile trigger.  Role changes
-- are trusted setup, not user-editable JWT claims.
insert into auth.users (id, email)
values
  ('07450000-0000-0000-0000-000000000001', 'p074-customer-a@example.invalid'),
  ('07450000-0000-0000-0000-000000000002', 'p074-manager-a@example.invalid'),
  ('07450000-0000-0000-0000-000000000003', 'p074-shipper-a@example.invalid'),
  ('07450000-0000-0000-0000-000000000004', 'p074-shipper-b@example.invalid'),
  ('07450000-0000-0000-0000-000000000005', 'p074-customer-b@example.invalid'),
  ('07450000-0000-0000-0000-000000000006', 'p074-manager-b@example.invalid');
update public.profiles
set role = case
  when id = '07450000-0000-0000-0000-000000000002'
    then 'manager'::public.user_role
  when id in (
    '07450000-0000-0000-0000-000000000003',
    '07450000-0000-0000-0000-000000000004'
  ) then 'shipper'::public.user_role
  else 'customer'::public.user_role
end
where id in (
  '07450000-0000-0000-0000-000000000001',
  '07450000-0000-0000-0000-000000000002',
  '07450000-0000-0000-0000-000000000003',
  '07450000-0000-0000-0000-000000000004',
  '07450000-0000-0000-0000-000000000005',
  '07450000-0000-0000-0000-000000000006'
);

insert into public.categories(id, code, name)
values ('07450000-0000-0000-0000-000000000100', 'P074', 'P07.4 reporting');
insert into public.products(id, category_id, name)
values ('07450000-0000-0000-0000-000000000101',
        '07450000-0000-0000-0000-000000000100', 'P07.4 reporting product');
insert into public.product_variants(
  id, product_id, sku, label, price_vnd, on_hand, reserved
) values (
  '07450000-0000-0000-0000-000000000111',
  '07450000-0000-0000-0000-000000000101',
  'P074-01', 'P07.4 reporting variant', 100000, 32, 15
);

-- Each order has a real reservation row.  Order 10 has two units so exact
-- full-item handover proof is tested rather than a one-item shortcut.
insert into public.orders(
  id, customer_id, request_id, status, recipient_name, recipient_phone,
  address_detail, latitude, longitude, subtotal_vnd, delivery_attempt_count
)
select x.order_id, x.customer_id, x.order_id, x.status::public.order_status,
  'P07.4 recipient ' || x.n, '090740' || lpad(x.n::text, 4, '0'),
  'P07.4 Hanoi address ' || x.n, 21.0285, 105.8542,
  x.quantity * 100000, 0
from (values
  ('07450000-0000-0000-0000-000000000010'::uuid,'07450000-0000-0000-0000-000000000001'::uuid,10,2,'preparing'),
  ('07450000-0000-0000-0000-000000000011'::uuid,'07450000-0000-0000-0000-000000000001'::uuid,11,1,'preparing'),
  ('07450000-0000-0000-0000-000000000012'::uuid,'07450000-0000-0000-0000-000000000001'::uuid,12,1,'preparing'),
  ('07450000-0000-0000-0000-000000000013'::uuid,'07450000-0000-0000-0000-000000000001'::uuid,13,1,'preparing'),
  ('07450000-0000-0000-0000-000000000014'::uuid,'07450000-0000-0000-0000-000000000001'::uuid,14,1,'preparing'),
  ('07450000-0000-0000-0000-000000000015'::uuid,'07450000-0000-0000-0000-000000000001'::uuid,15,1,'preparing'),
  ('07450000-0000-0000-0000-000000000016'::uuid,'07450000-0000-0000-0000-000000000001'::uuid,16,1,'preparing'),
  ('07450000-0000-0000-0000-000000000017'::uuid,'07450000-0000-0000-0000-000000000001'::uuid,17,1,'preparing'),
  ('07450000-0000-0000-0000-000000000018'::uuid,'07450000-0000-0000-0000-000000000001'::uuid,18,1,'preparing'),
  ('07450000-0000-0000-0000-000000000019'::uuid,'07450000-0000-0000-0000-000000000005'::uuid,19,1,'preparing')
) x(order_id, customer_id, n, quantity, status);

insert into public.order_items(
  id, order_id, product_id, variant_id, product_name, variant_label,
  unit_price_vnd, quantity
)
select ('07450000-0000-0000-0000-' || lpad((200 + x.n)::text, 12, '0'))::uuid,
  x.order_id, '07450000-0000-0000-0000-000000000101'::uuid,
  '07450000-0000-0000-0000-000000000111'::uuid,
  'P07.4 reporting product', 'P07.4 reporting variant', 100000, x.quantity
from (values
  ('07450000-0000-0000-0000-000000000010'::uuid,10,2),
  ('07450000-0000-0000-0000-000000000011'::uuid,11,1),
  ('07450000-0000-0000-0000-000000000012'::uuid,12,1),
  ('07450000-0000-0000-0000-000000000013'::uuid,13,1),
  ('07450000-0000-0000-0000-000000000014'::uuid,14,1),
  ('07450000-0000-0000-0000-000000000015'::uuid,15,1),
  ('07450000-0000-0000-0000-000000000016'::uuid,16,1),
  ('07450000-0000-0000-0000-000000000017'::uuid,17,1),
  ('07450000-0000-0000-0000-000000000018'::uuid,18,1),
  ('07450000-0000-0000-0000-000000000019'::uuid,19,1)
) x(order_id,n,quantity);

insert into public.inventory_movements(
  variant_id, order_id, event_id, kind, reserved_delta, actor_id, reason
)
select '07450000-0000-0000-0000-000000000111'::uuid, x.order_id,
  ('07450000-0000-0000-0000-' || lpad((500 + x.n)::text, 12, '0'))::uuid,
  'reserve'::public.inventory_movement_kind, x.quantity,
  '07450000-0000-0000-0000-000000000002'::uuid, 'P07.4 checkout reservation'
from (values
  ('07450000-0000-0000-0000-000000000010'::uuid,10,2),
  ('07450000-0000-0000-0000-000000000011'::uuid,11,1),
  ('07450000-0000-0000-0000-000000000012'::uuid,12,1),
  ('07450000-0000-0000-0000-000000000013'::uuid,13,1),
  ('07450000-0000-0000-0000-000000000014'::uuid,14,1),
  ('07450000-0000-0000-0000-000000000015'::uuid,15,1),
  ('07450000-0000-0000-0000-000000000016'::uuid,16,1),
  ('07450000-0000-0000-0000-000000000017'::uuid,17,1),
  ('07450000-0000-0000-0000-000000000018'::uuid,18,1),
  ('07450000-0000-0000-0000-000000000019'::uuid,19,1)
) x(order_id,n,quantity);

insert into public.cod_collections(order_id, shipper_id, status, expected_amount_vnd)
select o.id, '07450000-0000-0000-0000-000000000003'::uuid,
  'uncollected'::public.cod_status, o.total_cod_vnd
from public.orders o where o.id in (
  '07450000-0000-0000-0000-000000000010',
  '07450000-0000-0000-0000-000000000011',
  '07450000-0000-0000-0000-000000000012',
  '07450000-0000-0000-0000-000000000013',
  '07450000-0000-0000-0000-000000000014',
  '07450000-0000-0000-0000-000000000015',
  '07450000-0000-0000-0000-000000000016',
  '07450000-0000-0000-0000-000000000018'
);
insert into public.cod_collections(order_id, shipper_id, status, expected_amount_vnd)
select o.id, '07450000-0000-0000-0000-000000000004'::uuid,
  'uncollected'::public.cod_status, o.total_cod_vnd
from public.orders o where o.id = '07450000-0000-0000-0000-000000000019';

-- A real return-pickup task proves that this P07.4 scope is outbound only.
insert into public.return_requests(
  id, order_id, customer_id, request_id, status, reason, description,
  video_object_path
) values (
  '07450000-0000-0000-0000-000000000701',
  '07450000-0000-0000-0000-000000000017',
  '07450000-0000-0000-0000-000000000001',
  '07450000-0000-0000-0000-000000000702',
  'awaiting_return_pickup', 'defective', 'P07.4 return task scope',
  '07450000-0000-0000-0000-000000000701/video.mp4'
);
insert into public.delivery_tasks(
  id, order_id, return_request_id, kind, assigned_shipper_id, assigned_by,
  status, attempt_number, destination_name, destination_phone,
  destination_address, destination_latitude, destination_longitude,
  amount_to_collect_vnd, assigned_at
) values (
  '07450000-0000-0000-0000-000000000801',
  '07450000-0000-0000-0000-000000000017',
  '07450000-0000-0000-0000-000000000701', 'return_pickup',
  '07450000-0000-0000-0000-000000000003',
  '07450000-0000-0000-0000-000000000002', 'assigned', 1,
  'P07.4 return recipient', '0907401700', 'P07.4 return address',
  21.0285, 105.8542, 0, clock_timestamp()
);

-- Initial assignment is the real manager RPC.  Every later report is based on
-- the custody proof generated by accept/start/fail, never on a fake task row.
set local role authenticated;
select pg_temp.set_p074_claims('07450000-0000-0000-0000-000000000002');
insert into p074_ids(name, id)
select 'task10', (public.assign_delivery_task(
  '07450000-0000-0000-0000-000000000010',
  '07450000-0000-0000-0000-000000000003',
  '07450000-0000-0000-0000-000000000901'
)->>'task_id')::uuid;
insert into p074_ids(name, id)
select 'task11', (public.assign_delivery_task(
  '07450000-0000-0000-0000-000000000011',
  '07450000-0000-0000-0000-000000000003',
  '07450000-0000-0000-0000-000000000902'
)->>'task_id')::uuid;
insert into p074_ids(name, id)
select 'task12', (public.assign_delivery_task(
  '07450000-0000-0000-0000-000000000012',
  '07450000-0000-0000-0000-000000000003',
  '07450000-0000-0000-0000-000000000903'
)->>'task_id')::uuid;
insert into p074_ids(name, id)
select 'task13', (public.assign_delivery_task(
  '07450000-0000-0000-0000-000000000013',
  '07450000-0000-0000-0000-000000000003',
  '07450000-0000-0000-0000-000000000904'
)->>'task_id')::uuid;
insert into p074_ids(name, id)
select 'task14', (public.assign_delivery_task(
  '07450000-0000-0000-0000-000000000014',
  '07450000-0000-0000-0000-000000000003',
  '07450000-0000-0000-0000-000000000905'
)->>'task_id')::uuid;
insert into p074_ids(name, id)
select 'task15', (public.assign_delivery_task(
  '07450000-0000-0000-0000-000000000015',
  '07450000-0000-0000-0000-000000000003',
  '07450000-0000-0000-0000-000000000906'
)->>'task_id')::uuid;
insert into p074_ids(name, id)
select 'task16', (public.assign_delivery_task(
  '07450000-0000-0000-0000-000000000016',
  '07450000-0000-0000-0000-000000000003',
  '07450000-0000-0000-0000-000000000907'
)->>'task_id')::uuid;
insert into p074_ids(name, id)
select 'task18', (public.assign_delivery_task(
  '07450000-0000-0000-0000-000000000018',
  '07450000-0000-0000-0000-000000000003',
  '07450000-0000-0000-0000-000000000908'
)->>'task_id')::uuid;
insert into p074_ids(name, id)
select 'task19', (public.assign_delivery_task(
  '07450000-0000-0000-0000-000000000019',
  '07450000-0000-0000-0000-000000000004',
  '07450000-0000-0000-0000-000000000909'
)->>'task_id')::uuid;

select pg_temp.set_p074_claims('07450000-0000-0000-0000-000000000003');
select public.accept_delivery_task((select id from p074_ids where name='task10'),'07450000-0000-0000-0000-000000000910');
select public.start_delivery_task((select id from p074_ids where name='task10'),'07450000-0000-0000-0000-000000000911');
select public.fail_delivery_task((select id from p074_ids where name='task10'),'07450000-0000-0000-0000-000000000912','bad_address',null);
select public.accept_delivery_task((select id from p074_ids where name='task11'),'07450000-0000-0000-0000-000000000913');
select public.start_delivery_task((select id from p074_ids where name='task11'),'07450000-0000-0000-0000-000000000914');
select public.fail_delivery_task((select id from p074_ids where name='task11'),'07450000-0000-0000-0000-000000000915','unreachable',null);
select public.accept_delivery_task((select id from p074_ids where name='task12'),'07450000-0000-0000-0000-000000000916');
select public.accept_delivery_task((select id from p074_ids where name='task13'),'07450000-0000-0000-0000-000000000917');
select public.start_delivery_task((select id from p074_ids where name='task13'),'07450000-0000-0000-0000-000000000918');
select public.accept_delivery_task((select id from p074_ids where name='task14'),'07450000-0000-0000-0000-000000000919');
select public.start_delivery_task((select id from p074_ids where name='task14'),'07450000-0000-0000-0000-000000000920');
select public.fail_delivery_task((select id from p074_ids where name='task14'),'07450000-0000-0000-0000-000000000921','reschedule',null);
select public.accept_delivery_task((select id from p074_ids where name='task15'),'07450000-0000-0000-0000-000000000922');
select public.start_delivery_task((select id from p074_ids where name='task15'),'07450000-0000-0000-0000-000000000923');
select public.fail_delivery_task((select id from p074_ids where name='task15'),'07450000-0000-0000-0000-000000000924','refusal',null);
select public.accept_delivery_task((select id from p074_ids where name='task16'),'07450000-0000-0000-0000-000000000925');
select pg_temp.set_p074_claims('07450000-0000-0000-0000-000000000004');
select public.accept_delivery_task((select id from p074_ids where name='task19'),'07450000-0000-0000-0000-000000000926');
reset role;

-- Manager decisions are the real P07.2 return RPCs.  Task 11 returns before
-- any second attempt; task 15 proves an accepted task 2 may be cancelled
-- early while retaining the original holder's custody proof.
set local role authenticated;
select pg_temp.set_p074_claims('07450000-0000-0000-0000-000000000002');
select public.decide_outbound_retry(
  '07450000-0000-0000-0000-000000000010',
  '07450000-0000-0000-0000-000000000930', 'return_to_store',
  (select id from p074_ids where name='task10'), null
);
select public.decide_outbound_retry(
  '07450000-0000-0000-0000-000000000011',
  '07450000-0000-0000-0000-000000000931', 'retry',
  (select id from p074_ids where name='task11'), null
);
insert into p074_ids(name, id)
select 'task11_2', id from public.delivery_tasks
where order_id='07450000-0000-0000-0000-000000000011'
  and attempt_number=2;
select public.decide_outbound_retry(
  '07450000-0000-0000-0000-000000000011',
  '07450000-0000-0000-0000-000000000932', 'return_to_store',
  (select id from p074_ids where name='task11'),
  (select id from p074_ids where name='task11_2')
);
select public.decide_outbound_retry(
  '07450000-0000-0000-0000-000000000015',
  '07450000-0000-0000-0000-000000000933', 'retry',
  (select id from p074_ids where name='task15'), null
);
insert into p074_ids(name, id)
select 'task15_2', id from public.delivery_tasks
where order_id='07450000-0000-0000-0000-000000000015'
  and attempt_number=2;
reset role;
set local role authenticated;
select pg_temp.set_p074_claims('07450000-0000-0000-0000-000000000003');
select public.accept_delivery_task((select id from p074_ids where name='task15_2'),'07450000-0000-0000-0000-000000000934');
reset role;
set local role authenticated;
select pg_temp.set_p074_claims('07450000-0000-0000-0000-000000000002');
select public.decide_outbound_retry(
  '07450000-0000-0000-0000-000000000015',
  '07450000-0000-0000-0000-000000000935', 'return_to_store',
  (select id from p074_ids where name='task15'),
  (select id from p074_ids where name='task15_2')
);
reset role;

-- Public RPC metadata and permission checks are repeated after fixture setup so
-- a role/profile mutation cannot accidentally broaden the report boundary.
set local role authenticated;
select pg_temp.set_p074_claims(null);
select pg_temp.assert_p074_error(
  'incident without JWT is rejected',
  $$select public.report_delivery_incident(
    (select id from p074_ids where name='task12'),
    '07450000-0000-0000-0000-000000000940',
    'damaged'::public.delivery_incident_kind, 'missing seal')$$,
  '42501', 'AUTH_REQUIRED'
);
select pg_temp.assert_p074_error(
  'handover without JWT is rejected',
  $$select public.report_store_handover(
    (select id from p074_ids where name='task10'),
    '07450000-0000-0000-0000-000000000941',
    jsonb_build_array(jsonb_build_object(
      'order_item_id', '07450000-0000-0000-0000-000000000210'::uuid,
      'quantity', 2)))$$,
  '42501', 'AUTH_REQUIRED'
);
select pg_temp.set_p074_claims('07450000-0000-0000-0000-000000000001');
select pg_temp.assert_p074_error(
  'customer cannot report incident',
  $$select public.report_delivery_incident(
    (select id from p074_ids where name='task12'),
    '07450000-0000-0000-0000-000000000942',
    'damaged'::public.delivery_incident_kind, 'customer forged shipper')$$,
  '42501', 'PERMISSION_DENIED'
);
select pg_temp.assert_p074_error(
  'customer cannot report handover',
  $$select public.report_store_handover(
    (select id from p074_ids where name='task10'),
    '07450000-0000-0000-0000-000000000943', '[]'::jsonb)$$,
  '42501', 'PERMISSION_DENIED'
);
select pg_temp.set_p074_claims('07450000-0000-0000-0000-000000000002');
select pg_temp.assert_p074_error(
  'manager cannot report incident',
  $$select public.report_delivery_incident(
    (select id from p074_ids where name='task12'),
    '07450000-0000-0000-0000-000000000944',
    'damaged'::public.delivery_incident_kind, 'manager forged shipper')$$,
  '42501', 'PERMISSION_DENIED'
);
select pg_temp.assert_p074_error(
  'manager cannot report handover',
  $$select public.report_store_handover(
    (select id from p074_ids where name='task10'),
    '07450000-0000-0000-0000-000000000945', '[]'::jsonb)$$,
  '42501', 'PERMISSION_DENIED'
);
reset role;

-- A task without custody and an unrelated assigned task are not reportable.
set local role authenticated;
select pg_temp.set_p074_claims('07450000-0000-0000-0000-000000000003');
select pg_temp.assert_p074_error(
  'assigned task has no incident custody',
  $$select public.report_delivery_incident(
    (select id from p074_ids where name='task18'),
    '07450000-0000-0000-0000-000000000946',
    'damaged'::public.delivery_incident_kind, 'before accept')$$,
  'PT409', 'CUSTODY_UNRESOLVED'
);
select pg_temp.assert_p074_error(
  'assigned task has no handover custody',
  $$select public.report_store_handover(
    (select id from p074_ids where name='task18'),
    '07450000-0000-0000-0000-000000000947',
    jsonb_build_array(jsonb_build_object(
      'order_item_id', '07450000-0000-0000-0000-000000000218'::uuid,
      'quantity', 1)))$$,
  'PT409', 'CUSTODY_UNRESOLVED'
);
select pg_temp.assert_p074_error(
  'other assigned shipper cannot report',
  $$select public.report_delivery_incident(
    (select id from p074_ids where name='task19'),
    '07450000-0000-0000-0000-000000000948',
    'damaged'::public.delivery_incident_kind, 'wrong holder')$$,
  '42501', 'NOT_FOUND_OR_FORBIDDEN'
);
select pg_temp.assert_p074_error(
  'missing task is uniformly forbidden',
  $$select public.report_delivery_incident(
    '07450000-0000-0000-0000-000000009999',
    '07450000-0000-0000-0000-000000000949',
    'damaged'::public.delivery_incident_kind, 'missing')$$,
  '42501', 'NOT_FOUND_OR_FORBIDDEN'
);
reset role;

-- Invalid request/reason/kind inputs fail before any write.
set local role authenticated;
select pg_temp.set_p074_claims('07450000-0000-0000-0000-000000000003');
select pg_temp.assert_p074_error(
  'null incident request is invalid',
  $$select public.report_delivery_incident(
    (select id from p074_ids where name='task12'), null,
    'damaged'::public.delivery_incident_kind, 'reason')$$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p074_error(
  'blank incident reason is invalid',
  $$select public.report_delivery_incident(
    (select id from p074_ids where name='task12'),
    '07450000-0000-0000-0000-000000000950',
    'damaged'::public.delivery_incident_kind, E' \t\n ')$$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p074_error(
  'null incident kind is invalid',
  $$select public.report_delivery_incident(
    (select id from p074_ids where name='task12'),
    '07450000-0000-0000-0000-000000000951', null,
    'reason')$$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p074_error(
  'null handover items are invalid',
  $$select public.report_store_handover(
    (select id from p074_ids where name='task10'),
    '07450000-0000-0000-0000-000000000952', null)$$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p074_error(
  'empty handover items are invalid',
  $$select public.report_store_handover(
    (select id from p074_ids where name='task10'),
    '07450000-0000-0000-0000-000000000953', '[]'::jsonb)$$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p074_error(
  'handover items must be an array',
  $$select public.report_store_handover(
    (select id from p074_ids where name='task10'),
    '07450000-0000-0000-0000-000000000954', '{}'::jsonb)$$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p074_error(
  'handover item quantity must be positive',
  $$select public.report_store_handover(
    (select id from p074_ids where name='task10'),
    '07450000-0000-0000-0000-000000000955',
    jsonb_build_array(jsonb_build_object(
      'order_item_id', '07450000-0000-0000-0000-000000000210'::uuid,
      'quantity', 0)))$$,
  '22023', 'INVALID_ARGUMENT'
);
reset role;

-- Snapshot all state that a report must not mutate.  The later assertions
-- include order/task/COD/stock/count/attempts and return/inventory ledgers.
reset role;
select pg_temp.set_p074_claims('07450000-0000-0000-0000-000000000002');
select public.decide_outbound_retry(
  '07450000-0000-0000-0000-000000000014',
  '07450000-0000-0000-0000-000000000981', 'return_to_store',
  (select id from p074_ids where name='task14'), null
);
create temp table p074_before as
select o.id as order_id, o.status as order_status,
  o.delivery_attempt_count as attempts,
  t.id as task_id, t.status as task_status, t.accepted_at,
  t.started_at, t.completed_at, t.failure_reason, t.cancel_reason,
  v.on_hand, v.reserved, v.damaged,
  c.status as cod_status, c.collected_amount_vnd, c.received_amount_vnd,
  c.collected_by, c.received_by,
  (select count(*) from public.delivery_attempts a where a.order_id=o.id) as result_count,
  (select count(*) from public.inventory_movements m where m.order_id=o.id) as movement_count,
  (select coalesce(sum(m.on_hand_delta),0) from public.inventory_movements m where m.order_id=o.id) as movement_on_hand,
  (select coalesce(sum(m.reserved_delta),0) from public.inventory_movements m where m.order_id=o.id) as movement_reserved,
  (select coalesce(sum(m.damaged_delta),0) from public.inventory_movements m where m.order_id=o.id) as movement_damaged,
  (select count(*) from public.return_items ri where ri.order_id=o.id) as return_item_count
from public.orders o
join public.delivery_tasks t on t.order_id=o.id
join public.product_variants v on v.id='07450000-0000-0000-0000-000000000111'
join public.cod_collections c on c.order_id=o.id
where o.id in (
  '07450000-0000-0000-0000-000000000010',
  '07450000-0000-0000-0000-000000000011',
  '07450000-0000-0000-0000-000000000012',
  '07450000-0000-0000-0000-000000000013',
  '07450000-0000-0000-0000-000000000014',
  '07450000-0000-0000-0000-000000000015',
  '07450000-0000-0000-0000-000000000016'
);

-- Accepted, in-transit and failed are all valid incident states.  Repeated
-- damage reports are intentional; a report is an append-only observation, not
-- an order/task state transition.
set local role authenticated;
select pg_temp.set_p074_claims('07450000-0000-0000-0000-000000000003');
insert into p074_responses(name,response)
select 'accepted_damage', public.report_delivery_incident(
  (select id from p074_ids where name='task12'),
  '07450000-0000-0000-0000-000000000960',
  'damaged'::public.delivery_incident_kind, 'seal damaged at customer');
insert into p074_responses(name,response)
select 'transit_lost', public.report_delivery_incident(
  (select id from p074_ids where name='task13'),
  '07450000-0000-0000-0000-000000000961',
  'lost'::public.delivery_incident_kind, 'one parcel missing');
insert into p074_responses(name,response)
select 'failed_other', public.report_delivery_incident(
  (select id from p074_ids where name='task14'),
  '07450000-0000-0000-0000-000000000962',
  'other'::public.delivery_incident_kind, 'weather delay');
insert into p074_responses(name,response)
select 'task10_damage_one', public.report_delivery_incident(
  (select id from p074_ids where name='task10'),
  '07450000-0000-0000-0000-000000000963',
  'damaged'::public.delivery_incident_kind, 'box damaged');
insert into p074_responses(name,response)
select 'task10_damage_two', public.report_delivery_incident(
  (select id from p074_ids where name='task10'),
  '07450000-0000-0000-0000-000000000964',
  'damaged'::public.delivery_incident_kind, 'seal damaged again');
-- Incident after handover is tested below with a new request key; do not treat
-- the report as an actual store receipt or as closing incident intake.
reset role;

-- Exact item proof: duplicate, partial, fake, zero and extra payload fields
-- A genuinely eligible return task with a lost report cannot claim full goods.
set local role authenticated;
select pg_temp.set_p074_claims('07450000-0000-0000-0000-000000000003');
savepoint p074_lost_return;
select public.report_delivery_incident((select id from p074_ids where name='task10'),
 '07450000-0000-0000-0000-000000000988','lost','missing parcel');
select pg_temp.assert_p074_error('lost blocks full handover on eligible return task',
 $$select public.report_store_handover((select id from p074_ids where name='task10'),
 '07450000-0000-0000-0000-000000000989',
 jsonb_build_array(jsonb_build_object('order_item_id','07450000-0000-0000-0000-000000000210'::uuid,'quantity',2)))$$,
 'PT409','CUSTODY_UNRESOLVED');
rollback to savepoint p074_lost_return;
reset role;

-- Exact item proof: duplicate, partial, fake, zero and extra payload fields
-- must not be accepted.  These calls are against a valid failed/returning
-- outbound task, so the error is item proof rather than an unrelated state.
set local role authenticated;
select pg_temp.set_p074_claims('07450000-0000-0000-0000-000000000003');
select pg_temp.assert_p074_error(
  'duplicate item refs are rejected',
  $$select public.report_store_handover(
    (select id from p074_ids where name='task10'),
    '07450000-0000-0000-0000-000000000970',
    jsonb_build_array(
      jsonb_build_object('order_item_id','07450000-0000-0000-0000-000000000210'::uuid,'quantity',1),
      jsonb_build_object('order_item_id','07450000-0000-0000-0000-000000000210'::uuid,'quantity',1)))$$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p074_error(
  'partial item quantity is rejected',
  $$select public.report_store_handover(
    (select id from p074_ids where name='task10'),
    '07450000-0000-0000-0000-000000000971',
    jsonb_build_array(jsonb_build_object(
      'order_item_id','07450000-0000-0000-0000-000000000210'::uuid,'quantity',1)))$$,
  'PT409', 'ITEMS_MISMATCH'
);
select pg_temp.assert_p074_error(
  'fake item ref is rejected',
  $$select public.report_store_handover(
    (select id from p074_ids where name='task10'),
    '07450000-0000-0000-0000-000000000972',
    jsonb_build_array(jsonb_build_object(
      'order_item_id','07450000-0000-0000-0000-000000009999'::uuid,'quantity',2)))$$,
  'PT409', 'ITEMS_MISMATCH'
);
select pg_temp.assert_p074_error(
  'extra handover payload fields are rejected',
  $$select public.report_store_handover(
    (select id from p074_ids where name='task10'),
    '07450000-0000-0000-0000-000000000973',
    jsonb_build_array(jsonb_build_object(
      'order_item_id','07450000-0000-0000-0000-000000000210'::uuid,
      'quantity',2, 'received_quantity',2)))$$,
  '22023', 'INVALID_ARGUMENT'
);
reset role;

-- Full damaged goods can be handed over.  The server derives the order-item
-- quantity and accepts exactly the full payload, including the two-unit item.
set local role authenticated;
select pg_temp.set_p074_claims('07450000-0000-0000-0000-000000000003');
insert into p074_responses(name,response)
select 'task10_handover', public.report_store_handover(
  (select id from p074_ids where name='task10'),
  '07450000-0000-0000-0000-000000000974',
  jsonb_build_array(jsonb_build_object(
    'order_item_id','07450000-0000-0000-0000-000000000210'::uuid,
    'quantity',2)));

-- Handover is once per order: identical replay is an exact ACK; a new key is
-- a deterministic conflict.  A later incident is still allowed for the same
-- current holder/state and produces its own event/owner notification.
insert into p074_responses(name,response)
select 'task10_handover_replay', public.report_store_handover(
  (select id from p074_ids where name='task10'),
  '07450000-0000-0000-0000-000000000974',
  jsonb_build_array(jsonb_build_object(
    'order_item_id','07450000-0000-0000-0000-000000000210'::uuid,
    'quantity',2)));
select pg_temp.assert_p074(
  'handover replay returns exact response',
  (select response from p074_responses where name='task10_handover') =
  (select response from p074_responses where name='task10_handover_replay')
);
select pg_temp.assert_p074_error(
  'new handover key on the same order is rejected',
  $$select public.report_store_handover(
    (select id from p074_ids where name='task10'),
    '07450000-0000-0000-0000-000000000975',
    jsonb_build_array(jsonb_build_object(
      'order_item_id','07450000-0000-0000-0000-000000000210'::uuid,'quantity',2)))$$,
  'PT409', 'STATE_CONFLICT'
);
insert into p074_responses(name,response)
select 'task10_damage_after_handover', public.report_delivery_incident(
  (select id from p074_ids where name='task10'),
  '07450000-0000-0000-0000-000000000976',
  'damaged'::public.delivery_incident_kind, 'damage reported after handover');
reset role;

-- A lost incident blocks the full handover claim; no resolution/restock RPC is
-- invented here.  The task remains untouched after the rejected claim.
set local role authenticated;
select pg_temp.set_p074_claims('07450000-0000-0000-0000-000000000003');
select pg_temp.assert_p074_error(
  'lost goods block full handover',
  $$select public.report_store_handover(
    (select id from p074_ids where name='task13'),
    '07450000-0000-0000-0000-000000000977',
    jsonb_build_array(jsonb_build_object(
      'order_item_id','07450000-0000-0000-0000-000000000212'::uuid,'quantity',1)))$$,
  'PT409', 'STATE_CONFLICT'
);
reset role;

-- Task 2 cancellation is valid with the original holder's proof.  The task 2
-- has no own dispatch; the retained task-1 custody is the authoritative proof.
set local role authenticated;
select pg_temp.set_p074_claims('07450000-0000-0000-0000-000000000003');
insert into p074_responses(name,response)
select 'task11_handover_assigned_cancel', public.report_store_handover(
  (select id from p074_ids where name='task11_2'),
  '07450000-0000-0000-0000-000000000978',
  jsonb_build_array(jsonb_build_object(
    'order_item_id','07450000-0000-0000-0000-000000000211'::uuid,'quantity',1)));
insert into p074_responses(name,response)
select 'task15_handover_accepted_cancel', public.report_store_handover(
  (select id from p074_ids where name='task15_2'),
  '07450000-0000-0000-0000-000000000979',
  jsonb_build_array(jsonb_build_object(
    'order_item_id','07450000-0000-0000-0000-000000000215'::uuid,'quantity',1)));
insert into p074_responses(name,response)
select 'task15_cancelled_incident', public.report_delivery_incident(
  (select id from p074_ids where name='task15_2'),
  '07450000-0000-0000-0000-000000000983',
  'damaged'::public.delivery_incident_kind, 'damage noticed while waiting return');
reset role;

-- Handover and incident request keys share one actor-scoped operation ledger:
-- using a successful incident key for a handover (or vice versa) is a payload
-- conflict, not a second business success.
set local role authenticated;
select pg_temp.set_p074_claims('07450000-0000-0000-0000-000000000003');
insert into p074_responses(name,response)
select 'task14_incident_for_crossop', public.report_delivery_incident(
  (select id from p074_ids where name='task14'),
  '07450000-0000-0000-0000-000000000980',
  'damaged'::public.delivery_incident_kind, 'cross operation key');
reset role;
set local role authenticated;
select pg_temp.set_p074_claims('07450000-0000-0000-0000-000000000002');

reset role;
set local role authenticated;
select pg_temp.set_p074_claims('07450000-0000-0000-0000-000000000003');
select pg_temp.assert_p074_error(
  'incident key cannot become handover key',
  $$select public.report_store_handover(
    (select id from p074_ids where name='task14'),
    '07450000-0000-0000-0000-000000000980',
    jsonb_build_array(jsonb_build_object(
      'order_item_id','07450000-0000-0000-0000-000000000214'::uuid,'quantity',1)))$$,
  'PT409', 'IDEMPOTENCY_CONFLICT'
);
select pg_temp.assert_p074_error(
  'handover key cannot become incident key',
  $$select public.report_delivery_incident(
    (select id from p074_ids where name='task10'),
    '07450000-0000-0000-0000-000000000974',
    'damaged'::public.delivery_incident_kind, 'operation mismatch')$$,
  'PT409', 'IDEMPOTENCY_CONFLICT'
);
reset role;

-- Exactly one event per successful report and only the single store-owner
-- manager receives a notification.  Customers and shippers must not be
-- notified, and no second manager is present in this fixture.
select pg_temp.assert_p074(
  'one event per successful report',
  (select count(*) = 1 from public.business_events
    where id = ((select response->>'event_id' from p074_responses where name='task10_handover')::uuid))
  and (select count(*) = 1 from public.business_events
    where id = ((select response->>'event_id' from p074_responses where name='task10_damage_after_handover')::uuid))
);
select pg_temp.assert_p074(
  'owner-only notifications',
  (select count(*) = 2 and bool_and(n.recipient_id='07450000-0000-0000-0000-000000000002'::uuid)
   from public.notifications n
   where n.event_id in (
     (select (response->>'event_id')::uuid from p074_responses where name='task10_handover'),
     (select (response->>'event_id')::uuid from p074_responses where name='task10_damage_after_handover')
   ))
  and (select count(*) = 0 from public.notifications n
   where n.event_id in (
     (select (response->>'event_id')::uuid from p074_responses where name='task10_handover'),
     (select (response->>'event_id')::uuid from p074_responses where name='task10_damage_after_handover')
   ) and n.recipient_id in (
     '07450000-0000-0000-0000-000000000001'::uuid,
     '07450000-0000-0000-0000-000000000003'::uuid,
     '07450000-0000-0000-0000-000000000004'::uuid,
     '07450000-0000-0000-0000-000000000005'::uuid
   ))
);

-- Reports preserve every task/order/stock/COD/result/receipt/restock field.
select pg_temp.assert_p074(
  'reports do not mutate business state',
  not exists (
    select 1
    from p074_before b
    join public.orders o on o.id=b.order_id
    join public.delivery_tasks t on t.id=b.task_id
    join public.product_variants v on v.id='07450000-0000-0000-0000-000000000111'
    join public.cod_collections c on c.order_id=b.order_id
    where o.status is distinct from b.order_status
       or o.delivery_attempt_count is distinct from b.attempts
       or t.status is distinct from b.task_status
       or t.accepted_at is distinct from b.accepted_at
       or t.started_at is distinct from b.started_at
       or t.completed_at is distinct from b.completed_at
       or t.failure_reason is distinct from b.failure_reason
       or t.cancel_reason is distinct from b.cancel_reason
       or v.on_hand is distinct from b.on_hand
       or v.reserved is distinct from b.reserved
       or v.damaged is distinct from b.damaged
       or c.status is distinct from b.cod_status
       or c.collected_amount_vnd is distinct from b.collected_amount_vnd
       or c.received_amount_vnd is distinct from b.received_amount_vnd
       or c.collected_by is distinct from b.collected_by
       or c.received_by is distinct from b.received_by
       or (select count(*) from public.delivery_attempts a where a.order_id=b.order_id) <> b.result_count
       or (select count(*) from public.inventory_movements m where m.order_id=b.order_id) <> b.movement_count
       or (select coalesce(sum(m.on_hand_delta),0) from public.inventory_movements m where m.order_id=b.order_id) <> b.movement_on_hand
       or (select coalesce(sum(m.reserved_delta),0) from public.inventory_movements m where m.order_id=b.order_id) <> b.movement_reserved
       or (select coalesce(sum(m.damaged_delta),0) from public.inventory_movements m where m.order_id=b.order_id) <> b.movement_damaged
       or (select count(*) from public.return_items ri where ri.order_id=b.order_id) <> b.return_item_count
  )
);

-- A late notification failure rolls back the event, notification and private
-- report ledger as one transaction.  This trigger is test-only and rolls back
-- with the surrounding suite.
create or replace function public.p074_report_late_fault()
returns trigger
language plpgsql
as $$
begin
  if current_setting('p074.test_fault', true) = 'after_notification' then
    raise exception using errcode = 'P0741', message = 'P074_TEST_LATE_FAULT';
  end if;
  return new;
end;
$$;
create trigger p074_report_late_fault
after insert on public.notifications
for each row execute function public.p074_report_late_fault();

create temp table p074_fault_before on commit drop as
select
  (select count(*) from public.business_events) as events,
  (select count(*) from public.notifications) as notifications,
  (select count(*) from public.business_events where task_id=(select id from p074_ids where name='task12')) as task_events;
select set_config('p074.test_fault','after_notification',true);
set local role authenticated;
select pg_temp.set_p074_claims('07450000-0000-0000-0000-000000000003');
select pg_temp.assert_p074_error(
  'late notification failure rolls back incident',
  $$select public.report_delivery_incident(
    (select id from p074_ids where name='task12'),
    '07450000-0000-0000-0000-000000000982',
    'damaged'::public.delivery_incident_kind, 'late notification fault')$$,
  'P0741', 'P074_TEST_LATE_FAULT'
);
reset role;
select pg_temp.assert_p074(
  'late fault leaves no event or notification',
  (select count(*)=(select events from p074_fault_before) from public.business_events)
  and (select count(*)=(select notifications from p074_fault_before) from public.notifications)
  and (select count(*)=(select task_events from p074_fault_before) from public.business_events
       where task_id=(select id from p074_ids where name='task12'))
);

-- The migration's public-event CHECK must keep handover reports distinct from
-- incidents: no incident kind, no fake from/to state transition.
select pg_temp.assert_p074(
  'handover event is not disguised as incident',
  (select incident_kind is null and task_id=(select id from p074_ids where name='task10')
          and subject_type='delivery_task' and subject_id=task_id
   from public.business_events
   where id=((select response->>'event_id' from p074_responses where name='task10_handover')::uuid))
);

drop trigger p074_report_late_fault on public.notifications;
drop function public.p074_report_late_fault();

select 'delivery_reporting_production.sql: PASS' as result,
  'transaction rolled back' as cleanup;
rollback;
