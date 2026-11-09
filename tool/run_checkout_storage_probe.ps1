param(
    [string]$SdkRoot = $env:ANDROID_HOME,
    [ValidateRange(5554, 5584)][int]$Port = 5580
)

# Kiểm tra plugin Android thật với AVD và userdata mới trong build/.
# Không đăng nhập Supabase, không gửi đơn, không xóa dữ liệu AVD của người dùng.
$ErrorActionPreference = 'Stop'
if ($Port % 2 -ne 0) { throw 'Emulator console port must be even.' }
if (-not $SdkRoot) { throw 'Pass -SdkRoot or configure ANDROID_HOME.' }
$projectRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$sdk = (Resolve-Path -LiteralPath $SdkRoot).Path
$adb = Join-Path $sdk 'platform-tools/adb.exe'
$emulator = Join-Path $sdk 'emulator/emulator.exe'
$image = Join-Path $sdk 'system-images/android-33/google_apis/x86_64'
foreach ($required in @($adb, $emulator, (Join-Path $image 'userdata.img'))) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Missing Android tool/image: $required" }
}
$serial = "emulator-$Port"
$devices = (& $adb devices) -join "`n"
if ($devices -match "(?m)^$([regex]::Escape($serial))\s") {
    throw 'The chosen emulator port is already in use. No existing device will be changed.'
}

$runName = (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$probeRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot "build/checkout_storage_probe/$runName"))
if (-not $probeRoot.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Probe path escapes the project workspace.'
}
if (Test-Path -LiteralPath $probeRoot) { throw 'Fresh probe directory unexpectedly exists.' }
$avdHome = Join-Path $probeRoot 'avd'
$avdName = 'CheckoutStorageProbe_' + $runName
$avdDir = Join-Path $avdHome "$avdName.avd"
$emulatorHome = Join-Path $probeRoot 'emulator-home'
New-Item -ItemType Directory -Path $avdDir, $emulatorHome | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
$imagePath = $image.Replace('\', '/') + '/'
$avdPath = $avdDir.Replace('\', '/')
[IO.File]::WriteAllText((Join-Path $avdHome "$avdName.ini"), @"
avd.ini.encoding=UTF-8
path=$avdPath
target=android-33
"@, $utf8)
[IO.File]::WriteAllText((Join-Path $avdDir 'config.ini'), @"
AvdId=$avdName
avd.ini.encoding=UTF-8
avd.ini.displayname=Checkout Storage Probe
abi.type=x86_64
hw.cpu.arch=x86_64
hw.cpu.ncore=2
hw.device.name=pixel_5
hw.ramSize=2048
hw.lcd.width=1080
hw.lcd.height=1920
hw.lcd.density=420
hw.keyboard=yes
hw.gpu.enabled=yes
hw.gpu.mode=swiftshader
hw.sdCard=no
disk.dataPartition.size=2G
fastboot.forceColdBoot=yes
fastboot.forceFastBoot=no
image.sysdir.1=$imagePath
tag.id=google_apis
tag.display=Google APIs
target=android-33
showDeviceFrame=no
"@, $utf8)

$previous = @{}
$variables = @{
    ANDROID_AVD_HOME = $avdHome
    ANDROID_EMULATOR_HOME = $emulatorHome
    ANDROID_SDK_ROOT = $sdk
    ANDROID_HOME = $sdk
}
$process = $null
$testExit = 1
Push-Location $projectRoot
try {
    foreach ($name in $variables.Keys) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, $variables[$name], 'Process')
    }
    $userdata = Join-Path $avdDir 'userdata-qemu.img'
    $arguments = @(
        '-avd', $avdName,
        '-datadir', ('"' + $avdDir + '"'),
        '-data', ('"' + $userdata + '"'),
        '-initdata', ('"' + (Join-Path $image 'userdata.img') + '"'),
        '-sysdir', ('"' + $image + '"'),
        '-no-snapshot-load', '-no-snapshot-save', '-no-snapstorage',
        '-no-window', '-no-audio', '-no-boot-anim', '-gpu', 'swiftshader',
        '-port', $Port
    )
    $process = Start-Process -FilePath $emulator -ArgumentList $arguments -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $probeRoot 'emulator.stdout.log') `
        -RedirectStandardError (Join-Path $probeRoot 'emulator.stderr.log')
    Write-Host "Probe uses fresh userdata and emulator logs under $probeRoot"
    $deadline = (Get-Date).AddMinutes(4)
    $booted = $false
    while ((Get-Date) -lt $deadline) {
        $result = (& $adb -s $serial shell getprop sys.boot_completed 2>&1) -join ''
        if ($result.Trim() -eq '1') { $booted = $true; break }
        Start-Sleep -Seconds 2
    }
    if (-not $booted) { throw 'Fresh emulator did not finish booting. Inspect emulator logs in the probe directory.' }
    $nameResponse = (& $adb -s $serial emu avd name) -join "`n"
    if ($nameResponse -notmatch "(?m)^$([regex]::Escape($avdName))\r?$" ) {
        throw 'Device identity differs from the isolated AVD; refusing to install tests.'
    }
    Write-Host 'Running native checkout storage probe; no cloud login or order submission.'
    & flutter test --no-pub integration_test/checkout_secure_storage_test.dart -d $serial --reporter expanded 2>&1 |
        Tee-Object -FilePath (Join-Path $probeRoot 'checkout-storage-test.log')
    $testExit = $LASTEXITCODE
} finally {
    if ($process) {
        $nameResponse = (& $adb -s $serial emu avd name 2>&1) -join "`n"
        if ($nameResponse -match "(?m)^$([regex]::Escape($avdName))\r?$" ) {
            & $adb -s $serial emu kill | Out-Null
        }
    }
    foreach ($name in $previous.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
    }
    Pop-Location
}
exit $testExit
