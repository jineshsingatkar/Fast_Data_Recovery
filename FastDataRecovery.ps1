<#
Fast Data Recovery - Windows CLI Dashboard
Safe-first menu to assist with: listing disks, checking SMART, launching TestDisk/PhotoRec,
and running guarded filesystem checks on Windows.

IMPORTANT SAFETY NOTES
- Do not write to a failing source drive. Recover from a clone or image when possible.
- Use imaging (ddrescue on Linux) before attempting repairs.
- chkdsk /f /r can stress failing drives; only run after you’ve secured data.

Author: Agent Mode (CLI)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Compute script root for file output and tool discovery
if (-not $PSScriptRoot) { $script:ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path } else { $script:ScriptRoot = $PSScriptRoot }

function New-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null }
}

New-Dir (Join-Path $ScriptRoot 'logs')
New-Dir (Join-Path $ScriptRoot 'reports')

function Write-Title([string]$Text) { Write-Host "`n==== $Text ====\n" -ForegroundColor Cyan }
function Write-WarnLine([string]$Text) { Write-Host "WARNING: $Text" -ForegroundColor Yellow }
function Write-ErrLine([string]$Text) { Write-Host "ERROR: $Text" -ForegroundColor Red }
function Pause-Enter { [void](Read-Host 'Press Enter to continue...') }

function Get-ToolPath([string]$ExeName, [string[]]$ExtraCandidates) {
    $cmd = Get-Command $ExeName -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($cand in $ExtraCandidates) { if (Test-Path -LiteralPath $cand) { return (Resolve-Path $cand).Path } }
    # Search within the script directory (recursive)
    $match = Get-ChildItem -Path $ScriptRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq $ExeName } | Select-Object -First 1
    if ($match) { return $match.FullName }
    return $null
}

function Show-Disks {
    Write-Title 'Disks Overview'
    try {
        $disks = Get-Disk | Sort-Object Number
    } catch {
        Write-ErrLine "Failed to query disks: $($_.Exception.Message)"
        return
    }
    $wmiByIndex = @{}
    try {
        foreach ($d in (Get-CimInstance Win32_DiskDrive)) { $wmiByIndex[$d.Index] = $d }
    } catch {}

    $rows = @()
    foreach ($d in $disks) {
        $sizeGB = [math]::Round($d.Size/1GB, 2)
        $physical = "\\.\PhysicalDrive$($d.Number)"
        $model = if ($wmiByIndex.ContainsKey($d.Number)) { $wmiByIndex[$d.Number].Model } else { $d.FriendlyName }
        $vols = (Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue |
                 Get-Volume -ErrorAction SilentlyContinue |
                 Where-Object { $_.DriveLetter } |
                 ForEach-Object { "$($_.DriveLetter):" }) -join ', '
        $rows += [PSCustomObject]@{
            '#'        = $d.Number
            Physical   = $physical
            Bus        = $d.BusType
            'Size(GB)' = $sizeGB
            Style      = $d.PartitionStyle
            Health     = $d.HealthStatus
            Model      = $model
            Volumes    = if ($vols) { $vols } else { '-' }
        }
    }
    if ($rows.Count -eq 0) { Write-WarnLine 'No disks found.'; return }
    $rows | Format-Table -AutoSize
    Write-Host ''
    Write-WarnLine 'Never run repairs on a failing source before imaging (use Linux ddrescue).'
}

function Run-SMART {
    $smartctl = Get-ToolPath 'smartctl.exe' @(
        'C:\\Program Files\\smartmontools\\bin\\smartctl.exe',
        'C:\\Program Files (x86)\\smartmontools\\bin\\smartctl.exe'
    )
    if (-not $smartctl) {
        Write-ErrLine 'smartctl not found.'
        Write-Host 'Install smartmontools:' -ForegroundColor Gray
        Write-Host '  - Chocolatey: choco install smartmontools' -ForegroundColor Gray
        Write-Host '  - Or download: https://www.smartmontools.org/' -ForegroundColor Gray
        return
    }
    Show-Disks
    $num = Read-Host 'Enter disk number for SMART (e.g., 0)'
    if ($num -notmatch '^[0-9]+$') { Write-ErrLine 'Invalid disk number.'; return }
    $dev = "\\.\PhysicalDrive$($num)"
    Write-Title "SMART for $dev"
    try {
        & $smartctl '-a' '-d' 'auto' $dev
        if ($LASTEXITCODE -ne 0) { Write-WarnLine "smartctl exit code: $LASTEXITCODE (non-zero can include warnings)" }
    } catch {
        Write-ErrLine "smartctl failed: $($_.Exception.Message)"
    }
    Pause-Enter
}

function Launch-TestDisk {
    $path = Get-ToolPath 'testdisk_win.exe' @(
        (Join-Path $ScriptRoot 'testdisk_win.exe'),
        (Join-Path $ScriptRoot 'tools\\testdisk_win.exe')
    )
    if (-not $path) {
        Write-ErrLine 'testdisk_win.exe not found.'
        Write-Host 'Download TestDisk & PhotoRec (Windows): https://www.cgsecurity.org/' -ForegroundColor Gray
        Write-Host "Place 'testdisk_win.exe' in this folder and re-run." -ForegroundColor Gray
        return
    }
    Write-Title "Launching TestDisk: $path"
    try { & $path } catch { Write-ErrLine $_.Exception.Message }
    Pause-Enter
}

function Launch-PhotoRec {
    $path = Get-ToolPath 'photorec_win.exe' @(
        (Join-Path $ScriptRoot 'photorec_win.exe'),
        (Join-Path $ScriptRoot 'tools\\photorec_win.exe')
    )
    if (-not $path) {
        Write-ErrLine 'photorec_win.exe not found.'
        Write-Host 'Download TestDisk & PhotoRec (Windows): https://www.cgsecurity.org/' -ForegroundColor Gray
        Write-Host "Place 'photorec_win.exe' in this folder and re-run." -ForegroundColor Gray
        return
    }
    Write-Title "Launching PhotoRec: $path"
    try { & $path } catch { Write-ErrLine $_.Exception.Message }
    Pause-Enter
}

function Volume-Repair-Menu {
    Write-Title 'Volume Check / Repair (use only after backup)'
    $letter = Read-Host 'Enter drive letter to check (e.g., E)'
    if (-not $letter) { return }
    $letter = $letter.TrimEnd(':').ToUpper()
    if ($letter.Length -ne 1 -or ($letter -notmatch '^[A-Z]$')) { Write-ErrLine 'Invalid drive letter.'; return }
    if ($letter -eq 'C') {
        Write-WarnLine 'Selected system drive C:. HIGH RISK. Prefer to work on a cloned image.'
        $ack = Read-Host 'Type I UNDERSTAND to continue'
        if ($ack -ne 'I UNDERSTAND') { Write-Host 'Cancelled.'; return }
    }

    Write-Host 'Choose action:'
    Write-Host '  1) Repair-Volume -Scan (online scan, safe)'
    Write-Host '  2) Repair-Volume -OfflineScanAndFix (may dismount volume)'
    Write-Host '  3) chkdsk /scan (online quick check)'
    Write-Host '  4) chkdsk /f /r (repairs + surface scan; risky & slow)'
    Write-Host '  0) Back'
    $choice = Read-Host 'Select option'

    switch ($choice) {
        '1' { try { Repair-Volume -DriveLetter $letter -Scan } catch { Write-ErrLine $_.Exception.Message }; Pause-Enter }
        '2' { Write-WarnLine 'This may dismount the volume. Close apps using the drive.'; try { Repair-Volume -DriveLetter $letter -OfflineScanAndFix } catch { Write-ErrLine $_.Exception.Message }; Pause-Enter }
        '3' { try { chkdsk ("$letter:") '/scan' } catch { Write-ErrLine $_.Exception.Message }; Pause-Enter }
        '4' {
            Write-WarnLine 'This operation can take hours and may stress a failing drive.'
            $ok = Read-Host "Type YES to run: chkdsk $letter: /f /r"
            if ($ok -eq 'YES') { try { chkdsk ("$letter:") '/f' '/r' } catch { Write-ErrLine $_.Exception.Message } } else { Write-Host 'Cancelled.' }
            Pause-Enter
        }
        default { return }
    }
}

function Generate-Report {
    Write-Title 'Generate Disk Report'
    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    $outDir = Join-Path $ScriptRoot 'reports'
    New-Dir $outDir
    $out = Join-Path $outDir "disk_report_$ts.txt"

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('Fast Data Recovery - Disk Report (Windows)')
    [void]$sb.AppendLine("Timestamp: $(Get-Date)")
    [void]$sb.AppendLine('')

    try {
        $disks = Get-Disk | Sort-Object Number
        foreach ($d in $disks) {
            [void]$sb.AppendLine("Disk #$($d.Number)  Physical: \\.\\PhysicalDrive$($d.Number)")
            [void]$sb.AppendLine("  Model: $($d.FriendlyName)  Bus: $($d.BusType)  Style: $($d.PartitionStyle)  Health: $($d.HealthStatus)")
            [void]$sb.AppendLine("  Size: $([math]::Round($d.Size/1GB,2)) GB")
            $parts = Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue
            foreach ($p in $parts) {
                $vol = $null; try { $vol = Get-Volume -Partition $p -ErrorAction Stop } catch {}
                $drive = if ($vol -and $vol.DriveLetter) { "$($vol.DriveLetter):" } else { '-' }
                $fs = if ($vol) { $vol.FileSystem } else { '-' }
                [void]$sb.AppendLine("    Part $($p.PartitionNumber): Offset=$([math]::Round($p.Offset/1MB,0))MB  Size=$([math]::Round($p.Size/1GB,2))GB  Drive=$drive  FS=$fs")
            }
        }
    } catch {
        [void]$sb.AppendLine("Error enumerating disks: $($_.Exception.Message)")
    }

    $smartctl = Get-ToolPath 'smartctl.exe' @('C:\\Program Files\\smartmontools\\bin\\smartctl.exe')
    if ($smartctl) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('SMART overall-health:')
        foreach ($d in $disks) {
            $dev = "\\.\PhysicalDrive$($d.Number)"
            [void]$sb.AppendLine("== $dev ==")
            try {
                $o = & $smartctl '-H' '-d' 'auto' $dev 2>&1
                [void]$sb.AppendLine($o)
            } catch { [void]$sb.AppendLine("smartctl failed: $($_.Exception.Message)") }
            [void]$sb.AppendLine('')
        }
    } else {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('SMART: smartctl not found; install smartmontools to include SMART summaries.')
    }

    [IO.File]::WriteAllText($out, $sb.ToString(), [Text.Encoding]::UTF8)
    Write-Host "Saved: $out" -ForegroundColor Green
    Pause-Enter
}

function Open-Readme {
    $p = Join-Path $ScriptRoot 'README.md'
    if (Test-Path -LiteralPath $p) { Start-Process $p } else { Write-WarnLine 'README.md not found in script folder.' }
}

function Wizard-Complete-Recovery {
    while ($true) {
        Clear-Host
        Write-Title 'Complete Recovery - Guided Wizard'
        Write-Host 'Recommended steps:'
        Write-Host '  1) SMART health check (identify failing drives).'
        Write-Host '  2) If any issues: image with ddrescue (Linux).'
        Write-Host '  3) Work on the image: TestDisk (partitions) or PhotoRec (files).'
        Write-Host ''
        Write-Host 'Select action:'
        Write-Host '  1) Run SMART check now'
        Write-Host '  2) View Linux imaging instructions (README)'
        Write-Host '  3) Launch TestDisk'
        Write-Host '  4) Launch PhotoRec'
        Write-Host '  0) Back'
        $c = Read-Host 'Enter choice'
        switch ($c) {
            '1' { Run-SMART }
            '2' { Open-Readme; Pause-Enter }
            '3' { Launch-TestDisk }
            '4' { Launch-PhotoRec }
            '0' { return }
            default { Write-WarnLine 'Invalid selection.'; Start-Sleep -Seconds 1 }
        }
    }
}

function Quick-Recovery-Menu {
    while ($true) {
        Clear-Host
        Write-Title 'Quick Recovery'
        Write-Host 'Choose a recovery type:'
        Write-Host '  1) Deleted Recovery (PhotoRec)'
        Write-Host '  2) Complete Recovery (guided wizard)'
        Write-Host '  3) Lost Partition Recovery (TestDisk)'
        Write-Host '  4) Digital Media Recovery (PhotoRec, select media file types)'
        Write-Host '  0) Back'
        $sel = Read-Host 'Enter choice'
        switch ($sel) {
            '1' { Write-Host 'Tip: Choose only needed file types in PhotoRec for speed.' -ForegroundColor Gray; Launch-PhotoRec }
            '2' { Wizard-Complete-Recovery }
            '3' { Launch-TestDisk }
            '4' { Write-Host 'Tip: In PhotoRec, use File Opt to select photos/videos only.' -ForegroundColor Gray; Launch-PhotoRec }
            '0' { return }
            default { Write-WarnLine 'Invalid selection.'; Start-Sleep -Seconds 1 }
        }
    }
}

function Main-Menu {
    while ($true) {
        Clear-Host
        Write-Title 'Fast Data Recovery - Windows CLI Dashboard'
        Write-Host 'Select an option:'
        Write-Host '  1) Quick Recovery (Deleted, Complete, Lost Partition, Digital Media)'
        Write-Host '  2) List disks (safe)'
        Write-Host '  3) SMART health check (smartctl)'
        Write-Host '  4) Launch TestDisk (partition recovery)'
        Write-Host '  5) Launch PhotoRec (file carving)'
        Write-Host '  6) Volume check/repair (guarded)'
        Write-Host '  7) Generate disk report to file'
        Write-Host '  8) Open README'
        Write-Host '  0) Exit'
        $sel = Read-Host 'Enter choice'
        switch ($sel) {
            '1' { Quick-Recovery-Menu }
            '2' { Show-Disks; Pause-Enter }
            '3' { Run-SMART }
            '4' { Launch-TestDisk }
            '5' { Launch-PhotoRec }
            '6' { Volume-Repair-Menu }
            '7' { Generate-Report }
            '8' { Open-Readme; Pause-Enter }
            '0' { break }
            default { Write-WarnLine 'Invalid selection.'; Start-Sleep -Seconds 1 }
        }
    }
}

# Entry point
Main-Menu

