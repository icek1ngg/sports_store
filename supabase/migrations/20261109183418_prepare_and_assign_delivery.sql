-- Explicit preparation and first outbound assignment; source only, not deployed.
begin;
create table private.delivery_preparation_proofs (
 actor_id uuid not null, request_id uuid not null, order_id uuid not null,
 shipper_id uuid not null, prepared_at timestamptz not null default statement_timestamp(),
 transaction_id xid8 not null default pg_current_xact_id(),
 primary key(actor_id,request_id)
);
alter table private.delivery_preparation_proofs enable row level security;
alter table private.delivery_preparation_proofs force row level security;
revoke all on private.delivery_preparation_proofs from public,anon,authenticated,service_role;
grant select,insert on private.delivery_preparation_proofs to sports_store_delivery_writer;
create policy preparation_writer_read on private.delivery_preparation_proofs
 for select to sports_store_delivery_writer
 using (actor_id=auth.uid() and private.current_app_role()='manager');
create policy preparation_writer_insert on private.delivery_preparation_proofs
 for insert to sports_store_delivery_writer
 with check(actor_id=auth.uid() and private.current_app_role()='manager'
 and transaction_id=pg_current_xact_id());
create trigger preparation_proofs_append_only before update or delete
 on private.delivery_preparation_proofs for each row
 execute function private.reject_delivery_assignment_ledger_mutation();

create function private.require_delivery_preparation() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if old.status='preparing' and new.status='awaiting_pickup' then
  if not exists(select 1 from private.delivery_preparation_proofs p
   join public.delivery_tasks t on t.order_id=p.order_id
    and t.assigned_shipper_id=p.shipper_id and t.kind='outbound' and t.status='assigned'
   where p.order_id=new.id and p.actor_id=auth.uid()
    and p.transaction_id=pg_current_xact_id()) then
   raise exception using errcode='PT409',message='PREPARATION_REQUIRED';
  end if;
 end if;
 return new;
end $$;
revoke all on function private.require_delivery_preparation() from public,anon,authenticated,service_role;
create trigger orders_require_delivery_preparation before update of status on public.orders
 for each row when(old.status='preparing' and new.status='awaiting_pickup')
 execute function private.require_delivery_preparation();

create function public.prepare_and_assign_delivery(
 p_order_id uuid,p_shipper_id uuid,p_request_id uuid,p_prepared boolean
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 actor uuid:=auth.uid(); existing private.delivery_assignment_requests%rowtype;
 task_id uuid; task_shipper uuid; order_state public.order_status;
begin
 if actor is null then raise exception using errcode='42501',message='AUTH_REQUIRED'; end if;
 perform 1 from public.profiles where id=actor and role='manager' for share;
 if not found then raise exception using errcode='42501',message='PERMISSION_DENIED'; end if;
 if p_order_id is null or p_shipper_id is null or p_request_id is null then
  raise exception using errcode='22023',message='INVALID_ARGUMENT'; end if;
 if p_prepared is distinct from true then
  raise exception using errcode='22023',message='PREPARATION_REQUIRED'; end if;
 -- Same lock namespace/order as the canonical assignment RPC.
 perform pg_advisory_xact_lock(hashtextextended(
  'sports_store.assign_delivery_task:'||actor::text||':'||p_request_id::text,0));
 select * into existing from private.delivery_assignment_requests
 where actor_id=actor and request_id=p_request_id;
 if found then
  -- A legacy request is not evidence that this preparation command succeeded.
  if not exists(select 1 from private.delivery_preparation_proofs p
    where p.actor_id=actor and p.request_id=p_request_id
     and p.order_id=p_order_id and p.shipper_id=p_shipper_id) then
   raise exception using errcode='PT409',message='IDEMPOTENCY_CONFLICT'; end if;
  return public.assign_delivery_task(p_order_id,p_shipper_id,p_request_id,
   existing.expected_task_id,existing.expected_shipper_id);
 end if;
 select status into order_state from public.orders where id=p_order_id for update;
 if not found then raise exception using errcode='P0002',message='ORDER_NOT_FOUND'; end if;
 if order_state<>'preparing' then
  raise exception using errcode='PT409',message='STATE_CONFLICT'; end if;
 -- Existing unassigned task is supported; assignment RPC rechecks every CAS,
 -- attempt, custody, snapshot and COD invariant under its canonical locks.
 select id,assigned_shipper_id into task_id,task_shipper from public.delivery_tasks
 where order_id=p_order_id and kind='outbound'
 and status in ('pending_assignment','assigned','accepted','in_transit') order by id limit 1;
 insert into private.delivery_preparation_proofs(actor_id,request_id,order_id,shipper_id)
 values(actor,p_request_id,p_order_id,p_shipper_id);
 return public.assign_delivery_task(p_order_id,p_shipper_id,p_request_id,task_id,task_shipper);
end $$;
grant create on schema public to sports_store_delivery_writer;
alter function public.prepare_and_assign_delivery(uuid,uuid,uuid,boolean) owner to sports_store_delivery_writer;
revoke create on schema public from sports_store_delivery_writer;
revoke all on function public.prepare_and_assign_delivery(uuid,uuid,uuid,boolean)
 from public,anon,authenticated,service_role;
grant execute on function public.prepare_and_assign_delivery(uuid,uuid,uuid,boolean) to authenticated;
-- Existing RPC explicitly revoked owner EXECUTE; allow only the wrapper owner to compose it.
grant execute on function public.assign_delivery_task(uuid,uuid,uuid,uuid,uuid) to sports_store_delivery_writer;
-- Trigger runs as the established assignment writer, without new definer powers.
grant execute on function private.require_delivery_preparation() to sports_store_delivery_writer;

create function private.orders_can_assign_prepared(p_order_id uuid) returns boolean
language sql stable security invoker set search_path='' as $$
 select exists(select 1 from public.orders o
 join public.profiles p on p.id=auth.uid() and p.role='manager'
 where o.id=p_order_id and o.status='preparing' and o.delivery_attempt_count=0
 and not exists(select 1 from public.delivery_attempts a where a.order_id=o.id)
 and not exists(select 1 from public.delivery_tasks t where t.order_id=o.id and t.kind='outbound'
  and (t.status<>'pending_assignment' or t.assigned_shipper_id is not null
   or t.accepted_at is not null or t.started_at is not null or t.completed_at is not null
   or t.failure_reason is not null or t.cancel_reason is not null or t.attempt_number<>1))
 and (select count(*) from public.delivery_tasks t where t.order_id=o.id and t.kind='outbound')<=1
 and not exists(select 1 from public.cod_collections c where c.order_id=o.id
  and (c.status<>'uncollected' or c.collected_amount_vnd<>0 or c.received_amount_vnd<>0
   or c.collected_at is not null or c.collected_by is not null or c.handed_over_at is not null
   or c.received_at is not null or c.received_by is not null))) $$;
revoke all on function private.orders_can_assign_prepared(uuid) from public,anon,authenticated,service_role;
grant execute on function private.orders_can_assign_prepared(uuid) to authenticated;
-- Preserve the full existing return-capability merge, body, owner and ACLs.
do $$
declare f record; definition text; needle text; patched text; patched_count integer:=0;
begin
 for f in select p.oid,x.arg from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 join (values('private','orders_read_summary','p_order.id'),('public','get_order_details','o.id'))
 x(schema_name,function_name,arg) on n.nspname=x.schema_name and p.proname=x.function_name loop
  definition:=pg_get_functiondef(f.oid);
  needle:=format('private.orders_write_capabilities(%1$s) || pg_catalog.jsonb_build_object(''can_open_return_creation'', private.orders_return_creation_open(%1$s))',f.arg);
  patched:=replace(definition,needle,needle||format(' || pg_catalog.jsonb_build_object(''can_assign'', private.orders_can_assign_prepared(%s))',f.arg));
  if patched=definition then raise exception 'Expected Orders capabilities expression missing'; end if;
  execute patched; patched_count:=patched_count+1;
 end loop;
 if patched_count<>2 then raise exception 'Expected exactly two Orders capability call sites'; end if;
end $$;
notify pgrst,'reload schema';
commit;
