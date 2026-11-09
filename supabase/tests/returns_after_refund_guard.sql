-- Uses only temporary rows and existing read models. No order data is changed.
begin;
create temporary table refund_guard_probe(id uuid, order_id uuid, status text);
insert into refund_guard_probe
select gen_random_uuid(), order_id, 'awaiting_refund'
from public.return_requests where status = 'refunded' limit 1;
create trigger refund_guard_probe_trigger
before insert or update of status on refund_guard_probe
for each row execute function private.block_repeated_order_refund();
do $$
declare o uuid; c uuid;
begin
 select order_id into o from refund_guard_probe limit 1;
 if o is null then raise exception 'Need an existing refunded order for probe'; end if;
 begin
   insert into refund_guard_probe values(gen_random_uuid(),o,'pending_review');
   raise exception 'FAIL: allowed a new return for refunded order';
 exception when sqlstate 'PT409' then
   if sqlerrm <> 'ACTIVE_RETURN_EXISTS' then raise; end if;
 end;
 begin
   update refund_guard_probe set status='refunded' where order_id=o;
   raise exception 'FAIL: allowed a second refund';
 exception when sqlstate 'PT409' then
   if sqlerrm <> 'STATE_CONFLICT' then raise; end if;
 end;
 update refund_guard_probe set status='awaiting_refund' where order_id=o;
 select customer_id into c from public.orders where id=o;
 perform set_config('request.jwt.claim.sub',c::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',c,'role','authenticated')::text,true);
 perform set_config('sports_store.test_refunded_order',o::text,true);
end $$;
set local role authenticated;
do $$
declare o uuid := current_setting('sports_store.test_refunded_order')::uuid; ctx jsonb;
begin
 if private.orders_return_creation_open(o) then
   raise exception 'FAIL: customer can open return creation';
 end if;
 ctx := public.get_return_request_context(o);
 if (ctx->>'can_submit_return')::boolean then
   raise exception 'FAIL: customer return context accepts refunded order';
 end if;
end $$;
select 'PASS: repeat return and second refund blocked; customer entry disabled' as result;
rollback;
