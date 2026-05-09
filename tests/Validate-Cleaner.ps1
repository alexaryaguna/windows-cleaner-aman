Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root 'src\WindowsCleaner.ps1'
$corePath = Join-Path $root 'src\CleanerCore.ps1'
$cmdLauncherPath = Join-Path $root 'Run Cleaner.cmd'
$vbsLauncherPath = Join-Path $root 'Run Cleaner.vbs'
$artifactsPath = Join-Path $PSScriptRoot 'artifacts'

function Wait-ForArtifact {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [int]$TimeoutSeconds = 25
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $Path) {
            return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        }
        Start-Sleep -Milliseconds 250
    }

    throw "Artifact was not created in time: $Path"
}

$parseErrors = $null
$coreParseErrors = $null

Write-Host 'Running parser validation...'
$null = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw ('Parser validation failed: ' + (($parseErrors | ForEach-Object { $_.Message }) -join '; '))
}

$null = [System.Management.Automation.Language.Parser]::ParseFile($corePath, [ref]$null, [ref]$coreParseErrors)
if ($coreParseErrors.Count -gt 0) {
    throw ('Core parser validation failed: ' + (($coreParseErrors | ForEach-Object { $_.Message }) -join '; '))
}

Write-Host 'Checking launcher definitions...'
$cmdLauncherContent = Get-Content -LiteralPath $cmdLauncherPath -Raw
$vbsLauncherContent = Get-Content -LiteralPath $vbsLauncherPath -Raw
if ($cmdLauncherContent -notmatch 'Run Cleaner\.vbs') {
    throw 'CMD launcher no longer routes through the hidden VBS launcher.'
}

if ($vbsLauncherContent -notmatch 'shell\.Run command, 0, False') {
    throw 'VBS launcher is not configured to run hidden.'
}

Write-Host 'Inspecting configuration contract...'
$configJson = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -InspectConfig
if ($LASTEXITCODE -ne 0) {
    throw 'InspectConfig returned a non-zero exit code.'
}

$config = $configJson | ConvertFrom-Json
if ($config.TimerMinutes -ne 30) {
    throw "Expected default timer to be 30 minutes, got $($config.TimerMinutes)."
}

if ($config.TimerIntervalMilliseconds -ne 1800000) {
    throw "Expected timer interval 1800000 ms, got $($config.TimerIntervalMilliseconds)."
}

if (-not $config.RequiresAdministratorForGuiLaunch) {
    throw 'GUI launch is expected to require administrator elevation.'
}

if (-not $config.SupportsTrayMinimizeAndClose) {
    throw 'Tray minimize/close support is expected to be enabled.'
}

foreach ($requiredTarget in @('Temporary files Windows', 'File Prefetch Windows', 'Sisa Windows Update', 'Cache Delivery Optimization', 'Recycle Bin')) {
    if ($config.TargetNames -notcontains $requiredTarget) {
        throw "Required cleanup target missing: $requiredTarget"
    }
}

$scriptContent = Get-Content -LiteralPath $scriptPath -Raw
if ($scriptContent -notmatch '-Verb RunAs') {
    throw 'Administrator auto-elevation code is missing.'
}

Write-Host 'Running built-in self-test...'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -SelfTest
if ($LASTEXITCODE -ne 0) {
    throw 'Self-test process returned a non-zero exit code.'
}

Write-Host 'Running hidden VBS launcher self-test...'
$vbsMarkerPath = Join-Path $artifactsPath 'vbs-selftest.json'
if (Test-Path -LiteralPath $vbsMarkerPath) {
    Remove-Item -LiteralPath $vbsMarkerPath -Force
}
& wscript.exe $vbsLauncherPath -SelfTest -WriteRuntimeMarkerPath $vbsMarkerPath
$vbsMarker = Wait-ForArtifact -Path $vbsMarkerPath
if (-not $vbsMarker.Success -or $vbsMarker.Mode -ne 'SelfTest') {
    throw 'Hidden VBS launcher self-test did not complete successfully.'
}

Write-Host 'Running CMD wrapper launcher self-test...'
$cmdMarkerPath = Join-Path $artifactsPath 'cmd-selftest.json'
if (Test-Path -LiteralPath $cmdMarkerPath) {
    Remove-Item -LiteralPath $cmdMarkerPath -Force
}
& cmd.exe /c ('"' + $cmdLauncherPath + '" -SelfTest -WriteRuntimeMarkerPath "' + $cmdMarkerPath + '"')
$cmdMarker = Wait-ForArtifact -Path $cmdMarkerPath
if (-not $cmdMarker.Success -or $cmdMarker.Mode -ne 'SelfTest') {
    throw 'CMD wrapper self-test did not complete successfully.'
}

Write-Host 'Running tray behavior smoke test...'
$uiSmokeJson = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -SmokeTestUi -AllowNoAdminGui
if ($LASTEXITCODE -ne 0) {
    throw 'UI smoke test returned a non-zero exit code.'
}

$uiSmoke = $uiSmokeJson | ConvertFrom-Json
if (-not $uiSmoke.InitialShownState.FormVisible -or -not $uiSmoke.InitialShownState.ShowInTaskbar -or $uiSmoke.InitialShownState.WindowState -ne 'Normal') {
    throw 'Initial GUI launch did not show the main window first.'
}

if (-not $uiSmoke.MinimizeToTrayState.NotifyVisible -or $uiSmoke.MinimizeToTrayState.ShowInTaskbar -or $uiSmoke.MinimizeToTrayState.WaitedMilliseconds -lt 5000) {
    throw 'Minimize-to-tray behavior did not produce the expected tray state.'
}

if (-not $uiSmoke.TrayDoubleClickRestoreState.FormVisible -or -not $uiSmoke.TrayDoubleClickRestoreState.ShowInTaskbar -or $uiSmoke.TrayDoubleClickRestoreState.WindowState -ne 'Normal') {
    throw 'Tray double-click restore behavior did not restore the form correctly.'
}

if (-not $uiSmoke.CloseInterceptState.Cancelled -or -not $uiSmoke.CloseInterceptState.NotifyVisible) {
    throw 'Close-to-tray behavior did not intercept the close request correctly.'
}

if (-not $uiSmoke.CloseToTrayStableState.NotifyVisible -or $uiSmoke.CloseToTrayStableState.ShowInTaskbar -or $uiSmoke.CloseToTrayStableState.WaitedMilliseconds -lt 5000) {
    throw 'Tray process did not remain alive long enough after close-to-tray.'
}

Write-Host 'Running hidden VBS tray lifecycle smoke test...'
$vbsUiMarkerPath = Join-Path $artifactsPath 'vbs-ui-smoke.json'
if (Test-Path -LiteralPath $vbsUiMarkerPath) {
    Remove-Item -LiteralPath $vbsUiMarkerPath -Force
}

& wscript.exe $vbsLauncherPath -SmokeTestUi -AllowNoAdminGui -WriteRuntimeMarkerPath $vbsUiMarkerPath
$vbsUiMarker = Wait-ForArtifact -Path $vbsUiMarkerPath -TimeoutSeconds 40
if (-not $vbsUiMarker.Success -or $vbsUiMarker.Mode -ne 'SmokeTestUi') {
    throw 'Hidden VBS tray smoke test did not complete successfully.'
}

$vbsUi = $vbsUiMarker.Result
if (-not $vbsUi.InitialShownState.FormVisible -or -not $vbsUi.InitialShownState.ShowInTaskbar) {
    throw 'Hidden VBS launcher did not show the main window first.'
}

if (-not $vbsUi.TrayDoubleClickRestoreState.FormVisible -or -not $vbsUi.TrayDoubleClickRestoreState.ShowInTaskbar) {
    throw 'Hidden VBS launcher did not restore the window from tray double-click behavior.'
}

if (-not $vbsUi.CloseToTrayStableState.NotifyVisible -or $vbsUi.CloseToTrayStableState.WaitedMilliseconds -lt 5000) {
    throw 'Hidden VBS launcher did not keep the tray process alive after close-to-tray.'
}

Write-Host 'Validation finished successfully.'
