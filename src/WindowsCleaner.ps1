param(
    [switch]$NoGui,
    [switch]$RunOnce,
    [switch]$SelfTest,
    [switch]$InspectConfig,
    [int]$TimerMinutes = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'CleanerCore.ps1')

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
    New-Item -ItemType Directory -Path $tempTarget -Force | Out-Null
    New-Item -ItemType Directory -Path $patternTarget -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempTarget 'Nested') -Force | Out-Null

    'dummy temp file' | Set-Content -LiteralPath (Join-Path $tempTarget 'delete-me.tmp') -Encoding UTF8
    'nested temp file' | Set-Content -LiteralPath (Join-Path $tempTarget 'Nested\nested.log') -Encoding UTF8
    'thumb cache' | Set-Content -LiteralPath (Join-Path $patternTarget 'thumbcache_1.db') -Encoding UTF8
    'icon cache' | Set-Content -LiteralPath (Join-Path $patternTarget 'iconcache_1.db') -Encoding UTF8
    'keep me' | Set-Content -LiteralPath (Join-Path $patternTarget 'keep.txt') -Encoding UTF8

    $targets = @(
        [pscustomobject]@{ Name = 'Sandbox Temp'; Kind = 'DirectoryContents'; Path = $tempTarget; RequiresAdmin = $false },
        [pscustomobject]@{ Name = 'Sandbox Thumb'; Kind = 'FilePattern'; Path = $patternTarget; Filter = 'thumbcache_*.db'; RequiresAdmin = $false },
        [pscustomobject]@{ Name = 'Sandbox Icon'; Kind = 'FilePattern'; Path = $patternTarget; Filter = 'iconcache*.db'; RequiresAdmin = $false }
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

    if (-not (Test-Path -LiteralPath (Join-Path $patternTarget 'keep.txt'))) {
        throw 'Self-test gagal: file yang tidak boleh dihapus ikut terhapus.'
    }

    if ($run.Summary.DeletedItems -lt 4) {
        throw 'Self-test gagal: jumlah item terhapus lebih kecil dari yang diharapkan.'
    }

    'SELF-TEST OK'
    Write-ConsoleSummary -CleanupRun $run
}

function Start-ConsoleCleanup {
    $run = Invoke-WindowsCleanup -IsAdministrator:(Test-IsAdministrator)
    Write-ConsoleSummary -CleanupRun $run
}

if ($SelfTest) {
    Invoke-SelfTest
    exit 0
}

if ($InspectConfig) {
    [pscustomobject]@{
        TimerMinutes = $TimerMinutes
        TimerIntervalMilliseconds = ([Math]::Max(1, $TimerMinutes) * 60 * 1000)
        LaunchMode = if ($NoGui -or $RunOnce) { 'Console' } else { 'Gui' }
    } | ConvertTo-Json -Depth 3
    exit 0
}

if ($NoGui -or $RunOnce) {
    Start-ConsoleCleanup
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:isAdministrator = Test-IsAdministrator
$script:lastCleanupRun = $null

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Windows Cleaner Aman'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(760, 540)
$form.MinimumSize = New-Object System.Drawing.Size(760, 540)
$form.MaximizeBox = $false

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = 'Pembersih sampah Windows - aman dan sekali klik'
$titleLabel.Location = New-Object System.Drawing.Point(20, 20)
$titleLabel.Size = New-Object System.Drawing.Size(680, 30)
$titleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)

$descriptionLabel = New-Object System.Windows.Forms.Label
$descriptionLabel.Text = 'Membersihkan file sementara, cache thumbnail/ikon, crash dump lokal, Recycle Bin, dan target sistem yang aman bila dijalankan sebagai Administrator.'
$descriptionLabel.Location = New-Object System.Drawing.Point(20, 60)
$descriptionLabel.Size = New-Object System.Drawing.Size(700, 50)

$modeLabel = New-Object System.Windows.Forms.Label
$modeLabel.Text = if ($script:isAdministrator) { 'Mode: Administrator aktif. Target sistem juga akan dicoba.' } else { 'Mode: Standar. Target yang butuh Administrator akan dilewati dengan aman.' }
$modeLabel.Location = New-Object System.Drawing.Point(20, 112)
$modeLabel.Size = New-Object System.Drawing.Size(700, 25)
$modeLabel.ForeColor = if ($script:isAdministrator) { [System.Drawing.Color]::DarkGreen } else { [System.Drawing.Color]::DarkOrange }

$autoCleanCheckBox = New-Object System.Windows.Forms.CheckBox
$autoCleanCheckBox.Text = 'Aktifkan auto-clean setiap 30 menit selama aplikasi ini tetap terbuka'
$autoCleanCheckBox.Location = New-Object System.Drawing.Point(20, 150)
$autoCleanCheckBox.Size = New-Object System.Drawing.Size(520, 28)
$autoCleanCheckBox.Checked = $true

$runButton = New-Object System.Windows.Forms.Button
$runButton.Text = 'Bersihkan Sekarang'
$runButton.Location = New-Object System.Drawing.Point(20, 190)
$runButton.Size = New-Object System.Drawing.Size(180, 40)

$nextRunLabel = New-Object System.Windows.Forms.Label
$nextRunLabel.Location = New-Object System.Drawing.Point(220, 198)
$nextRunLabel.Size = New-Object System.Drawing.Size(460, 25)

$summaryLabel = New-Object System.Windows.Forms.Label
$summaryLabel.Text = 'Belum ada proses pembersihan yang dijalankan.'
$summaryLabel.Location = New-Object System.Drawing.Point(20, 240)
$summaryLabel.Size = New-Object System.Drawing.Size(700, 25)

$targetsLabel = New-Object System.Windows.Forms.Label
$targetsLabel.Text = 'Target aman yang dibersihkan:'
$targetsLabel.Location = New-Object System.Drawing.Point(20, 275)
$targetsLabel.Size = New-Object System.Drawing.Size(300, 20)

$targetsBox = New-Object System.Windows.Forms.ListBox
$targetsBox.Location = New-Object System.Drawing.Point(20, 300)
$targetsBox.Size = New-Object System.Drawing.Size(300, 160)
foreach ($target in Get-SafeCleanupTargets) {
    $suffix = if ($target.RequiresAdmin) { ' (butuh Admin)' } else { '' }
    [void]$targetsBox.Items.Add("$($target.Name)$suffix")
}

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(340, 300)
$logBox.Size = New-Object System.Drawing.Size(380, 160)
$logBox.Multiline = $true
$logBox.ScrollBars = 'Vertical'
$logBox.ReadOnly = $true

$footerLabel = New-Object System.Windows.Forms.Label
$footerLabel.Text = 'Catatan: aplikasi ini tidak menyentuh Documents, Downloads, Desktop, maupun file pribadi Anda.'
$footerLabel.Location = New-Object System.Drawing.Point(20, 470)
$footerLabel.Size = New-Object System.Drawing.Size(700, 24)

$cleanupTimer = New-Object System.Windows.Forms.Timer
$cleanupTimer.Interval = [Math]::Max(1, $TimerMinutes) * 60 * 1000

function Update-NextRunLabel {
    if ($cleanupTimer.Enabled) {
        $nextTime = (Get-Date).AddMilliseconds($cleanupTimer.Interval)
        $nextRunLabel.Text = "Pembersihan otomatis aktif. Perkiraan proses berikutnya: $($nextTime.ToString('HH:mm:ss'))"
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
$form.Add_Shown({
        if ($autoCleanCheckBox.Checked) {
            $cleanupTimer.Start()
        }
        Update-NextRunLabel
    })

$form.Controls.AddRange(@(
        $titleLabel,
        $descriptionLabel,
        $modeLabel,
        $autoCleanCheckBox,
        $runButton,
        $nextRunLabel,
        $summaryLabel,
        $targetsLabel,
        $targetsBox,
        $logBox,
        $footerLabel
    ))

[void]$form.ShowDialog()
