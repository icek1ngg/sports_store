-- P10.3 READ-ONLY DEMO CATALOG, not an operational custody/stock seed.
-- Loaded only into a new guarded local database; no login/password/live users.
begin;
do $$ begin
  if current_setting('sports_store.fixture_mode',true) is distinct from 'p011_isolated'
     or current_database() !~ '^p011_' then
    raise exception 'P10.3 requires an isolated fixture database';
  end if;
end $$;
create function pg_temp.demo_id(n integer) returns uuid language sql immutable as $$
 select ('10300000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid
$$;
create function pg_temp.demo_assert(ok boolean) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'P10.3 catalog assertion failed';end if;end $$;

insert into auth.users(id,email)
select pg_temp.demo_id(n),'p103-'||n||'@example.invalid' from generate_series(1,5) n;
update public.profiles set role=case
 when id=pg_temp.demo_id(1) then 'manager'::public.user_role
 when id in(pg_temp.demo_id(2),pg_temp.demo_id(3)) then 'shipper'::public.user_role
 else 'customer'::public.user_role end
where id in(select pg_temp.demo_id(n) from generate_series(1,5)n);
insert into public.orders(id,customer_id,request_id,status,recipient_name,recipient_phone,
 address_detail,latitude,longitude,subtotal_vnd)
select pg_temp.demo_id(10+n),pg_temp.demo_id(case when n%2=0 then 4 else 5 end),
 pg_temp.demo_id(20+n),'delivered','DEMO recipient '||n,'0900000000',
 'DEMO saved Hanoi destination',21.028511,105.804817,520000
from generate_series(1,5)n;
insert into public.return_requests(id,order_id,customer_id,request_id,status,reason,
 description,video_object_path)
select pg_temp.demo_id(30+n),pg_temp.demo_id(10+n),customer_id,pg_temp.demo_id(40+n),
 case when n=2 then 'awaiting_return_pickup'::public.return_request_status
 else 'awaiting_redelivery'::public.return_request_status end,
 'defective','DEMO read-only request','fixture-only/no-object.mp4'
from generate_series(2,3)n join public.orders on id=pg_temp.demo_id(10+n);
insert into public.delivery_tasks(id,order_id,return_request_id,kind,assigned_shipper_id,
 assigned_by,status,attempt_number,destination_name,destination_phone,destination_address,
 destination_latitude,destination_longitude,amount_to_collect_vnd,assigned_at)
select pg_temp.demo_id(50+n),pg_temp.demo_id(10+n),
 case when n in(2,3) then pg_temp.demo_id(30+n) else null end,
 case n when 2 then 'return_pickup'::public.delivery_task_kind
 when 3 then 'redelivery'::public.delivery_task_kind else 'outbound'::public.delivery_task_kind end,
 pg_temp.demo_id(case when n=4 then 3 else 2 end),pg_temp.demo_id(1),'assigned',1,
 'DEMO recipient '||n,'0900000000','DEMO saved Hanoi destination',21.028511,105.804817,
 case when n in(2,3) then 0 else 550000 end,clock_timestamp()
from generate_series(1,4)n;
insert into public.cod_collections(order_id,shipper_id,status,expected_amount_vnd,
 collected_amount_vnd,collected_by,collected_at,received_amount_vnd,received_by,received_at,handed_over_at)
select pg_temp.demo_id(10+n),pg_temp.demo_id(case when n=4 then 3 else 2 end),
 case when n=4 then 'collected'::public.cod_status else 'received'::public.cod_status end,
 550000,550000,pg_temp.demo_id(case when n=4 then 3 else 2 end),clock_timestamp(),case when n=5 then 550000 else 0 end,
 case when n=5 then pg_temp.demo_id(1) else null end,
 case when n=5 then clock_timestamp() else null end,
 case when n=5 then clock_timestamp() else null end
from generate_series(4,5)n;

select pg_temp.demo_assert((select count(*)=5 from public.profiles));
select pg_temp.demo_assert((select count(*)filter(where role='manager')=1
 and count(*)filter(where role='shipper')=2 and count(*)filter(where role='customer')=2 from public.profiles));
select pg_temp.demo_assert((select count(distinct kind)=3 from public.delivery_tasks));
select pg_temp.demo_assert((select bool_and(
 assigned_shipper_id=pg_temp.demo_id(case when n=4 then 3 else 2 end)
 and amount_to_collect_vnd=case when n in(2,3) then 0 else 550000 end
 and kind::text=case n when 2 then 'return_pickup' when 3 then 'redelivery' else 'outbound' end)
 from generate_series(1,4)n join public.delivery_tasks on id=pg_temp.demo_id(50+n)));
set local role authenticated;
select set_config('request.jwt.claim.sub','10300000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"10300000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select pg_temp.demo_assert((select count(*)=3 from public.read_my_delivery_tasks(null)));
select pg_temp.demo_assert((select count(*)=0 from public.read_my_delivery_tasks('10300000-0000-4000-8000-000000000054')));
do $$ begin
 begin perform public.confirm_cod_received('10300000-0000-4000-8000-000000000014',550000,gen_random_uuid());
 raise exception 'P10.3 shipper receipt must be denied';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','10300000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"10300000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select pg_temp.demo_assert((select count(*)=1 from public.read_my_delivery_tasks('10300000-0000-4000-8000-000000000054')));
select pg_temp.demo_assert((public.list_cod_collections()->>'outstanding_vnd')::bigint=550000);
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','10300000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"10300000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select pg_temp.demo_assert((public.list_cod_collections()->>'outstanding_vnd')::bigint=550000);
select pg_temp.demo_assert(jsonb_array_length(public.list_cod_collections()->'items')=2);
reset role;
select pg_temp.demo_assert((select status='collected' and collected_amount_vnd=550000
 and received_amount_vnd=0 and shipper_id=pg_temp.demo_id(3)
 from public.cod_collections where order_id=pg_temp.demo_id(14)));
select pg_temp.demo_assert((select status='received' and collected_amount_vnd=550000
 and received_amount_vnd=550000 and shipper_id=pg_temp.demo_id(2)
 from public.cod_collections where order_id=pg_temp.demo_id(15)));
select 'P103 DEMO CATALOG' as demo_step,jsonb_build_object(
 'manager',pg_temp.demo_id(1),'shipper_a',pg_temp.demo_id(2),'shipper_b',pg_temp.demo_id(3),
 'customers',jsonb_build_array(pg_temp.demo_id(4),pg_temp.demo_id(5)),
 'tasks',jsonb_build_array(pg_temp.demo_id(51),pg_temp.demo_id(52),pg_temp.demo_id(53),pg_temp.demo_id(54)),
 'held_cod_vnd',(select sum(collected_amount_vnd) from public.cod_collections where status='collected'),
 'reconciled_cod_vnd',(select sum(received_amount_vnd) from public.cod_collections where status='received'),
 'scope','READ-ONLY FIXTURE; no physical custody/proof/Storage objects; rolled back') as snapshot;
select 'p103_demo_catalog.sql: PASS' as result;
rollback;
