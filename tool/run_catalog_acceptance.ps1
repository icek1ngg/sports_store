param([string]$DeviceId = 'emulator-5554')

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $projectRoot 'config/supabase.json'
$credentialPath = Join-Path $projectRoot 'config/catalog_acceptance.local.json'
if (-not (Test-Path -LiteralPath $credentialPath)) {
    throw 'Chưa nhập tài khoản thử. Chạy .\tool\set_catalog_acceptance_credentials.ps1 trước.'
}
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$credentials = Get-Content -LiteralPath $credentialPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($credentials.version -ne 1 -or $credentials.supabase_url -ne $config.SUPABASE_URL) {
    throw 'Tệp tài khoản thử không khớp cấu hình project hiện tại.'
}
if (-not $credentials.primary -or -not $credentials.secondary -or
    [string]::Equals($credentials.primary.email, $credentials.secondary.email, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Nghiệm thu đầy đủ cần hai tài khoản khách hàng khác nhau.'
}
function Read-ProtectedPassword([object]$account) {
    if (-not $account.email -or -not $account.protected_password) {
        throw 'Thiếu thông tin tài khoản thử.'
    }
    try {
        $securePassword = ConvertTo-SecureString $account.protected_password
        return [System.Net.NetworkCredential]::new('', $securePassword).Password
    } catch {
        throw 'Không giải mã được mật khẩu. Hãy nhập lại bằng tài khoản Windows hiện tại.'
    }
}

$runtime = [ordered]@{
    CATALOG_TEST_EMAIL = $credentials.primary.email
    CATALOG_TEST_PASSWORD = Read-ProtectedPassword $credentials.primary
    CATALOG_TEST_SECONDARY_EMAIL = $credentials.secondary.email
    CATALOG_TEST_SECONDARY_PASSWORD = Read-ProtectedPassword $credentials.secondary
}
$previousEnvironment = @{}
$testExitCode = 1
Push-Location $projectRoot
try {
    # Credentials are runtime-only inputs for the host driver. They are never
    # compiler defines, source constants, command-line arguments or JSON files.
    foreach ($name in $runtime.Keys) {
        $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, $runtime[$name], 'Process')
    }
    Write-Host 'Đang nghiệm thu MH04 → MH05 → MH06 với Supabase thật trên thiết bị đã chọn.'
    & flutter drive --target=integration_test/catalog_cart_live_test.dart --driver=test_driver/catalog_live_driver.dart -d $DeviceId "--dart-define-from-file=$configPath"
    $testExitCode = $LASTEXITCODE
} finally {
    foreach ($name in $previousEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
    }
    Pop-Location
}
exit $testExitCode
