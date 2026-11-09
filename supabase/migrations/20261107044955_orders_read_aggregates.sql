-- OP-O01..03 owner-decided v1.2 READ aggregates. SOURCE ONLY: not deployed.
-- Security invoker preserves existing table RLS. No mutation or policy changes.
-- Missing external adapters remain unavailable; never infer custody/financial state.
begin;

create function private.orders_read_failure(p_code text) returns jsonb
language sql immutable security invoker set search_path = '' set timezone = 'UTC'
as $$ select pg_catalog.jsonb_build_object('ok',false,'data',null,'error',
 pg_catalog.jsonb_build_object('code',p_code,'message_key',null,'retryable',false,'current_order',null)) $$;

create function private.orders_read_capabilities() returns jsonb
language sql immutable security invoker set search_path = '' set timezone = 'UTC'
as $$ select pg_catalog.jsonb_build_object(
 'can_cancel_customer',false,'can_confirm',false,'can_reject',false,
 'can_cancel_exceptional',false,'can_assign',false,'can_reassign',false,
 'can_arrange_second_attempt',false,'can_request_early_return',false,
 'can_receive_undelivered',false,'can_open_return_creation',false) $$;

create function private.orders_read_order(p_order public.orders,p_customer boolean) returns jsonb
language sql immutable security invoker set search_path = '' set timezone = 'UTC'
as $$ select pg_catalog.jsonb_build_object(
 'id',p_order.id,'customer_id',p_order.customer_id,'request_id',p_order.request_id,
 'status',p_order.status,'recipient_name',p_order.recipient_name,
 'recipient_phone',p_order.recipient_phone,'address_detail',p_order.address_detail,
 'latitude',p_order.latitude,'longitude',p_order.longitude,
 'subtotal_vnd',p_order.subtotal_vnd,'delivery_fee_vnd',p_order.delivery_fee_vnd,
 'total_cod_vnd',p_order.total_cod_vnd,'delivery_attempt_count',p_order.delivery_attempt_count,
 'placed_at',p_order.placed_at,'confirmed_at',p_order.confirmed_at,'source',p_order.source,
 'confirmed_by',case when p_customer then null else p_order.confirmed_by end,
 'delivered_at',p_order.delivered_at,'cancel_reason',p_order.cancel_reason,
 'created_at',p_order.created_at,'updated_at',p_order.updated_at) $$;

create function private.orders_read_items(p_order_id uuid) returns jsonb
language sql stable security invoker set search_path = '' set timezone = 'UTC'
as $$ select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
 'id',i.id,'order_id',i.order_id,'product_id',i.product_id,'variant_id',i.variant_id,
 'product_name',i.product_name,'variant_label',i.variant_label,'attributes',i.attributes,
 'unit_price_vnd',i.unit_price_vnd,'quantity',i.quantity,'line_total_vnd',i.line_total_vnd,
 'created_at',i.created_at) order by i.created_at,i.id),'[]'::jsonb)
 from public.order_items i where i.order_id=p_order_id $$;

-- Existing return rows only; eligibility remains unavailable until the canonical
-- Returns bridge is accepted. No bank details, video or payment evidence emitted.
create function private.orders_read_returns(p_order_id uuid) returns jsonb
language sql stable security invoker set search_path = '' set timezone = 'UTC'
as $$ select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
 'return_id',r.id,'order_id',r.order_id,'status',r.status,'submitted_at',r.submitted_at,
 'closed_at',r.closed_at,'decision_reason',r.decision_reason,
 'is_active',r.status::text in ('pending_review','awaiting_return_pickup','returning_to_store',
 'under_inspection','awaiting_refund','awaiting_redelivery','redelivery_failed','manager_action_required'),
 'can_submit_return',false,'eligibility_reason','missing_contract','return_deadline',null)
 order by (r.status::text in ('pending_review','awaiting_return_pickup','returning_to_store',
 'under_inspection','awaiting_refund','awaiting_redelivery','redelivery_failed','manager_action_required')) desc,
 r.submitted_at desc,r.id desc),'[]'::jsonb)
 from public.return_requests r where r.order_id=p_order_id $$;

create function private.orders_read_summary(p_order public.orders,p_customer boolean) returns jsonb
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
 'message','Delivery/COD projections and mutation contracts are unavailable.'),
 pg_catalog.jsonb_build_object('code','history_incomplete','source_id',p_order.id,
 'message','Typed cross-module history is not yet integrated.')),
 'capabilities',private.orders_read_capabilities()) $$;

create function private.orders_read_page(
 p_scope text,p_search text,p_statuses public.order_status[],p_limit integer,p_cursor text
) returns jsonb language plpgsql stable security invoker set search_path = '' set timezone = 'UTC'
as $$
declare
 l_uid uuid := auth.uid(); l_role text; l_search text; l_statuses public.order_status[];
 l_cursor jsonb; l_last_time timestamptz; l_last_id uuid; l_result jsonb;
 l_whitespace text := U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000';
begin
 if l_uid is null then return private.orders_read_failure('unauthenticated'); end if;
 select p.role::text into l_role from public.profiles p where p.id=l_uid;
 if p_scope not in ('customer','manager') or l_role is distinct from p_scope then
  return private.orders_read_failure('forbidden_or_unavailable');
 end if;
 if p_limit is null or p_limit<1 or p_limit>100 or p_statuses is null
    or pg_catalog.array_ndims(p_statuses)>1 or pg_catalog.array_position(p_statuses,null) is not null then
  return private.orders_read_failure('invalid_argument');
 end if;
 l_search := nullif(pg_catalog.btrim(p_search,l_whitespace),'');
 if pg_catalog.char_length(l_search)>200 then return private.orders_read_failure('invalid_argument'); end if;
 select coalesce(pg_catalog.array_agg(s order by s::text),'{}'::public.order_status[]) into l_statuses
 from (select distinct unnest(p_statuses) s) x;
 if p_cursor is not null then
  begin
   if pg_catalog.length(p_cursor)>2048 or p_cursor='' or p_cursor !~ '^[A-Za-z0-9_-]+$'
      or pg_catalog.length(p_cursor)%4=1 then raise exception 'invalid'; end if;
   l_cursor := pg_catalog.convert_from(pg_catalog.decode(pg_catalog.translate(p_cursor,'-_','+/')
      ||pg_catalog.repeat('=',(4-pg_catalog.length(p_cursor)%4)%4),'base64'),'UTF8')::jsonb;
   if pg_catalog.jsonb_typeof(l_cursor)<>'object' or
      (select pg_catalog.array_agg(k order by k) from pg_catalog.jsonb_object_keys(l_cursor) k)
      <>array['last_id','last_placed_at','limit','scope','search','statuses','user_id','v']::text[]
      or l_cursor->'v'<>'1'::jsonb or l_cursor->>'scope' is distinct from p_scope
      or l_cursor->>'user_id' is distinct from l_uid::text
      or l_cursor->'search' is distinct from coalesce(pg_catalog.to_jsonb(l_search),'null'::jsonb)
      or l_cursor->'statuses' is distinct from pg_catalog.to_jsonb(l_statuses)
      or l_cursor->'limit' is distinct from pg_catalog.to_jsonb(p_limit)
      or pg_catalog.jsonb_typeof(l_cursor->'last_id')<>'string'
      or pg_catalog.jsonb_typeof(l_cursor->'last_placed_at')<>'string'
      or l_cursor->>'last_placed_at' !~ '(Z|[+]00:00)$' then raise exception 'invalid'; end if;
   l_last_time := (l_cursor->>'last_placed_at')::timestamptz;
   l_last_id := (l_cursor->>'last_id')::uuid;
   if not pg_catalog.isfinite(l_last_time) then raise exception 'invalid'; end if;
  exception when others then return private.orders_read_failure('invalid_cursor'); end;
 end if;
 -- One statement produces rows, matching total, all-ten status distribution,
 -- cursor and as_of. STABLE also keeps helpers on the calling statement snapshot.
 with searched as materialized (
  select o.* from public.orders o
  where (p_scope='manager' or o.customer_id=l_uid)
   and (l_search is null or o.id::text=pg_catalog.lower(l_search)
    or (p_scope='customer' and exists(select 1 from public.order_items i where i.order_id=o.id
       and pg_catalog.strpos(pg_catalog.lower(i.product_name),pg_catalog.lower(l_search))>0))
    or (p_scope='manager' and exists(select 1 from public.profiles p where p.id=o.customer_id
       and pg_catalog.strpos(pg_catalog.lower(p.full_name),pg_catalog.lower(l_search))>0)))
 ), filtered as materialized (
  select s.* from searched s where pg_catalog.cardinality(l_statuses)=0 or s.status=any(l_statuses)
 ), candidates as materialized (
  select f.* from filtered f where l_last_time is null or (f.placed_at,f.id)<(l_last_time,l_last_id)
  order by f.placed_at desc,f.id desc limit (p_limit+1)
 ), page as materialized (
  select c.* from candidates c order by c.placed_at desc,c.id desc limit p_limit
 ), last_row as (
  select p.placed_at,p.id from page p order by p.placed_at,p.id limit 1
 )
 select pg_catalog.jsonb_build_object('ok',true,'error',null,'data',pg_catalog.jsonb_build_object(
  'items',coalesce((select pg_catalog.jsonb_agg(private.orders_read_summary(p::public.orders,p_scope='customer')
     order by p.placed_at desc,p.id desc) from page p),'[]'::jsonb),
  'total_count',(select count(*) from filtered),
  'status_counts',(select pg_catalog.jsonb_object_agg(e::text,(select count(*) from searched s where s.status=e))
      from unnest(enum_range(null::public.order_status)) e),
  'as_of',pg_catalog.statement_timestamp(),
  'next_cursor',case when (select count(*) from candidates)>p_limit then
   (select pg_catalog.rtrim(pg_catalog.translate(pg_catalog.replace(pg_catalog.encode(pg_catalog.convert_to(
     pg_catalog.jsonb_build_object('v',1,'scope',p_scope,'user_id',l_uid,'search',l_search,
      'statuses',l_statuses,'limit',p_limit,'last_placed_at',
      pg_catalog.to_char(l.placed_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'last_id',l.id)::text,'UTF8'),'base64'),E'\n',''),'+/','-_'),'=') from last_row l)
   else null end)) into l_result;
 return l_result;
end $$;

create function public.get_customer_orders(
 p_search text default null,p_statuses public.order_status[] default '{}',
 p_limit integer default 20,p_cursor text default null
) returns jsonb language sql stable security invoker set search_path = '' set timezone = 'UTC'
as $$ select private.orders_read_page('customer',p_search,p_statuses,p_limit,p_cursor) $$;

create function public.get_manager_orders(
 p_search text default null,p_statuses public.order_status[] default '{}',
 p_limit integer default 20,p_cursor text default null
) returns jsonb language sql stable security invoker set search_path = '' set timezone = 'UTC'
as $$ select private.orders_read_page('manager',p_search,p_statuses,p_limit,p_cursor) $$;

create function public.get_order_details(p_order_id uuid) returns jsonb
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
  'history_complete',false,'capabilities',private.orders_read_capabilities(),
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

-- Public functions are callable only with an authenticated QA/application JWT.
-- Private helpers stay outside the exposed schemas and obey caller table RLS.
revoke all on function private.orders_read_failure(text),private.orders_read_capabilities(),
 private.orders_read_order(public.orders,boolean),private.orders_read_items(uuid),
 private.orders_read_returns(uuid),private.orders_read_summary(public.orders,boolean),
 private.orders_read_page(text,text,public.order_status[],integer,text)
 from public,anon,authenticated,service_role;
grant execute on function private.orders_read_failure(text),private.orders_read_capabilities(),
 private.orders_read_order(public.orders,boolean),private.orders_read_items(uuid),
 private.orders_read_returns(uuid),private.orders_read_summary(public.orders,boolean),
 private.orders_read_page(text,text,public.order_status[],integer,text) to authenticated;
revoke all on function public.get_customer_orders(text,public.order_status[],integer,text),
 public.get_manager_orders(text,public.order_status[],integer,text),public.get_order_details(uuid)
 from public,anon,authenticated,service_role;
grant execute on function public.get_customer_orders(text,public.order_status[],integer,text),
 public.get_manager_orders(text,public.order_status[],integer,text),public.get_order_details(uuid) to authenticated;
comment on function public.get_order_details(uuid) is
 'OP-O03 core snapshot READ; RLS invoker, incomplete snapshot milestones, Delivery/COD unavailable, all actions disabled. SOURCE deployment requires owner review.';
notify pgrst, 'reload schema';
commit;
