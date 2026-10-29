# Local PostgreSQL/Auth-Storage stubs only; never deploys or resets a Supabase project.
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$pgBin = Join-Path $workspace 'supabase/.temp/p011_pg_runtime/node_modules/@embedded-postgres/windows-x64/native/bin'
$pgData = Join-Path $workspace 'supabase/.temp/p011_native_data'
if (-not (Test-Path -LiteralPath (Join-Path $pgBin 'postgres.exe')) -or
    -not (Test-Path -LiteralPath (Join-Path $pgData 'PG_VERSION'))) {
  throw 'Workspace-local PG17 fixture runtime/data unavailable; see docs/demos/p061_cod_list_api.md. Do not use cloud credentials.'
}
$startedHere = $false
$testExitCode = 1
$database = 'p011_p061_cod_' + (Get-Date -Format 'yyyyMMddHHmmss') + '_' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
try {
  & (Join-Path $pgBin 'pg_ctl.exe') -D $pgData status | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Start-Process -FilePath (Join-Path $pgBin 'postgres.exe') -ArgumentList @('-D', ('"' + $pgData + '"'), '-p', '55439', '-h', '127.0.0.1') -WindowStyle Hidden
    $startedHere = $true
  }
  $ready = $false
  for ($attempt = 0; $attempt -lt 50; $attempt++) {
    & (Join-Path $pgBin 'pg_ctl.exe') -D $pgData status | Out-Null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Milliseconds 100
  }
  if (-not $ready) { throw 'Workspace-local fixture server did not become ready.' }
  Write-Host "P06.1 local migration/RLS tests; new retained database: $database. Auth/Storage stubs, not cloud acceptance."
  & node (Join-Path $PSScriptRoot 'run_delivery_read_fixture.mjs') $database
  $testExitCode = $LASTEXITCODE
} finally {
  if ($startedHere) {
    & (Join-Path $pgBin 'pg_ctl.exe') -D $pgData stop -m fast
    if ($LASTEXITCODE -ne 0) { throw 'Unable to stop local server started by this test.' }
  }
}
exit $testExitCode
