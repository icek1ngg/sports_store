-- Local isolated PostgreSQL regression; fixture rows are rolled back.
begin;
create function pg_temp.prep_assert(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'Preparation assertion: %',label; end if; end $$;
create function pg_temp.prep_error(command text,expected_state text,expected_message text) returns void
language plpgsql as $$
declare s text; m text;
begin
 begin execute command; exception when others then
  get stacked diagnostics s=returned_sqlstate,m=message_text; end;
 if s is distinct from expected_state or m is distinct from expected_message then
  raise exception 'Expected % %, got % %',expected_state,expected_message,s,m; end if;
end $$;
insert into auth.users(id,email) values
 ('09180000-0000-0000-0000-000000000001','prep-customer@example.invalid'),
 ('09180000-0000-0000-0000-000000000002','prep-manager@example.invalid'),
 ('09180000-0000-0000-0000-000000000003','prep-shipper@example.invalid');
update public.profiles set role=case right(id::text,1) when '2' then 'manager'::public.user_role
 when '3' then 'shipper'::public.user_role else 'customer'::public.user_role end
 where id::text like '09180000-%';
insert into public.orders(id,customer_id,request_id,status,recipient_name,recipient_phone,
 address_detail,latitude,longitude,subtotal_vnd)
select id,'09180000-0000-0000-0000-000000000001',id,'preparing','Preparation fixture',
 '0900000000','Ha Noi',21.0285,105.8542,100000
from unnest(array['09180000-0000-0000-0000-000000000010'::uuid,
 '09180000-0000-0000-0000-000000000011'::uuid,
 '09180000-0000-0000-0000-000000000012'::uuid]) id;
-- Pre-existing clean pending task must be reused, not duplicated.
insert into public.delivery_tasks(id,order_id,kind,status,attempt_number,destination_name,
 destination_phone,destination_address,destination_latitude,destination_longitude,amount_to_collect_vnd)
values('09180000-0000-0000-0000-000000000040','09180000-0000-0000-0000-000000000012',
 'outbound','pending_assignment',1,'Preparation fixture','0900000000','Ha Noi',21.0285,105.8542,130000);
create temp table prep_baseline as select
 (select count(*) from public.inventory_movements) movements,
 (select coalesce(jsonb_agg(to_jsonb(b) order by b.id),'[]') from public.product_variants b) balances;
create temp table prep_results(result jsonb);
grant select,insert on prep_results to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','09180000-0000-0000-0000-000000000001',true);
select pg_temp.prep_assert(not private.orders_can_assign_prepared('09180000-0000-0000-0000-000000000010'),'customer cannot assign');
select pg_temp.prep_error($q$select public.prepare_and_assign_delivery('09180000-0000-0000-0000-000000000010','09180000-0000-0000-0000-000000000003','09180000-0000-0000-0000-000000000020',true)$q$,'42501','PERMISSION_DENIED');
select set_config('request.jwt.claim.sub','09180000-0000-0000-0000-000000000003',true);
select pg_temp.prep_assert(not private.orders_can_assign_prepared('09180000-0000-0000-0000-000000000010'),'shipper cannot assign');
select pg_temp.prep_error($q$select public.prepare_and_assign_delivery('09180000-0000-0000-0000-000000000010','09180000-0000-0000-0000-000000000003','09180000-0000-0000-0000-000000000020',true)$q$,'42501','PERMISSION_DENIED');
select set_config('request.jwt.claim.sub','09180000-0000-0000-0000-000000000002',true);
select pg_temp.prep_assert(private.orders_can_assign_prepared('09180000-0000-0000-0000-000000000010'),'manager capability');
select pg_temp.prep_error($q$select public.prepare_and_assign_delivery('09180000-0000-0000-0000-000000000010','09180000-0000-0000-0000-000000000003','09180000-0000-0000-0000-000000000020',false)$q$,'22023','PREPARATION_REQUIRED');
select pg_temp.prep_error($q$select public.prepare_and_assign_delivery('09180000-0000-0000-0000-000000000010','09180000-0000-0000-0000-000000000003','09180000-0000-0000-0000-000000000020',null)$q$,'22023','PREPARATION_REQUIRED');
select pg_temp.prep_error($q$select public.assign_delivery_task('09180000-0000-0000-0000-000000000010','09180000-0000-0000-0000-000000000003','09180000-0000-0000-0000-000000000020')$q$,'PT409','PREPARATION_REQUIRED');
-- Failed assignment rolls the preparation proof back too.
select pg_temp.prep_error($q$select public.prepare_and_assign_delivery('09180000-0000-0000-0000-000000000010','09180000-0000-0000-0000-000000000001','09180000-0000-0000-0000-000000000020',true)$q$,'PT409','INVALID_SHIPPER');
insert into prep_results select public.prepare_and_assign_delivery('09180000-0000-0000-0000-000000000010','09180000-0000-0000-0000-000000000003','09180000-0000-0000-0000-000000000020',true);
select pg_temp.prep_assert((select result=public.prepare_and_assign_delivery('09180000-0000-0000-0000-000000000010','09180000-0000-0000-0000-000000000003','09180000-0000-0000-0000-000000000020',true) from prep_results),'exact replay');
select pg_temp.prep_error($q$select public.prepare_and_assign_delivery('09180000-0000-0000-0000-000000000011','09180000-0000-0000-0000-000000000003','09180000-0000-0000-0000-000000000020',true)$q$,'PT409','IDEMPOTENCY_CONFLICT');
select pg_temp.prep_assert(not private.orders_can_assign_prepared('09180000-0000-0000-0000-000000000010'),'assigned capability false');
select pg_temp.prep_assert((public.prepare_and_assign_delivery('09180000-0000-0000-0000-000000000012','09180000-0000-0000-0000-000000000003','09180000-0000-0000-0000-000000000022',true)->>'task_id')='09180000-0000-0000-0000-000000000040','existing pending task reused');
-- Successful proof for another order cannot authorize a direct initial assignment.
select pg_temp.prep_error($q$select public.assign_delivery_task('09180000-0000-0000-0000-000000000011','09180000-0000-0000-0000-000000000003','09180000-0000-0000-0000-000000000023')$q$,'PT409','PREPARATION_REQUIRED');
select set_config('request.jwt.claim.sub','',true);
select pg_temp.prep_error($q$select public.prepare_and_assign_delivery('09180000-0000-0000-0000-000000000011','09180000-0000-0000-0000-000000000003','09180000-0000-0000-0000-000000000024',true)$q$,'42501','AUTH_REQUIRED');
reset role;
select pg_temp.prep_assert((select count(*)=2 from private.delivery_preparation_proofs where actor_id='09180000-0000-0000-0000-000000000002'),'two proofs; failures rolled back');
select pg_temp.prep_assert((select status='awaiting_pickup' and delivery_attempt_count=0 from public.orders where id='09180000-0000-0000-0000-000000000010'),'order assigned without attempt');
select pg_temp.prep_assert((select count(*)=1 from public.delivery_tasks where order_id='09180000-0000-0000-0000-000000000010' and status='assigned' and attempt_number=1),'single assigned task');
select pg_temp.prep_assert((select status='uncollected' and expected_amount_vnd=130000 from public.cod_collections where order_id='09180000-0000-0000-0000-000000000010'),'COD includes delivery fee');
select pg_temp.prep_assert(not exists(select 1 from public.delivery_attempts where order_id::text like '09180000-%'),'no attempt rows');
select pg_temp.prep_assert((select movements=(select count(*) from public.inventory_movements) and balances=(select coalesce(jsonb_agg(to_jsonb(b) order by b.id),'[]') from public.product_variants b) from prep_baseline),'inventory unchanged');
select pg_temp.prep_assert((select count(*)=2 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where (n.nspname,p.proname) in (('private','orders_read_summary'),('public','get_order_details'))
 and position('orders_can_assign_prepared' in p.prosrc)>0 and position('orders_return_creation_open' in p.prosrc)>0),'both capability merges preserved');
select pg_temp.prep_assert(not has_table_privilege('authenticated','private.delivery_preparation_proofs','INSERT'),'no client proof writes');
rollback;
