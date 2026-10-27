-- P07.2 production manager retry/return decision contract.
--
-- This suite intentionally runs in one transaction and rolls back. It uses
-- the real P03.3 assignment, P04.1 accept/start and P07.1 failure RPCs; only
-- the P07.2 fixture rows are seeded here. The second outbound task must be
-- assigned but not accepted by the decision RPC. The existing shipper
-- accept/start path proves custody continuation and increments the order
-- attempt count exactly once without a second dispatch.
begin;
set constraints all deferred;

create or replace function pg_temp.set_p072_claims(p_user_id uuid)
returns void language plpgsql as $$
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

create or replace function pg_temp.assert_p072(p_label text, p_ok boolean)
returns void language plpgsql as $$
begin
  if coalesce(p_ok, false) is not true then
    raise exception 'P07.2 production test failed: %', p_label;
  end if;
end;
$$;

create or replace function pg_temp.assert_p072_error(
  p_label text, p_sql text, p_state text, p_message text
)
returns void language plpgsql as $$
declare l_state text; l_message text;
begin
  begin execute p_sql;
  exception when others then
    get stacked diagnostics l_state = returned_sqlstate, l_message = message_text;
  end;
  if l_state is distinct from p_state or l_message is distinct from p_message then
    raise exception 'P07.2 production error % expected %/% got %/%', p_label,
      p_state, p_message, coalesce(l_state, 'success'), coalesce(l_message, '');
  end if;
end;
$$;

create or replace function pg_temp.assert_p072_state(
  p_label text, p_sql text, p_state text
)
returns void language plpgsql as $$
declare l_state text;
begin
  begin execute p_sql;
  exception when others then get stacked diagnostics l_state = returned_sqlstate;
  end;
  if l_state is distinct from p_state then
    raise exception 'P07.2 production error % expected % got %', p_label,
      p_state, coalesce(l_state, 'success');
  end if;
end;
$$;

-- Metadata/ACL checks are catalog based. They do not assume a client can read
-- the P07.2 private ledger, nor do they grant it one.
do $$
declare l_proc record; l_owner record; l_private_count integer; l_private record;
begin
  select p.*, pg_get_userbyid(p.proowner) as owner_name into l_proc
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.oid='public.decide_outbound_retry(uuid,uuid,text,uuid,uuid)'::regprocedure;
  if not found or l_proc.prosecdef is not true
     or not (l_proc.proconfig @> array['search_path=""']) then
    raise exception 'P07.2 RPC metadata is not SECURITY DEFINER/search_path empty';
  end if;
  if l_proc.owner_name is null or l_proc.owner_name in ('postgres','supabase_admin') then
    raise exception 'P07.2 RPC must have a dedicated non-login owner';
  end if;
  select r.rolcanlogin,r.rolsuper,r.rolbypassrls,r.rolinherit,
         r.rolcreaterole,r.rolcreatedb,r.rolreplication into l_owner
  from pg_roles r where r.rolname=l_proc.owner_name;
  if not found or l_owner.rolcanlogin or l_owner.rolsuper or l_owner.rolbypassrls
     or l_owner.rolinherit or l_owner.rolcreaterole or l_owner.rolcreatedb
     or l_owner.rolreplication then raise exception 'P07.2 RPC owner is unsafe'; end if;
  if not has_function_privilege('authenticated',
       'public.decide_outbound_retry(uuid,uuid,text,uuid,uuid)','EXECUTE')
     or has_function_privilege('anon',
       'public.decide_outbound_retry(uuid,uuid,text,uuid,uuid)','EXECUTE')
     or has_function_privilege('service_role',
       'public.decide_outbound_retry(uuid,uuid,text,uuid,uuid)','EXECUTE') then
    raise exception 'P07.2 RPC ACL is broader than authenticated';
  end if;
  select count(*) into l_private_count from pg_class c join pg_namespace n
    on n.oid=c.relnamespace where n.nspname='private' and c.relkind='r'
      and (c.relname like '%retry%' or c.relname like '%decision%');
  if l_private_count=0 then raise exception 'P07.2 private retry/decision ledger is missing'; end if;
  for l_private in select c.relname,c.relrowsecurity,c.relforcerowsecurity
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='private' and c.relkind='r'
      and (c.relname like '%retry%' or c.relname like '%decision%') loop
    if not l_private.relrowsecurity or not l_private.relforcerowsecurity then
      raise exception 'P07.2 private ledger % must force RLS',l_private.relname;
    end if;
    if has_table_privilege('authenticated',format('private.%I',l_private.relname),'SELECT,INSERT,UPDATE,DELETE')
       or has_table_privilege('anon',format('private.%I',l_private.relname),'SELECT,INSERT,UPDATE,DELETE')
       or has_table_privilege('service_role',format('private.%I',l_private.relname),'SELECT,INSERT,UPDATE,DELETE') then
      raise exception 'P07.2 private ledger % is client-readable/writable',l_private.relname;
    end if;
  end loop;
end;
$$;

-- One product/variant backs five separate orders. Each order has its own
-- reservation evidence; P04.1 dispatch consumes one unit, while retry/return
-- must never consume a second unit.
insert into auth.users (id,email) values
  ('07250000-0000-0000-0000-000000000001','p072-customer@example.invalid'),
  ('07250000-0000-0000-0000-000000000002','p072-manager-a@example.invalid'),
  ('07250000-0000-0000-0000-000000000003','p072-manager-b@example.invalid'),
  ('07250000-0000-0000-0000-000000000004','p072-shipper-a@example.invalid'),
  ('07250000-0000-0000-0000-000000000005','p072-shipper-b@example.invalid'),
  ('07250000-0000-0000-0000-000000000006','p072-other-customer@example.invalid');
update public.profiles set role=case
  when id in ('07250000-0000-0000-0000-000000000002','07250000-0000-0000-0000-000000000003') then 'manager'::public.user_role
  when id in ('07250000-0000-0000-0000-000000000004','07250000-0000-0000-0000-000000000005') then 'shipper'::public.user_role
  else 'customer'::public.user_role end
where id in ('07250000-0000-0000-0000-000000000001','07250000-0000-0000-0000-000000000002',
             '07250000-0000-0000-0000-000000000003','07250000-0000-0000-0000-000000000004',
             '07250000-0000-0000-0000-000000000005','07250000-0000-0000-0000-000000000006');
insert into public.categories(id,code,name)
values ('07250000-0000-0000-0000-000000000100','P072','P07.2 retry');
insert into public.products(id,category_id,name)
values ('07250000-0000-0000-0000-000000000101','07250000-0000-0000-0000-000000000100','P07.2 product');
insert into public.product_variants(id,product_id,sku,label,price_vnd,on_hand,reserved)
values ('07250000-0000-0000-0000-000000000111','07250000-0000-0000-0000-000000000101',
        'P072-01','P07.2 variant',520000,5,5);

insert into public.orders(
  id,customer_id,request_id,status,recipient_name,recipient_phone,address_detail,
  latitude,longitude,subtotal_vnd,delivery_attempt_count
) values
  ('07250000-0000-0000-0000-000000000010','07250000-0000-0000-0000-000000000001','07250000-0000-0000-0000-000000000010','preparing','P072 main','0907200001','P072 Hanoi main',21.0285,105.8542,520000,0),
  ('07250000-0000-0000-0000-000000000011','07250000-0000-0000-0000-000000000001','07250000-0000-0000-0000-000000000011','preparing','P072 early return','0907200002','P072 Hanoi early',21.0285,105.8542,520000,0),
  ('07250000-0000-0000-0000-000000000012','07250000-0000-0000-0000-000000000001','07250000-0000-0000-0000-000000000012','preparing','P072 assigned return','0907200003','P072 Hanoi assigned',21.0285,105.8542,520000,0),
  ('07250000-0000-0000-0000-000000000013','07250000-0000-0000-0000-000000000001','07250000-0000-0000-0000-000000000013','preparing','P072 accepted return','0907200004','P072 Hanoi accepted',21.0285,105.8542,520000,0),
  ('07250000-0000-0000-0000-000000000014','07250000-0000-0000-0000-000000000001','07250000-0000-0000-0000-000000000014','preparing','P072 late fault','0907200005','P072 Hanoi fault',21.0285,105.8542,520000,0);
insert into public.order_items(id,order_id,product_id,variant_id,product_name,variant_label,unit_price_vnd,quantity)
select v.item_id,v.order_id,'07250000-0000-0000-0000-000000000101'::uuid,
       '07250000-0000-0000-0000-000000000111'::uuid,'P07.2 product','P07.2 variant',520000,1
from (values
 ('07250000-0000-0000-0000-000000000201'::uuid,'07250000-0000-0000-0000-000000000010'::uuid),
 ('07250000-0000-0000-0000-000000000202'::uuid,'07250000-0000-0000-0000-000000000011'::uuid),
 ('07250000-0000-0000-0000-000000000203'::uuid,'07250000-0000-0000-0000-000000000012'::uuid),
 ('07250000-0000-0000-0000-000000000204'::uuid,'07250000-0000-0000-0000-000000000013'::uuid),
 ('07250000-0000-0000-0000-000000000205'::uuid,'07250000-0000-0000-0000-000000000014'::uuid)
) v(item_id,order_id);
insert into public.inventory_movements(variant_id,order_id,event_id,kind,reserved_delta,actor_id,reason)
select '07250000-0000-0000-0000-000000000111'::uuid,v.order_id,v.event_id,
       'reserve'::public.inventory_movement_kind,1,
       '07250000-0000-0000-0000-000000000002'::uuid,'p072 reservation'
from (values
 ('07250000-0000-0000-0000-000000000010'::uuid,'07250000-0000-0000-0000-000000000301'::uuid),
 ('07250000-0000-0000-0000-000000000011'::uuid,'07250000-0000-0000-0000-000000000302'::uuid),
 ('07250000-0000-0000-0000-000000000012'::uuid,'07250000-0000-0000-0000-000000000303'::uuid),
 ('07250000-0000-0000-0000-000000000013'::uuid,'07250000-0000-0000-0000-000000000304'::uuid),
 ('07250000-0000-0000-0000-000000000014'::uuid,'07250000-0000-0000-0000-000000000305'::uuid)
) v(order_id,event_id);

-- Initial assignment is the real P03.3 API. P07.2 never fabricates task 1.
set local role authenticated;
create temp table p072_ids(name text primary key,id uuid) on commit drop;
create temp table p072_responses(name text primary key,response jsonb) on commit drop;
select pg_temp.set_p072_claims('07250000-0000-0000-0000-000000000002');
insert into p072_ids(name,id) select 'main_task1',(public.assign_delivery_task(
 '07250000-0000-0000-0000-000000000010'::uuid,'07250000-0000-0000-0000-000000000004'::uuid,
 '07250000-0000-0000-0000-000000000401'::uuid,null,null)->>'task_id')::uuid;
insert into p072_ids(name,id) select 'early_task1',(public.assign_delivery_task(
 '07250000-0000-0000-0000-000000000011'::uuid,'07250000-0000-0000-0000-000000000004'::uuid,
 '07250000-0000-0000-0000-000000000402'::uuid,null,null)->>'task_id')::uuid;
insert into p072_ids(name,id) select 'assigned_task1',(public.assign_delivery_task(
 '07250000-0000-0000-0000-000000000012'::uuid,'07250000-0000-0000-0000-000000000004'::uuid,
 '07250000-0000-0000-0000-000000000403'::uuid,null,null)->>'task_id')::uuid;
insert into p072_ids(name,id) select 'accepted_task1',(public.assign_delivery_task(
 '07250000-0000-0000-0000-000000000013'::uuid,'07250000-0000-0000-0000-000000000004'::uuid,
 '07250000-0000-0000-0000-000000000404'::uuid,null,null)->>'task_id')::uuid;
insert into p072_ids(name,id) select 'fault_task1',(public.assign_delivery_task(
 '07250000-0000-0000-0000-000000000014'::uuid,'07250000-0000-0000-0000-000000000004'::uuid,
 '07250000-0000-0000-0000-000000000405'::uuid,null,null)->>'task_id')::uuid;

select pg_temp.set_p072_claims('07250000-0000-0000-0000-000000000004');
select public.accept_delivery_task((select id from p072_ids where name='main_task1'),'07250000-0000-0000-0000-000000000411'::uuid);
select public.start_delivery_task((select id from p072_ids where name='main_task1'),'07250000-0000-0000-0000-000000000412'::uuid);
select public.fail_delivery_task((select id from p072_ids where name='main_task1'),'07250000-0000-0000-0000-000000000413'::uuid,'bad_address',null);
select public.accept_delivery_task((select id from p072_ids where name='early_task1'),'07250000-0000-0000-0000-000000000421'::uuid);
select public.start_delivery_task((select id from p072_ids where name='early_task1'),'07250000-0000-0000-0000-000000000422'::uuid);
select public.fail_delivery_task((select id from p072_ids where name='early_task1'),'07250000-0000-0000-0000-000000000423'::uuid,'unreachable',null);
select public.accept_delivery_task((select id from p072_ids where name='assigned_task1'),'07250000-0000-0000-0000-000000000431'::uuid);
select public.start_delivery_task((select id from p072_ids where name='assigned_task1'),'07250000-0000-0000-0000-000000000432'::uuid);
select public.fail_delivery_task((select id from p072_ids where name='assigned_task1'),'07250000-0000-0000-0000-000000000433'::uuid,'reschedule',null);
select public.accept_delivery_task((select id from p072_ids where name='accepted_task1'),'07250000-0000-0000-0000-000000000441'::uuid);
select public.start_delivery_task((select id from p072_ids where name='accepted_task1'),'07250000-0000-0000-0000-000000000442'::uuid);
select public.fail_delivery_task((select id from p072_ids where name='accepted_task1'),'07250000-0000-0000-0000-000000000443'::uuid,'refusal',null);
select public.accept_delivery_task((select id from p072_ids where name='fault_task1'),'07250000-0000-0000-0000-000000000451'::uuid);
select public.start_delivery_task((select id from p072_ids where name='fault_task1'),'07250000-0000-0000-0000-000000000452'::uuid);
select public.fail_delivery_task((select id from p072_ids where name='fault_task1'),'07250000-0000-0000-0000-000000000453'::uuid,'other','late fault fixture');

reset role;
-- Main chain: manager retry creates task 2 for the same shipper, but no
-- acceptance/custody/dispatch is fabricated by the decision.
select pg_temp.set_p072_claims('07250000-0000-0000-0000-000000000002');
insert into p072_responses(name,response)
select 'main_retry',public.decide_outbound_retry(
 '07250000-0000-0000-0000-000000000010'::uuid,'07250000-0000-0000-0000-000000000461'::uuid,
 'retry',(select id from p072_ids where name='main_task1'),null);
insert into p072_ids(name,id) select 'main_task2',id from public.delivery_tasks
where order_id='07250000-0000-0000-0000-000000000010'::uuid and attempt_number=2;
select pg_temp.assert_p072('retry creates exactly one assigned task 2',
 (select count(*)=1 from public.delivery_tasks where order_id='07250000-0000-0000-0000-000000000010'::uuid and attempt_number=2)
 and (select status='assigned' and assigned_shipper_id='07250000-0000-0000-0000-000000000004'::uuid
      and accepted_at is null and started_at is null and completed_at is null and failure_reason is null
      from public.delivery_tasks where id=(select id from p072_ids where name='main_task2'))
 and (select count(*)=0 from private.outbound_custody_acceptances where task_id=(select id from p072_ids where name='main_task2')));
select pg_temp.assert_p072('retry leaves order awaiting pickup/count one',
 (select status='awaiting_pickup' and delivery_attempt_count=1 from public.orders where id='07250000-0000-0000-0000-000000000010'::uuid));
select pg_temp.assert_p072('retry preserves same shipper and full COD snapshot',
 (select t.assigned_shipper_id='07250000-0000-0000-0000-000000000004'::uuid and t.amount_to_collect_vnd=o.total_cod_vnd
      and c.expected_amount_vnd=o.total_cod_vnd and c.status='uncollected'::public.cod_status
      and c.collected_amount_vnd=0 and c.received_amount_vnd=0
      from public.delivery_tasks t join public.orders o on o.id=t.order_id
      join public.cod_collections c on c.order_id=o.id where t.id=(select id from p072_ids where name='main_task2')));
select pg_temp.assert_p072('retry notification goes only to the custody holder',
 (select count(*)=1 and bool_and(n.recipient_id='07250000-0000-0000-0000-000000000004'::uuid)
  from public.notifications n where n.subject_id=(select id from p072_ids where name='main_task2')));

-- Idempotent replay is exact; a changed decision/expected-task payload is not.
insert into p072_responses(name,response)
select 'main_retry_replay',public.decide_outbound_retry(
 '07250000-0000-0000-0000-000000000010'::uuid,'07250000-0000-0000-0000-000000000461'::uuid,
 'retry',(select id from p072_ids where name='main_task1'),null);
select pg_temp.assert_p072('retry duplicate returns exact response',
 (select response from p072_responses where name='main_retry')=(select response from p072_responses where name='main_retry_replay'));
select pg_temp.assert_p072_error('retry payload mismatch is rejected',
 $$select public.decide_outbound_retry('07250000-0000-0000-0000-000000000010'::uuid,
  '07250000-0000-0000-0000-000000000461'::uuid,'return_to_store',
  '07250000-0000-0000-0000-000000000020'::uuid,'07250000-0000-0000-0000-000000000021'::uuid)$$,
 'PT409','IDEMPOTENCY_CONFLICT');

-- Role changes are rechecked before replay; a stale manager session cannot
-- receive the old response after losing its server-managed role.
reset role;
update public.profiles set role='customer'::public.user_role where id='07250000-0000-0000-0000-000000000002'::uuid;
reset role;
select pg_temp.set_p072_claims('07250000-0000-0000-0000-000000000002');
select pg_temp.assert_p072_error('lost manager role rejects retry replay',
 $$select public.decide_outbound_retry('07250000-0000-0000-0000-000000000010'::uuid,
  '07250000-0000-0000-0000-000000000461'::uuid,'retry',
  '07250000-0000-0000-0000-000000000020'::uuid,null)$$,
 '42501','PERMISSION_DENIED');
reset role;
update public.profiles set role='manager'::public.user_role where id='07250000-0000-0000-0000-000000000002'::uuid;
reset role;

-- The real shipper accept/start path transfers the existing dispatch proof to
-- task 2. Stock, dispatch history and COD remain unchanged; count rises once.
select pg_temp.set_p072_claims('07250000-0000-0000-0000-000000000004');
create temp table p072_main_stock_before on commit drop as
select on_hand,reserved from public.product_variants where id='07250000-0000-0000-0000-000000000111'::uuid;
create temp table p072_main_dispatch_before on commit drop as
select count(*)::int as n from public.inventory_movements
where order_id='07250000-0000-0000-0000-000000000010'::uuid and kind='dispatch'::public.inventory_movement_kind;
select public.accept_delivery_task((select id from p072_ids where name='main_task2'),'07250000-0000-0000-0000-000000000462'::uuid);
select pg_temp.assert_p072('second accept owns custody but does not start',
 (select status='accepted' and accepted_at is not null and started_at is null from public.delivery_tasks where id=(select id from p072_ids where name='main_task2'))
 and (select count(*)=1 from private.outbound_custody_acceptances where task_id=(select id from p072_ids where name='main_task2'))
 and (select v.on_hand=b.on_hand and v.reserved=b.reserved from public.product_variants v cross join p072_main_stock_before b where v.id='07250000-0000-0000-0000-000000000111'::uuid)
 and (select count(*)=(select n from p072_main_dispatch_before) from public.inventory_movements where order_id='07250000-0000-0000-0000-000000000010'::uuid and kind='dispatch'::public.inventory_movement_kind));
select public.start_delivery_task((select id from p072_ids where name='main_task2'),'07250000-0000-0000-0000-000000000463'::uuid);
select pg_temp.assert_p072('second start increments order count once/no second stock deduction',
 (select status='in_transit' from public.delivery_tasks where id=(select id from p072_ids where name='main_task2'))
 and (select status='delivering' and delivery_attempt_count=2 from public.orders where id='07250000-0000-0000-0000-000000000010'::uuid)
 and (select v.on_hand=b.on_hand and v.reserved=b.reserved from public.product_variants v cross join p072_main_stock_before b where v.id='07250000-0000-0000-0000-000000000111'::uuid)
 and (select count(*)=(select n from p072_main_dispatch_before) from public.inventory_movements where order_id='07250000-0000-0000-0000-000000000010'::uuid and kind='dispatch'::public.inventory_movement_kind));
select public.fail_delivery_task((select id from p072_ids where name='main_task2'),'07250000-0000-0000-0000-000000000464'::uuid,'bad_address',null);
select pg_temp.assert_p072('second failure preserves COD/stock and awaits store return',
 (select status='failed' from public.delivery_tasks where id=(select id from p072_ids where name='main_task2'))
 and (select status='awaiting_store_return' and delivery_attempt_count=2 from public.orders where id='07250000-0000-0000-0000-000000000010'::uuid)
 and (select count(*)=2 and bool_and(result='failed'::public.delivery_attempt_result) from public.delivery_attempts where order_id='07250000-0000-0000-0000-000000000010'::uuid)
 and (select status='uncollected'::public.cod_status and collected_amount_vnd=0 and received_amount_vnd=0 from public.cod_collections where order_id='07250000-0000-0000-0000-000000000010'::uuid));
select pg_temp.set_p072_claims('07250000-0000-0000-0000-000000000002');
select pg_temp.assert_p072('retry ACK remains replayable after second attempt finished',
 public.decide_outbound_retry('07250000-0000-0000-0000-000000000010'::uuid,
  '07250000-0000-0000-0000-000000000461'::uuid,'retry',
  (select id from p072_ids where name='main_task1'),null)
  = (select response from p072_responses where name='main_retry'));
select pg_temp.assert_p072_error('third retry is denied by order attempt count',
 $$select public.decide_outbound_retry('07250000-0000-0000-0000-000000000010'::uuid,
  '07250000-0000-0000-0000-000000000465'::uuid,'retry',
  (select id from p072_ids where name='main_task2'),null)$$,
 'PT409','ATTEMPT_LIMIT');
select pg_temp.assert_p072_state('decision cannot switch after task 2 start/failure',
 $$select public.decide_outbound_retry('07250000-0000-0000-0000-000000000010'::uuid,
  '07250000-0000-0000-0000-000000000466'::uuid,'return_to_store',
  (select id from p072_ids where name='main_task1'),
  (select id from p072_ids where name='main_task2'))$$,
 'PT409');

-- Early return after first failure: no retry task is created and custody/history
-- remains on the failed first task.
select pg_temp.set_p072_claims('07250000-0000-0000-0000-000000000002');
select public.decide_outbound_retry('07250000-0000-0000-0000-000000000011'::uuid,
   '07250000-0000-0000-0000-000000000471'::uuid,'return_to_store',
   (select id from p072_ids where name='early_task1'),null);
select pg_temp.assert_p072('early return succeeds without task 2',
 true
 and (select count(*)=1 from public.delivery_tasks where order_id='07250000-0000-0000-0000-000000000011'::uuid)
 and (select status='failed' from public.delivery_tasks where id=(select id from p072_ids where name='early_task1'))
 and (select delivery_attempt_count=1 from public.orders where id='07250000-0000-0000-0000-000000000011'::uuid));

-- Retry then return while task 2 is still assigned. The explicit expected
-- retry task ID is required by the CAS; the task is cancelled, not deleted.
insert into p072_responses(name,response)
select 'assigned_retry',public.decide_outbound_retry('07250000-0000-0000-0000-000000000012'::uuid,
 '07250000-0000-0000-0000-000000000481'::uuid,'retry',
 (select id from p072_ids where name='assigned_task1'),null);
insert into p072_ids(name,id) select 'assigned_task2',id from public.delivery_tasks
where order_id='07250000-0000-0000-0000-000000000012'::uuid and attempt_number=2;
select public.decide_outbound_retry('07250000-0000-0000-0000-000000000012'::uuid,
   '07250000-0000-0000-0000-000000000482'::uuid,'return_to_store',
   (select id from p072_ids where name='assigned_task1'),(select id from p072_ids where name='assigned_task2'));
select pg_temp.assert_p072('return after task 2 assigned keeps history and stock',
 true
 and (select status='cancelled' and accepted_at is null and started_at is null from public.delivery_tasks where id=(select id from p072_ids where name='assigned_task2'))
 and (select count(*)=2 from public.delivery_tasks where order_id='07250000-0000-0000-0000-000000000012'::uuid)
 and (select status='failed' from public.delivery_tasks where id=(select id from p072_ids where name='assigned_task1')));

-- Retry then accept task 2, then switch to return before start. Custody is
-- retained for audit/history even though the task becomes cancelled.
select pg_temp.set_p072_claims('07250000-0000-0000-0000-000000000002');
insert into p072_responses(name,response)
select 'accepted_retry',public.decide_outbound_retry('07250000-0000-0000-0000-000000000013'::uuid,
 '07250000-0000-0000-0000-000000000491'::uuid,'retry',
 (select id from p072_ids where name='accepted_task1'),null);
insert into p072_ids(name,id) select 'accepted_task2',id from public.delivery_tasks
where order_id='07250000-0000-0000-0000-000000000013'::uuid and attempt_number=2;
select pg_temp.set_p072_claims('07250000-0000-0000-0000-000000000004');
select public.accept_delivery_task((select id from p072_ids where name='accepted_task2'),'07250000-0000-0000-0000-000000000492'::uuid);
select pg_temp.set_p072_claims('07250000-0000-0000-0000-000000000002');
reset role;
select pg_temp.assert_p072_error('normal direct cancellation of accepted task 2 is denied',
 $$update public.delivery_tasks set status='cancelled' where id=(select id from p072_ids where name='accepted_task2')$$,
 'PT409','CUSTODY_UNRESOLVED');
reset role;
select pg_temp.set_p072_claims('07250000-0000-0000-0000-000000000002');
select public.decide_outbound_retry('07250000-0000-0000-0000-000000000013'::uuid,
   '07250000-0000-0000-0000-000000000493'::uuid,'return_to_store',
   (select id from p072_ids where name='accepted_task1'),(select id from p072_ids where name='accepted_task2'));
select pg_temp.assert_p072('return after task 2 accepted cancels but retains custody/history',
 true
 and (select status='cancelled' and accepted_at is not null and started_at is null from public.delivery_tasks where id=(select id from p072_ids where name='accepted_task2'))
 and (select count(*)=1 from private.outbound_custody_acceptances where task_id=(select id from p072_ids where name='accepted_task2'))
 and (select count(*)=2 from public.delivery_tasks where order_id='07250000-0000-0000-0000-000000000013'::uuid)
 and (select delivery_attempt_count=1 from public.orders where id='07250000-0000-0000-0000-000000000013'::uuid));
-- Generic assignment cannot switch an accepted retry holder; only the
-- trusted P07.2 decision path may cancel it before start.
select pg_temp.assert_p072_state('accepted retry task cannot be reassigned through P03 CAS',
 $$select public.assign_delivery_task('07250000-0000-0000-0000-000000000013'::uuid,
  '07250000-0000-0000-0000-000000000005'::uuid,'07250000-0000-0000-0000-000000000494'::uuid,
  (select id from p072_ids where name='accepted_task2'),'07250000-0000-0000-0000-000000000004'::uuid)$$,
 'PT409');

-- Late notification failure must roll back task creation, decision state,
-- history, notification and private idempotency result as one transaction.
reset role;
create or replace function public.p072_test_late_fault()
returns trigger language plpgsql as $$
begin
  if current_setting('p072.test_fault',true)='after_notification' then
    raise exception using errcode='P0722',message='P072_TEST_LATE_FAULT';
  end if;
  return new;
end;
$$;
create trigger p072_test_late_fault after insert on public.notifications
for each row execute function public.p072_test_late_fault();
reset role;
select pg_temp.set_p072_claims('07250000-0000-0000-0000-000000000002');
create temp table p072_fault_before on commit drop as
select (select count(*)::int from public.delivery_tasks where order_id='07250000-0000-0000-0000-000000000014'::uuid) task_count,
       (select count(*)::int from public.notifications where subject_id='07250000-0000-0000-0000-000000000014'::uuid) notification_count,
       (select count(*)::int from public.business_events where subject_id='07250000-0000-0000-0000-000000000014'::uuid) event_count;
select set_config('p072.test_fault','after_notification',true);
select pg_temp.assert_p072_error('late notification fault rolls back retry',
 $$select public.decide_outbound_retry('07250000-0000-0000-0000-000000000014'::uuid,
  '07250000-0000-0000-0000-000000000501'::uuid,'retry',
  (select id from p072_ids where name='fault_task1'),null)$$,
 'P0722','P072_TEST_LATE_FAULT');
select pg_temp.assert_p072('late fault leaves no task/notification/event mutation',
 (select count(*)=(select task_count from p072_fault_before) from public.delivery_tasks where order_id='07250000-0000-0000-0000-000000000014'::uuid)
 and (select count(*)=(select notification_count from p072_fault_before) from public.notifications where subject_id='07250000-0000-0000-0000-000000000014'::uuid)
 and (select count(*)=(select event_count from p072_fault_before) from public.business_events where subject_id='07250000-0000-0000-0000-000000000014'::uuid)
 and (select count(*)=1 from public.delivery_tasks where order_id='07250000-0000-0000-0000-000000000014'::uuid and attempt_number=1)
 and (select status='awaiting_redelivery' from public.orders where id='07250000-0000-0000-0000-000000000014'::uuid));
reset role;
drop trigger p072_test_late_fault on public.notifications;
drop function public.p072_test_late_fault();

-- Read privacy: a different shipper/customer cannot use an old assignment or
-- order ownership to read the retry task; private ledgers are also denied.
set local role authenticated;
select pg_temp.set_p072_claims('07250000-0000-0000-0000-000000000005');
select pg_temp.assert_p072_error('shipper cannot choose retry directly',
 $$select public.decide_outbound_retry('07250000-0000-0000-0000-000000000010',
 '07250000-0000-0000-0000-000000000601','retry',
 (select id from p072_ids where name='main_task1'),null)$$,
 '42501','PERMISSION_DENIED');
select pg_temp.assert_p072('different shipper cannot read retry task',
 (select count(*)=0 from public.delivery_tasks where id=(select id from p072_ids where name='main_task2')));
select pg_temp.set_p072_claims('07250000-0000-0000-0000-000000000006');
select pg_temp.assert_p072_error('customer cannot choose return directly',
 $$select public.decide_outbound_retry('07250000-0000-0000-0000-000000000010',
 '07250000-0000-0000-0000-000000000602','return_to_store',
 (select id from p072_ids where name='main_task1'),null)$$,
 '42501','PERMISSION_DENIED');
select pg_temp.assert_p072('different customer cannot read retry task',
 (select count(*)=0 from public.delivery_tasks where id=(select id from p072_ids where name='main_task2')));
do $$
declare l_private record; l_denied boolean;
begin
  for l_private in select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='private' and c.relkind='r' and (c.relname like '%retry%' or c.relname like '%decision%') loop
    begin execute format('select count(*) from private.%I',l_private.relname); l_denied:=false;
    exception when insufficient_privilege then l_denied:=true; end;
    if not l_denied then raise exception 'P07.2 private ledger % leaked to authenticated',l_private.relname; end if;
  end loop;
end;
$$;

reset role;
select 'outbound_retry_production.sql: PASS' as result,
       'P07.2 real retry/return/custody/CAS/privacy/rollback contract' as scope;
rollback;

