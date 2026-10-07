@echo off
setlocal DisableDelayedExpansion
title RDR2 + Assassin's Creed Unity - Installation Check
echo RDR2 + Assassin's Creed Unity v0.2.0. This is NOT a playable crossover mod.
echo No game files are changed. Nothing is uploaded.
echo.
set "RDR2_CHECK_SELF=%~f0"
powershell.exe -STA -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { $text=[IO.File]::ReadAllText($env:RDR2_CHECK_SELF); $marker='# BEGIN EMBEDDED POWERSHELL'; $index=$text.LastIndexOf($marker); if($index -lt 0){throw 'Embedded script missing. Download CHECK-WINDOWS.cmd again.'}; $code=$text.Substring($index+$marker.Length); $reportRoot=$env:RDR2_CHECK_REPORT_ROOT; if(-not $reportRoot){$base=[Environment]::GetFolderPath('Desktop'); if(-not $base){$base=[Environment]::GetFolderPath('MyDocuments')}; if(-not $base){$base=$env:USERPROFILE}; if(-not $base){throw 'Cannot find a persistent report folder.'}; $reportRoot=Join-Path $base 'RDR2-UNITY-Reports'}; & ([scriptblock]::Create($code)) -ReportRoot $reportRoot -UnityPath $env:RDR2_CHECK_UNITY_PATH -PromptForMissingUnity:([string]::IsNullOrEmpty($env:RDR2_CHECK_NONINTERACTIVE)); exit 0 } catch { Write-Host ('Check failed: '+$_.Exception.Message) -ForegroundColor Red; exit 1 }"
set "RDR2_CHECK_EXIT=%ERRORLEVEL%"
if not "%RDR2_CHECK_EXIT%"=="0" echo Please send the error text from this window.
echo.
if not defined RDR2_CHECK_NONINTERACTIVE pause
exit /b %RDR2_CHECK_EXIT%
# BEGIN EMBEDDED POWERSHELL
#requires -Version 5.1
[CmdletBinding()]
param(
    [string[]]$SteamRoot = @(),
    [string]$ReportRoot = $PSScriptRoot,
    [switch]$NoAutoDiscovery,
    [string]$UnityPath,
    [switch]$PromptForMissingUnity
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

function Get-VdfValue([string]$Text, [string]$Key) {
    $m = [regex]::Match($Text, '(?m)^\s*"' + [regex]::Escape($Key) + '"\s+"([^"\r\n]*)"')
    if ($m.Success) { return $m.Groups[1].Value.Replace('\\', '\') }
    return $null
}

function Get-PeInfo([string]$Path) {
    $stream = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    $reader = New-Object IO.BinaryReader($stream)
    try {
        if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) { throw 'Invalid MZ' }
        $stream.Position = 0x3c
        $offset = $reader.ReadUInt32()
        if ($offset -gt ($stream.Length - 24)) { throw 'Invalid PE offset' }
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x00004550) { throw 'Invalid PE signature' }
        $machine = $reader.ReadUInt16()
        switch ($machine) {
            0x14c { return 'x86' }
            0x8664 { return 'x64' }
            0xaa64 { return 'ARM64' }
            default { return ('unknown-0x{0:x}' -f $machine) }
        }
    } finally { $reader.Dispose(); $stream.Dispose() }
}

function Get-Installation($Game, [string]$Path, [string]$Source, $BuildId, $StateFlags) {
    $exists = Test-Path -LiteralPath $Path -PathType Container
    $executables = @()
    $modFiles = @()
    $archiveCount = 0
    if ($exists) {
        Write-Host ('Checking ' + $Game.title + '...')
        $files = @(Get-ChildItem -LiteralPath $Path -File)
        $archiveCount = @($files | Where-Object { $_.Extension -in @('.rpf', '.forge') }).Count
        $modFiles = @($files | Where-Object { $_.Extension -eq '.asi' -or $_.Name -in @('dinput8.dll','version.dll','ScriptHookRDR2.dll') } | Select-Object -ExpandProperty Name)
        if ($Game.id -eq '289650') {
            foreach ($relative in @('ACUFixes/ACUFixes-PluginLoader.dll', 'ACUFixes/plugins/ACUFixes.dll', 'ACUFixes/plugins/AssetOverrides.dll')) {
                if (Test-Path -LiteralPath (Join-Path $Path $relative) -PathType Leaf) { $modFiles += $relative }
            }
        }
        foreach ($exe in @($files | Where-Object { $_.Name -match $Game.exePattern })) {
            try {
                $executables += [ordered]@{
                    name = $exe.Name
                    bytes = $exe.Length
                    architecture = Get-PeInfo $exe.FullName
                    fileVersion = $exe.VersionInfo.FileVersion
                    productVersion = $exe.VersionInfo.ProductVersion
                    sha256 = (Get-FileHash -LiteralPath $exe.FullName -Algorithm SHA256).Hash
                }
            } catch {
                $executables += [ordered]@{ name = $exe.Name; error = $_.Exception.GetType().Name }
            }
        }
    }
    return [ordered]@{
        discoverySource = $Source
        buildId = $BuildId
        stateFlags = $StateFlags
        directoryExists = [bool]$exists
        executables = @($executables)
        existingModFiles = @($modFiles)
        rootArchiveCount = $archiveCount
    }
}

function Resolve-UnityDirectory([string]$Path) {
    if (-not $Path) { return $null }
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        if ([IO.Path]::GetFileName($Path) -ine 'ACU.exe') { return $null }
        $Path = Split-Path $Path -Parent
    }
    if (Test-Path -LiteralPath (Join-Path $Path 'ACU.exe') -PathType Leaf) {
        return [IO.Path]::GetFullPath($Path)
    }
    return $null
}

$roots = New-Object 'System.Collections.Generic.List[string]'
foreach ($root in $SteamRoot) { if ($root) { $roots.Add($root) } }
if (-not $NoAutoDiscovery) {
    if ($env:OS -ne 'Windows_NT') { throw 'Run CHECK-WINDOWS.cmd on the Windows gaming PC.' }
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam')) {
        if (-not (Test-Path -LiteralPath $key)) { continue }
        $entry = Get-ItemProperty -LiteralPath $key
        foreach ($field in @('SteamPath', 'InstallPath')) {
            $prop = $entry.PSObject.Properties[$field]
            if ($prop -and $prop.Value) { $roots.Add([string]$prop.Value) }
        }
    }
    foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if ($base) { $roots.Add((Join-Path $base 'Steam')) }
    }
}

$libraries = New-Object 'System.Collections.Generic.List[string]'
foreach ($root in @($roots | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
    $libraries.Add($root)
    foreach ($relative in @('steamapps/libraryfolders.vdf', 'config/libraryfolders.vdf')) {
        $vdfPath = Join-Path $root $relative
        if (-not (Test-Path -LiteralPath $vdfPath -PathType Leaf)) { continue }
        $vdf = [IO.File]::ReadAllText($vdfPath)
        foreach ($match in [regex]::Matches($vdf, '(?m)^\s*"(?:path|\d+)"\s+"([^"\r\n]+)"')) {
            $candidate = $match.Groups[1].Value.Replace('\\', '\')
            if (Test-Path -LiteralPath $candidate -PathType Container) { $libraries.Add($candidate) }
        }
    }
}

$games = @(
    @{ id = '1174180'; title = 'Red Dead Redemption 2'; exePattern = '(?i)^RDR2\.exe$' },
    @{ id = '289650'; title = "Assassin's Creed Unity"; exePattern = '(?i)^ACU\.exe$' }
)
$results = @()
foreach ($game in $games) {
    $installs = @()
    $seenPaths = @{}
    foreach ($library in @($libraries | Select-Object -Unique)) {
        $manifest = Join-Path $library ('steamapps/appmanifest_' + $game.id + '.acf')
        if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { continue }
        $text = [IO.File]::ReadAllText($manifest)
        if ((Get-VdfValue $text 'appid') -ne $game.id) { continue }
        $dir = Get-VdfValue $text 'installdir'
        if (-not $dir -or $dir -eq '.' -or $dir -eq '..' -or $dir.IndexOfAny([char[]]'\/:') -ge 0) { continue }
        $gamePath = Join-Path (Join-Path $library 'steamapps/common') $dir
        $canonicalPath = [IO.Path]::GetFullPath($gamePath)
        if (-not $seenPaths.ContainsKey($canonicalPath)) {
            $installs += Get-Installation $game $gamePath 'Steam' (Get-VdfValue $text 'buildid') (Get-VdfValue $text 'StateFlags')
            $seenPaths[$canonicalPath] = $true
        }
    }
    if ($game.id -eq '289650') {
        $candidates = @()
        if ($UnityPath) {
            $resolved = Resolve-UnityDirectory $UnityPath
            if ($resolved) { $candidates += @{ path = $resolved; source = 'Manual' } }
            else { Write-Warning 'The specified Unity location does not contain ACU.exe.' }
        }
        if (-not $NoAutoDiscovery) {
            foreach ($key in @('HKLM:\SOFTWARE\WOW6432Node\Ubisoft\Launcher\Installs', 'HKLM:\SOFTWARE\Ubisoft\Launcher\Installs', 'HKCU:\SOFTWARE\Ubisoft\Launcher\Installs')) {
                if (-not (Test-Path -LiteralPath $key)) { continue }
                foreach ($entry in @(Get-ChildItem -LiteralPath $key -ErrorAction SilentlyContinue)) {
                    $values = Get-ItemProperty -LiteralPath $entry.PSPath -ErrorAction SilentlyContinue
                    if (-not $values) { continue }
                    $prop = $values.PSObject.Properties['InstallDir']
                    if ($prop -and $prop.Value) {
                        $resolved = Resolve-UnityDirectory ([string]$prop.Value)
                        if ($resolved) { $candidates += @{ path = $resolved; source = 'Ubisoft' } }
                    }
                }
            }
        }
        foreach ($candidate in $candidates) {
            if ($seenPaths.ContainsKey($candidate.path)) { continue }
            $installs += Get-Installation $game $candidate.path $candidate.source $null $null
            $seenPaths[$candidate.path] = $true
        }
        $hasExe = @($installs | Where-Object { $_.executables.Count -gt 0 }).Count -gt 0
        if (-not $hasExe -and $PromptForMissingUnity -and $env:OS -eq 'Windows_NT') {
            Write-Host 'Unity not found automatically. Select ACU.exe in the game folder, or Cancel.'
            Add-Type -AssemblyName System.Windows.Forms
            $dialog = New-Object System.Windows.Forms.OpenFileDialog
            try {
                $dialog.Title = "Select Assassin's Creed Unity - ACU.exe"
                $dialog.Filter = 'Assassin''s Creed Unity (ACU.exe)|ACU.exe'
                $dialog.CheckFileExists = $true
                if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $resolved = Resolve-UnityDirectory $dialog.FileName
                    if ($resolved -and -not $seenPaths.ContainsKey($resolved)) {
                        $installs += Get-Installation $game $resolved 'FilePicker' $null $null
                    }
                }
            } finally { $dialog.Dispose() }
        }
    }
    $results += [ordered]@{ appId = $game.id; name = $game.title; installations = @($installs) }
}

$report = [ordered]@{
    schemaVersion = 2
    purpose = "Installation metadata for RDR2 and Assassin's Creed Unity; not a playable mod"
    createdUtc = [DateTime]::UtcNow.ToString('o')
    osVersion = [Environment]::OSVersion.Version.ToString()
    powerShellVersion = $PSVersionTable.PSVersion.ToString()
    librariesDetected = @($libraries | Select-Object -Unique).Count
    games = @($results)
    omitted = @('full paths','Steam account identifiers','saves','game file contents')
}
if (-not (Test-Path -LiteralPath $ReportRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $ReportRoot | Out-Null
}
$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$reportPath = Join-Path $ReportRoot ('RDR2-UNITY-report-' + $stamp + '.json')
$json = $report | ConvertTo-Json -Depth 10
[IO.File]::WriteAllText($reportPath, $json, (New-Object Text.UTF8Encoding($false)))
foreach ($result in $results) {
    $count = @($result.installations | Where-Object { $_.directoryExists -and $_.executables.Count -gt 0 }).Count
    Write-Host ($result.name + ': ' + $count + ' installation(s) with a matching EXE')
}
Write-Host ('Report saved: ' + $reportPath)
Write-Host 'Attach that JSON file to the conversation. No upload has been made.'
if ($libraries.Count -eq 0) {
    Write-Host 'Steam not found. Advanced: run Check-Games.ps1 -SteamRoot "D:\Steam"'
}
