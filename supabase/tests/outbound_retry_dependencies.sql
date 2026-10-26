-- P07.2 TEST-ONLY dependency boundary.
-- The production retry decision and custody-safe reassignment RPCs are not
-- available in the current migrations. This suite verifies only that the
-- explicitly labelled temporary interfaces validate draft input and fail
-- closed without fabricating success or writing state.
--
-- It is not a live manager authorization, task kind/state, custody/dispatch,
-- attempt-limit/third-attempt, reassignment CAS, recipient, event,
-- notification or idempotency-success test. D3 is unresolved and requires the
-- owner-approved production transaction. No fixture rows are seeded.

begin;
set constraints all deferred;

-- P072_RETRY_CONTRACT_FIXTURE

create or replace function pg_temp.assert_p072(
  p_label text,
  p_condition boolean
) returns void
language plpgsql
as $$
begin
  if coalesce(p_condition, false) is not true then
    raise exception 'P07.2 retry dependency fixture failed: %', p_label;
  end if;
end;
$$;

create or replace function pg_temp.set_p072_claims(
  p_user_id uuid
) returns void
language plpgsql
as $$
begin
  perform set_config(
    'request.jwt.claim.sub', coalesce(p_user_id::text, ''), true
  );
  perform set_config(
    'request.jwt.claims',
    case when p_user_id is null then '' else jsonb_build_object(
      'sub', p_user_id::text,
      'role', 'authenticated',
      'aud', 'authenticated'
    )::text end,
    true
  );
end;
$$;

create or replace function pg_temp.assert_p072_error(
  p_label text,
  p_sql text,
  p_state text,
  p_message text
) returns void
language plpgsql
as $$
declare
  l_state text;
  l_message text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics
      l_state = returned_sqlstate,
      l_message = message_text;
  end;

  if l_state is distinct from p_state or l_message is distinct from p_message then
    raise exception
      'P07.2 retry dependency fixture failed: % (expected %/%; got %/%)',
      p_label, p_state, p_message, coalesce(l_state, 'success'),
      coalesce(l_message, '');
  end if;
end;
$$;

-- Capture complete row values for every public table that survives the
-- simplify migration. The test functions themselves do not read any of these
-- tables. Deliberately do not reference the two legacy tables removed by the
-- simplify migration. The two assignment ledgers are included as the optional
-- private snapshots; the fixture cannot write either ledger.
create temp table p072_state_before as
select
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.profiles x) as profiles,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.categories x) as categories,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.products x) as products,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.product_variants x) as product_variants,
  (select coalesce(jsonb_agg(to_jsonb(x)
                            order by x.customer_id, x.variant_id),
                   '[]'::jsonb)
     from public.cart_items x) as cart_items,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.orders x) as orders,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.order_items x) as order_items,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.return_requests x) as return_requests,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.inventory_movements x) as inventory_movements,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.delivery_tasks x) as tasks,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.delivery_attempts x) as attempts,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.order_id), '[]'::jsonb)
     from public.cod_collections x) as cod,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.return_items x) as return_items,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.business_events x) as events,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.notifications x) as notifications,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.conversations x) as conversations,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.messages x) as messages,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.store_settings x) as store_settings,
  (select coalesce(jsonb_agg(to_jsonb(x)
                            order by x.actor_id, x.request_id),
                   '[]'::jsonb)
     from private.delivery_assignment_requests x) as assignment_requests,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from private.delivery_assignment_audits x) as assignment_audits;

select pg_temp.assert_p072(
  'temporary retry decision interface is loaded',
  to_regprocedure(
    'pg_temp.decide_outbound_retry_contract(uuid,uuid,text)'
  ) is not null
);
select pg_temp.assert_p072(
  'temporary reassignment interface is loaded',
  to_regprocedure(
    'pg_temp.reassign_outbound_task_contract(uuid,uuid,uuid)'
  ) is not null
);
select pg_temp.assert_p072(
  'no public decide_outbound_retry RPC is claimed as existing',
  not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'decide_outbound_retry'
  )
);
select pg_temp.assert_p072(
  'existing public assign_delivery_task remains available to authenticated',
  to_regprocedure(
    'public.assign_delivery_task(uuid,uuid,uuid,uuid,uuid)'
  ) is not null
  and has_function_privilege(
    'authenticated',
    'public.assign_delivery_task(uuid,uuid,uuid,uuid,uuid)',
    'EXECUTE'
  )
);

-- The fixture uses the real database role plus the isolated auth.uid() stub.
-- It does not infer or assert a server-managed profile role.
set local role authenticated;

select pg_temp.set_p072_claims(null);
select pg_temp.assert_p072(
  'anonymous claims produce a null auth.uid',
  auth.uid() is null
);
select pg_temp.assert_p072_error(
  'anonymous valid retry decision is rejected before dependency fallback',
  $sql$select pg_temp.decide_outbound_retry_contract(
    '07200000-0000-0000-0000-000000000001'::uuid,
    '07200000-0000-0000-0000-000000000101'::uuid,
    'retry'
  )$sql$,
  '42501', 'AUTH_REQUIRED'
);
select pg_temp.assert_p072_error(
  'anonymous valid reassignment is rejected before dependency fallback',
  $sql$select pg_temp.reassign_outbound_task_contract(
    '07200000-0000-0000-0000-000000000201'::uuid,
    '07200000-0000-0000-0000-000000000202'::uuid,
    '07200000-0000-0000-0000-000000000102'::uuid
  )$sql$,
  '42501', 'AUTH_REQUIRED'
);

select pg_temp.set_p072_claims(
  '07200000-0000-0000-0000-000000000010'::uuid
);
select pg_temp.assert_p072(
  'authenticated claims produce the expected auth.uid',
  auth.uid() = '07200000-0000-0000-0000-000000000010'::uuid
);

-- Draft decision input is checked without consulting production task/order
-- state. Null, blank, case-changed and unknown decisions are all invalid.
select pg_temp.assert_p072_error(
  'null order ID is rejected',
  $sql$select pg_temp.decide_outbound_retry_contract(
    null::uuid,
    '07200000-0000-0000-0000-000000000103'::uuid,
    'retry'
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p072_error(
  'null decision request ID is rejected',
  $sql$select pg_temp.decide_outbound_retry_contract(
    '07200000-0000-0000-0000-000000000001'::uuid,
    null::uuid,
    'retry'
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p072_error(
  'null retry decision is rejected',
  $sql$select pg_temp.decide_outbound_retry_contract(
    '07200000-0000-0000-0000-000000000001'::uuid,
    '07200000-0000-0000-0000-000000000104'::uuid,
    null
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p072_error(
  'blank retry decision is rejected',
  $sql$select pg_temp.decide_outbound_retry_contract(
    '07200000-0000-0000-0000-000000000001'::uuid,
    '07200000-0000-0000-0000-000000000105'::uuid,
    ' '
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p072_error(
  'unknown retry decision is rejected',
  $sql$select pg_temp.decide_outbound_retry_contract(
    '07200000-0000-0000-0000-000000000001'::uuid,
    '07200000-0000-0000-0000-000000000106'::uuid,
    'retry_now'
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p072_error(
  'case-changed return decision is rejected',
  $sql$select pg_temp.decide_outbound_retry_contract(
    '07200000-0000-0000-0000-000000000001'::uuid,
    '07200000-0000-0000-0000-000000000107'::uuid,
    'RETURN_TO_STORE'
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);

-- Both draft decisions fail closed. The interface does not create attempt 2,
-- a task, a return-to-store state, or an idempotency result.
select pg_temp.assert_p072_error(
  'retry decision fails closed',
  $sql$select pg_temp.decide_outbound_retry_contract(
    '07200000-0000-0000-0000-000000000001'::uuid,
    '07200000-0000-0000-0000-000000000108'::uuid,
    'retry'
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);
select pg_temp.assert_p072_error(
  'return-to-store decision fails closed',
  $sql$select pg_temp.decide_outbound_retry_contract(
    '07200000-0000-0000-0000-000000000001'::uuid,
    '07200000-0000-0000-0000-000000000109'::uuid,
    'return_to_store'
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);

-- No retry/idempotency ledger exists in this fixture: duplicate and changed
-- payloads must remain the same dependency error, never fake a replay or a
-- payload-conflict result.
select pg_temp.assert_p072_error(
  'same retry request remains fail closed on duplicate',
  $sql$select pg_temp.decide_outbound_retry_contract(
    '07200000-0000-0000-0000-000000000001'::uuid,
    '07200000-0000-0000-0000-000000000108'::uuid,
    'retry'
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);
select pg_temp.assert_p072_error(
  'same retry request with changed decision remains fail closed',
  $sql$select pg_temp.decide_outbound_retry_contract(
    '07200000-0000-0000-0000-000000000001'::uuid,
    '07200000-0000-0000-0000-000000000108'::uuid,
    'return_to_store'
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);
select pg_temp.assert_p072_error(
  'new retry request remains fail closed',
  $sql$select pg_temp.decide_outbound_retry_contract(
    '07200000-0000-0000-0000-000000000001'::uuid,
    '07200000-0000-0000-0000-000000000110'::uuid,
    'retry'
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);

-- Reassignment has only UUID/null input validation in this boundary. It does
-- not authorize a manager, inspect current assignment/custody, or change the
-- existing public assignment RPC.
select pg_temp.assert_p072_error(
  'null task ID is rejected for reassignment',
  $sql$select pg_temp.reassign_outbound_task_contract(
    null::uuid,
    '07200000-0000-0000-0000-000000000202'::uuid,
    '07200000-0000-0000-0000-000000000111'::uuid
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p072_error(
  'null shipper ID is rejected for reassignment',
  $sql$select pg_temp.reassign_outbound_task_contract(
    '07200000-0000-0000-0000-000000000201'::uuid,
    null::uuid,
    '07200000-0000-0000-0000-000000000112'::uuid
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p072_error(
  'null reassignment request ID is rejected',
  $sql$select pg_temp.reassign_outbound_task_contract(
    '07200000-0000-0000-0000-000000000201'::uuid,
    '07200000-0000-0000-0000-000000000202'::uuid,
    null::uuid
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p072_error(
  'valid reassignment fails closed',
  $sql$select pg_temp.reassign_outbound_task_contract(
    '07200000-0000-0000-0000-000000000201'::uuid,
    '07200000-0000-0000-0000-000000000202'::uuid,
    '07200000-0000-0000-0000-000000000113'::uuid
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);
select pg_temp.assert_p072_error(
  'same reassignment request remains fail closed on duplicate',
  $sql$select pg_temp.reassign_outbound_task_contract(
    '07200000-0000-0000-0000-000000000201'::uuid,
    '07200000-0000-0000-0000-000000000202'::uuid,
    '07200000-0000-0000-0000-000000000113'::uuid
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);
select pg_temp.assert_p072_error(
  'changed reassignment shipper remains fail closed',
  $sql$select pg_temp.reassign_outbound_task_contract(
    '07200000-0000-0000-0000-000000000201'::uuid,
    '07200000-0000-0000-0000-000000000203'::uuid,
    '07200000-0000-0000-0000-000000000113'::uuid
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);
select pg_temp.assert_p072_error(
  'changed reassignment task remains fail closed',
  $sql$select pg_temp.reassign_outbound_task_contract(
    '07200000-0000-0000-0000-000000000204'::uuid,
    '07200000-0000-0000-0000-000000000202'::uuid,
    '07200000-0000-0000-0000-000000000113'::uuid
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);

reset role;
select pg_temp.assert_p072(
  'fail-closed calls leave all surviving public/private state unchanged',
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.profiles x)
      = (select profiles from p072_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.categories x)
      = (select categories from p072_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.products x)
      = (select products from p072_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.product_variants x)
      = (select product_variants from p072_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x)
                                order by x.customer_id, x.variant_id),
                       '[]'::jsonb)
     from public.cart_items x)
      = (select cart_items from p072_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.orders x)
      = (select orders from p072_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.order_items x)
      = (select order_items from p072_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.return_requests x)
      = (select return_requests from p072_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.inventory_movements x)
      = (select inventory_movements from p072_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.delivery_tasks x)
      = (select tasks from p072_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.delivery_attempts x)
      = (select attempts from p072_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.order_id), '[]'::jsonb)
     from public.cod_collections x)
      = (select cod from p072_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.return_items x)
      = (select return_items from p072_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.business_events x)
      = (select events from p072_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.notifications x)
      = (select notifications from p072_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.conversations x)
      = (select conversations from p072_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.messages x)
      = (select messages from p072_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.store_settings x)
      = (select store_settings from p072_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x)
                                order by x.actor_id, x.request_id),
                       '[]'::jsonb)
     from private.delivery_assignment_requests x)
      = (select assignment_requests from p072_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from private.delivery_assignment_audits x)
      = (select assignment_audits from p072_state_before)
);

select 'outbound_retry_dependencies.sql: PASS' as result,
       'TEST-ONLY fail-closed fixture; no live role/custody/state/third-attempt/concurrency acceptance' as scope;

rollback;
