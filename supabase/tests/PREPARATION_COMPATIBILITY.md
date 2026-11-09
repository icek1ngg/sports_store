# Preparation assignment test compatibility

Current-schema tests require all migrations through
`20261109183418_prepare_and_assign_delivery.sql`. Run only on an isolated local
PostgreSQL fixture with `sports_store.fixture_mode = 'p011_isolated'` set before
loading `fixtures/p011_auth_storage.sql.fixture`. Never use these Auth fixtures
on shared or production databases.

Successful initial assignment setup now calls `prepare_and_assign_delivery`
with `p_prepared=true`. Legacy `assign_delivery_task` remains in reassignment,
no-op, stale CAS, authorization and business-error probes. The dedicated
`prepare_and_assign_delivery.sql` regression checks the legacy initial-assignment
guard. Concurrency cleanup also removes scoped preparation proofs while using
its existing isolated-admin trigger handling.

`orders_transactional_mutations.sql` additionally requires the session setting
`sports_store.qa_local_disposable = 'YES'` before execution.

`outbound_retry_dependencies.sql` is a HISTORICAL dependency-boundary test,
not a current-schema suite: it explicitly asserts that production
`public.decide_outbound_retry` does not exist. Preserve that assertion. To run:

1. Create a new isolated database and set fixture_mode as above.
2. Load the Auth/Storage fixture.
3. Apply migrations in filename order strictly BEFORE
   `20261027062118_decide_outbound_retry.sql` (last migration is
   `20261027060030_fail_outbound_delivery.sql`).
4. Replace its single `-- P072_RETRY_CONTRACT_FIXTURE` marker in memory with
   `fixtures/p072_retry_contract.sql.fixture`, execute on the same connection,
   and allow its final ROLLBACK. Do not apply later migrations first.

Local verification: preparation, Orders mutations, assignment, reporting and
retry production SQL passed; all five modified concurrency modules passed.
Current read/accept/start/completion/failure/pickup/COD suites also passed.
`database_security.sql` failed separately at its active-return seed with
`ACTIVE_RETURN_EXISTS`; do not report a completely passing global runner.
The historical cutoff run was not validated: its initial attempt omitted the
required fixture_mode setting and stopped before loading the schema.
The hosted UI runner was syntax-checked only; no hosted execution or deployment.
The older Orders migration also rejects an existing cluster-global writer role;
our full local migration replay reused a security-validated existing role only
in test memory, without changing source migrations or that role.
