Set-StrictMode -Version Latest

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Format-Bytes {
    param(
        [Parameter(Mandatory)]
        [Int64]$Bytes
    )

    if ($Bytes -lt 1KB) { return "$Bytes B" }
    if ($Bytes -lt 1MB) { return ('{0:N2} KB' -f ($Bytes / 1KB)) }
    if ($Bytes -lt 1GB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    return ('{0:N2} GB' -f ($Bytes / 1GB))
}

function Get-SafeCleanupTargets {
    $targets = New-Object System.Collections.Generic.List[object]
    $currentTemp = [System.IO.Path]::GetTempPath()
    $localAppData = $env:LOCALAPPDATA
    $windowsDir = $env:WINDIR

    $targets.Add([pscustomobject]@{
            Name = 'Temporary files pengguna'
            Kind = 'DirectoryContents'
            Path = $currentTemp
            RequiresAdmin = $false
        })

    if ($localAppData) {
        $targets.Add([pscustomobject]@{
                Name = 'Cache thumbnail Windows'
                Kind = 'FilePattern'
                Path = (Join-Path $localAppData 'Microsoft\Windows\Explorer')
                Filter = 'thumbcache_*.db'
                RequiresAdmin = $false
            })

        $targets.Add([pscustomobject]@{
                Name = 'Cache ikon Windows'
                Kind = 'FilePattern'
                Path = (Join-Path $localAppData 'Microsoft\Windows\Explorer')
                Filter = 'iconcache*.db'
                RequiresAdmin = $false
            })

        $targets.Add([pscustomobject]@{
                Name = 'Laporan crash lokal'
                Kind = 'DirectoryContents'
                Path = (Join-Path $localAppData 'CrashDumps')
                RequiresAdmin = $false
            })

        $targets.Add([pscustomobject]@{
                Name = 'File log diagnosis lokal'
                Kind = 'DirectoryContents'
                Path = (Join-Path $localAppData 'Diagnostics')
                RequiresAdmin = $false
            })
    }

    if ($windowsDir) {
        $targets.Add([pscustomobject]@{
                Name = 'Temporary files Windows'
                Kind = 'DirectoryContents'
                Path = (Join-Path $windowsDir 'Temp')
                RequiresAdmin = $true
            })

        $targets.Add([pscustomobject]@{
                Name = 'Sisa Windows Update'
                Kind = 'DirectoryContents'
                Path = (Join-Path $windowsDir 'SoftwareDistribution\Download')
                RequiresAdmin = $true
            })
    }

    $targets.Add([pscustomobject]@{
            Name = 'Recycle Bin'
            Kind = 'RecycleBin'
            Path = '$Recycle.Bin'
            RequiresAdmin = $false
        })

    return $targets
}

function New-CleanupResult {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$Message,

        [Int64]$DeletedBytes = 0,
        [int]$DeletedItems = 0,
        [int]$SkippedItems = 0
    )

    [pscustomobject]@{
        Name = $Name
        Status = $Status
        Message = $Message
        DeletedBytes = $DeletedBytes
        DeletedItems = $DeletedItems
        SkippedItems = $SkippedItems
    }
}

function Remove-DirectoryContentsSafe {
    param(
        [Parameter(Mandatory)]
        [string]$TargetPath,

        [Parameter(Mandatory)]
        [string]$DisplayName
    )

    if (-not (Test-Path -LiteralPath $TargetPath)) {
        return (New-CleanupResult -Name $DisplayName -Status 'Skipped' -Message 'Folder tidak ditemukan.')
    }

    $items = Get-ChildItem -LiteralPath $TargetPath -Force -ErrorAction SilentlyContinue
    if (-not $items) {
        return (New-CleanupResult -Name $DisplayName -Status 'Clean' -Message 'Tidak ada file yang perlu dibersihkan.')
    }

    $deletedBytes = 0L
    $deletedItems = 0
    $skippedItems = 0

    foreach ($item in $items) {
        try {
            if ($item.PSIsContainer) {
                $childFiles = @(Get-ChildItem -LiteralPath $item.FullName -Recurse -Force -File -ErrorAction SilentlyContinue)
                foreach ($childFile in $childFiles) {
                    $deletedBytes += [int64]$childFile.Length
                }

                $childCount = @(Get-ChildItem -LiteralPath $item.FullName -Recurse -Force -ErrorAction SilentlyContinue).Count
                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
                $deletedItems += [Math]::Max(1, $childCount)
            }
            else {
                $deletedBytes += [int64]$item.Length
                Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
                $deletedItems += 1
            }
        }
        catch {
            $skippedItems += 1
        }
    }

    $message = "Terhapus $deletedItems item, dilewati $skippedItems item, ruang bebas $(Format-Bytes -Bytes $deletedBytes)."
    return (New-CleanupResult -Name $DisplayName -Status 'Completed' -Message $message -DeletedBytes $deletedBytes -DeletedItems $deletedItems -SkippedItems $skippedItems)
}

function Remove-FilePatternSafe {
    param(
        [Parameter(Mandatory)]
        [string]$TargetPath,

        [Parameter(Mandatory)]
        [string]$Filter,

        [Parameter(Mandatory)]
        [string]$DisplayName
    )

    if (-not (Test-Path -LiteralPath $TargetPath)) {
        return (New-CleanupResult -Name $DisplayName -Status 'Skipped' -Message 'Folder target tidak ditemukan.')
    }

    $files = @(Get-ChildItem -LiteralPath $TargetPath -Filter $Filter -Force -File -ErrorAction SilentlyContinue)
    if (-not $files) {
        return (New-CleanupResult -Name $DisplayName -Status 'Clean' -Message 'Tidak ada file yang cocok untuk dibersihkan.')
    }

    $deletedBytes = 0L
    $deletedItems = 0
    $skippedItems = 0

    foreach ($file in $files) {
        try {
            $deletedBytes += [int64]$file.Length
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            $deletedItems += 1
        }
        catch {
            $skippedItems += 1
        }
    }

    $message = "Terhapus $deletedItems file, dilewati $skippedItems file, ruang bebas $(Format-Bytes -Bytes $deletedBytes)."
    return (New-CleanupResult -Name $DisplayName -Status 'Completed' -Message $message -DeletedBytes $deletedBytes -DeletedItems $deletedItems -SkippedItems $skippedItems)
}

function Clear-RecycleBinSafe {
    param(
        [Parameter(Mandatory)]
        [string]$DisplayName
    )

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class NativeRecycleBin {
    [DllImport("Shell32.dll", CharSet = CharSet.Unicode)]
    public static extern uint SHEmptyRecycleBin(IntPtr hwnd, string pszRootPath, uint dwFlags);
}
'@ -ErrorAction SilentlyContinue

    $flags = 0x00000001 -bor 0x00000002 -bor 0x00000004

    try {
        $result = [NativeRecycleBin]::SHEmptyRecycleBin([IntPtr]::Zero, $null, [uint32]$flags)
        if ($result -eq 0 -or $result -eq 0x00000008) {
            return (New-CleanupResult -Name $DisplayName -Status 'Completed' -Message 'Recycle Bin berhasil dibersihkan.')
        }

        return (New-CleanupResult -Name $DisplayName -Status 'Skipped' -Message "Recycle Bin tidak dapat dibersihkan. Kode: $result")
    }
    catch {
        return (New-CleanupResult -Name $DisplayName -Status 'Skipped' -Message 'Recycle Bin dilewati karena akses sistem tidak tersedia.')
    }
}

function Invoke-CleanupTarget {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Target,

        [switch]$IsAdministrator
    )

    if ($Target.RequiresAdmin -and -not $IsAdministrator) {
        return (New-CleanupResult -Name $Target.Name -Status 'Skipped' -Message 'Membutuhkan Run as Administrator untuk target ini.')
    }

    switch ($Target.Kind) {
        'DirectoryContents' {
            return Remove-DirectoryContentsSafe -TargetPath $Target.Path -DisplayName $Target.Name
        }
        'FilePattern' {
            return Remove-FilePatternSafe -TargetPath $Target.Path -Filter $Target.Filter -DisplayName $Target.Name
        }
        'RecycleBin' {
            return Clear-RecycleBinSafe -DisplayName $Target.Name
        }
        default {
            return (New-CleanupResult -Name $Target.Name -Status 'Skipped' -Message 'Jenis pembersihan tidak dikenali.')
        }
    }
}

function Invoke-WindowsCleanup {
    param(
        [object[]]$Targets = (Get-SafeCleanupTargets),
        [switch]$IsAdministrator
    )

    $results = foreach ($target in $Targets) {
        Invoke-CleanupTarget -Target $target -IsAdministrator:$IsAdministrator
    }

    $totalBytes = ($results | Measure-Object -Property DeletedBytes -Sum).Sum
    $totalItems = ($results | Measure-Object -Property DeletedItems -Sum).Sum
    $totalSkipped = ($results | Measure-Object -Property SkippedItems -Sum).Sum

    [pscustomobject]@{
        RanAt = Get-Date
        IsAdministrator = [bool]$IsAdministrator
        Targets = $Targets
        Results = $results
        Summary = [pscustomobject]@{
            DeletedBytes = [int64]($totalBytes | ForEach-Object { if ($_ -eq $null) { 0 } else { $_ } })
            DeletedItems = [int]($totalItems | ForEach-Object { if ($_ -eq $null) { 0 } else { $_ } })
            SkippedItems = [int]($totalSkipped | ForEach-Object { if ($_ -eq $null) { 0 } else { $_ } })
        }
    }
}
