param(
    [switch]$PreflightOnly,
    [switch]$VerifyOnly
)

# Administrative upload only. Authenticate with `npx --yes supabase@3.0.0 login`.
# No credentials are read into this script, logged, or written into app code.
$ErrorActionPreference = 'Stop'
if ($PreflightOnly -and $VerifyOnly) { throw 'Choose one mode.' }
$projectRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$imageRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'assets/images'))
$manifestPath = Join-Path $projectRoot 'supabase/seeds/stride_color_images_20261109.json'
$manifest = @(Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json)
if ($manifest.Count -ne 52) { throw 'Expected the 52-color upload manifest.' }
$projectRef = 'bqoyfytmrtvjwrpshuhh'
$bucket = 'product-images'
$prefix = 'demo/stride-colors-20261109/'
$paths = [Collections.Generic.HashSet[string]]::new()
$plan = @(
    foreach ($item in $manifest) {
        $objectPath = [string]$item.image_path
        $fileName = [IO.Path]::GetFileName($objectPath)
        if ($item.bucket -ne $bucket -or
            $objectPath -ne ($prefix + $fileName) -or
            $fileName -notmatch '^stride_color_20261109_(S0[1-5]|A0[1-8])_C[1-4]\.(png|jpg|webp)$' -or
            -not $paths.Add($objectPath)) {
            throw 'Invalid or duplicate storage target in the color manifest.'
        }
        if ($item.local_source -ne ('assets/images/' + $fileName)) {
            throw 'Local source must match the exact color image filename.'
        }
        $sourcePath = [IO.Path]::GetFullPath((Join-Path $projectRoot $item.local_source))
        if (-not $sourcePath.StartsWith($imageRoot + [IO.Path]::DirectorySeparatorChar,
                [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Image source escapes the project images directory.'
        }
        $file = Get-Item -LiteralPath $sourcePath
        if ($file.Length -le 0 -or $file.Length -gt 6MB) {
            throw "Unsupported upload size: $fileName"
        }
        $mime = switch ([IO.Path]::GetExtension($fileName)) {
            '.png' { 'image/png' }
            '.jpg' { 'image/jpeg' }
            '.webp' { 'image/webp' }
        }
        [pscustomobject]@{
            source = $sourcePath
            object = $objectPath
            name = $fileName
            mime = $mime
            bytes = $file.Length
            sha256 = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
        }
    }
)
Write-Host "Validated $($plan.Count) images for the private product-images bucket."
if ($PreflightOnly) { exit 0 }

$runName = (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$runRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot "build/stride_color_storage/$runName"))
if (-not $runRoot.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) { throw 'Run directory escapes the workspace.' }
$verifiedRoot = Join-Path $runRoot 'verified'
New-Item -ItemType Directory -Path $verifiedRoot -Force | Out-Null

Push-Location $projectRoot
try {
    & npx --yes supabase@3.0.0 storage ls "ss:///$bucket/$prefix" "--remote=$projectRef" `
        --experimental --output json *> (Join-Path $runRoot 'preflight.log')
    if ($LASTEXITCODE -ne 0) {
        throw "Storage access unavailable. Complete Supabase CLI login first. See $runRoot/preflight.log"
    }
    $index = 0
    foreach ($image in $plan) {
        $index++
        $remotePath = "ss:///$bucket/$($image.object)"
        if (-not $VerifyOnly) {
            & npx --yes supabase@3.0.0 storage cp $image.source $remotePath `
                "--remote=$projectRef" --experimental --content-type $image.mime `
                --cache-control 'max-age=31536000' --yes *> (Join-Path $runRoot "$($image.name).upload.log")
            if ($LASTEXITCODE -ne 0) { throw "Upload failed for $($image.name). Inspect $runRoot" }
        }
        $downloadPath = Join-Path $verifiedRoot $image.name
        & npx --yes supabase@3.0.0 storage cp $remotePath $downloadPath `
            "--remote=$projectRef" --experimental --yes *> (Join-Path $runRoot "$($image.name).verify.log")
        if ($LASTEXITCODE -ne 0 -or
            (Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash -ne $image.sha256) {
            throw "Storage round-trip verification failed for $($image.name)."
        }
        Write-Host "[$index/52] Uploaded/verified $($image.name)"
    }
    $receipt = [ordered]@{
        project = $projectRef
        bucket = $bucket
        prefix = $prefix
        verified_count = $plan.Count
        verified_utc = [DateTime]::UtcNow.ToString('o')
        images = @($plan | Select-Object object, bytes, sha256)
    }
    $receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runRoot 'receipt.json') -Encoding UTF8
    Write-Host "All 52 private images verified. Receipt: $runRoot/receipt.json"
} finally {
    Pop-Location
}
