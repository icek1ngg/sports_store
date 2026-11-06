-- Pickup handover is a shipper report, never a manager receipt/inspection.
-- Reuse the restricted P08.1 writer and actor/request namespace.
alter table private.return_pickup_requests
  drop constraint return_pickup_requests_operation_valid;
alter table private.return_pickup_requests
  add constraint return_pickup_requests_operation_valid check(operation in (
    'assign_return_pickup_task','collect_return_items','fail_return_pickup_task',
    'report_return_pickup_handover'));

create table private.return_pickup_handover_reports (
  return_request_id uuid primary key references public.return_requests(id),
  task_id uuid not null unique references public.delivery_tasks(id),
  order_id uuid not null references public.orders(id),
  shipper_id uuid not null references public.profiles(id),
  request_id uuid not null,
  event_id uuid not null unique references public.business_events(id),
  items jsonb not null check(jsonb_typeof(items)='array' and jsonb_array_length(items)>0),
  reported_at timestamptz not null,
  response jsonb not null check(jsonb_typeof(response)='object')
);
alter table private.return_pickup_handover_reports enable row level security;
alter table private.return_pickup_handover_reports force row level security;
revoke all on private.return_pickup_handover_reports from public,anon,authenticated,service_role;
grant select,insert on private.return_pickup_handover_reports to sports_store_return_pickup_writer;
grant select(reason) on public.business_events to sports_store_return_pickup_writer;
create policy pickup_handover_writer_read on private.return_pickup_handover_reports
 for select to sports_store_return_pickup_writer
 using(current_user='sports_store_return_pickup_writer');
create policy pickup_handover_writer_insert on private.return_pickup_handover_reports
 for insert to sports_store_return_pickup_writer
 with check(current_user='sports_store_return_pickup_writer' and shipper_id=(select private.delivery_request_user_id()));
create trigger pickup_handover_append_only before update or delete
 on private.return_pickup_handover_reports for each row
 execute function private.reject_return_pickup_ledger_mutation();

create policy pickup_handover_event_insert on public.business_events
 for insert to sports_store_return_pickup_writer with check(
  current_user='sports_store_return_pickup_writer'
  and actor_id=(select private.delivery_request_user_id())
  and subject_type='delivery_task' and subject_id=task_id
  and task_id is not null and request_id=id and incident_kind is null
  and from_state is null and to_state is null and reason='return_pickup_handover_reported');
create policy pickup_handover_event_read on public.business_events
 for select to sports_store_return_pickup_writer using(
  current_user='sports_store_return_pickup_writer'
  and actor_id=(select private.delivery_request_user_id())
  and subject_type='delivery_task' and reason='return_pickup_handover_reported');
create policy pickup_handover_notification_insert on public.notifications
 for insert to sports_store_return_pickup_writer with check(
  current_user='sports_store_return_pickup_writer' and subject_type='delivery_task'
  and title='Đã báo bàn giao hàng thu hồi'
  and body='Shipper đã báo bàn giao hàng thu hồi. Cửa hàng cần xác nhận nhận và kiểm tra riêng.'
  and exists(select 1 from public.business_events e
    join public.profiles p on p.id=notifications.recipient_id
    where e.id=notifications.event_id and e.task_id=notifications.subject_id
      and e.actor_id=(select private.delivery_request_user_id())
      and e.reason='return_pickup_handover_reported' and p.role='manager'));

grant create on schema public,private to sports_store_return_pickup_writer;
-- Identity/assignment/custody proof independent of transient state, so a
-- committed same-key replay remains possible after future manager receipt.
create function private.lock_return_pickup_handover(p_task_id uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
 a uuid := (select private.delivery_request_user_id());
 o uuid; r uuid; t record; c private.return_pickup_custody%rowtype;
 os public.order_status; rs public.return_request_status; role_name text;
 plan jsonb; live jsonb; n bigint;
begin
 if a is null then raise exception using errcode='42501',message='AUTH_REQUIRED'; end if;
 if p_task_id is null then raise exception using errcode='22023',message='INVALID_ARGUMENT'; end if;
 select role::text into role_name from public.profiles where id=a for share;
 if role_name is distinct from 'shipper' then raise exception using errcode='42501',message='PERMISSION_DENIED'; end if;
 select order_id,return_request_id into o,r from public.delivery_tasks
 where id=p_task_id and kind='return_pickup' and assigned_shipper_id=a;
 if not found then raise exception using errcode='42501',message='NOT_FOUND_OR_FORBIDDEN'; end if;
 perform pg_advisory_xact_lock(hashtextextended('sports_store.complete_outbound_delivery:order:'||o::text,0));
 select status into os from public.orders where id=o for update;
 if not found then raise exception using errcode='42501',message='NOT_FOUND_OR_FORBIDDEN'; end if;
 select status into rs from public.return_requests where id=r and order_id=o for update;
 if not found then raise exception using errcode='PT409',message='STATE_CONFLICT'; end if;
 perform 1 from public.delivery_tasks where return_request_id=r order by id for update;
 select * into t from (select id,order_id,return_request_id,kind,status,assigned_shipper_id,
   accepted_at,started_at,completed_at,attempt_number,amount_to_collect_vnd
   from public.delivery_tasks where id=p_task_id) target;
 if not found or t.assigned_shipper_id is distinct from a or t.kind<>'return_pickup'
   or t.order_id is distinct from o or t.return_request_id is distinct from r then
   raise exception using errcode='42501',message='NOT_FOUND_OR_FORBIDDEN'; end if;
 select * into c from private.return_pickup_custody where task_id=p_task_id;
 if not found or c.shipper_id is distinct from a or c.order_id is distinct from o
   or c.return_request_id is distinct from r or c.accepted_at is distinct from t.accepted_at
   or c.started_at is distinct from t.started_at or c.accepted_at is distinct from c.started_at
   or c.accepted_at>clock_timestamp() or t.attempt_number<>1 or t.amount_to_collect_vnd<>0 then
   raise exception using errcode='PT409',message='CUSTODY_UNRESOLVED'; end if;
 plan:=private.return_pickup_plan_json(p_task_id);
 if plan='[]'::jsonb or c.items is distinct from plan then
   raise exception using errcode='PT409',message='ITEMS_MISMATCH'; end if;
 perform 1 from public.return_items where return_request_id=r order by id for update;
 select jsonb_agg(jsonb_build_object('return_item_id',id,'quantity',quantity_collected) order by id),count(*)
 into live,n from public.return_items where return_request_id=r and order_id=o;
 if live is distinct from plan or n<>jsonb_array_length(plan)
   or exists(select 1 from public.return_items where return_request_id=r
      and (order_id<>o or quantity_collected<>quantity_to_collect)) then
   raise exception using errcode='PT409',message='ITEMS_MISMATCH'; end if;
 return jsonb_build_object('task_id',p_task_id,'order_id',o,'return_request_id',r,
  'task_status',t.status,'order_status',os,'return_status',rs,'completed_at',t.completed_at,
  'items',plan);
end;
$$;
alter function private.lock_return_pickup_handover(uuid) owner to sports_store_return_pickup_writer;
revoke all on function private.lock_return_pickup_handover(uuid) from public,anon,authenticated,service_role;

create function public.report_return_pickup_handover(p_task_id uuid,p_request_id uuid,p_items jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 a uuid := (select private.delivery_request_user_id()); context jsonb; items jsonb;
 payload jsonb; old_request private.return_pickup_requests%rowtype;
 event uuid; at_time timestamptz; result jsonb; recipient record; o uuid; r uuid;
begin
 if a is null then raise exception using errcode='42501',message='AUTH_REQUIRED'; end if;
 if p_request_id is null then raise exception using errcode='22023',message='INVALID_ARGUMENT'; end if;
 items:=private.normalize_return_pickup_items(p_items);
 payload:=jsonb_build_object('operation','report_return_pickup_handover','task_id',p_task_id,
   'request_id',p_request_id,'items',items);
 perform pg_advisory_xact_lock(hashtextextended('sports_store.return_pickup:request:'||a::text||':'||p_request_id::text,0));
 context:=private.lock_return_pickup_handover(p_task_id);
 o:=(context->>'order_id')::uuid; r:=(context->>'return_request_id')::uuid;
 select * into old_request from private.return_pickup_requests where actor_id=a and request_id=p_request_id;
 if found then
  if old_request.operation<>'report_return_pickup_handover' or old_request.task_id is distinct from p_task_id
    or old_request.payload is distinct from payload then
    raise exception using errcode='PT409',message='IDEMPOTENCY_CONFLICT'; end if;
  return old_request.response;
 end if;
 if context->>'task_status'<>'in_transit' or context->>'return_status'<>'returning_to_store'
   or context->>'order_status'<>'delivered' or context->>'completed_at' is not null then
   raise exception using errcode='PT409',message='STATE_CONFLICT'; end if;
 if exists(select 1 from private.return_pickup_handover_reports where return_request_id=r) then
   raise exception using errcode='PT409',message='STATE_CONFLICT'; end if;
 if items is distinct from context->'items' then raise exception using errcode='PT409',message='ITEMS_MISMATCH'; end if;
 event:=gen_random_uuid(); at_time:=clock_timestamp();
 result:=jsonb_build_object('task_id',p_task_id,'order_id',o,'return_request_id',r,
  'operation','report_return_pickup_handover','task_status','in_transit','return_status','returning_to_store',
  'reported_at',at_time,'occurred_at',at_time,'event_id',event,'request_id',p_request_id);
 insert into public.business_events(id,actor_id,subject_type,subject_id,task_id,reason,request_id,created_at)
 values(event,a,'delivery_task',p_task_id,p_task_id,'return_pickup_handover_reported',event,at_time);
 for recipient in select id from public.profiles where role='manager' order by id loop
  insert into public.notifications(id,recipient_id,event_id,subject_type,subject_id,title,body,created_at)
  values(gen_random_uuid(),recipient.id,event,'delivery_task',p_task_id,'Đã báo bàn giao hàng thu hồi',
   'Shipper đã báo bàn giao hàng thu hồi. Cửa hàng cần xác nhận nhận và kiểm tra riêng.',at_time);
 end loop;
 insert into private.return_pickup_handover_reports(return_request_id,task_id,order_id,shipper_id,
  request_id,event_id,items,reported_at,response) values(r,p_task_id,o,a,p_request_id,event,items,at_time,result);
 insert into private.return_pickup_requests(actor_id,request_id,operation,return_request_id,order_id,
  task_id,shipper_id,payload,payload_hash,response,created_at)
 values(a,p_request_id,'report_return_pickup_handover',r,o,p_task_id,a,payload,md5(payload::text),result,at_time);
 return result;
end;
$$;
alter function public.report_return_pickup_handover(uuid,uuid,jsonb) owner to sports_store_return_pickup_writer;
revoke all on function public.report_return_pickup_handover(uuid,uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.report_return_pickup_handover(uuid,uuid,jsonb) to authenticated;

create function public.get_my_return_pickup_handover(p_task_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare context jsonb; at_time timestamptz;
begin
 context:=private.lock_return_pickup_handover(p_task_id);
 select reported_at into at_time from private.return_pickup_handover_reports
 where task_id=p_task_id and shipper_id=(select private.delivery_request_user_id());
 return jsonb_build_object('task_id',p_task_id,'reported',found,'reported_at',at_time);
end;
$$;
alter function public.get_my_return_pickup_handover(uuid) owner to sports_store_return_pickup_writer;
revoke all on function public.get_my_return_pickup_handover(uuid) from public,anon,authenticated,service_role;
grant execute on function public.get_my_return_pickup_handover(uuid) to authenticated;
revoke create on schema public,private from sports_store_return_pickup_writer;
notify pgrst,'reload schema';
