# Export the versioned migration as one atomic script for Supabase SQL Editor.
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskMigration = Join-Path $taskRoot 'supabase/migrations/20261029041230_dung_an_management_integration.sql'
$taskOutputDirectory = Join-Path $taskRoot 'supabase/manual'
$taskOutput = Join-Path $taskOutputDirectory 'dung_an_management.sql'
$taskHeader = @'
-- CHAY TOAN BO FILE trong SQL Editor cua project bqoyfytmrtvjwrpshuhh.
-- Run once as the project administrator. This script does not reset data.
-- Generated from migration 20261029041230; edit the source, then regenerate.
-- An error rolls back this entire script; do not run only a selected section.
begin;

do $prerequisites$
begin
  if to_regclass('public.profiles') is null
     or to_regclass('public.products') is null
     or to_regclass('public.product_variants') is null
     or to_regclass('public.inventory_movements') is null
     or to_regclass('public.conversations') is null
     or to_regclass('public.messages') is null
     or to_regprocedure('private.current_app_role()') is null
     or not exists (select 1 from information_schema.columns
       where table_schema='public' and table_name='product_variants' and column_name='on_hand')
     or not exists (select 1 from information_schema.columns
       where table_schema='public' and table_name='conversations' and column_name='read_at_by_user') then
    raise exception 'Required Sports Store baseline schema is missing. Stop and inspect the existing schema; do not reset or replay old migrations.';
  end if;
end;
$prerequisites$;

'@
$taskFooter = @'

notify pgrst, 'reload schema';
commit;

select 'Dung An migration committed. Run verify_dung_an_management.sql next.' as result;
'@
New-Item -ItemType Directory -Path $taskOutputDirectory -Force | Out-Null
$taskBody = Get-Content -LiteralPath $taskMigration -Raw
[System.IO.File]::WriteAllText($taskOutput, $taskHeader + "`n" + $taskBody + "`n" + $taskFooter, [System.Text.UTF8Encoding]::new($false))
Write-Output 'Exported supabase/manual/dung_an_management.sql'
