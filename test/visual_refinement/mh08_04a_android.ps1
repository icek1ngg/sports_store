# Android runtime audit helpers; every tap resolves the current UI hierarchy.
$mh08Adb = 'C:/Users/ACER/AppData/Local/Android/Sdk/platform-tools/adb.exe'
$mh08Device = 'emulator-5554'
$mh08Output = 'docs/features/mh08/artifacts/visual_04a'

function Get-Mh08Ui {
    & $mh08Adb -s $mh08Device shell uiautomator dump /sdcard/mh08_04a.xml | Out-Null
    [xml]$tree = (& $mh08Adb -s $mh08Device shell cat /sdcard/mh08_04a.xml)
    return $tree.SelectNodes('//node')
}

function Invoke-Mh08Tap([string]$label) {
    $node = Get-Mh08Ui | Where-Object {
        $_.'content-desc' -eq $label -or $_.text -eq $label
    } | Select-Object -First 1
    if (-not $node) { throw "No Android UI node: $label" }
    $bounds = [regex]::Matches($node.bounds, '\d+') | ForEach-Object { [int]$_.Value }
    $x = [int](($bounds[0] + $bounds[2]) / 2)
    $y = [int]($bounds[1] + ($bounds[3] - $bounds[1]) * .8)
    & $mh08Adb -s $mh08Device shell input tap $x $y
}

function Save-Mh08Android([string]$name) {
    & $mh08Adb -s $mh08Device shell screencap -p /sdcard/mh08_04a.png
    & $mh08Adb -s $mh08Device pull /sdcard/mh08_04a.png "$mh08Output/$name.png" | Out-Null
}

function Show-Mh08Labels([string]$pattern) {
    Get-Mh08Ui | Where-Object { $_.'content-desc' -match $pattern -or $_.text -match $pattern } |
        ForEach-Object { '{0}{1} {2}' -f $_.text, ($_.'content-desc' -split "`n")[0], $_.bounds }
}
