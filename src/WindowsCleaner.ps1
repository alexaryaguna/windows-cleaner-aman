param(
    [switch]$NoGui,
    [switch]$RunOnce,
    [switch]$SelfTest,
    [switch]$InspectConfig,
    [switch]$SmokeTestUi,
    [switch]$AllowNoAdminGui,
    [string]$WriteRuntimeMarkerPath,
    [int]$TimerMinutes = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'CleanerCore.ps1')

function Save-JsonArtifact {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [object]$Data
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $Data | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-RuntimeMarker {
    param(
        [Parameter(Mandatory)]
        [object]$Data
    )

    if ($WriteRuntimeMarkerPath) {
        Save-JsonArtifact -Path $WriteRuntimeMarkerPath -Data $Data
    }
}

function ConvertTo-ProcessArgumentString {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $escaped = foreach ($argument in $Arguments) {
        '"{0}"' -f ($argument -replace '"', '""')
    }

    return ($escaped -join ' ')
}

function Get-CleanerConfigSnapshot {
    $targets = Get-SafeCleanupTargets
    [pscustomobject]@{
        TimerMinutes = [Math]::Max(1, $TimerMinutes)
        TimerIntervalMilliseconds = ([Math]::Max(1, $TimerMinutes) * 60 * 1000)
        LaunchMode = if ($NoGui -or $RunOnce) { 'Console' } else { 'Gui' }
        RequiresAdministratorForGuiLaunch = $true
        SupportsTrayMinimizeAndClose = $true
        PreferredLauncher = 'Run Cleaner.vbs'
        CmdWrapperUsesHiddenVbs = $true
        CurrentProcessIsAdministrator = (Test-IsAdministrator)
        TargetNames = @($targets | ForEach-Object { $_.Name })
        Targets = $targets
    }
}

function Write-ConsoleSummary {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$CleanupRun
    )

    "Waktu: $($CleanupRun.RanAt)"
    "Admin: $($CleanupRun.IsAdministrator)"
    foreach ($result in $CleanupRun.Results) {
        "[$($result.Status)] $($result.Name) - $($result.Message)"
    }
    "Total item terhapus: $($CleanupRun.Summary.DeletedItems)"
    "Total item dilewati: $($CleanupRun.Summary.SkippedItems)"
    "Total ruang bebas: $(Format-Bytes -Bytes $CleanupRun.Summary.DeletedBytes)"
}

function Invoke-SelfTest {
    $artifactsRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'tests\artifacts'
    $sandboxRoot = Join-Path $artifactsRoot 'sandbox'

    if (Test-Path -LiteralPath $sandboxRoot) {
        Remove-Item -LiteralPath $sandboxRoot -Recurse -Force
    }

    New-Item -ItemType Directory -Path $sandboxRoot -Force | Out-Null
    $tempTarget = Join-Path $sandboxRoot 'TempFiles'
    $patternTarget = Join-Path $sandboxRoot 'Explorer'
    $prefetchTarget = Join-Path $sandboxRoot 'Prefetch'

    New-Item -ItemType Directory -Path $tempTarget -Force | Out-Null
    New-Item -ItemType Directory -Path $patternTarget -Force | Out-Null
    New-Item -ItemType Directory -Path $prefetchTarget -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempTarget 'Nested') -Force | Out-Null

    'dummy temp file' | Set-Content -LiteralPath (Join-Path $tempTarget 'delete-me.tmp') -Encoding UTF8
    'nested temp file' | Set-Content -LiteralPath (Join-Path $tempTarget 'Nested\nested.log') -Encoding UTF8
    'thumb cache' | Set-Content -LiteralPath (Join-Path $patternTarget 'thumbcache_1.db') -Encoding UTF8
    'icon cache' | Set-Content -LiteralPath (Join-Path $patternTarget 'iconcache_1.db') -Encoding UTF8
    'keep me' | Set-Content -LiteralPath (Join-Path $patternTarget 'keep.txt') -Encoding UTF8
    'prefetch cache' | Set-Content -LiteralPath (Join-Path $prefetchTarget 'APP01ABC.pf') -Encoding UTF8
    'prefetch config' | Set-Content -LiteralPath (Join-Path $prefetchTarget 'Layout.ini') -Encoding UTF8

    $targets = @(
        [pscustomobject]@{ Name = 'Sandbox Temp'; Kind = 'DirectoryContents'; Path = $tempTarget; RequiresAdmin = $false },
        [pscustomobject]@{ Name = 'Sandbox Thumb'; Kind = 'FilePattern'; Path = $patternTarget; Filter = 'thumbcache_*.db'; RequiresAdmin = $false },
        [pscustomobject]@{ Name = 'Sandbox Icon'; Kind = 'FilePattern'; Path = $patternTarget; Filter = 'iconcache*.db'; RequiresAdmin = $false },
        [pscustomobject]@{ Name = 'Sandbox Prefetch'; Kind = 'FilePattern'; Path = $prefetchTarget; Filter = '*.pf'; RequiresAdmin = $false }
    )

    $run = Invoke-WindowsCleanup -Targets $targets -IsAdministrator:$false

    if (Test-Path -LiteralPath (Join-Path $tempTarget 'delete-me.tmp')) {
        throw 'Self-test gagal: file temp utama masih ada.'
    }

    if (Test-Path -LiteralPath (Join-Path $tempTarget 'Nested\nested.log')) {
        throw 'Self-test gagal: file nested temp masih ada.'
    }

    if (Test-Path -LiteralPath (Join-Path $patternTarget 'thumbcache_1.db')) {
        throw 'Self-test gagal: file thumbcache masih ada.'
    }

    if (Test-Path -LiteralPath (Join-Path $patternTarget 'iconcache_1.db')) {
        throw 'Self-test gagal: file iconcache masih ada.'
    }

    if (Test-Path -LiteralPath (Join-Path $prefetchTarget 'APP01ABC.pf')) {
        throw 'Self-test gagal: file prefetch masih ada.'
    }

    if (-not (Test-Path -LiteralPath (Join-Path $patternTarget 'keep.txt'))) {
        throw 'Self-test gagal: file yang tidak boleh dihapus ikut terhapus.'
    }

    if (-not (Test-Path -LiteralPath (Join-Path $prefetchTarget 'Layout.ini'))) {
        throw 'Self-test gagal: file sistem non-target ikut terhapus.'
    }

    if ($run.Summary.DeletedItems -lt 5) {
        throw 'Self-test gagal: jumlah item terhapus lebih kecil dari yang diharapkan.'
    }

    Write-RuntimeMarker -Data ([pscustomobject]@{
            Mode = 'SelfTest'
            Success = $true
            DeletedItems = $run.Summary.DeletedItems
            DeletedBytes = $run.Summary.DeletedBytes
        })

    'SELF-TEST OK'
    Write-ConsoleSummary -CleanupRun $run
}

function Start-ConsoleCleanup {
    $run = Invoke-WindowsCleanup -IsAdministrator:(Test-IsAdministrator)
    Write-RuntimeMarker -Data ([pscustomobject]@{
            Mode = 'ConsoleCleanup'
            Success = $true
            DeletedItems = $run.Summary.DeletedItems
            DeletedBytes = $run.Summary.DeletedBytes
        })
    Write-ConsoleSummary -CleanupRun $run
}

if ($SelfTest) {
    Invoke-SelfTest
    exit 0
}

if ($InspectConfig) {
    $config = Get-CleanerConfigSnapshot
    Write-RuntimeMarker -Data ([pscustomobject]@{
            Mode = 'InspectConfig'
            Success = $true
            Config = $config
        })
    $config | ConvertTo-Json -Depth 8
    exit 0
}

if ($NoGui -or $RunOnce) {
    Start-ConsoleCleanup
    exit 0
}

if (-not $AllowNoAdminGui -and -not (Test-IsAdministrator)) {
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-STA',
        '-File',
        $PSCommandPath
    )

    if ($TimerMinutes -ne 30) {
        $arguments += @('-TimerMinutes', $TimerMinutes.ToString())
    }

    if ($WriteRuntimeMarkerPath) {
        $arguments += @('-WriteRuntimeMarkerPath', $WriteRuntimeMarkerPath)
    }

    Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden -ArgumentList (ConvertTo-ProcessArgumentString -Arguments $arguments) | Out-Null
    Write-RuntimeMarker -Data ([pscustomobject]@{
            Mode = 'ElevationRequested'
            Success = $true
            RequestedAdministrator = $true
        })
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:isAdministrator = Test-IsAdministrator
$script:lastCleanupRun = $null
$script:isExitRequested = $false

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Windows Cleaner Aman'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(800, 575)
$form.MinimumSize = New-Object System.Drawing.Size(800, 575)
$form.MaximizeBox = $false
$form.ShowInTaskbar = $true

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = 'Pembersih sampah Windows - aman, admin, dan tetap berjalan di tray'
$titleLabel.Location = New-Object System.Drawing.Point(20, 20)
$titleLabel.Size = New-Object System.Drawing.Size(740, 30)
$titleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)

$descriptionLabel = New-Object System.Windows.Forms.Label
$descriptionLabel.Text = 'Aplikasi ini membersihkan file sementara pengguna, cache Windows, Recycle Bin, Prefetch, Temp Windows, dan target sistem aman lainnya. Saat di-minimize atau ditutup, aplikasi akan tetap berjalan di tray.'
$descriptionLabel.Location = New-Object System.Drawing.Point(20, 60)
$descriptionLabel.Size = New-Object System.Drawing.Size(740, 55)

$modeLabel = New-Object System.Windows.Forms.Label
$modeLabel.Text = 'Mode: Administrator aktif. Semua target sistem aman akan dicoba.'
$modeLabel.Location = New-Object System.Drawing.Point(20, 118)
$modeLabel.Size = New-Object System.Drawing.Size(740, 25)
$modeLabel.ForeColor = [System.Drawing.Color]::DarkGreen

$autoCleanCheckBox = New-Object System.Windows.Forms.CheckBox
$autoCleanCheckBox.Text = 'Aktifkan auto-clean setiap 30 menit selama aplikasi ini tetap berjalan di tray atau sedang terbuka'
$autoCleanCheckBox.Location = New-Object System.Drawing.Point(20, 150)
$autoCleanCheckBox.Size = New-Object System.Drawing.Size(640, 28)
$autoCleanCheckBox.Checked = $true

$runButton = New-Object System.Windows.Forms.Button
$runButton.Text = 'Bersihkan Sekarang'
$runButton.Location = New-Object System.Drawing.Point(20, 190)
$runButton.Size = New-Object System.Drawing.Size(180, 40)

$openTrayHintLabel = New-Object System.Windows.Forms.Label
$openTrayHintLabel.Text = 'Tip: klik ikon tray untuk membuka kembali aplikasi jika jendelanya disembunyikan.'
$openTrayHintLabel.Location = New-Object System.Drawing.Point(220, 198)
$openTrayHintLabel.Size = New-Object System.Drawing.Size(520, 25)

$nextRunLabel = New-Object System.Windows.Forms.Label
$nextRunLabel.Location = New-Object System.Drawing.Point(20, 240)
$nextRunLabel.Size = New-Object System.Drawing.Size(720, 25)

$summaryLabel = New-Object System.Windows.Forms.Label
$summaryLabel.Text = 'Belum ada proses pembersihan yang dijalankan.'
$summaryLabel.Location = New-Object System.Drawing.Point(20, 270)
$summaryLabel.Size = New-Object System.Drawing.Size(740, 25)

$targetsLabel = New-Object System.Windows.Forms.Label
$targetsLabel.Text = 'Target aman yang dibersihkan:'
$targetsLabel.Location = New-Object System.Drawing.Point(20, 305)
$targetsLabel.Size = New-Object System.Drawing.Size(300, 20)

$targetsBox = New-Object System.Windows.Forms.ListBox
$targetsBox.Location = New-Object System.Drawing.Point(20, 330)
$targetsBox.Size = New-Object System.Drawing.Size(320, 180)
foreach ($target in Get-SafeCleanupTargets) {
    $suffix = if ($target.RequiresAdmin) { ' (admin)' } else { '' }
    [void]$targetsBox.Items.Add("$($target.Name)$suffix")
}

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(360, 330)
$logBox.Size = New-Object System.Drawing.Size(400, 180)
$logBox.Multiline = $true
$logBox.ScrollBars = 'Vertical'
$logBox.ReadOnly = $true

$footerLabel = New-Object System.Windows.Forms.Label
$footerLabel.Text = 'Catatan: aplikasi ini tidak menyentuh Documents, Downloads, Desktop, maupun file pribadi Anda.'
$footerLabel.Location = New-Object System.Drawing.Point(20, 520)
$footerLabel.Size = New-Object System.Drawing.Size(740, 24)

$cleanupTimer = New-Object System.Windows.Forms.Timer
$cleanupTimer.Interval = [Math]::Max(1, $TimerMinutes) * 60 * 1000

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Text = 'Windows Cleaner Aman'
$notifyIcon.Icon = [System.Drawing.SystemIcons]::Shield
$notifyIcon.Visible = $false

$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$openMenuItem = $trayMenu.Items.Add('Buka Aplikasi')
$cleanNowMenuItem = $trayMenu.Items.Add('Bersihkan Sekarang')
$exitMenuItem = $trayMenu.Items.Add('Keluar')
$notifyIcon.ContextMenuStrip = $trayMenu

function Update-NextRunLabel {
    if ($cleanupTimer.Enabled) {
        $nextTime = (Get-Date).AddMilliseconds($cleanupTimer.Interval)
        $nextRunLabel.Text = "Pembersihan otomatis aktif. Proses berikutnya diperkirakan pada $($nextTime.ToString('HH:mm:ss'))."
    }
    else {
        $nextRunLabel.Text = 'Pembersihan otomatis sedang nonaktif.'
    }
}

function Append-Log {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($logBox.Text)) {
        $logBox.Text = $Text
    }
    else {
        $logBox.AppendText([Environment]::NewLine + $Text)
    }
}

function Show-TrayBalloon {
    param(
        [string]$Title,
        [string]$Message
    )

    try {
        $notifyIcon.BalloonTipTitle = $Title
        $notifyIcon.BalloonTipText = $Message
        $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        $notifyIcon.ShowBalloonTip(3000)
    }
    catch {
    }
}

function Send-AppToTray {
    param(
        [string]$Reason = 'Aplikasi tetap berjalan di tray.',
        [bool]$ShowBalloon = $true
    )

    $notifyIcon.Visible = $true
    $form.Hide()
    $form.ShowInTaskbar = $false

    if ($ShowBalloon) {
        Show-TrayBalloon -Title 'Windows Cleaner Aman' -Message $Reason
    }
}

function Restore-AppFromTray {
    $notifyIcon.Visible = $true
    $form.ShowInTaskbar = $true
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $form.Show()
    $form.Activate()
}

function Exit-AppCompletely {
    $script:isExitRequested = $true
    $cleanupTimer.Stop()
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    $form.Close()
}

function Handle-ResizeToTray {
    if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
        Send-AppToTray -Reason 'Aplikasi diminimize dan tetap berjalan di tray.' -ShowBalloon $true
    }
}

function Handle-UserCloseRequest {
    param(
        [Parameter(Mandatory)]
        $EventArgs
    )

    if (-not $script:isExitRequested) {
        $EventArgs.Cancel = $true
        Send-AppToTray -Reason 'Jendela ditutup, tetapi aplikasi tetap berjalan di tray.' -ShowBalloon $true
    }
}

function Invoke-AndRenderCleanup {
    $runButton.Enabled = $false
    try {
        $run = Invoke-WindowsCleanup -IsAdministrator:$script:isAdministrator
        $script:lastCleanupRun = $run

        $summaryLabel.Text = "Terakhir dibersihkan: $($run.RanAt.ToString('dd/MM/yyyy HH:mm:ss')) | Item terhapus: $($run.Summary.DeletedItems) | Item dilewati: $($run.Summary.SkippedItems) | Ruang bebas: $(Format-Bytes -Bytes $run.Summary.DeletedBytes)"
        Append-Log "===== $($run.RanAt.ToString('dd/MM/yyyy HH:mm:ss')) ====="
        foreach ($result in $run.Results) {
            Append-Log ("[{0}] {1} - {2}" -f $result.Status, $result.Name, $result.Message)
        }
        Append-Log ' '
    }
    finally {
        $runButton.Enabled = $true
        Update-NextRunLabel
    }
}

$autoCleanCheckBox.Add_CheckedChanged({
        if ($autoCleanCheckBox.Checked) {
            $cleanupTimer.Start()
        }
        else {
            $cleanupTimer.Stop()
        }
        Update-NextRunLabel
    })

$runButton.Add_Click({ Invoke-AndRenderCleanup })
$cleanupTimer.Add_Tick({ Invoke-AndRenderCleanup })
$openMenuItem.add_Click({ Restore-AppFromTray })
$cleanNowMenuItem.add_Click({ Invoke-AndRenderCleanup })
$exitMenuItem.add_Click({ Exit-AppCompletely })
$notifyIcon.Add_DoubleClick({ Restore-AppFromTray })
$form.Add_Resize({ Handle-ResizeToTray })
$form.Add_FormClosing({ param($sender, $eventArgs) Handle-UserCloseRequest -EventArgs $eventArgs })
$form.Add_Shown({
        $notifyIcon.Visible = $true
        if ($autoCleanCheckBox.Checked) {
            $cleanupTimer.Start()
        }
        Update-NextRunLabel
        Write-RuntimeMarker -Data ([pscustomobject]@{
                Mode = 'GuiShown'
                Success = $true
                Administrator = $script:isAdministrator
            })
    })

$form.Controls.AddRange(@(
        $titleLabel,
        $descriptionLabel,
        $modeLabel,
        $autoCleanCheckBox,
        $runButton,
        $openTrayHintLabel,
        $nextRunLabel,
        $summaryLabel,
        $targetsLabel,
        $targetsBox,
        $logBox,
        $footerLabel
    ))

if ($SmokeTestUi) {
    $resizeStateBefore = $form.ShowInTaskbar
    $notifyVisibleBefore = $notifyIcon.Visible

    Send-AppToTray -Reason 'Smoke test minimize.' -ShowBalloon $false
    $minimizeState = [pscustomobject]@{
        NotifyVisible = $notifyIcon.Visible
        ShowInTaskbar = $form.ShowInTaskbar
        FormVisible = $form.Visible
    }

    Restore-AppFromTray
    $restoreState = [pscustomobject]@{
        NotifyVisible = $notifyIcon.Visible
        ShowInTaskbar = $form.ShowInTaskbar
        FormVisible = $form.Visible
        WindowState = $form.WindowState.ToString()
    }

    $closingArgs = New-Object System.Windows.Forms.FormClosingEventArgs([System.Windows.Forms.CloseReason]::UserClosing, $false)
    Handle-UserCloseRequest -EventArgs $closingArgs
    $closeState = [pscustomobject]@{
        Cancelled = $closingArgs.Cancel
        NotifyVisible = $notifyIcon.Visible
        ShowInTaskbar = $form.ShowInTaskbar
        FormVisible = $form.Visible
    }

    $result = [pscustomobject]@{
        InitialState = [pscustomobject]@{
            NotifyVisible = $notifyVisibleBefore
            ShowInTaskbar = $resizeStateBefore
        }
        MinimizeToTrayState = $minimizeState
        RestoreState = $restoreState
        CloseToTrayState = $closeState
    }

    Write-RuntimeMarker -Data ([pscustomobject]@{
            Mode = 'SmokeTestUi'
            Success = $true
            Result = $result
        })
    $result | ConvertTo-Json -Depth 8
    $notifyIcon.Dispose()
    $form.Dispose()
    exit 0
}

[void]$form.ShowDialog()
