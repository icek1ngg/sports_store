-- Disposable local database only. Never execute this fixture on shared Cloud.
-- Apply project schema/access/simplification and the new read migration first.
begin;
do $$ begin
 if current_setting('sports_store.qa_local_disposable',true) is distinct from 'YES' then
  raise exception 'Set sports_store.qa_local_disposable=YES only on an isolated local test DB';
 end if;
end $$;
create function pg_temp.check_orders(p_ok boolean,p_label text) returns void language plpgsql as $$
begin if p_ok is distinct from true then raise exception 'orders READ assertion failed: %',p_label; end if; end $$;
insert into auth.users(id,raw_user_meta_data) values
 ('a1111111-1111-4111-8111-111111111111','{"full_name":"Alice QA"}'),
 ('b1111111-1111-4111-8111-111111111111','{"full_name":"Manager QA"}'),
 ('c1111111-1111-4111-8111-111111111111','{"full_name":"Other QA"}'),
 ('d1111111-1111-4111-8111-111111111111','{"full_name":"Shipper QA"}');
update public.profiles set role='manager' where id='b1111111-1111-4111-8111-111111111111';
update public.profiles set role='shipper' where id='d1111111-1111-4111-8111-111111111111';
insert into public.categories(id,code,name) values ('e1111111-1111-4111-8111-111111111111','qa-orders-read','QA');
insert into public.products(id,category_id,name) values ('e2222222-2222-4222-8222-222222222222','e1111111-1111-4111-8111-111111111111','Current catalog name');
insert into public.product_variants(id,product_id,sku,label,price_vnd) values ('e3333333-3333-4333-8333-333333333333','e2222222-2222-4222-8222-222222222222','qa-orders-read','QA',100);
insert into public.orders(id,customer_id,request_id,status,recipient_name,recipient_phone,address_detail,latitude,longitude,subtotal_vnd,placed_at,confirmed_at,source,confirmed_by) values
 ('01111111-1111-4111-8111-111111111111','a1111111-1111-4111-8111-111111111111','91111111-1111-4111-8111-111111111111','pending_confirmation','Snapshot Recipient','000','QA Hanoi',21,105,200,'2026-11-01T00:00:00Z',null,null,null),
 ('02222222-2222-4222-8222-222222222222','a1111111-1111-4111-8111-111111111111','92222222-2222-4222-8222-222222222222','pending_confirmation','Snapshot Recipient','000','QA Hanoi',21,105,0,'2026-11-01T00:00:00Z',null,null,null),
 ('03333333-3333-4333-8333-333333333333','a1111111-1111-4111-8111-111111111111','93333333-3333-4333-8333-333333333333','preparing','Snapshot Recipient','000','QA Hanoi',21,105,0,'2026-10-31T00:00:00Z','2026-10-31T01:00:00Z','manager','b1111111-1111-4111-8111-111111111111'),
 ('04444444-4444-4444-8444-444444444444','c1111111-1111-4111-8111-111111111111','94444444-4444-4444-8444-444444444444','pending_confirmation','Private C Recipient','000','QA Hanoi',21,105,0,'2026-11-02T00:00:00Z',null,null,null);
insert into public.order_items(id,order_id,product_id,variant_id,product_name,variant_label,unit_price_vnd,quantity) values
 ('05555555-5555-4555-8555-555555555555','01111111-1111-4111-8111-111111111111','e2222222-2222-4222-8222-222222222222','e3333333-3333-4333-8333-333333333333','Snapshot %Ball_','QA',100,2);
select pg_temp.check_orders(not has_function_privilege('anon','public.get_order_details(uuid)','execute'),'anon execute denied');
select pg_temp.check_orders(not (select prosecdef from pg_proc where oid='public.get_order_details(uuid)'::regprocedure),'security invoker');
set local role authenticated;
select set_config('request.jwt.claim.sub','a1111111-1111-4111-8111-111111111111',true);
set local timezone='Asia/Ho_Chi_Minh';
do $$ declare first_page jsonb; next_page jsonb; detail jsonb; all_page jsonb; f jsonb; c text; begin
 first_page:=public.get_customer_orders(p_limit=>1);
 perform pg_temp.check_orders((first_page->>'ok')::boolean,'A page success');
 perform pg_temp.check_orders(first_page#>>'{data,total_count}'='3','A count excludes C');
 perform pg_temp.check_orders((select count(*) from jsonb_object_keys(first_page#>'{data,status_counts}'))=10,'all ten status keys');
 perform pg_temp.check_orders(first_page#>>'{data,status_counts,pending_confirmation}'='2','pending count complete');
 perform pg_temp.check_orders(first_page#>>'{data,items,0,order,id}'='02222222-2222-4222-8222-222222222222','UUID descending tie-break');
 c:=first_page#>>'{data,next_cursor}';
 next_page:=public.get_customer_orders(p_limit=>1,p_cursor=>c);
 perform pg_temp.check_orders(next_page#>>'{data,items,0,order,id}'='01111111-1111-4111-8111-111111111111','keyset second row');
 perform pg_temp.check_orders(next_page#>>'{data,total_count}'='3','count ignores cursor');
 perform pg_temp.check_orders(public.get_customer_orders(p_limit=>2,p_cursor=>c)#>>'{error,code}'='invalid_cursor','cursor limit binding');
 perform pg_temp.check_orders(public.get_customer_orders(p_search=>'different',p_limit=>1,p_cursor=>c)#>>'{error,code}'='invalid_cursor','cursor search binding');
 perform pg_temp.check_orders(public.get_customer_orders(p_limit=>1,p_cursor=>'eyJ2IjpudWxsfQ')#>>'{error,code}'='invalid_cursor','malformed cursor');
 perform pg_temp.check_orders(public.get_customer_orders(p_limit=>0)#>>'{error,code}'='invalid_argument','invalid limit');
 perform pg_temp.check_orders(public.get_customer_orders(p_statuses=>array[null]::public.order_status[])#>>'{error,code}'='invalid_argument','null enum denied');
 f:=public.get_customer_orders(p_statuses=>array['preparing']::public.order_status[]);
 perform pg_temp.check_orders(f#>>'{data,total_count}'='1' and f#>>'{data,status_counts,pending_confirmation}'='2','status counters exclude filter');
 f:=public.get_customer_orders(p_search=>'%Ball_');
 perform pg_temp.check_orders(f#>>'{data,total_count}'='1','literal wildcard search and item snapshot');
 perform pg_temp.check_orders(public.get_customer_orders(p_search=>'Current catalog name')#>>'{data,total_count}'='0','not catalog live-name search');
 perform pg_temp.check_orders(public.get_manager_orders()#>>'{error,code}'='forbidden_or_unavailable','customer denied manager list');
 perform pg_temp.check_orders(public.get_order_details('04444444-4444-4444-8444-444444444444')#>>'{error,code}'='forbidden_or_unavailable','foreign C detail denied');
 perform pg_temp.check_orders(public.get_order_details('09999999-9999-4999-8999-999999999999')#>>'{error,code}'='forbidden_or_unavailable','missing indistinguishable');
 detail:=public.get_order_details('01111111-1111-4111-8111-111111111111');
 perform pg_temp.check_orders(detail#>>'{data,items,0,product_name}'='Snapshot %Ball_','immutable item snapshot');
 perform pg_temp.check_orders(detail#>>'{data,items,0,quantity}'='2','detail full quantities');
 perform pg_temp.check_orders(detail#>'{data,buyer}'='null'::jsonb,'customer buyer null');
 perform pg_temp.check_orders(detail#>>'{data,history_complete}'='false','incomplete history honest');
 perform pg_temp.check_orders(detail#>'{data,delivery_summary}'='null'::jsonb and detail#>'{data,cod_summary}'='null'::jsonb,'external summaries unavailable');
 perform pg_temp.check_orders(not exists(select 1 from jsonb_each_text(detail#>'{data,capabilities}') v where v.value<>'false'),'all mutation flags unavailable');
 perform pg_temp.check_orders(detail#>>'{data,as_of}' ~ '(Z|[+]00:00)$' and detail#>>'{data,order,placed_at}' ~ '(Z|[+]00:00)$','UTC despite session timezone');
 detail:=public.get_order_details('03333333-3333-4333-8333-333333333333');
 perform pg_temp.check_orders(detail#>'{data,order,confirmed_by}'='null'::jsonb,'customer confirmation actor sanitized');
 perform pg_temp.check_orders(not exists(select 1 from jsonb_array_elements(detail#>'{data,timeline}') t where t->>'source'<>'snapshot_milestone' or t->'event_id'<>'null'::jsonb or t->'actor_id'<>'null'::jsonb),'no invented event/actor');
end $$;
select set_config('request.jwt.claim.sub','b1111111-1111-4111-8111-111111111111',true);
do $$ declare r jsonb; begin
 r:=public.get_manager_orders(p_search=>'Alice QA');
 perform pg_temp.check_orders(r#>>'{data,total_count}'='3','manager searches account name');
 perform pg_temp.check_orders(public.get_manager_orders(p_search=>'Snapshot Recipient')#>>'{data,total_count}'='0','manager no recipient fallback');
 perform pg_temp.check_orders(public.get_manager_orders()#>>'{data,total_count}'='4','manager all authorized orders');
 r:=public.get_order_details('03333333-3333-4333-8333-333333333333');
 perform pg_temp.check_orders(r#>>'{data,buyer,id}'='a1111111-1111-4111-8111-111111111111','manager buyer safe projection');
 perform pg_temp.check_orders(r#>>'{data,order,confirmed_by}'='b1111111-1111-4111-8111-111111111111','manager confirmation actor retained');
end $$;
select set_config('request.jwt.claim.sub','c1111111-1111-4111-8111-111111111111',true);
select pg_temp.check_orders(public.get_customer_orders()#>>'{data,total_count}'='1','C isolated list');
select pg_temp.check_orders(public.get_order_details('01111111-1111-4111-8111-111111111111')#>>'{error,code}'='forbidden_or_unavailable','C denied A detail');
select set_config('request.jwt.claim.sub','d1111111-1111-4111-8111-111111111111',true);
select pg_temp.check_orders(public.get_customer_orders()#>>'{error,code}'='forbidden_or_unavailable','shipper denied list');
select pg_temp.check_orders(public.get_order_details('01111111-1111-4111-8111-111111111111')#>>'{error,code}'='forbidden_or_unavailable','shipper denied details');
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_orders(public.get_customer_orders()#>>'{error,code}'='unauthenticated','expired/no identity fail closed');
reset role;
update public.profiles set full_name=null where id='a1111111-1111-4111-8111-111111111111';
update public.orders set status='delivered',delivered_at='2026-11-02T00:00:00Z' where id='01111111-1111-4111-8111-111111111111';
insert into public.return_requests(id,order_id,customer_id,request_id,status,reason,description,video_object_path)
 values('06666666-6666-4666-8666-666666666666','01111111-1111-4111-8111-111111111111',
 'a1111111-1111-4111-8111-111111111111','96666666-6666-4666-8666-666666666666','pending_review','defective','QA fixture','qa-only/video.mp4');
set local role authenticated;
select set_config('request.jwt.claim.sub','a1111111-1111-4111-8111-111111111111',true);
do $$ declare c text; r jsonb; begin
 c:=public.get_customer_orders(p_limit=>1)#>>'{data,next_cursor}';
 perform set_config('request.jwt.claim.sub','c1111111-1111-4111-8111-111111111111',true);
 perform pg_temp.check_orders(public.get_customer_orders(p_limit=>1,p_cursor=>c)#>>'{error,code}'='invalid_cursor','cross-account cursor rejected');
 perform set_config('request.jwt.claim.sub','b1111111-1111-4111-8111-111111111111',true);
 perform pg_temp.check_orders(public.get_manager_orders(p_limit=>1,p_cursor=>c)#>>'{error,code}'='invalid_cursor','cross-role cursor rejected');
 perform pg_temp.check_orders(public.get_manager_orders(p_search=>'Alice QA')#>>'{data,total_count}'='0','null buyer name has no recipient fallback');
 r:=public.get_order_details('01111111-1111-4111-8111-111111111111');
 perform pg_temp.check_orders(r#>'{data,buyer,full_name}'='null'::jsonb,'null manager buyer name preserved');
 perform set_config('request.jwt.claim.sub','a1111111-1111-4111-8111-111111111111',true);
 r:=public.get_order_details('01111111-1111-4111-8111-111111111111');
 perform pg_temp.check_orders(r#>>'{data,return_summaries,0,return_id}'='06666666-6666-4666-8666-666666666666','actual return not dropped');
 perform pg_temp.check_orders(r#>>'{data,return_summaries,0,is_active}'='true','existing active return truthful');
 perform pg_temp.check_orders(r#>>'{data,return_summaries,0,can_submit_return}'='false' and r#>>'{data,return_summaries,0,eligibility_reason}'='missing_contract','no invented eligibility');
 perform pg_temp.check_orders(not (r#>'{data,return_summaries,0}' ? 'video_object_path'),'return evidence omitted');
 perform set_config('request.jwt.claim.sub','c1111111-1111-4111-8111-111111111111',true);
 perform pg_temp.check_orders(public.get_order_details('01111111-1111-4111-8111-111111111111')#>>'{error,code}'='forbidden_or_unavailable','foreign return graph denied');
end $$;
reset role;
rollback;
select 'ORDERS_READ_SQL_PASS' as result;
