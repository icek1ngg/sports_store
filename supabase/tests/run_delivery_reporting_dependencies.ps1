# Workspace-local PG17 tests of real migrations, not a cloud deployment.
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$pgBin = Join-Path $workspace 'supabase/.temp/p011_pg_runtime/node_modules/@embedded-postgres/windows-x64/native/bin'
$pgData = Join-Path $workspace 'supabase/.temp/p011_native_data'
if (-not (Test-Path -LiteralPath (Join-Path $pgBin 'postgres.exe')) -or
    -not (Test-Path -LiteralPath (Join-Path $pgData 'PG_VERSION'))) {
  throw 'Workspace-local PG17 runtime/data unavailable; see docs/demos/p074_delivery_reporting_boundary.md. Do not substitute cloud credentials.'
}
$startedHere = $false
$testExitCode = 1
$database = 'p011_p074_boundary_' + (Get-Date -Format 'yyyyMMddHHmmss') + '_' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
try {
  & (Join-Path $pgBin 'pg_ctl.exe') -D $pgData status | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Start-Process -FilePath (Join-Path $pgBin 'postgres.exe') -ArgumentList @('-D', ('"' + $pgData + '"'), '-p', '55439', '-h', '127.0.0.1') -WindowStyle Hidden
    $startedHere = $true
  }
  $ready = $false
  for ($attempt = 0; $attempt -lt 50; $attempt++) {
    & node (Join-Path $PSScriptRoot 'probe_local_fixture_ready.mjs') | Out-Null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Milliseconds 100
  }
  if (-not $ready) { throw 'Workspace-local test server did not become ready.' }
  Write-Host "P07.4 fail-closed boundary plus regression migrations/RLS on local PG17, Auth/Storage stubs; new database: $database (retained, no reset/drop)."
  & node (Join-Path $PSScriptRoot 'run_delivery_read_fixture.mjs') $database
  $testExitCode = $LASTEXITCODE
} finally {
  if ($startedHere) {
    & (Join-Path $pgBin 'pg_ctl.exe') -D $pgData stop -m fast
    if ($LASTEXITCODE -ne 0) { throw 'Unable to stop test server started by this wrapper.' }
  }
}
exit $testExitCode
