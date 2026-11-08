-- Orders B2 / DR-01. SOURCE ONLY: never deploy implicitly to shared Cloud.
-- Existing B1 source and all external producer functions remain unchanged.
-- Manager cancellation is deliberately limited to never-assigned orders with
-- authoritative Checkout provenance. Task revocation requires CIN-03 acceptance.
begin;

do $$ begin
 if exists(select 1 from pg_catalog.pg_roles where rolname='sports_store_orders_writer') then
  raise exception 'Orders writer role collision';
 end if;
 create role sports_store_orders_writer nologin noinherit nobypassrls;
end $$;
grant sports_store_orders_writer to postgres;
grant usage,create on schema public,private to sports_store_orders_writer;
grant usage on schema auth to sports_store_orders_writer;
grant execute on function auth.uid(),private.current_app_role() to sports_store_orders_writer;

create table private.order_operation_receipts(
 principal_key text not null,
 request_id uuid not null,
 actor_id uuid,
 actor_source text not null check(actor_source in ('customer','manager')),
 operation text not null check(operation in ('confirm','reject','customer_cancel','manager_cancel')),
 order_id uuid not null references public.orders(id),
 payload_fingerprint jsonb not null,
 outcome text not null check(outcome in ('success','failure')),
 result_envelope jsonb not null,
 event_id uuid references public.business_events(id),
 recorded_at timestamptz not null,
 primary key(principal_key,request_id),
 check(actor_id is not null and principal_key='user:'||actor_id::text),
 check((actor_source='customer')=(operation='customer_cancel')),
 check(jsonb_typeof(payload_fingerprint)='object'
  and payload_fingerprint= jsonb_build_object('v',1,'operation',operation,
   'order_id',order_id,'reason',payload_fingerprint->'reason')),
 check(jsonb_typeof(result_envelope)='object'
  and ((outcome='success' and event_id is not null
   and result_envelope->'ok'='true'::jsonb and result_envelope->'error'='null'::jsonb
   and jsonb_typeof(result_envelope->'data')='object')
  or (outcome='failure' and event_id is null
   and result_envelope->'ok'='false'::jsonb and result_envelope->'data'='null'::jsonb
   and jsonb_typeof(result_envelope->'error')='object')))
);

-- Owned Orders subset of CIN-09. External producer registration is NOT enabled.
create table private.business_event_contracts(
 event_id uuid primary key references public.business_events(id),
 root_event_id uuid not null references private.business_event_contracts(event_id),
 event_type text not null check(event_type in ('order_confirmed_manual','order_rejected','order_cancelled')),
 origin_module text not null check(origin_module='orders'),
 source_operation_key text not null check(length(source_operation_key) between 1 and 200),
 subject_type text not null check(subject_type='order'),
 subject_id uuid not null references public.orders(id),
 actor_source text not null check(actor_source in ('customer','manager')),
 source_facts jsonb not null,
 event_fingerprint jsonb not null,
 notification_manifest jsonb not null check(jsonb_typeof(notification_manifest)='array'),
 notification_emitted_at timestamptz not null,
 unique(origin_module,source_operation_key),
 check(root_event_id=event_id),
 check(jsonb_typeof(source_facts)='object' and jsonb_typeof(event_fingerprint)='object')
);
alter table private.order_operation_receipts enable row level security;
alter table private.order_operation_receipts force row level security;
alter table private.business_event_contracts enable row level security;
alter table private.business_event_contracts force row level security;
revoke all on private.order_operation_receipts,private.business_event_contracts from public,anon,authenticated,service_role;
grant select,insert on private.order_operation_receipts,private.business_event_contracts to sports_store_orders_writer;
create policy orders_receipts_writer_read on private.order_operation_receipts for select to sports_store_orders_writer using(current_user='sports_store_orders_writer');
create policy orders_receipts_writer_insert on private.order_operation_receipts for insert to sports_store_orders_writer with check(current_user='sports_store_orders_writer');
create policy orders_event_contracts_writer_read on private.business_event_contracts for select to sports_store_orders_writer using(current_user='sports_store_orders_writer');
create policy orders_event_contracts_writer_insert on private.business_event_contracts for insert to sports_store_orders_writer with check(current_user='sports_store_orders_writer');

create function private.orders_immutable_ledger() returns trigger language plpgsql
security invoker set search_path='' as $$ begin raise exception 'Orders ledger is append-only'; end $$;
create trigger order_receipts_append_only before update or delete on private.order_operation_receipts for each row execute function private.orders_immutable_ledger();
create trigger order_events_append_only before update or delete on private.business_event_contracts for each row execute function private.orders_immutable_ledger();
revoke all on function private.orders_immutable_ledger() from public,anon,authenticated,service_role;

-- No raw table privileges are granted to mobile roles. Dedicated NOLOGIN role
-- is reachable only through checked RPCs below; RLS remains enabled everywhere.
grant select on public.orders,public.order_items,public.profiles,public.product_variants,
 public.inventory_movements,public.delivery_tasks,public.cod_collections,
 public.return_requests,public.business_events to sports_store_orders_writer;
grant update(status,confirmed_at,source,confirmed_by,cancel_reason) on public.orders to sports_store_orders_writer;
grant insert(id,actor_id,subject_type,subject_id,from_state,to_state,reason,request_id) on public.business_events to sports_store_orders_writer;
grant insert(id,recipient_id,event_id,subject_type,subject_id,title,body,created_at) on public.notifications to sports_store_orders_writer;
grant select on private.checkout_placements,private.outbound_dispatches,private.outbound_custody_acceptances to sports_store_orders_writer;
create policy orders_writer_orders_read on public.orders for select to sports_store_orders_writer using(private.current_app_role()='manager' or (private.current_app_role()='customer' and customer_id=auth.uid()));
create policy orders_writer_orders_update on public.orders for update to sports_store_orders_writer using(private.current_app_role()='manager' or (private.current_app_role()='customer' and customer_id=auth.uid())) with check(private.current_app_role()='manager' or (private.current_app_role()='customer' and customer_id=auth.uid()));
-- UPDATE(id) exists only for SELECT FOR UPDATE row-lock privileges; no public
-- RPC accepts raw identifiers to update. The dedicated role has no LOGIN/member.
grant update(id) on public.product_variants,public.delivery_tasks to sports_store_orders_writer;
create policy orders_writer_variant_lock on public.product_variants for update to sports_store_orders_writer using(current_user='sports_store_orders_writer') with check(current_user='sports_store_orders_writer');
create policy orders_writer_task_lock on public.delivery_tasks for update to sports_store_orders_writer using(current_user='sports_store_orders_writer') with check(current_user='sports_store_orders_writer');
-- Internal aggregate validation policies do not expose these rows to clients.
do $$ declare t text; begin
 foreach t in array array['order_items','profiles','product_variants','inventory_movements','delivery_tasks','cod_collections','return_requests','business_events'] loop
  execute format('create policy orders_writer_internal_read on public.%I for select to sports_store_orders_writer using (current_user = ''sports_store_orders_writer'')',t);
 end loop;
 foreach t in array array['checkout_placements','outbound_dispatches','outbound_custody_acceptances'] loop
  execute format('create policy orders_writer_internal_read on private.%I for select to sports_store_orders_writer using (current_user = ''sports_store_orders_writer'')',t);
 end loop;
end $$;
create policy orders_writer_events_insert on public.business_events for insert to sports_store_orders_writer with check(actor_id=auth.uid() and subject_type='order' and request_id is null and exists(select 1 from public.orders o where o.id=subject_id));
create policy orders_writer_notifications_insert on public.notifications for insert to sports_store_orders_writer with check(subject_type='order' and exists(select 1 from public.orders o where o.id=subject_id and o.customer_id=recipient_id));
grant execute on function private.apply_order_inventory_event(uuid,uuid,text,jsonb,uuid,text),private.orders_read_order(public.orders,boolean) to sports_store_orders_writer;

create function private.orders_normalize_reason(p_reason text) returns text
language sql immutable security invoker set search_path='' as $$
 select btrim(replace(replace(p_reason,E'\r\n',E'\n'),E'\r',E'\n'),
 U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000')
$$;
create function private.orders_mutation_error(p_code text,p_id uuid default null,p_status text default null) returns jsonb
language sql immutable security invoker set search_path='' as $$
 select jsonb_build_object('ok',false,'data',null,'error',jsonb_build_object(
 'code',p_code,'message_key',case when p_code='forbidden_or_unavailable' then 'MSG-08' when p_code in ('state_changed','cancellation_not_allowed') then 'MSG-26' else null end,
 'retryable',p_code in ('custody_unverified','external_dependency_unavailable'),
 'current_order',case when p_id is null then null else jsonb_build_object('id',p_id,'status',p_status) end))
$$;

-- Returns NULL only when Checkout provenance and NEVER assigned custody are
-- proved. This conservative subset excludes all task/COD revocation scenarios.
create function private.orders_mutation_eligibility(p_order_id uuid) returns text
language plpgsql stable security invoker set search_path='' as $$
declare o public.orders; begin
 select * into o from public.orders where id=p_order_id;
 if not found then return 'forbidden_or_unavailable'; end if;
 if not exists(select 1 from private.checkout_placements p where p.order_id=o.id and p.customer_id=o.customer_id and p.request_id=o.request_id)
  or o.delivery_attempt_count<>0 or o.delivered_at is not null
  or exists(select 1 from public.delivery_tasks t where t.order_id=o.id)
  or exists(select 1 from private.outbound_dispatches d where d.order_id=o.id)
  or exists(select 1 from private.outbound_custody_acceptances c where c.order_id=o.id)
  or exists(select 1 from public.cod_collections c where c.order_id=o.id)
  or exists(select 1 from public.return_requests r where r.order_id=o.id)
 then return 'custody_unverified'; end if;
 if not exists(select 1 from public.order_items i where i.order_id=o.id)
  or exists(select 1 from public.inventory_movements m where m.order_id=o.id and (m.kind<>'reserve' or m.on_hand_delta<>0 or m.damaged_delta<>0 or m.reserved_delta<=0 or m.return_request_id is not null or not exists(select 1 from public.order_items i where i.order_id=o.id and i.variant_id=m.variant_id)))
  or exists(select 1 from public.order_items i join public.product_variants v on v.id=i.variant_id where i.order_id=o.id and (v.reserved<i.quantity or i.quantity<>coalesce((select sum(m.reserved_delta) from public.inventory_movements m where m.order_id=o.id and m.variant_id=i.variant_id and m.kind='reserve'),0)))
 then return 'data_integrity'; end if;
 return null;
end $$;

create function private.orders_execute_command(p_order_id uuid,p_request_id uuid,p_operation text,p_reason text) returns jsonb
language plpgsql security invoker set search_path='' set timezone='UTC' as $$
declare
 u uuid:=auth.uid(); r text; principal text; reason text; fp jsonb;
 old_receipt private.order_operation_receipts; o public.orders; result jsonb;
 code text; event_id uuid; event_type text; target_state public.order_status;
 actor_source text; now_at timestamptz; notification_id uuid; title text; body text;
 facts jsonb; event_fields jsonb; manifest jsonb; items jsonb; variant uuid; attempts integer;
begin
 if u is null then return private.orders_mutation_error('unauthenticated'); end if;
 r:=private.current_app_role()::text;
 if p_operation is null or p_operation not in ('confirm','reject','customer_cancel','manager_cancel')
  or p_order_id is null or p_request_id is null then return private.orders_mutation_error('invalid_argument'); end if;
 if (p_operation='customer_cancel' and r is distinct from 'customer')
  or (p_operation<>'customer_cancel' and r is distinct from 'manager') then return private.orders_mutation_error('forbidden_or_unavailable'); end if;
 reason:=private.orders_normalize_reason(p_reason);
 if (p_operation in ('reject','manager_cancel') and (reason is null or char_length(reason) not between 1 and 1000))
  or (p_operation in ('confirm','customer_cancel') and p_reason is not null) then return private.orders_mutation_error('invalid_argument'); end if;
 select * into o from public.orders where id=p_order_id;
 if not found or (r='customer' and o.customer_id<>u) then return private.orders_mutation_error('forbidden_or_unavailable'); end if;
 principal:='user:'||u::text; actor_source:=r;
 fp:=jsonb_build_object('v',1,'operation',p_operation,'order_id',p_order_id,'reason',reason);
 perform pg_advisory_xact_lock(hashtextextended('orders.receipt/v1|'||principal||'|'||p_request_id::text,0));
 select * into old_receipt from private.order_operation_receipts where principal_key=principal and request_id=p_request_id;
 if found then
  if old_receipt.payload_fingerprint<>fp then return private.orders_mutation_error('idempotency_conflict'); end if;
  if old_receipt.outcome='success' then return jsonb_set(old_receipt.result_envelope,'{data,replayed}','true'::jsonb); end if;
  return old_receipt.result_envelope;
 end if;
 select * into o from public.orders where id=p_order_id for update;
 if not found or (r='customer' and o.customer_id<>u) then return private.orders_mutation_error('forbidden_or_unavailable'); end if;
 -- Task writers in this project lock the order first. Lock any task rows in
 -- stable order before checking history; eligible subset then requires none.
 perform 1 from public.delivery_tasks t where t.order_id=o.id order by t.id for update;
 if (p_operation='manager_cancel' and o.status not in ('preparing','awaiting_pickup'))
  or (p_operation<>'manager_cancel' and o.status<>'pending_confirmation') then
  code:=case when p_operation in ('customer_cancel','manager_cancel') then 'cancellation_not_allowed' else 'state_changed' end;
  result:=private.orders_mutation_error(code,o.id,o.status::text);
 else
  for variant in select i.variant_id from public.order_items i where i.order_id=o.id order by i.variant_id loop
   perform 1 from public.product_variants v where v.id=variant for update;
  end loop;
  code:=private.orders_mutation_eligibility(o.id);
  if code is not null then
   -- Missing custody evidence/ledger corruption must remain retryable after
   -- repair, never poison request key with immutable terminal failure.
   return private.orders_mutation_error(code);
  end if;
  target_state:=case p_operation when 'confirm' then 'preparing' when 'reject' then 'rejected' else 'cancelled' end;
  event_type:=case p_operation when 'confirm' then 'order_confirmed_manual' when 'reject' then 'order_rejected' else 'order_cancelled' end;
  now_at:=clock_timestamp();
  -- All effects below are one SQL transaction. Unexpected SQL/timeout/deadlock
  -- aborts it completely; only explicit state errors above are persisted.
  for attempts in 1..3 loop
   begin
    event_id:=gen_random_uuid();
    insert into public.business_events(id,actor_id,subject_type,subject_id,from_state,to_state,reason,request_id)
    values(event_id,u,'order',o.id,o.status::text,target_state::text,reason,null);
    exit;
   exception when unique_violation then
    if attempts=3 then raise; end if;
   end;
  end loop;
  if p_operation<>'confirm' then
   select jsonb_agg(jsonb_build_object('order_item_id',i.id,'variant_id',i.variant_id,'quantity',i.quantity) order by i.variant_id) into items from public.order_items i where i.order_id=o.id;
   perform private.apply_order_inventory_event(o.id,event_id,'release',items,u,reason);
  end if;
  update public.orders set status=target_state,
   confirmed_at=case when p_operation='confirm' then now_at else confirmed_at end,
   source=case when p_operation='confirm' then 'manager'::public.order_confirmation_source else source end,
   confirmed_by=case when p_operation='confirm' then u else confirmed_by end,
   cancel_reason=case when p_operation='manager_cancel' then reason else cancel_reason end
  where id=o.id returning * into o;
  title:=case p_operation when 'confirm' then 'Đơn hàng đã được xác nhận' when 'reject' then 'Đơn hàng đã được từ chối' else 'Đơn hàng đã được hủy' end;
  body:='Mở đơn để xem trạng thái hiện tại.';
  notification_id:=gen_random_uuid();
  insert into public.notifications(id,recipient_id,event_id,subject_type,subject_id,title,body,created_at)
  values(notification_id,o.customer_id,event_id,'order',o.id,title,body,now_at);
  facts:=jsonb_build_object('order_id',o.id,'task_id',null,'return_request_id',null,'customer_id',o.customer_id,'assigned_shipper_id',null,'previous_shipper_id',null,'collecting_shipper_id',null,'conversation_id',null,'sender_id',null);
  event_fields:=jsonb_build_object('actor_id',u,'subject_type','order','subject_id',o.id,'from_state',case when p_operation='manager_cancel' then (select status::text from public.orders where false) else 'pending_confirmation' end,'to_state',target_state,'reason',reason,'task_id',null,'incident_kind',null,'request_id',null);
  -- Fingerprint uses actual public event fields, including prior preparing vs
  -- awaiting_pickup, never an inferred historical state.
  select jsonb_build_object('actor_id',e.actor_id,'subject_type',e.subject_type,'subject_id',e.subject_id,'from_state',e.from_state,'to_state',e.to_state,'reason',e.reason,'task_id',e.task_id,'incident_kind',e.incident_kind,'request_id',e.request_id) into event_fields from public.business_events e where e.id=event_id;
  manifest:=jsonb_build_array(jsonb_build_object('id',notification_id,'recipient_id',o.customer_id,'event_id',event_id,'subject_type','order','subject_id',o.id,'title',title,'body',body,'created_at',now_at));
  insert into private.business_event_contracts values(event_id,event_id,event_type,'orders',principal||'/'||p_request_id::text,'order',o.id,actor_source,facts,jsonb_build_object('event_type',event_type,'actor_source',actor_source,'public_fields',event_fields,'root_ref',null,'source_facts',facts),manifest,now_at);
  now_at:=clock_timestamp();
  result:=jsonb_build_object('ok',true,'data',jsonb_build_object('operation',p_operation,'request_id',p_request_id,'event_id',event_id,'order',private.orders_read_order(o,r='customer'),'committed_at',now_at,'replayed',false,'current_order',null),'error',null);
 end if;
 insert into private.order_operation_receipts values(principal,p_request_id,u,actor_source,p_operation,p_order_id,fp,case when result->>'ok'='true' then 'success' else 'failure' end,result,case when result->>'ok'='true' then event_id else null end,clock_timestamp());
 return result;
end $$;

create function public.confirm_order(p_order_id uuid,p_request_id uuid) returns jsonb
language sql volatile security definer set search_path='' set timezone='UTC' as $$ select private.orders_execute_command(p_order_id,p_request_id,'confirm',null) $$;
create function public.reject_order(p_order_id uuid,p_request_id uuid,p_reason text) returns jsonb
language sql volatile security definer set search_path='' set timezone='UTC' as $$ select private.orders_execute_command(p_order_id,p_request_id,'reject',p_reason) $$;
create function public.cancel_customer_order(p_order_id uuid,p_request_id uuid) returns jsonb
language sql volatile security definer set search_path='' set timezone='UTC' as $$ select private.orders_execute_command(p_order_id,p_request_id,'customer_cancel',null) $$;
create function public.cancel_manager_order(p_order_id uuid,p_request_id uuid,p_reason text) returns jsonb
language sql volatile security definer set search_path='' set timezone='UTC' as $$ select private.orders_execute_command(p_order_id,p_request_id,'manager_cancel',p_reason) $$;

create function public.get_order_operation_result(p_request_id uuid,p_order_id uuid,p_operation text) returns jsonb
language plpgsql stable security definer set search_path='' set timezone='UTC' as $$
declare u uuid:=auth.uid(); r text; rec private.order_operation_receipts; o public.orders; begin
 if u is null then return private.orders_mutation_error('unauthenticated'); end if;
 r:=private.current_app_role()::text;
 if p_order_id is null or p_request_id is null or p_operation is null or p_operation not in ('confirm','reject','customer_cancel','manager_cancel') then return private.orders_mutation_error('invalid_argument'); end if;
 if (p_operation='customer_cancel' and r is distinct from 'customer') or (p_operation<>'customer_cancel' and r is distinct from 'manager') then return private.orders_mutation_error('forbidden_or_unavailable'); end if;
 select * into o from public.orders where id=p_order_id;
 if not found or (r='customer' and o.customer_id<>u) then return private.orders_mutation_error('forbidden_or_unavailable'); end if;
 select * into rec from private.order_operation_receipts where principal_key='user:'||u::text and request_id=p_request_id;
 if not found then return jsonb_build_object('ok',true,'data',jsonb_build_object('state','not_found','receipt',null,'failure',null),'error',null); end if;
 if rec.order_id<>p_order_id or rec.operation<>p_operation then return private.orders_mutation_error('idempotency_conflict'); end if;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('state',case rec.outcome when 'success' then 'committed' else 'failed' end,'receipt',case when rec.outcome='success' then jsonb_set(rec.result_envelope->'data','{replayed}','true'::jsonb) else null end,'failure',case when rec.outcome='failure' then rec.result_envelope->'error' else null end),'error',null);
end $$;

-- Change ownership only to a NOLOGIN/NOBYPASSRLS role, with no client membership.
do $$ declare f record; begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='public' and p.proname in ('confirm_order','reject_order','cancel_customer_order','cancel_manager_order','get_order_operation_result')) or (n.nspname='private' and p.proname in ('orders_execute_command','orders_mutation_eligibility','orders_normalize_reason','orders_mutation_error')) loop
  execute format('alter function %s owner to sports_store_orders_writer',f.signature);
  execute format('revoke all on function %s from public,anon,authenticated,service_role',f.signature);
  if f.signature::text like 'confirm_order(%' or f.signature::text like 'reject_order(%' or f.signature::text like 'cancel_customer_order(%' or f.signature::text like 'cancel_manager_order(%' or f.signature::text like 'get_order_operation_result(%' then execute format('grant execute on function %s to authenticated',f.signature); end if;
 end loop;
end $$;
revoke create on schema public,private from sports_store_orders_writer;
notify pgrst,'reload schema';
commit;
