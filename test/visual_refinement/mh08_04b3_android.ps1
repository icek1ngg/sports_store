param(
    [string]$Device = 'emulator-5554',
    [string]$AdbPath = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Android/Sdk/platform-tools/adb.exe'),
    [string]$OutputRoot = 'docs/features/mh08/artifacts/visual_04b3'
)

$script:Mh08Device = $Device
$script:Mh08AdbPath = [IO.Path]::GetFullPath($AdbPath)
$script:Mh08ProjectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$script:Mh08ArtifactsRoot = [IO.Path]::GetFullPath((Join-Path $script:Mh08ProjectRoot 'docs/features/mh08/artifacts'))
$script:Mh08RemoteXml = '/sdcard/mh08_04b3.xml'
$script:Mh08RemotePng = '/sdcard/mh08_04b3.png'

function Resolve-Mh08OutputRoot {
    param([Parameter(Mandatory)][string]$Path)
    $candidate = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $script:Mh08ProjectRoot $Path }
    $full = [IO.Path]::GetFullPath($candidate).TrimEnd('\')
    $base = [IO.Path]::GetFullPath($script:Mh08ArtifactsRoot).TrimEnd('\')
    if ($full -eq $base -or -not $full.StartsWith("$base\", [StringComparison]::OrdinalIgnoreCase)) {
        throw "MH08 evidence output must remain below $base"
    }
    $segments = $full.Substring($base.Length).TrimStart('\') -split '\\'
    if ($segments | Where-Object { $_ -in @('visual_04a', 'visual_04b2') }) {
        throw 'MH08-04B3 cannot write visual_04a or visual_04b2 artifacts'
    }
    return $full
}

function Ensure-Mh08OutputRoot {
    if (-not (Test-Path -LiteralPath $script:Mh08OutputRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $script:Mh08OutputRoot -Force | Out-Null
    }
}

function Invoke-Mh08RuntimeAdb {
    param([Parameter(Mandatory)][string[]]$Arguments)
    if (-not (Test-Path -LiteralPath $script:Mh08AdbPath -PathType Leaf)) {
        throw "ADB executable not found: $script:Mh08AdbPath"
    }
    $output = & $script:Mh08AdbPath -s $script:Mh08Device @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "ADB failed ($LASTEXITCODE): $($output -join [Environment]::NewLine)"
    }
    return $output
}

function Get-Mh08RuntimeUi {
    param([string]$XmlPath, [switch]$AsXml)
    $null = Invoke-Mh08RuntimeAdb -Arguments @('shell', 'uiautomator', 'dump', $script:Mh08RemoteXml)
    $raw = @(Invoke-Mh08RuntimeAdb -Arguments @('shell', 'cat', $script:Mh08RemoteXml))
    try { [xml]$tree = ($raw -join [Environment]::NewLine) } catch { throw 'Current Android UI XML is invalid' }
    if ($XmlPath) {
        $target = [IO.Path]::GetFullPath($XmlPath)
        if (-not $target.StartsWith("$script:Mh08OutputRoot\", [StringComparison]::OrdinalIgnoreCase)) { throw 'UI XML must stay in the 04B3 output directory' }
        if (Test-Path -LiteralPath $target) { throw "Evidence already exists: $target" }
        $tree.Save($target)
    }
    if ($AsXml) { return $tree }
    return @($tree.SelectNodes('//node'))
}

function Get-Mh08NodeCenter {
    param([Parameter(Mandatory)]$Node)
    $bounds = [regex]::Matches([string]$Node.bounds, '\d+') | ForEach-Object { [int]$_.Value }
    if ($bounds.Count -lt 4) { throw "UI node has no usable bounds: $($Node.bounds)" }
    return @{ X = [int](($bounds[0] + $bounds[2]) / 2); Y = [int](($bounds[1] + $bounds[3]) / 2) }
}

function Get-Mh08RuntimeEditField {
    for ($attempt = 0; $attempt -lt 4; $attempt++) {
        $node = Get-Mh08RuntimeUi | Where-Object { $_.class -eq 'android.widget.EditText' } | Select-Object -First 1
        if ($node) { return $node }
    }
    throw 'No editable field appeared in the current Android UI'
}

function Tap-Mh08Runtime {
    param(
        [string]$Text,
        [string]$ContentDescription,
        [string]$ExactLabel,
        [scriptblock]$Predicate
    )
    if (-not $ExactLabel -and -not $Text -and -not $ContentDescription) { throw 'Tap needs -ExactLabel, -Text, or -ContentDescription' }
    $node = @(Get-Mh08RuntimeUi | Where-Object {
        if ($ExactLabel) { $labelMatch = ($_.text -eq $ExactLabel -or $_.'content-desc' -eq $ExactLabel) }
        else { $labelMatch = ((-not $Text -or $_.text -eq $Text) -and (-not $ContentDescription -or $_.'content-desc' -eq $ContentDescription)) }
        $predicateMatch = $true
        if ($Predicate) { $predicateMatch = & $Predicate $_ }
        $labelMatch -and $predicateMatch
    } | Select-Object -First 1)
    if (-not $node) { throw "No current Android UI node matched the requested label" }
    $center = Get-Mh08NodeCenter -Node $node
    $null = Invoke-Mh08RuntimeAdb -Arguments @('shell', 'input', 'tap', $center.X, $center.Y)
    return $node
}

function Show-Mh08RuntimeLabels {
    param([Parameter(Mandatory)][string]$Pattern)
    try { $regex = [regex]::new($Pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase) } catch { throw "Invalid label regex: $Pattern" }
    Get-Mh08RuntimeUi | Where-Object { $regex.IsMatch([string]$_.text) -or $regex.IsMatch([string]$_.'content-desc') } |
        ForEach-Object { '{0} | {1} | {2}' -f $_.text, $_.'content-desc', $_.bounds }
}

function Send-Mh08RuntimeText {
    param([Parameter(Mandatory)][string]$Text)
    if ($Text -notmatch '^[A-Za-z0-9 _.,:/@+\-]+$') { throw 'Input text must use the supported safe ASCII character set' }
    $encoded = $Text.Replace(' ', '%s')
    $null = Invoke-Mh08RuntimeAdb -Arguments @('shell', 'input', 'text', $encoded)
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $field = Get-Mh08RuntimeEditField
        if ([string]$field.text -and ([string]$field.text).Contains($Text)) { return }
    }
    throw 'Android text input did not reach the requested value'
}

function Swipe-Mh08Runtime {
    param([int]$X1, [int]$Y1, [int]$X2, [int]$Y2, [int]$DurationMs = 300)
    if ($DurationMs -lt 1) { throw 'Swipe duration must be positive' }
    $null = Invoke-Mh08RuntimeAdb -Arguments @('shell', 'input', 'swipe', $X1, $Y1, $X2, $Y2, $DurationMs)
}

function Back-Mh08Runtime {
    $null = Invoke-Mh08RuntimeAdb -Arguments @('shell', 'input', 'keyevent', 'KEYCODE_BACK')
}

function Save-Mh08RuntimeScreenshot {
    param([Parameter(Mandatory)][string]$Name)
    if ($Name -notmatch '^[A-Za-z0-9._-]+$' -or [IO.Path]::GetExtension($Name)) { throw 'Screenshot name must be a simple stem without an extension' }
    Ensure-Mh08OutputRoot
    $png = Join-Path $script:Mh08OutputRoot "$Name.png"
    $xml = Join-Path $script:Mh08OutputRoot "$Name.xml"
    if ((Test-Path -LiteralPath $png) -or (Test-Path -LiteralPath $xml)) { throw "Evidence already exists: $Name" }
    $tree = Get-Mh08RuntimeUi -AsXml
    $tree.Save($xml)
    $null = Invoke-Mh08RuntimeAdb -Arguments @('shell', 'screencap', '-p', $script:Mh08RemotePng)
    $null = Invoke-Mh08RuntimeAdb -Arguments @('pull', $script:Mh08RemotePng, $png)
    [pscustomobject]@{ Screenshot = $png; UiXml = $xml }
}

$script:Mh08OutputRoot = Resolve-Mh08OutputRoot -Path $OutputRoot
