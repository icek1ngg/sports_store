-- MH07 -> MH13: expose `can_open_return_creation` in Orders capabilities.
--
-- `private.orders_write_capabilities` returns early for every delivered order
-- (`orders_mutation_eligibility` reports custody_unverified once delivered_at
-- is set), so the return capability was always false. This migration does not
-- touch that writer-owned SECURITY DEFINER function. It adds a SECURITY
-- INVOKER helper (caller RLS applies) and merges its result into the two read
-- call sites. The rules mirror `submit_return_request`, which still enforces
-- them at submission time; this flag only controls the MH07 entry button.
begin;

create function private.orders_return_creation_open(p_order_id uuid)
returns boolean
language sql stable security invoker set search_path = '' set timezone = 'UTC'
as $$
 select exists (
  select 1
  from public.orders o
  join public.profiles p on p.id = auth.uid() and p.role = 'customer'
  where o.id = p_order_id
    and o.customer_id = auth.uid()
    and o.status = 'delivered'
    and o.delivered_at is not null
    and pg_catalog.clock_timestamp() <= o.delivered_at + interval '7 days'
    and not exists (
      select 1 from public.return_requests r
      where r.order_id = o.id
        and r.status in (
          'pending_review', 'awaiting_return_pickup', 'returning_to_store',
          'under_inspection', 'awaiting_refund', 'awaiting_redelivery',
          'redelivery_failed', 'manager_action_required'
        )
    )
 ) $$;

revoke all on function private.orders_return_creation_open(uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.orders_return_creation_open(uuid)
  to authenticated;

-- Rewrite only the capabilities expression in the two read functions,
-- preserving their remaining bodies, owners, ACLs and invoker flags.
do $$
declare
  f record;
  definition text;
  patched text;
begin
  for f in
    select p.oid, p.proname, x.arg
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join (values
      ('private', 'orders_read_summary', 'p_order.id'),
      ('public', 'get_order_details', 'o.id')
    ) x(schema_name, function_name, arg)
      on n.nspname = x.schema_name and p.proname = x.function_name
  loop
    definition := pg_get_functiondef(f.oid);
    patched := replace(
      definition,
      format('private.orders_write_capabilities(%s)', f.arg),
      format(
        'private.orders_write_capabilities(%1$s) || pg_catalog.jsonb_build_object(''can_open_return_creation'', private.orders_return_creation_open(%1$s))',
        f.arg
      )
    );
    if patched = definition then
      raise exception 'Capabilities call site not found in %', f.proname;
    end if;
    execute patched;
  end loop;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where (n.nspname, p.proname) in (('private', 'orders_read_summary'), ('public', 'get_order_details'))
        and position('orders_return_creation_open' in p.prosrc) > 0) <> 2 then
    raise exception 'Expected exactly two patched Orders read functions';
  end if;
end $$;

notify pgrst, 'reload schema';
commit;
