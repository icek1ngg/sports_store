# TEST-ONLY: isolated P05.1 completion contract fixture, never a Supabase deployment.
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$pgBin = Join-Path $workspace 'supabase/.temp/p011_pg_runtime/node_modules/@embedded-postgres/windows-x64/native/bin'
$pgData = Join-Path $workspace 'supabase/.temp/p011_native_data'
if (-not (Test-Path -LiteralPath (Join-Path $pgBin 'postgres.exe')) -or
    -not (Test-Path -LiteralPath (Join-Path $pgData 'PG_VERSION'))) {
  throw 'Local PG17 fixture runtime/data are unavailable. See docs/demos/p051_outbound_completion_fixture.md; do not use cloud credentials.'
}
$startedHere = $false
$demoExitCode = 1
$database = 'p011_p051_fixture_' + (Get-Date -Format 'yyyyMMddHHmmss') + '_' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
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
  if (-not $ready) { throw 'The local fixture server did not become ready.' }
  Write-Host 'P05.1 ISOLATED CONTRACT FIXTURE - simulated custody/events/recipients; NOT live acceptance.'
  Write-Host "New fixture database: $database (retained; no reset/drop)."
  & node (Join-Path $PSScriptRoot 'run_delivery_read_fixture.mjs') $database --p051-fixture
  $demoExitCode = $LASTEXITCODE
} finally {
  if ($startedHere) {
    & (Join-Path $pgBin 'pg_ctl.exe') -D $pgData stop -m fast
    if ($LASTEXITCODE -ne 0) { throw 'Unable to stop the local fixture server started by this demo.' }
  }
}
exit $demoExitCode
