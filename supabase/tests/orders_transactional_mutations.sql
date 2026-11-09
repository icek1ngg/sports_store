-- Disposable local PostgreSQL ONLY. All fixtures/effects rolled back.
begin;
do $$ begin
 if current_setting('sports_store.qa_local_disposable',true) is distinct from 'YES' then raise exception 'Local disposable DB required'; end if;
end $$;
-- Reproduce hosted Supabase: custom writer cannot use managed auth schema.
-- The canonical identity-only helper must preserve all behavior without it.
revoke usage on schema auth from sports_store_orders_writer;
create function pg_temp.b2_check(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'B2 assertion: %',label; end if; end $$;
insert into auth.users(id,email) values
 ('a2222222-2222-4222-8222-222222222222','a@b2.invalid'),
 ('b2222222-2222-4222-8222-222222222222','b@b2.invalid'),
 ('c2222222-2222-4222-8222-222222222222','c@b2.invalid'),
 ('d2222222-2222-4222-8222-222222222222','d@b2.invalid');
update public.profiles set role='manager' where id='b2222222-2222-4222-8222-222222222222';
update public.profiles set role='shipper' where id='d2222222-2222-4222-8222-222222222222';
insert into public.categories(id,code,name) values('e2222222-2222-4222-8222-222222222221','b2-only','B2 fixture');
insert into public.products(id,category_id,name) values('e2222222-2222-4222-8222-222222222222','e2222222-2222-4222-8222-222222222221','B2 fixture');
insert into public.product_variants(id,product_id,sku,label,price_vnd,on_hand) values('e2222222-2222-4222-8222-222222222223','e2222222-2222-4222-8222-222222222222','B2-LOCAL','Local',100000,100);
insert into public.store_settings(id,name,address,latitude,longitude,approved_service_area_geojson)
 values(true,'Local','Local',21,105,'{"type":"Polygon","coordinates":[[[104,20],[106,20],[106,22],[104,22],[104,20]]]}')
 on conflict(id) do update set approved_service_area_geojson=excluded.approved_service_area_geojson;
create temp table b2_orders(label text primary key,id uuid,request uuid,receipt jsonb);
select set_config('request.jwt.claim.sub','a2222222-2222-4222-8222-222222222222',true);
do $$ declare label text; ack jsonb; begin
 foreach label in array array['confirm','reject','cancel','manager_cancel','corrupt','rollback'] loop
  ack:=public.place_order(gen_random_uuid(),'[{"variant_id":"e2222222-2222-4222-8222-222222222223","quantity":1}]','Local QA','0900000001','Local Hanoi',21,105);
  insert into b2_orders values(label,(ack#>>'{data,order,id}')::uuid,gen_random_uuid(),null);
 end loop;
end $$;
grant select,update on b2_orders to authenticated;
select pg_temp.b2_check(not has_function_privilege('anon','public.confirm_order(uuid,uuid)','execute'),'anon denied');
select pg_temp.b2_check(not has_table_privilege('authenticated','private.order_operation_receipts','select'),'ledger private');
select pg_temp.b2_check(not has_schema_privilege('sports_store_orders_writer','auth','USAGE'),'hosted Auth schema restriction reproduced');
select pg_temp.b2_check(has_function_privilege('sports_store_orders_writer','private.delivery_request_user_id()','EXECUTE') and not has_function_privilege('authenticated','private.delivery_request_user_id()','EXECUTE'),'internal identity bridge restricted');
select pg_temp.b2_check(not rolbypassrls and not rolcanlogin and not rolsuper,'writer constrained') from pg_roles where rolname='sports_store_orders_writer';
set local role authenticated;
do $$ declare o record; r jsonb; begin
 select * into o from b2_orders where label='confirm';
 perform pg_temp.b2_check(public.confirm_order(o.id,o.request)#>>'{error,code}'='forbidden_or_unavailable','customer cannot confirm');
 perform pg_temp.b2_check(public.get_order_details(o.id)#>>'{data,capabilities,can_cancel_customer}'='true','customer capability grounded');
end $$;
select set_config('request.jwt.claim.sub','c2222222-2222-4222-8222-222222222222',true);
do $$ declare o record; begin
 select * into o from b2_orders where label='cancel';
 perform pg_temp.b2_check(public.cancel_customer_order(o.id,o.request)#>>'{error,code}'='forbidden_or_unavailable','foreign cancel denied');
 perform pg_temp.b2_check(public.get_order_operation_result(o.request,o.id,'customer_cancel')#>>'{error,code}'='forbidden_or_unavailable','foreign lookup denied');
end $$;
select set_config('request.jwt.claim.sub','b2222222-2222-4222-8222-222222222222',true);
do $$ declare o record; r jsonb; first jsonb; begin
 select * into o from b2_orders where label='confirm';
 perform pg_temp.b2_check(public.get_order_operation_result(o.request,o.id,'confirm')#>>'{data,state}'='not_found','lookup no claim');
 perform pg_temp.b2_check(public.cancel_customer_order(o.id,o.request)#>>'{error,code}'='forbidden_or_unavailable','manager cannot impersonate customer operation');
 perform pg_temp.b2_check(public.get_order_details(o.id)#>>'{data,capabilities,can_confirm}'='true','manager capability');
 first:=public.confirm_order(o.id,o.request);
 perform pg_temp.b2_check(first#>>'{data,order,status}'='preparing','confirm preparing');
 update b2_orders set receipt=first where label='confirm';
 r:=public.confirm_order(o.id,o.request);
 perform pg_temp.b2_check(r#>>'{data,replayed}'='true' and r#>>'{data,event_id}'=first#>>'{data,event_id}','stable success replay');
 perform pg_temp.b2_check(public.reject_order(o.id,o.request,'different')#>>'{error,code}'='idempotency_conflict','same key changed operation');
 perform pg_temp.b2_check(public.confirm_order((select id from b2_orders where label='reject'),o.request)#>>'{error,code}'='idempotency_conflict','same key changed order');
 r:=public.confirm_order(o.id,gen_random_uuid());
 perform pg_temp.b2_check(r#>>'{error,code}'='state_changed','stale different key');
 perform pg_temp.b2_check(public.get_order_operation_result(o.request,o.id,'confirm')#>>'{data,state}'='committed','committed lookup');
 select * into o from b2_orders where label='reject';
 perform pg_temp.b2_check(public.reject_order(o.id,o.request,'  ')#>>'{error,code}'='invalid_argument','blank reason');
 first:=public.reject_order(o.id,o.request,E' \r\nQA\r\nreason\t');
 perform pg_temp.b2_check(first#>>'{data,order,status}'='rejected','reject success');
 perform pg_temp.b2_check(public.reject_order(o.id,o.request,E'QA\nreason')#>>'{data,replayed}'='true','normalized fingerprint replay');
 perform pg_temp.b2_check(public.reject_order(o.id,o.request,'QA reason')#>>'{error,code}'='idempotency_conflict','inner whitespace preserved');
 select * into o from b2_orders where label='manager_cancel';
 perform pg_temp.b2_check(public.confirm_order(o.id,gen_random_uuid())#>>'{data,order,status}'='preparing','prepare exceptional cancellation');
 r:=public.cancel_manager_order(o.id,o.request,'Local cancellation');
 perform pg_temp.b2_check(r#>>'{data,order,status}'='cancelled','never-assigned manager cancellation');
end $$;
select set_config('request.jwt.claim.sub','a2222222-2222-4222-8222-222222222222',true);
do $$ declare o record; r jsonb; first jsonb; begin
 select * into o from b2_orders where label='cancel';
 first:=public.cancel_customer_order(o.id,o.request);
 perform pg_temp.b2_check(first#>>'{data,order,status}'='cancelled','customer cancellation');
 perform pg_temp.b2_check(public.cancel_customer_order(o.id,o.request)#>>'{data,replayed}'='true','cancel replay after terminal state');
 select * into o from b2_orders where label='confirm';
 r:=public.cancel_customer_order(o.id,o.request);
 perform pg_temp.b2_check(r#>>'{error,code}'='cancellation_not_allowed','customer loses after confirm');
 perform pg_temp.b2_check(public.get_order_operation_result(o.request,o.id,'customer_cancel')#>>'{data,state}'='failed','terminal failure lookup');
 perform pg_temp.b2_check(public.cancel_customer_order(o.id,o.request)=r,'terminal failure stable replay');
end $$;
reset role;
select pg_temp.b2_check((select reserved from public.product_variants where sku='B2-LOCAL')=3,'release once only');
select pg_temp.b2_check((select count(*) from public.inventory_movements m join b2_orders o on o.id=m.order_id where kind='release')=3,'three release movements');
select pg_temp.b2_check(not exists(select 1 from private.order_operation_receipts r where r.outcome='success' and not exists(select 1 from private.business_event_contracts e where e.event_id=r.event_id)),'receipt/event atomic');
select pg_temp.b2_check(not exists(select 1 from private.business_event_contracts e where jsonb_array_length(e.notification_manifest)<>1),'frozen customer manifest');
-- Inject a late transaction error after effects: the caller must roll back ALL.
create function pg_temp.fail_receipt() returns trigger language plpgsql as $$ begin raise exception 'injected late failure'; end $$;
create trigger b2_injected_failure before insert on private.order_operation_receipts for each row execute function pg_temp.fail_receipt();
do $$ declare o record; before_stock bigint; begin
 select * into o from b2_orders where label='rollback';
 select reserved into before_stock from public.product_variants where sku='B2-LOCAL';
 perform set_config('request.jwt.claim.sub','b2222222-2222-4222-8222-222222222222',true);
 begin perform public.reject_order(o.id,o.request,'Injected'); raise exception 'must fail';
 exception when raise_exception then if sqlerrm<>'injected late failure' then raise; end if; end;
 perform pg_temp.b2_check((select status='pending_confirmation' from public.orders where id=o.id),'late error status rolled back');
 perform pg_temp.b2_check((select reserved=before_stock from public.product_variants where sku='B2-LOCAL'),'late error stock rolled back');
 perform pg_temp.b2_check(not exists(select 1 from private.order_operation_receipts where request_id=o.request),'late error no receipt');
 perform pg_temp.b2_check(not exists(select 1 from public.inventory_movements where order_id=o.id and kind='release'),'late error no release');
end $$;
drop trigger b2_injected_failure on private.order_operation_receipts;
-- Provenance missing: no fabricated eligibility or durable terminal error.
delete from private.checkout_placements where order_id=(select id from b2_orders where label='corrupt');
set local role authenticated;
select set_config('request.jwt.claim.sub','b2222222-2222-4222-8222-222222222222',true);
do $$ declare o record; begin
 select * into o from b2_orders where label='corrupt';
 perform pg_temp.b2_check(public.confirm_order(o.id,o.request)#>>'{error,code}'='custody_unverified','missing proof fails closed');
 perform pg_temp.b2_check(public.get_order_operation_result(o.request,o.id,'confirm')#>>'{data,state}'='not_found','dependency not cached terminal');
 perform pg_temp.b2_check(public.get_order_details(o.id)#>>'{data,capabilities,can_confirm}'='false','missing proof disabled');
end $$;
reset role;
select set_config('request.jwt.claim.sub','b2222222-2222-4222-8222-222222222222',true);
set local role authenticated;
do $$ declare o record; assignment jsonb; begin
 select * into o from b2_orders where label='confirm';
 assignment:=public.prepare_and_assign_delivery(o.id,'d2222222-2222-4222-8222-222222222222',gen_random_uuid(),true);
 perform pg_temp.b2_check(public.cancel_manager_order(o.id,gen_random_uuid(),'No revoke contract')#>>'{error,code}'='custody_unverified','assigned cancellation blocked');
 perform pg_temp.b2_check(public.get_order_details(o.id)#>>'{data,capabilities,can_cancel_exceptional}'='false','assigned capability disabled');
end $$;
reset role;
select pg_temp.b2_check((select count(*) from public.cod_collections where order_id=(select id from b2_orders where label='confirm'))=1,'existing COD obligation preserved');
update public.profiles set role='shipper' where id='b2222222-2222-4222-8222-222222222222';
set local role authenticated;
do $$ declare o record; begin
 select * into o from b2_orders where label='confirm';
 perform pg_temp.b2_check(public.get_order_operation_result(o.request,o.id,'confirm')#>>'{error,code}'='forbidden_or_unavailable','revoked manager cannot replay');
end $$;
reset role;
select 'orders_transactional_mutations.sql: PASS' as result;
rollback;
