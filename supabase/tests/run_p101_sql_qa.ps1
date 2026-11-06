# P10.1 isolated PG17 production-function QA; never targets Supabase cloud.
param([switch]$DemoCatalog)
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$pgBin = Join-Path $workspace 'supabase/.temp/p011_pg_runtime/node_modules/@embedded-postgres/windows-x64/native/bin'
$pgData = Join-Path $workspace 'supabase/.temp/p011_native_data'
if (-not (Test-Path -LiteralPath (Join-Path $pgBin 'postgres.exe')) -or
    -not (Test-Path -LiteralPath (Join-Path $pgData 'PG_VERSION'))) {
  throw 'Workspace-local PG17 runtime/data unavailable. No cloud credentials or automatic download fallback.'
}
$startedHere = $false
$testExitCode = 1
$suffix = (Get-Date -Format 'yyyyMMddHHmmss') + '_' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
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
  # Existing redelivery SQL fixture requires this prefix; it remains entirely
  # inside BEGIN/ROLLBACK, unlike its separate diagnostic concurrency runner.
  Write-Host "P10.1 isolated database: p011_p083_p101_$suffix (new only; retained, never reset/drop)."
  $qaFlags = @('--p101')
  if ($DemoCatalog) { $qaFlags += '--p103-demo' }
  & node (Join-Path $PSScriptRoot 'run_delivery_read_fixture.mjs') ('p011_p083_p101_' + $suffix) @qaFlags
  $testExitCode = $LASTEXITCODE
} finally {
  if ($startedHere) {
    & (Join-Path $pgBin 'pg_ctl.exe') -D $pgData stop -m fast
    if ($LASTEXITCODE -ne 0) { throw 'Unable to stop the fixture server started by this wrapper.' }
  }
}
exit $testExitCode
