-- Hosted Supabase does not permit application-owned roles to receive USAGE on
-- the managed auth schema.  The existing identity bridge is a SECURITY
-- DEFINER function owned by postgres and is already executable by the locked
-- projection owner.  Rewrite only the new RPC and the four policies changed
-- by the history migration so the deployed function works with hosted ACLs.
do $migration$
declare
  l_definition text;
begin
  select pg_catalog.pg_get_functiondef(
    'public.get_my_delivery_task_history(uuid)'::pg_catalog.regprocedure
  ) into l_definition;
  if l_definition is null then
    raise exception
      'P03.2 auth bridge correction requires get_my_delivery_task_history(uuid)';
  end if;
  if pg_catalog.strpos(l_definition, 'auth.uid()') < 1 then
    raise exception
      'P03.2 auth bridge correction expected auth.uid() in history RPC';
  end if;
  l_definition := pg_catalog.replace(
    l_definition,
    'auth.uid()',
    'private.delivery_request_user_id()'
  );
  execute l_definition;
end;
$migration$;

alter policy delivery_reader_cod_history_read
  on public.cod_collections
  using (shipper_id = (select private.delivery_request_user_id()));

alter policy delivery_reader_order_items
  on public.order_items
  using (
    exists (
      select 1
      from public.delivery_tasks t
      where t.order_id = order_items.order_id
        and t.kind = 'outbound'::public.delivery_task_kind
        and t.assigned_shipper_id = (select private.delivery_request_user_id())
    )
  );

alter policy delivery_reader_return_items
  on public.return_items
  using (
    exists (
      select 1
      from public.delivery_tasks t
      where t.return_request_id = return_items.return_request_id
        and t.kind = 'return_pickup'::public.delivery_task_kind
        and t.assigned_shipper_id = (select private.delivery_request_user_id())
    )
  );

alter policy redelivery_task_items_reader_read
  on private.redelivery_task_items
  using (
    current_user = 'sports_store_delivery_reader'
    and exists (
      select 1
      from public.delivery_tasks t
      where t.id = redelivery_task_items.task_id
        and t.kind = 'redelivery'::public.delivery_task_kind
        and t.assigned_shipper_id = (select private.delivery_request_user_id())
    )
  );

comment on function public.get_my_delivery_task_history(uuid) is
  'P03.2 shipper-only immutable task history/detail with hosted auth identity bridge; assignment remains the authorization boundary.';

notify pgrst, 'reload schema';
