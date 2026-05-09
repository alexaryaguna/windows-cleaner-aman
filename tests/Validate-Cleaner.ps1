Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root 'src\WindowsCleaner.ps1'
$launcherPath = Join-Path $root 'Run Cleaner.cmd'

$parseErrors = $null
$coreParseErrors = $null

Write-Host 'Running parser validation...'
$null = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw ('Parser validation failed: ' + (($parseErrors | ForEach-Object { $_.Message }) -join '; '))
}

$corePath = Join-Path $root 'src\CleanerCore.ps1'
$null = [System.Management.Automation.Language.Parser]::ParseFile($corePath, [ref]$null, [ref]$coreParseErrors)
if ($coreParseErrors.Count -gt 0) {
    throw ('Core parser validation failed: ' + (($coreParseErrors | ForEach-Object { $_.Message }) -join '; '))
}

Write-Host 'Inspecting timer configuration...'
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

Write-Host 'Running built-in self-test...'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -SelfTest
if ($LASTEXITCODE -ne 0) {
    throw 'Self-test process returned a non-zero exit code.'
}

Write-Host 'Running launcher self-test...'
& cmd.exe /c ('"' + $launcherPath + '" -SelfTest')
if ($LASTEXITCODE -ne 0) {
    throw 'Launcher self-test returned a non-zero exit code.'
}

Write-Host 'Validation finished successfully.'
