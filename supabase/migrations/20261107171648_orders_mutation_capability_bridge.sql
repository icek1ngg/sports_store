-- Reviewed B2 bridge: exact delta to two B1 bodies, original B1 file untouched.
-- Existing grants/signatures/security invoker preserved on read functions.
begin;
create function private.orders_write_capabilities(p_order_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' set timezone='UTC' as $$
declare o public.orders; r text; result jsonb:=private.orders_read_capabilities(); begin
 if auth.uid() is null then return result; end if;
 r:=private.current_app_role()::text;
 if r not in ('customer','manager') or r is null then return result; end if;
 select * into o from public.orders where id=p_order_id;
 if not found or (r='customer' and o.customer_id<>auth.uid()) then return result; end if;
 if private.orders_mutation_eligibility(o.id) is not null then return result; end if;
 return result || jsonb_build_object(
 'can_confirm',r='manager' and o.status='pending_confirmation',
 'can_reject',r='manager' and o.status='pending_confirmation',
 'can_cancel_customer',r='customer' and o.status='pending_confirmation',
 'can_cancel_exceptional',r='manager' and o.status in ('preparing','awaiting_pickup'));
end $$;
grant create on schema private to sports_store_orders_writer;
alter function private.orders_write_capabilities(uuid) owner to sports_store_orders_writer;
revoke create on schema private from sports_store_orders_writer;
grant execute on function private.orders_read_capabilities() to sports_store_orders_writer;
revoke all on function private.orders_write_capabilities(uuid) from public,anon,authenticated,service_role;
grant execute on function private.orders_write_capabilities(uuid) to authenticated;
create or replace function private.orders_read_summary(p_order public.orders,p_customer boolean) returns jsonb
language sql stable security invoker set search_path = '' set timezone = 'UTC'
as $$ select pg_catalog.jsonb_build_object(
 'order',private.orders_read_order(p_order,p_customer),
 'customer_display_name',case when p_customer then null else
 (select p.full_name from public.profiles p where p.id=p_order.customer_id) end,
 'item_preview',coalesce((select pg_catalog.jsonb_agg(x.value order by x.ordinality)
 from pg_catalog.jsonb_array_elements(private.orders_read_items(p_order.id)) with ordinality x(value,ordinality)
 where x.ordinality<=2),'[]'::jsonb),
 'item_line_count',(select count(*) from public.order_items i where i.order_id=p_order.id),
 'item_quantity_total',(select coalesce(sum(i.quantity),0) from public.order_items i where i.order_id=p_order.id),
 'delivery_summary',null,'cod_summary',null,
 'return_summary',private.orders_read_returns(p_order.id)->0,
 'warnings',pg_catalog.jsonb_build_array(
 pg_catalog.jsonb_build_object('code','external_dependency_unavailable','source_id',p_order.id,
 'message','Delivery/COD projections are unavailable.'),
 pg_catalog.jsonb_build_object('code','history_incomplete','source_id',p_order.id,
 'message','Typed cross-module history is not yet integrated.')),
 'capabilities',private.orders_write_capabilities(p_order.id)) $$;


create or replace function public.get_order_details(p_order_id uuid) returns jsonb
language plpgsql stable security invoker set search_path = '' set timezone = 'UTC'
as $$
declare l_uid uuid:=auth.uid(); l_role text; l_result jsonb;
begin
 if l_uid is null then return private.orders_read_failure('unauthenticated'); end if;
 select p.role::text into l_role from public.profiles p where p.id=l_uid;
 if l_role is null or l_role not in ('customer','manager') then
  return private.orders_read_failure('forbidden_or_unavailable'); end if;
 if p_order_id is null then return private.orders_read_failure('invalid_argument'); end if;
 select pg_catalog.jsonb_build_object('ok',true,'error',null,'data',pg_catalog.jsonb_build_object(
  'order',private.orders_read_order(o,l_role='customer'),
  'items',private.orders_read_items(o.id),
  'buyer',case when l_role='manager' then
    (select pg_catalog.jsonb_build_object('id',p.id,'full_name',p.full_name) from public.profiles p where p.id=o.customer_id)
    else null end,
  'delivery_summary',null,'cod_summary',null,'return_summaries',private.orders_read_returns(o.id),
  'history_complete',false,'capabilities',private.orders_write_capabilities(o.id),
  'as_of',pg_catalog.statement_timestamp(),
  -- Explicit factual timestamp milestones only. No invented actual event/type,
  -- actor, rejection reason or false claim that this is complete audit history.
  'timeline',(select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'event_id',null,'source_entity_type','order','source_entity_id',o.id,
    'event_kind','snapshot_milestone','from_state',null,'to_state',m.state,
    'actor_id',null,'actor_label',null,'actor_source','unknown',
    'occurred_at',m.occurred_at,'reason',null,'source','snapshot_milestone')
    order by m.occurred_at,m.state),'[]'::jsonb)
   from (values ('pending_confirmation'::text,o.placed_at),
      ('preparing'::text,o.confirmed_at),('delivered'::text,o.delivered_at)) m(state,occurred_at)
   where m.occurred_at is not null))) into l_result
 from public.orders o where o.id=p_order_id and (l_role='manager' or o.customer_id=l_uid);
 return coalesce(l_result,private.orders_read_failure('forbidden_or_unavailable'));
end $$;


notify pgrst,'reload schema';
commit;
