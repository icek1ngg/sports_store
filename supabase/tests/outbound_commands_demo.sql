-- P04.1 DEMO ONLY. The runner replaces the marker with the isolated
-- p041_demo schema/functions. This suite is never a deployment migration.
begin;
set constraints all deferred;

-- P041_DEMO_FIXTURE

create or replace function pg_temp.assert_demo(label text, condition boolean)
returns void language plpgsql as $$
begin
  if coalesce(condition, false) is not true then
    raise exception 'P04.1 demo failed: %', label;
  end if;
end;
$$;
create or replace function pg_temp.set_demo_claims(user_id uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(user_id::text, ''), true);
  perform set_config('request.jwt.claims', case when user_id is null then '' else
    jsonb_build_object('sub', user_id::text, 'role', 'authenticated', 'aud', 'authenticated')::text end, true);
end;
$$;
create or replace function pg_temp.assert_demo_error(label text, command text, state text, message text)
returns void language plpgsql as $$
declare got_state text; got_message text;
begin
  begin execute command;
  exception when others then get stacked diagnostics got_state = returned_sqlstate, got_message = message_text;
  end;
  if got_state is distinct from state or got_message is distinct from message then
    raise exception 'P04.1 demo failed: % expected %/% got %/%', label, state, message,
      coalesce(got_state,'success'), coalesce(got_message,'');
  end if;
end;
$$;

insert into p041_demo.actors values
 ('04110000-0000-0000-0000-000000000001','customer'),
 ('04110000-0000-0000-0000-000000000002','shipper'),
 ('04110000-0000-0000-0000-000000000003','shipper'),
 ('04110000-0000-0000-0000-000000000004','manager');
insert into p041_demo.orders values
 ('04110000-0000-0000-0000-000000000010','awaiting_pickup',0),
 ('04110000-0000-0000-0000-000000000011','awaiting_pickup',0),
 ('04110000-0000-0000-0000-000000000012','awaiting_pickup',0),
 ('04110000-0000-0000-0000-000000000013','awaiting_pickup',1),
 ('04110000-0000-0000-0000-000000000014','awaiting_pickup',0),
 ('04110000-0000-0000-0000-000000000015','awaiting_pickup',0),
 ('04110000-0000-0000-0000-000000000016','awaiting_pickup',2);
insert into p041_demo.variants values
 ('04110000-0000-0000-0000-000000000101',10,2),
 ('04110000-0000-0000-0000-000000000102',5,1),
 ('04110000-0000-0000-0000-000000000103',1,0),
 ('04110000-0000-0000-0000-000000000104',8,1),
 ('04110000-0000-0000-0000-000000000105',8,1),
 ('04110000-0000-0000-0000-000000000106',8,1);
insert into p041_demo.items values
 ('04110000-0000-0000-0000-000000000010','04110000-0000-0000-0000-000000000101',2),
 ('04110000-0000-0000-0000-000000000010','04110000-0000-0000-0000-000000000102',1),
 ('04110000-0000-0000-0000-000000000011','04110000-0000-0000-0000-000000000104',1),
 ('04110000-0000-0000-0000-000000000012','04110000-0000-0000-0000-000000000103',2),
 ('04110000-0000-0000-0000-000000000013','04110000-0000-0000-0000-000000000105',1),
 ('04110000-0000-0000-0000-000000000014','04110000-0000-0000-0000-000000000106',1),
 ('04110000-0000-0000-0000-000000000015','04110000-0000-0000-0000-000000000105',1),
 ('04110000-0000-0000-0000-000000000016','04110000-0000-0000-0000-000000000105',1);
insert into p041_demo.tasks(id,order_id,kind,shipper_id,status,attempt_number) values
 ('04110000-0000-0000-0000-000000000201','04110000-0000-0000-0000-000000000010','outbound','04110000-0000-0000-0000-000000000002','assigned',1),
 ('04110000-0000-0000-0000-000000000202','04110000-0000-0000-0000-000000000011','outbound','04110000-0000-0000-0000-000000000002','assigned',1),
 ('04110000-0000-0000-0000-000000000203','04110000-0000-0000-0000-000000000012','outbound','04110000-0000-0000-0000-000000000002','assigned',1),
 ('04110000-0000-0000-0000-000000000204','04110000-0000-0000-0000-000000000013','outbound','04110000-0000-0000-0000-000000000002','failed',1),
 ('04110000-0000-0000-0000-000000000205','04110000-0000-0000-0000-000000000013','outbound','04110000-0000-0000-0000-000000000002','assigned',2),
 ('04110000-0000-0000-0000-000000000206','04110000-0000-0000-0000-000000000014','outbound','04110000-0000-0000-0000-000000000002','assigned',1),
 ('04110000-0000-0000-0000-000000000207','04110000-0000-0000-0000-000000000015','outbound','04110000-0000-0000-0000-000000000002','assigned',1),
 ('04110000-0000-0000-0000-000000000208','04110000-0000-0000-0000-000000000016','outbound','04110000-0000-0000-0000-000000000002','accepted',2),
 ('04110000-0000-0000-0000-000000000209','04110000-0000-0000-0000-000000000015','return_pickup','04110000-0000-0000-0000-000000000002','assigned',1);
insert into p041_demo.dispatches(order_id) values ('04110000-0000-0000-0000-000000000013');
insert into p041_demo.dispatch_items values ('04110000-0000-0000-0000-000000000013','04110000-0000-0000-0000-000000000105',1);
insert into p041_demo.dispatches(order_id) values ('04110000-0000-0000-0000-000000000016');
insert into p041_demo.dispatch_items values ('04110000-0000-0000-0000-000000000016','04110000-0000-0000-0000-000000000105',1);
insert into p041_demo.custody values ('04110000-0000-0000-0000-000000000013','04110000-0000-0000-0000-000000000204','04110000-0000-0000-0000-000000000002',clock_timestamp());
insert into p041_demo.custody values ('04110000-0000-0000-0000-000000000016','04110000-0000-0000-0000-000000000208','04110000-0000-0000-0000-000000000002',clock_timestamp());
update p041_demo.tasks set result='failed',finished_at=clock_timestamp() where id='04110000-0000-0000-0000-000000000204';
update p041_demo.tasks set accepted_at=clock_timestamp() where id='04110000-0000-0000-0000-000000000208';

select pg_temp.assert_demo('public accept RPC is absent', not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='accept_delivery_task'));
select pg_temp.assert_demo('public start RPC is absent', not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='start_delivery_task'));

select pg_temp.set_demo_claims('04110000-0000-0000-0000-000000000002');
-- First attempt: dispatch and custody are one demo transaction.
select pg_temp.assert_demo('accept first attempt',
  (p041_demo.command('accept','04110000-0000-0000-0000-000000000201','04110000-0000-0000-0000-000000000301')->>'status')='accepted');
select 'accept' as demo_step, row_to_json(s) as snapshot
from (select t.status as task_status, t.accepted_at, o.status as order_status, o.attempt_count,
             (select count(*) from p041_demo.dispatches d where d.order_id=o.id) as dispatch_count,
             (select sum(v.on_hand) from p041_demo.variants v join p041_demo.items i on i.variant_id=v.id where i.order_id=o.id) as stock_on_hand
      from p041_demo.tasks t join p041_demo.orders o on o.id=t.order_id
      where t.id='04110000-0000-0000-0000-000000000201') s;
select pg_temp.assert_demo('dispatch consumed reserved/on_hand',
  (select on_hand=8 and reserved=0 from p041_demo.variants where id='04110000-0000-0000-0000-000000000101')
  and (select on_hand=4 and reserved=0 from p041_demo.variants where id='04110000-0000-0000-0000-000000000102'));
select pg_temp.assert_demo('accept retry returns exact result',
  p041_demo.command('accept','04110000-0000-0000-0000-000000000201','04110000-0000-0000-0000-000000000301') =
  (select result from p041_demo.requests where request_id='04110000-0000-0000-0000-000000000301'));
select pg_temp.assert_demo_error('new accept after accepted is blocked', $q$select p041_demo.command('accept','04110000-0000-0000-0000-000000000201','04110000-0000-0000-0000-000000000302')$q$, 'P0001','STATE_CONFLICT');
select pg_temp.assert_demo_error('same request different operation conflicts', $q$select p041_demo.command('start','04110000-0000-0000-0000-000000000201','04110000-0000-0000-0000-000000000301')$q$, 'P0001','IDEMPOTENCY_CONFLICT');
select pg_temp.assert_demo_error('same request different task conflicts', $q$select p041_demo.command('accept','04110000-0000-0000-0000-000000000202','04110000-0000-0000-0000-000000000301')$q$, 'P0001','IDEMPOTENCY_CONFLICT');

create temp table p041_start_result as
select p041_demo.command('start','04110000-0000-0000-0000-000000000201','04110000-0000-0000-0000-000000000303') as result;
select pg_temp.assert_demo('start increments once',
  (select result->>'status'='in_transit' from p041_start_result)
  and (select attempt_count=1 and status='delivering' from p041_demo.orders
       where id='04110000-0000-0000-0000-000000000010')
  and (select status='in_transit' from p041_demo.tasks
       where id='04110000-0000-0000-0000-000000000201'));
select 'start' as demo_step, row_to_json(s) as snapshot
from (select t.status as task_status, o.status as order_status, o.attempt_count,
             (select count(*) from p041_demo.dispatches d where d.order_id=o.id) as dispatch_count
      from p041_demo.tasks t join p041_demo.orders o on o.id=t.order_id
      where t.id='04110000-0000-0000-0000-000000000201') s;
select pg_temp.assert_demo('start retry exact result',
  p041_demo.command('start','04110000-0000-0000-0000-000000000201','04110000-0000-0000-0000-000000000303') =
  (select result from p041_demo.requests where request_id='04110000-0000-0000-0000-000000000303'));
-- Replay must re-check current assignment before returning the stored result.
update p041_demo.tasks set shipper_id='04110000-0000-0000-0000-000000000003'::uuid
where id='04110000-0000-0000-0000-000000000201'::uuid;
select pg_temp.set_demo_claims('04110000-0000-0000-0000-000000000002');
select pg_temp.assert_demo_error('start replay rechecks assignment',
  $q$select p041_demo.command('start','04110000-0000-0000-0000-000000000201','04110000-0000-0000-0000-000000000303')$q$,
  '42501','FORBIDDEN');
select pg_temp.assert_demo('no attempt result is created by accept/start',
  (select result is null from p041_demo.tasks where id='04110000-0000-0000-0000-000000000201'));

select pg_temp.set_demo_claims('04110000-0000-0000-0000-000000000003');
select pg_temp.assert_demo_error('wrong shipper denied', $q$select p041_demo.command('accept','04110000-0000-0000-0000-000000000206','04110000-0000-0000-0000-000000000310')$q$, '42501','FORBIDDEN');
select pg_temp.set_demo_claims('04110000-0000-0000-0000-000000000004');
select pg_temp.assert_demo_error('manager cannot accept', $q$select p041_demo.command('accept','04110000-0000-0000-0000-000000000206','04110000-0000-0000-0000-000000000311')$q$, '42501','FORBIDDEN');
select pg_temp.set_demo_claims('04110000-0000-0000-0000-000000000001');
select pg_temp.assert_demo_error('customer cannot accept', $q$select p041_demo.command('accept','04110000-0000-0000-0000-000000000206','04110000-0000-0000-0000-000000000312')$q$, '42501','FORBIDDEN');
select pg_temp.set_demo_claims('04110000-0000-0000-0000-000000000002');
select pg_temp.assert_demo_error('return pickup kind denied', $q$select p041_demo.command('accept','04110000-0000-0000-0000-000000000209','04110000-0000-0000-0000-000000000313')$q$, 'P0001','STATE_CONFLICT');
select pg_temp.assert_demo_error('unknown task does not leak', $q$select p041_demo.command('accept','04110000-0000-0000-0000-000000000999','04110000-0000-0000-0000-000000000314')$q$, 'P0001','NOT_FOUND_OR_FORBIDDEN');

select pg_temp.assert_demo_error('insufficient inventory rolls back', $q$select p041_demo.command('accept','04110000-0000-0000-0000-000000000203','04110000-0000-0000-0000-000000000320')$q$, 'P0001','INVENTORY_UNAVAILABLE');
select pg_temp.assert_demo('failed dispatch has no side effects',
  (select status='assigned' from p041_demo.tasks where id='04110000-0000-0000-0000-000000000203')
  and not exists(select 1 from p041_demo.dispatches where order_id='04110000-0000-0000-0000-000000000012')
  and not exists(select 1 from p041_demo.custody where order_id='04110000-0000-0000-0000-000000000012')
  and (select on_hand=1 and reserved=0 from p041_demo.variants where id='04110000-0000-0000-0000-000000000103'));

-- Cancel-before-accept and accept-before-cancel are demonstrated sequentially;
-- this is not a substitute for a live cross-owner cancellation race.
select pg_temp.set_demo_claims('04110000-0000-0000-0000-000000000004');
select pg_temp.assert_demo('manager cancel before accept',
  (p041_demo.command('cancel','04110000-0000-0000-0000-000000000202','04110000-0000-0000-0000-000000000330')->>'status')='cancelled');
select pg_temp.assert_demo('cancel releases reservation', (select reserved=0 from p041_demo.variants where id='04110000-0000-0000-0000-000000000104'));
select pg_temp.set_demo_claims('04110000-0000-0000-0000-000000000002');
select pg_temp.assert_demo_error('cancelled task rejects stale accept', $q$select p041_demo.command('accept','04110000-0000-0000-0000-000000000202','04110000-0000-0000-0000-000000000331')$q$, '42501','FORBIDDEN');
select pg_temp.assert_demo('accept before cancel', (p041_demo.command('accept','04110000-0000-0000-0000-000000000206','04110000-0000-0000-0000-000000000340')->>'status')='accepted');
select pg_temp.set_demo_claims('04110000-0000-0000-0000-000000000004');
select pg_temp.assert_demo_error('cancel after custody denied', $q$select p041_demo.command('cancel','04110000-0000-0000-0000-000000000206','04110000-0000-0000-0000-000000000341')$q$, 'P0001','CUSTODY_UNRESOLVED');

create trigger p041_demo_fault_trigger before insert on p041_demo.requests
for each row execute function p041_demo.reject_fault_request();
select pg_temp.set_demo_claims('04110000-0000-0000-0000-000000000002');
select pg_temp.assert_demo_error('late request failure rolls back dispatch/custody',
  $q$select p041_demo.command('accept','04110000-0000-0000-0000-000000000207','04110000-0000-0000-0000-000000000399')$q$,
  'P0001','DEMO_FAULT_INJECTION');
select pg_temp.assert_demo('late failure has no side effects',
  (select status='assigned' from p041_demo.tasks where id='04110000-0000-0000-0000-000000000207')
  and (select on_hand=8 and reserved=1 from p041_demo.variants where id='04110000-0000-0000-0000-000000000105')
  and not exists(select 1 from p041_demo.dispatches where order_id='04110000-0000-0000-0000-000000000015')
  and not exists(select 1 from p041_demo.custody where order_id='04110000-0000-0000-0000-000000000015')
  and not exists(select 1 from p041_demo.requests where request_id='04110000-0000-0000-0000-000000000399'));
drop trigger p041_demo_fault_trigger on p041_demo.requests;

-- Explicit demo-only second attempt: same holder retains existing dispatch.
select pg_temp.set_demo_claims('04110000-0000-0000-0000-000000000002');
create temp table p041_second_accept_result as
select p041_demo.command('accept','04110000-0000-0000-0000-000000000205','04110000-0000-0000-0000-000000000350') as result;
select pg_temp.assert_demo('second attempt accepts without dispatching again',
  (select result->>'status'='accepted' and result->>'dispatched_now'='false'
     from p041_second_accept_result)
  and (select count(*)=1 from p041_demo.dispatches
       where order_id='04110000-0000-0000-0000-000000000013')
  and (select task_id='04110000-0000-0000-0000-000000000205' from p041_demo.custody
       where order_id='04110000-0000-0000-0000-000000000013'));
create temp table p041_second_start_result as
select p041_demo.command('start','04110000-0000-0000-0000-000000000205','04110000-0000-0000-0000-000000000351') as result;
select pg_temp.assert_demo('second attempt start increments to two',
  (select result->>'status'='in_transit' from p041_second_start_result)
  and (select attempt_count=2 and status='delivering' from p041_demo.orders
       where id='04110000-0000-0000-0000-000000000013'));
select 'second_start' as demo_step, row_to_json(s) as snapshot
from (select t.status as task_status, o.status as order_status, o.attempt_count,
             (select count(*) from p041_demo.dispatches d where d.order_id=o.id) as dispatch_count
      from p041_demo.tasks t join p041_demo.orders o on o.id=t.order_id
      where t.id='04110000-0000-0000-0000-000000000205') s;
select pg_temp.assert_demo_error('third attempt is blocked', $q$select p041_demo.command('start','04110000-0000-0000-0000-000000000208','04110000-0000-0000-0000-000000000360')$q$, 'P0001','ATTEMPT_LIMIT');

select 'outbound_commands_demo.sql: PASS' as result,
  'P04.1 isolated simulation only; no runtime accept/start implementation' as scope;
rollback;
