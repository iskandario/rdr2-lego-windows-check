#requires -Version 5.1
[CmdletBinding()]
param(
    [string[]]$SteamRoot = @(),
    [string]$ReportRoot = $PSScriptRoot,
    [switch]$NoAutoDiscovery
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
    @{ id = '32510'; title = 'LEGO Star Wars III - The Clone Wars'; exePattern = '(?i)^LEGO.*\.exe$' }
)
$results = @()
foreach ($game in $games) {
    $installs = @()
    foreach ($library in @($libraries | Select-Object -Unique)) {
        $manifest = Join-Path $library ('steamapps/appmanifest_' + $game.id + '.acf')
        if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { continue }
        $text = [IO.File]::ReadAllText($manifest)
        if ((Get-VdfValue $text 'appid') -ne $game.id) { continue }
        $dir = Get-VdfValue $text 'installdir'
        if (-not $dir -or $dir -eq '.' -or $dir -eq '..' -or $dir.IndexOfAny([char[]]'\/:') -ge 0) { continue }
        $gamePath = Join-Path (Join-Path $library 'steamapps/common') $dir
        $exists = Test-Path -LiteralPath $gamePath -PathType Container
        $executables = @()
        $modFiles = @()
        $archiveCount = 0
        if ($exists) {
            Write-Host ('Checking ' + $game.title + '...')
            $files = @(Get-ChildItem -LiteralPath $gamePath -File)
            $archiveCount = @($files | Where-Object { $_.Extension -in @('.dat', '.rpf') }).Count
            $modFiles = @($files | Where-Object { $_.Extension -eq '.asi' -or $_.Name -in @('dinput8.dll','version.dll','ScriptHookRDR2.dll') } | Select-Object -ExpandProperty Name)
            foreach ($exe in @($files | Where-Object { $_.Name -match $game.exePattern })) {
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
                    # Avoid including local account names or full paths in the shared report.
                    $executables += [ordered]@{ name = $exe.Name; error = $_.Exception.GetType().Name }
                }
            }
        }
        $installs += [ordered]@{
            buildId = Get-VdfValue $text 'buildid'
            stateFlags = Get-VdfValue $text 'StateFlags'
            directoryExists = [bool]$exists
            executables = @($executables)
            existingModFiles = @($modFiles)
            rootArchiveCount = $archiveCount
        }
    }
    $results += [ordered]@{ appId = $game.id; name = $game.title; installations = @($installs) }
}

$report = [ordered]@{
    schemaVersion = 1
    purpose = 'Installation metadata for developing RDR2 inside LEGO Star Wars III; not a playable mod'
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
$reportPath = Join-Path $ReportRoot ('RDR2-LEGO-report-' + $stamp + '.json')
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
