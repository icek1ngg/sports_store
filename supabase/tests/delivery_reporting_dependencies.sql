-- P07.4 TEST-ONLY reporting dependency boundary.
-- The production custody/handover schema and proof are not available.  D2,
-- D8 and D9 still need owner-approved receipt/item, custody and redelivery
-- decisions; exact manager recipients and deep links remain open under D7.
-- This suite therefore exercises only the explicitly labelled temporary
-- interfaces.  It is not a live role, assignment, task-kind/state, custody,
-- per-kind allowed-state, recipient, event, notification or idempotency test.
-- No fixture rows are seeded and all valid calls fail closed.

begin;
set constraints all deferred;

-- P074_REPORTING_CONTRACT_FIXTURE

create or replace function pg_temp.assert_p074(
  p_label text,
  p_condition boolean
) returns void
language plpgsql
as $$
begin
  if coalesce(p_condition, false) is not true then
    raise exception 'P07.4 reporting dependency fixture failed: %', p_label;
  end if;
end;
$$;

create or replace function pg_temp.set_p074_claims(
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

create or replace function pg_temp.assert_p074_error(
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
      'P07.4 reporting dependency fixture failed: % (expected %/%; got %/%)',
      p_label, p_state, p_message, coalesce(l_state, 'success'),
      coalesce(l_message, '');
  end if;
end;
$$;

create or replace function pg_temp.assert_p074_sqlstate(
  p_label text,
  p_sql text,
  p_state text
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

  if l_state is distinct from p_state then
    raise exception
      'P07.4 reporting dependency fixture failed: % (expected SQLSTATE %; got %/% )',
      p_label, p_state, coalesce(l_state, 'success'),
      coalesce(l_message, '');
  end if;
end;
$$;

-- Capture complete row values for the surviving delivery, inventory and
-- notification tables.  The interface fixture has no table I/O.  The two
-- assignment ledgers are the existing private ledgers in this boundary; the
-- reporting interfaces cannot write either one.
create temp table p074_state_before as
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
     from public.product_variants x) as variants,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.inventory_movements x) as movements,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.business_events x) as events,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.notifications x) as notifications,
  (select coalesce(jsonb_agg(to_jsonb(x)
                            order by x.actor_id, x.request_id),
                   '[]'::jsonb)
     from private.delivery_assignment_requests x) as assignment_requests,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from private.delivery_assignment_audits x) as assignment_audits;

select pg_temp.assert_p074(
  'temporary store-handover interface is loaded without an items payload',
  to_regprocedure(
    'pg_temp.report_store_handover_contract(uuid,uuid)'
  ) is not null
  and to_regprocedure(
    'pg_temp.report_store_handover_contract(uuid,uuid,jsonb)'
  ) is null
);
select pg_temp.assert_p074(
  'temporary incident interface uses the existing incident enum',
  to_regprocedure(
    'pg_temp.report_delivery_incident_contract(uuid,uuid,public.delivery_incident_kind,text)'
  ) is not null
);
select pg_temp.assert_p074(
  'no public reporting RPC exists',
  not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('report_store_handover', 'report_delivery_incident')
  )
);

-- The fixture uses the database role plus the isolated auth.uid() stub.  This
-- does not infer or assert a server-managed profile role or current assignment.
set local role authenticated;

select pg_temp.set_p074_claims(null);
select pg_temp.assert_p074(
  'anonymous claims produce a null auth.uid',
  auth.uid() is null
);
select pg_temp.assert_p074_error(
  'anonymous valid store handover is rejected before dependency fallback',
  $sql$select pg_temp.report_store_handover_contract(
    '07400000-0000-0000-0000-000000000001'::uuid,
    '07400000-0000-0000-0000-000000000101'::uuid
  )$sql$,
  '42501', 'AUTH_REQUIRED'
);
select pg_temp.assert_p074_error(
  'anonymous valid damaged incident is rejected before dependency fallback',
  $sql$select pg_temp.report_delivery_incident_contract(
    '07400000-0000-0000-0000-000000000001'::uuid,
    '07400000-0000-0000-0000-000000000102'::uuid,
    'damaged'::public.delivery_incident_kind,
    'Package was visibly damaged'
  )$sql$,
  '42501', 'AUTH_REQUIRED'
);

select pg_temp.set_p074_claims(
  '07400000-0000-0000-0000-000000000010'::uuid
);
select pg_temp.assert_p074(
  'authenticated claims produce the expected auth.uid',
  auth.uid() = '07400000-0000-0000-0000-000000000010'::uuid
);

-- Null identifiers are input errors.  The two-argument handover shape is
-- intentionally the complete draft shape; no payload is silently invented.
select pg_temp.assert_p074_error(
  'null handover task ID is rejected',
  $sql$select pg_temp.report_store_handover_contract(
    null::uuid,
    '07400000-0000-0000-0000-000000000103'::uuid
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p074_error(
  'null handover request ID is rejected',
  $sql$select pg_temp.report_store_handover_contract(
    '07400000-0000-0000-0000-000000000001'::uuid,
    null::uuid
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);

select pg_temp.assert_p074_error(
  'null incident task ID is rejected',
  $sql$select pg_temp.report_delivery_incident_contract(
    null::uuid,
    '07400000-0000-0000-0000-000000000104'::uuid,
    'damaged'::public.delivery_incident_kind,
    'Package was visibly damaged'
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p074_error(
  'null incident request ID is rejected',
  $sql$select pg_temp.report_delivery_incident_contract(
    '07400000-0000-0000-0000-000000000001'::uuid,
    null::uuid,
    'damaged'::public.delivery_incident_kind,
    'Package was visibly damaged'
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p074_error(
  'null incident kind is rejected',
  $sql$select pg_temp.report_delivery_incident_contract(
    '07400000-0000-0000-0000-000000000001'::uuid,
    '07400000-0000-0000-0000-000000000105'::uuid,
    null::public.delivery_incident_kind,
    'Package was visibly damaged'
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p074_error(
  'null incident reason is rejected',
  $sql$select pg_temp.report_delivery_incident_contract(
    '07400000-0000-0000-0000-000000000001'::uuid,
    '07400000-0000-0000-0000-000000000106'::uuid,
    'damaged'::public.delivery_incident_kind,
    null
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p074_error(
  'empty incident reason is rejected',
  $sql$select pg_temp.report_delivery_incident_contract(
    '07400000-0000-0000-0000-000000000001'::uuid,
    '07400000-0000-0000-0000-000000000107'::uuid,
    'lost'::public.delivery_incident_kind,
    ''
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p074_error(
  'spaces-only incident reason is rejected',
  $sql$select pg_temp.report_delivery_incident_contract(
    '07400000-0000-0000-0000-000000000001'::uuid,
    '07400000-0000-0000-0000-000000000108'::uuid,
    'other'::public.delivery_incident_kind,
    '   '
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);
select pg_temp.assert_p074_error(
  'tab/newline-only incident reason is rejected',
  $sql$select pg_temp.report_delivery_incident_contract(
    '07400000-0000-0000-0000-000000000001'::uuid,
    '07400000-0000-0000-0000-000000000109'::uuid,
    'other'::public.delivery_incident_kind,
    E'\t\n'
  )$sql$,
  '22023', 'INVALID_ARGUMENT'
);

-- The production enum is deliberately `damaged`/`lost`/`other`.  These draft
-- spellings fail at the enum boundary before the temporary function runs.
select pg_temp.assert_p074_sqlstate(
  'damage is not a valid incident enum value',
  $sql$select pg_temp.report_delivery_incident_contract(
    '07400000-0000-0000-0000-000000000001'::uuid,
    '07400000-0000-0000-0000-000000000110'::uuid,
    'damage'::text::public.delivery_incident_kind,
    'Draft enum spelling'
  )$sql$,
  '22P02'
);
select pg_temp.assert_p074_sqlstate(
  'loss is not a valid incident enum value',
  $sql$select pg_temp.report_delivery_incident_contract(
    '07400000-0000-0000-0000-000000000001'::uuid,
    '07400000-0000-0000-0000-000000000111'::uuid,
    'loss'::text::public.delivery_incident_kind,
    'Draft enum spelling'
  )$sql$,
  '22P02'
);
select pg_temp.assert_p074_sqlstate(
  'case-changed damaged is not a valid incident enum value',
  $sql$select pg_temp.report_delivery_incident_contract(
    '07400000-0000-0000-0000-000000000001'::uuid,
    '07400000-0000-0000-0000-000000000112'::uuid,
    'DAMAGED'::text::public.delivery_incident_kind,
    'Case-changed enum spelling'
  )$sql$,
  '22P02'
);

-- Every valid enum kind is accepted only through the draft boundary and then
-- fails closed.  No per-kind D2/D8/D9 state is selected by this fixture.
select pg_temp.assert_p074_error(
  'damaged incident fails closed',
  $sql$select pg_temp.report_delivery_incident_contract(
    '07400000-0000-0000-0000-000000000001'::uuid,
    '07400000-0000-0000-0000-000000000113'::uuid,
    'damaged'::public.delivery_incident_kind,
    'Package was visibly damaged'
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);
select pg_temp.assert_p074_error(
  'lost incident fails closed',
  $sql$select pg_temp.report_delivery_incident_contract(
    '07400000-0000-0000-0000-000000000001'::uuid,
    '07400000-0000-0000-0000-000000000114'::uuid,
    'lost'::public.delivery_incident_kind,
    'The package could not be located'
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);
select pg_temp.assert_p074_error(
  'other incident fails closed',
  $sql$select pg_temp.report_delivery_incident_contract(
    '07400000-0000-0000-0000-000000000001'::uuid,
    '07400000-0000-0000-0000-000000000115'::uuid,
    'other'::public.delivery_incident_kind,
    'An incident requiring manager review'
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);

-- Store handover has no item payload and therefore cannot claim custody or a
-- receipt.  A valid draft call remains dependency-blocked.
select pg_temp.assert_p074_error(
  'valid store handover fails closed',
  $sql$select pg_temp.report_store_handover_contract(
    '07400000-0000-0000-0000-000000000001'::uuid,
    '07400000-0000-0000-0000-000000000116'::uuid
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);

-- Repeated and changed payloads remain dependency-blocked.  There is no
-- success ledger in this fixture, so no replay or payload-conflict result is
-- fabricated and no request can mutate state.
select pg_temp.assert_p074_error(
  'same handover request remains fail closed on repeat',
  $sql$select pg_temp.report_store_handover_contract(
    '07400000-0000-0000-0000-000000000001'::uuid,
    '07400000-0000-0000-0000-000000000116'::uuid
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);
select pg_temp.assert_p074_error(
  'changed handover task remains fail closed for same request',
  $sql$select pg_temp.report_store_handover_contract(
    '07400000-0000-0000-0000-000000000002'::uuid,
    '07400000-0000-0000-0000-000000000116'::uuid
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);
select pg_temp.assert_p074_error(
  'new handover request remains fail closed',
  $sql$select pg_temp.report_store_handover_contract(
    '07400000-0000-0000-0000-000000000001'::uuid,
    '07400000-0000-0000-0000-000000000117'::uuid
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);

select pg_temp.assert_p074_error(
  'same incident request remains fail closed on repeat',
  $sql$select pg_temp.report_delivery_incident_contract(
    '07400000-0000-0000-0000-000000000001'::uuid,
    '07400000-0000-0000-0000-000000000113'::uuid,
    'damaged'::public.delivery_incident_kind,
    'Package was visibly damaged'
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);
select pg_temp.assert_p074_error(
  'changed incident reason remains fail closed for same request',
  $sql$select pg_temp.report_delivery_incident_contract(
    '07400000-0000-0000-0000-000000000001'::uuid,
    '07400000-0000-0000-0000-000000000113'::uuid,
    'damaged'::public.delivery_incident_kind,
    'Changed incident payload'
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);
select pg_temp.assert_p074_error(
  'changed incident kind remains fail closed for same request',
  $sql$select pg_temp.report_delivery_incident_contract(
    '07400000-0000-0000-0000-000000000001'::uuid,
    '07400000-0000-0000-0000-000000000113'::uuid,
    'lost'::public.delivery_incident_kind,
    'Changed incident payload'
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);
select pg_temp.assert_p074_error(
  'changed incident task remains fail closed for same request',
  $sql$select pg_temp.report_delivery_incident_contract(
    '07400000-0000-0000-0000-000000000002'::uuid,
    '07400000-0000-0000-0000-000000000113'::uuid,
    'other'::public.delivery_incident_kind,
    'Changed incident payload'
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);
select pg_temp.assert_p074_error(
  'new incident request remains fail closed',
  $sql$select pg_temp.report_delivery_incident_contract(
    '07400000-0000-0000-0000-000000000001'::uuid,
    '07400000-0000-0000-0000-000000000118'::uuid,
    'other'::public.delivery_incident_kind,
    'A new incident payload'
  )$sql$,
  'P0001', 'DEPENDENCY_NOT_READY'
);

reset role;

-- Full-row snapshots prove that these fail-closed calls did not mutate any
-- table in scope, including both existing assignment ledgers.
create temp table p074_state_after as
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
     from public.product_variants x) as variants,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.inventory_movements x) as movements,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.business_events x) as events,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from public.notifications x) as notifications,
  (select coalesce(jsonb_agg(to_jsonb(x)
                            order by x.actor_id, x.request_id),
                   '[]'::jsonb)
     from private.delivery_assignment_requests x) as assignment_requests,
  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)
     from private.delivery_assignment_audits x) as assignment_audits;

select pg_temp.assert_p074(
  'orders unchanged',
  (select orders from p074_state_after) = (select orders from p074_state_before)
);
select pg_temp.assert_p074(
  'delivery tasks unchanged',
  (select tasks from p074_state_after) = (select tasks from p074_state_before)
);
select pg_temp.assert_p074(
  'delivery attempts unchanged',
  (select attempts from p074_state_after) = (select attempts from p074_state_before)
);
select pg_temp.assert_p074(
  'COD collections unchanged',
  (select cod from p074_state_after) = (select cod from p074_state_before)
);
select pg_temp.assert_p074(
  'product variants unchanged',
  (select variants from p074_state_after) = (select variants from p074_state_before)
);
select pg_temp.assert_p074(
  'inventory movements unchanged',
  (select movements from p074_state_after) = (select movements from p074_state_before)
);
select pg_temp.assert_p074(
  'business events unchanged',
  (select events from p074_state_after) = (select events from p074_state_before)
);
select pg_temp.assert_p074(
  'notifications unchanged',
  (select notifications from p074_state_after) = (select notifications from p074_state_before)
);
select pg_temp.assert_p074(
  'assignment request ledger unchanged',
  (select assignment_requests from p074_state_after)
    = (select assignment_requests from p074_state_before)
);
select pg_temp.assert_p074(
  'assignment audit ledger unchanged',
  (select assignment_audits from p074_state_after)
    = (select assignment_audits from p074_state_before)
);

select 'delivery_reporting_dependencies.sql: PASS' as result,
       'TEST-ONLY fail-closed reporting interfaces; no custody/receipt,
        per-kind state, D7 recipient or idempotency success is claimed' as scope;

rollback;
