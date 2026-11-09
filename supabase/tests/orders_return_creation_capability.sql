-- Disposable local database only. Never execute this fixture on shared Cloud.
-- Verifies migration 20261109124501: MH07 `can_open_return_creation`.
begin;
do $$ begin
 if current_setting('sports_store.qa_local_disposable',true) is distinct from 'YES' then
  raise exception 'Set sports_store.qa_local_disposable=YES only on an isolated local test DB';
 end if;
end $$;
create function pg_temp.check_cap(p_ok boolean,p_label text) returns void language plpgsql as $$
begin if p_ok is distinct from true then raise exception 'return capability assertion failed: %',p_label; end if; end $$;

insert into auth.users(id,raw_user_meta_data) values
 ('a2222222-1111-4111-8111-111111111111','{"full_name":"Customer QA"}'),
 ('b2222222-1111-4111-8111-111111111111','{"full_name":"Manager QA"}');
update public.profiles set role='manager' where id='b2222222-1111-4111-8111-111111111111';

-- 11: delivered 1 day ago (open); 12: delivered 8 days ago (expired);
-- 13: delivered 1 day ago with an active return; 14: pending confirmation.
insert into public.orders(id,customer_id,request_id,status,recipient_name,recipient_phone,address_detail,latitude,longitude,subtotal_vnd,placed_at,confirmed_at,delivered_at) values
 ('11111111-2222-4111-8111-111111111111','a2222222-1111-4111-8111-111111111111','11111111-3333-4111-8111-111111111111','delivered','QA','000','QA Hanoi',21,105,100,now()-interval '3 days',now()-interval '3 days',now()-interval '1 day'),
 ('12222222-2222-4111-8111-111111111111','a2222222-1111-4111-8111-111111111111','12222222-3333-4111-8111-111111111111','delivered','QA','000','QA Hanoi',21,105,100,now()-interval '10 days',now()-interval '10 days',now()-interval '8 days'),
 ('13333333-2222-4111-8111-111111111111','a2222222-1111-4111-8111-111111111111','13333333-3333-4111-8111-111111111111','delivered','QA','000','QA Hanoi',21,105,100,now()-interval '3 days',now()-interval '3 days',now()-interval '1 day'),
 ('14444444-2222-4111-8111-111111111111','a2222222-1111-4111-8111-111111111111','14444444-3333-4111-8111-111111111111','pending_confirmation','QA','000','QA Hanoi',21,105,100,now(),null,null);
insert into public.return_requests(order_id,customer_id,request_id,status,reason,description,video_object_path) values
 ('13333333-2222-4111-8111-111111111111','a2222222-1111-4111-8111-111111111111','13333333-4444-4111-8111-111111111111','pending_review','defective','QA active return','qa/video.mp4');

select pg_temp.check_cap(not (select prosecdef from pg_proc where oid='private.orders_return_creation_open(uuid)'::regprocedure),'helper is security invoker');
select pg_temp.check_cap(not has_function_privilege('anon','private.orders_return_creation_open(uuid)','execute'),'anon execute denied');
select pg_temp.check_cap(not (select prosecdef from pg_proc where oid='public.get_order_details(uuid)'::regprocedure),'get_order_details still invoker');

set local role authenticated;
select set_config('request.jwt.claim.sub','a2222222-1111-4111-8111-111111111111',true);
do $$ declare page jsonb; begin
 perform pg_temp.check_cap((public.get_order_details('11111111-2222-4111-8111-111111111111')#>>'{data,capabilities,can_open_return_creation}')::boolean,'customer delivered within 7 days: open');
 perform pg_temp.check_cap(not (public.get_order_details('12222222-2222-4111-8111-111111111111')#>>'{data,capabilities,can_open_return_creation}')::boolean,'expired 7-day window: closed');
 perform pg_temp.check_cap(not (public.get_order_details('13333333-2222-4111-8111-111111111111')#>>'{data,capabilities,can_open_return_creation}')::boolean,'active return exists: closed');
 perform pg_temp.check_cap(not (public.get_order_details('14444444-2222-4111-8111-111111111111')#>>'{data,capabilities,can_open_return_creation}')::boolean,'not delivered: closed');
 perform pg_temp.check_cap((public.get_order_details('14444444-2222-4111-8111-111111111111')#>>'{data,capabilities,can_cancel_customer}') is not null,'other capabilities preserved');
 page:=public.get_customer_orders(p_limit=>10);
 perform pg_temp.check_cap((select (x#>>'{capabilities,can_open_return_creation}')::boolean
   from jsonb_array_elements(page#>'{data,items}') x where x#>>'{order,id}'='11111111-2222-4111-8111-111111111111'),'list summary open');
 perform pg_temp.check_cap(not (select (x#>>'{capabilities,can_open_return_creation}')::boolean
   from jsonb_array_elements(page#>'{data,items}') x where x#>>'{order,id}'='12222222-2222-4111-8111-111111111111'),'list summary expired closed');
end $$;

select set_config('request.jwt.claim.sub','b2222222-1111-4111-8111-111111111111',true);
do $$ begin
 perform pg_temp.check_cap(not (public.get_order_details('11111111-2222-4111-8111-111111111111')#>>'{data,capabilities,can_open_return_creation}')::boolean,'manager never gets customer return entry');
end $$;

select 'orders_return_creation_capability PASS' as result;
rollback;
