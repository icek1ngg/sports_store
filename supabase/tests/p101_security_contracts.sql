-- P10.1 regression checks alongside database_security.sql.
-- Catalog assertions need no customer data; every test is rolled back.
begin;
do $$
declare
  r record;
  checked integer := 0;
  rpc_names text[] := array[
    'assign_delivery_task','accept_delivery_task','start_delivery_task',
    'complete_outbound_delivery','fail_delivery_task','decide_outbound_retry',
    'confirm_cod_received','list_cod_collections','read_my_delivery_tasks',
    'read_my_delivery_task_items','list_my_delivery_tasks','get_my_delivery_task',
    'get_my_delivery_reporting_context','report_store_handover','report_delivery_incident',
    'assign_return_pickup_task','collect_return_items','fail_return_pickup_task',
    'get_my_return_pickup_handover','report_return_pickup_handover',
    'approve_return_pickup_plan','receive_customer_return','reject_return_after_inspection',
    'assign_redelivery_task','accept_redelivery_task','start_redelivery_task',
    'complete_redelivery','fail_redelivery_task'];
begin
  if current_setting('sports_store.fixture_mode', true) is distinct from 'p011_isolated'
     or current_database() !~ '^p011_' then
    raise exception 'P10.1 requires the guarded isolated fixture runner';
  end if;
  -- Audit every overload, not a hand-picked signature that can miss a newly
  -- exposed overload. Public wrappers must remain authenticated-only.
  if exists (select 1 from unnest(rpc_names) name where not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname=name)) then
    raise exception 'P10.1 expected production RPC missing';
  end if;
  for r in select p.oid, p.oid::regprocedure as signature
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname=any(rpc_names)
  loop
    checked := checked+1;
    if has_function_privilege('anon',r.oid,'execute')
       or has_function_privilege('service_role',r.oid,'execute')
       or not has_function_privilege('authenticated',r.oid,'execute') then
      raise exception 'P10.1 unexpected RPC ACL: %',r.signature;
    end if;
  end loop;
  if checked < cardinality(rpc_names) then raise exception 'P10.1 missing production RPCs: %',checked; end if;

  checked := 0;
  for r in select c.oid, c.relname, c.relrowsecurity, c.relforcerowsecurity
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='private' and c.relkind='r'
      and c.relname ~ '^(outbound_|delivery_assignment_|cod_receipt_|return_pickup_|redelivery_)'
  loop
    checked := checked+1;
    if not r.relrowsecurity or not r.relforcerowsecurity then
      raise exception 'P10.1 private ledger lacks FORCE RLS: %',r.relname;
    end if;
    if has_table_privilege('anon',r.oid,'select,insert,update,delete,truncate')
       or has_table_privilege('authenticated',r.oid,'select,insert,update,delete,truncate') then
      raise exception 'P10.1 client base-ledger access: %',r.relname;
    end if;
  end loop;
  if checked < 15 then raise exception 'P10.1 missing private ledgers: %',checked; end if;

  for r in select oid,rolname,rolsuper,rolbypassrls,rolcanlogin,rolinherit from pg_roles
    where rolname like 'sports_store_%writer'
  loop
    if r.rolsuper or r.rolbypassrls or r.rolcanlogin or r.rolinherit
       or pg_has_role('authenticated',r.rolname,'member')
       or pg_has_role('anon',r.rolname,'member')
       or pg_has_role('service_role',r.rolname,'member')
       -- Current migrations grant writers TO postgres, never another role
       -- TO a writer. Check both directions so a pg_read_all_data membership
       -- cannot silently expand a SECURITY DEFINER owner's powers.
       or exists (select 1 from pg_auth_members where member=r.oid) then
      raise exception 'P10.1 unsafe internal writer role: %',r.rolname;
    end if;
  end loop;
end $$;

-- Actual permission-denied operations, not only catalog inspection. This
-- anonymous authenticated identity has no profile/role to elevate through.
set local role authenticated;
do $$
begin
  begin
    perform 1 from private.outbound_dispatches;
    raise exception 'P10.1 unexpected dispatch proof read';
  exception when insufficient_privilege then null; end;
  begin
    execute 'update private.cod_receipt_requests set request_id=request_id';
    raise exception 'P10.1 unexpected receipt ledger write';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'p101_security_contracts.sql: PASS' as result;
rollback;
