$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $projectRoot 'config/supabase.json'
$credentialPath = Join-Path $projectRoot 'config/catalog_acceptance.local.json'
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json

function Read-TestAccount([string]$label) {
    $email = (Read-Host "Địa chỉ thư điện tử của tài khoản $label").Trim()
    if ($email -notmatch '^[^\s@]+@[^\s@]+\.[^\s@]+$') {
        throw 'Địa chỉ thư điện tử không hợp lệ.'
    }
    $password = Read-Host "Mật khẩu của tài khoản $label (không hiển thị)" -AsSecureString
    if ($password.Length -eq 0) { throw 'Mật khẩu không được để trống.' }
    return [ordered]@{
        email = $email
        protected_password = ConvertFrom-SecureString -SecureString $password
    }
}

$primary = Read-TestAccount 'khách hàng chính'
$secondary = Read-TestAccount 'khách hàng thứ hai'
if ([string]::Equals($primary.email, $secondary.email, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Hai tài khoản kiểm tra quyền phải khác nhau.'
}
$record = [ordered]@{
    version = 1
    supabase_url = $config.SUPABASE_URL
    primary = $primary
    secondary = $secondary
}
$record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $credentialPath -Encoding UTF8
Write-Host 'Đã lưu thông tin thử dưới dạng mã hóa gắn với tài khoản Windows hiện tại.'
Write-Host 'Chưa tạo tài khoản trên Supabase và chưa xác nhận đăng nhập; bước nghiệm thu sẽ kiểm tra.'
Write-Host 'Chạy tiếp: .\tool\run_catalog_acceptance.ps1'
