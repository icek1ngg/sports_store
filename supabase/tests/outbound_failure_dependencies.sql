-- P07.1 TEST-ONLY dependency boundary.
-- The production fail_delivery_task RPC, recipient policy and idempotency
-- ledger are not available in the current migrations. This suite verifies
-- only that the explicitly labelled temporary interface validates its draft
-- input and fails closed without fabricating success or writing state.
--
-- It is not a live authorization, task-kind/state, custody, attempt-limit,
-- recipient, event, notification or idempotency-success test. Those checks
-- require the owner-approved production contract. No fixture rows are seeded;
-- the pre/post snapshots may therefore be empty. The authenticated calls use
-- the isolated Auth `auth.uid()` stub and database role, but no profile role or
-- task lifecycle is asserted here.

begin;
set constraints all deferred;

-- P071_FAILURE_CONTRACT_FIXTURE

create or replace function pg_temp.assert_p071(
  p_label text,
  p_condition boolean
) returns void
language plpgsql
as $$
begin
  if coalesce(p_condition, false) is not true then
    raise exception 'P07.1 failure dependency fixture failed: %', p_label;
  end if;
end;
$$;

create or replace function pg_temp.set_p071_claims(
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

create or replace function pg_temp.assert_p071_error(
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
      'P07.1 failure dependency fixture failed: % (expected %/%; got %/%)',
      p_label, p_state, p_message, coalesce(l_state, 'success'),
      coalesce(l_message, '');
  end if;
end;
$$;

-- Capture complete row values rather than counts. All current business rows
-- are preserved if this suite is run against an isolated database that has
-- existing test data; the interface itself never reads these tables.
create temp table p071_state_before as
select
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.orders x) as orders,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.delivery_tasks x) as tasks,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.delivery_attempts x) as attempts,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.order_id), '[]'::jsonb)
     from public.cod_collections x) as cod,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.business_events x) as events,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.notifications x) as notifications,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.inventory_movements x) as inventory_movements,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.product_variants x) as product_variants,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.return_requests x) as return_requests,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.actor_id, x.request_id), '[]'::jsonb)
     from private.delivery_assignment_requests x) as assignment_requests,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from private.delivery_assignment_audits x) as assignment_audits,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.actor_id, x.request_id), '[]'::jsonb)
     from private.cod_receipt_requests x) as cod_receipt_requests;

select pg_temp.assert_p071(
  'temporary failure interface is loaded',
  to_regprocedure(
    'pg_temp.fail_outbound_delivery_contract(uuid,uuid,text,text)'
  ) is not null
);
select pg_temp.assert_p071(
  'no public fail RPC is claimed as existing',
  not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fail_delivery_task'
  )
);

-- The fixture uses the real database role plus the isolated auth.uid() stub;
-- this does not infer or assert a server-managed profile role.
set local role authenticated;

select pg_temp.set_p071_claims(null);
select pg_temp.assert_p071(
  'anonymous claims produce a null auth.uid',
  auth.uid() is null
);
select pg_temp.assert_p071_error(
  'anonymous valid failure is rejected before dependency fallback',
  $sql$select pg_temp.fail_outbound_delivery_contract(
    '07100000-0000-0000-0000-000000000001'::uuid,
    '07100000-0000-0000-0000-000000000101'::uuid,
    'unreachable',
    null
  )$sql$,
  '42501', 'AUTH_REQUIRED'
);

select pg_temp.set_p071_claims(
  '07100000-0000-0000-0000-000000000010'::uuid
);
select pg_temp.assert_p071(
  'authenticated claims produce the expected auth.uid',
  auth.uid() = '07100000-0000-0000-0000-000000000010'::uuid
);

-- Null identifiers and reason are argument errors, not fabricated success or
-- a dependency result. The function has no task/profile lookup to bypass.
select pg_temp.assert_p071_error(
  'null task ID is rejected',
  $sql$select pg_temp.fail_outbound_delivery_contract(
    null::uuid,
    '07100000-0000-0000-0000-000000000101'::uuid,
    'unreachable',
    null
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p071_error(
  'null request ID is rejected',
  $sql$select pg_temp.fail_outbound_delivery_contract(
    '07100000-0000-0000-0000-000000000001'::uuid,
    null::uuid,
    'unreachable',
    null
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p071_error(
  'null reason code is rejected',
  $sql$select pg_temp.fail_outbound_delivery_contract(
    '07100000-0000-0000-0000-000000000001'::uuid,
    '07100000-0000-0000-0000-000000000101'::uuid,
    null,
    null
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p071_error(
  'unknown reason code is rejected',
  $sql$select pg_temp.fail_outbound_delivery_contract(
    '07100000-0000-0000-0000-000000000001'::uuid,
    '07100000-0000-0000-0000-000000000102'::uuid,
    'customer_changed_mind',
    'Draft-only reason'
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p071_error(
  'blank reason code is rejected',
  $sql$select pg_temp.fail_outbound_delivery_contract(
    '07100000-0000-0000-0000-000000000001'::uuid,
    '07100000-0000-0000-0000-000000000103'::uuid,
    '   ',
    null
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);

-- Only `other` requires a nonblank description. Whitespace-only values cover
-- spaces, tabs and newlines; no maximum length is imposed on text input.
select pg_temp.assert_p071_error(
  'other with null description is rejected',
  $sql$select pg_temp.fail_outbound_delivery_contract(
    '07100000-0000-0000-0000-000000000001'::uuid,
    '07100000-0000-0000-0000-000000000104'::uuid,
    'other',
    null
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p071_error(
  'other with empty description is rejected',
  $sql$select pg_temp.fail_outbound_delivery_contract(
    '07100000-0000-0000-0000-000000000001'::uuid,
    '07100000-0000-0000-0000-000000000105'::uuid,
    'other',
    ''
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p071_error(
  'other with spaces is rejected',
  $sql$select pg_temp.fail_outbound_delivery_contract(
    '07100000-0000-0000-0000-000000000001'::uuid,
    '07100000-0000-0000-0000-000000000106'::uuid,
    'other',
    '   '
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p071_error(
  'other with tab and newline is rejected',
  $sql$select pg_temp.fail_outbound_delivery_contract(
    '07100000-0000-0000-0000-000000000001'::uuid,
    '07100000-0000-0000-0000-000000000107'::uuid,
    'other',
    E'\t\n'
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);

-- The other reason codes may have no description; this confirms no extra
-- description requirement was invented for them.
select pg_temp.assert_p071_error(
  'unreachable with null description reaches dependency gate',
  $sql$select pg_temp.fail_outbound_delivery_contract(
    '07100000-0000-0000-0000-000000000001'::uuid,
    '07100000-0000-0000-0000-000000000108'::uuid,
    'unreachable',
    null
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);
select pg_temp.assert_p071_error(
  'reschedule with blank description reaches dependency gate',
  $sql$select pg_temp.fail_outbound_delivery_contract(
    '07100000-0000-0000-0000-000000000001'::uuid,
    '07100000-0000-0000-0000-000000000109'::uuid,
    'reschedule',
    ' '
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);

-- Every valid draft reason fails closed. The IDs are deliberately not seeded;
-- the interface must not turn an unknown, non-outbound-labelled ID into a
-- fabricated success. This is not a test of live task kind/state enforcement.
select pg_temp.assert_p071_error(
  'bad_address fails closed',
  $sql$select pg_temp.fail_outbound_delivery_contract(
    '07100000-0000-0000-0000-000000000001'::uuid,
    '07100000-0000-0000-0000-000000000110'::uuid,
    'bad_address',
    null
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);
select pg_temp.assert_p071_error(
  'refusal fails closed',
  $sql$select pg_temp.fail_outbound_delivery_contract(
    '07100000-0000-0000-0000-000000000001'::uuid,
    '07100000-0000-0000-0000-000000000111'::uuid,
    'refusal',
    null
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);
select pg_temp.assert_p071_error(
  'other with nonblank description fails closed',
  $sql$select pg_temp.fail_outbound_delivery_contract(
    '07100000-0000-0000-0000-000000000001'::uuid,
    '07100000-0000-0000-0000-000000000112'::uuid,
    'other',
    'Recipient reported an unclassified delivery problem'
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);

-- Same request and payload remain fail closed on retry; a different request
-- cannot manufacture an idempotency result either. No success ledger exists
-- in this fixture.
select pg_temp.assert_p071_error(
  'same failure request remains fail closed on retry',
  $sql$select pg_temp.fail_outbound_delivery_contract(
    '07100000-0000-0000-0000-000000000001'::uuid,
    '07100000-0000-0000-0000-000000000110'::uuid,
    'bad_address',
    null
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);
select pg_temp.assert_p071_error(
  'different failure request remains fail closed',
  $sql$select pg_temp.fail_outbound_delivery_contract(
    '07100000-0000-0000-0000-000000000001'::uuid,
    '07100000-0000-0000-0000-000000000113'::uuid,
    'unreachable',
    null
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);

reset role;
select pg_temp.assert_p071(
  'fail-closed calls leave all relevant state unchanged',
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.orders x)
      = (select orders from p071_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.delivery_tasks x)
      = (select tasks from p071_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.delivery_attempts x)
      = (select attempts from p071_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.order_id), '[]'::jsonb)
     from public.cod_collections x)
      = (select cod from p071_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.business_events x)
      = (select events from p071_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.notifications x)
      = (select notifications from p071_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.inventory_movements x)
      = (select inventory_movements from p071_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.product_variants x)
      = (select product_variants from p071_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.return_requests x)
      = (select return_requests from p071_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.actor_id, x.request_id), '[]'::jsonb)
     from private.delivery_assignment_requests x)
      = (select assignment_requests from p071_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from private.delivery_assignment_audits x)
      = (select assignment_audits from p071_state_before)
  and (select coalesce(jsonb_agg(to_jsonb(x) order by x.actor_id, x.request_id), '[]'::jsonb)
     from private.cod_receipt_requests x)
      = (select cod_receipt_requests from p071_state_before)
);

select 'outbound_failure_dependencies.sql: PASS' as result,
       'TEST-ONLY fail-closed fixture; no production failure RPC, role/state, recipient or ledger enforcement' as scope;

rollback;
