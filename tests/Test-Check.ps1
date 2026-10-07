#requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = Split-Path $PSScriptRoot -Parent
$collector = Join-Path $root 'Check-Games.ps1'
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
$parseErrors = $null
$tokens = $null
[void][Management.Automation.Language.Parser]::ParseFile($collector, [ref]$tokens, [ref]$parseErrors)
Assert ($parseErrors.Count -eq 0) 'Scanner syntax errors'

$cmd = [IO.File]::ReadAllText((Join-Path $root 'CHECK-WINDOWS.cmd'))
$marker = '# BEGIN EMBEDDED POWERSHELL'
$offset = $cmd.LastIndexOf($marker)
Assert ($offset -gt 0) 'No embedded PowerShell source'
$embedded = $cmd.Substring($offset + $marker.Length).Trim()
Assert ($embedded.Replace("`r`n", "`n") -eq [IO.File]::ReadAllText($collector).Trim().Replace("`r`n", "`n")) 'Embedded source is stale'
$embeddedBlock = [scriptblock]::Create($embedded)

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('rdr2-unity-test-' + [Guid]::NewGuid().ToString('N'))
$steam = Join-Path $fixture 'Steam Main'
$extra = Join-Path $fixture 'Library Two'
$rdr = Join-Path $steam 'steamapps/common/Red Dead Redemption 2'
$unity = Join-Path $extra "steamapps/common/Assassin's Creed Unity"
$reports = Join-Path $fixture 'reports'
foreach ($dir in @($rdr, $unity, $reports, (Join-Path $unity 'ACUFixes/plugins'))) { [void][IO.Directory]::CreateDirectory($dir) }
function Write-Pe($Path, [UInt16]$Machine) {
    $bytes = New-Object byte[] 256
    $bytes[0] = 0x4d; $bytes[1] = 0x5a; $bytes[0x3c] = 0x80
    $bytes[0x80] = 0x50; $bytes[0x81] = 0x45
    [BitConverter]::GetBytes($Machine).CopyTo($bytes, 0x84)
    [IO.File]::WriteAllBytes($Path, $bytes)
}
Write-Pe (Join-Path $rdr 'RDR2.exe') 0x8664
Write-Pe (Join-Path $unity 'ACU.exe') 0x8664
[IO.File]::WriteAllText((Join-Path $unity 'DataPC_ACU_Paris.forge'), 'fixture')
[IO.File]::WriteAllText((Join-Path $unity 'ACUFixes/ACUFixes-PluginLoader.dll'), 'fixture')
[IO.File]::WriteAllText((Join-Path $unity 'ACUFixes/plugins/AssetOverrides.dll'), 'fixture')
[IO.File]::WriteAllText((Join-Path $steam 'steamapps/libraryfolders.vdf'), ('"libraryfolders"' + "`n{`n" + '"1"' + "`n{`n" + '"path" "' + $extra.Replace('\', '\\') + '"' + "`n}`n}"))
[IO.File]::WriteAllText((Join-Path $steam 'steamapps/appmanifest_1174180.acf'), "`"appid`" `"1174180`"`n`"installdir`" `"Red Dead Redemption 2`"`n`"buildid`" `"123`"`n`"StateFlags`" `"4`"")
[IO.File]::WriteAllText((Join-Path $extra 'steamapps/appmanifest_289650.acf'), "`"appid`" `"289650`"`n`"installdir`" `"Assassin's Creed Unity`"`n`"buildid`" `"456`"`n`"StateFlags`" `"4`"")
$before = Get-ChildItem $steam,$extra -Recurse -File | Get-FileHash | Select-Object Path,Hash | ConvertTo-Json
& $embeddedBlock -SteamRoot $steam -ReportRoot $reports -NoAutoDiscovery
$raw = Get-ChildItem $reports -File | Get-Content -Raw
$report = $raw | ConvertFrom-Json
Assert ($report.librariesDetected -eq 2) 'Secondary library detection failed'
Assert ($report.games[0].installations[0].executables[0].architecture -eq 'x64') 'RDR x64 detection failed'
Assert ($report.games[1].appId -eq '289650') 'Wrong Unity Steam app ID'
Assert ($report.games[1].installations[0].executables[0].architecture -eq 'x64') 'Unity x64 detection failed'
Assert ($report.games[1].installations[0].rootArchiveCount -eq 1) 'Unity forge count failed'
Assert ($report.games[1].installations[0].existingModFiles.Count -eq 2) 'Unity mod loader detection failed'
Assert (-not $raw.Contains($fixture)) 'Local path leaked'
$after = Get-ChildItem $steam,$extra -Recurse -File | Get-FileHash | Select-Object Path,Hash | ConvertTo-Json
Assert ($before -eq $after) 'Steam/game fixture files changed'
[IO.File]::WriteAllText((Join-Path $rdr 'RDR2.exe'), 'broken')
& $collector -SteamRoot $steam -ReportRoot (Join-Path $fixture 'broken-report') -NoAutoDiscovery
$broken = Get-ChildItem (Join-Path $fixture 'broken-report') -File | Get-Content -Raw | ConvertFrom-Json
Assert ([bool]$broken.games[0].installations[0].executables[0].error) 'Corrupt EXE handling failed'
& $collector -SteamRoot (Join-Path $fixture 'absent') -ReportRoot (Join-Path $fixture 'empty-report') -NoAutoDiscovery
$empty = Get-ChildItem (Join-Path $fixture 'empty-report') -File | Get-Content -Raw | ConvertFrom-Json
Assert ($empty.librariesDetected -eq 0 -and $empty.games[0].installations.Count -eq 0) 'Absent games handling failed'

& $collector -UnityPath (Join-Path $unity 'ACU.exe') -ReportRoot (Join-Path $fixture 'manual-report') -NoAutoDiscovery
$manual = Get-ChildItem (Join-Path $fixture 'manual-report') -File | Get-Content -Raw | ConvertFrom-Json
Assert ($manual.games[1].installations[0].discoverySource -eq 'Manual') 'Explicit Unity EXE detection failed'
Assert ($manual.games[1].installations[0].executables[0].name -eq 'ACU.exe') 'Explicit Unity EXE missing'
& $collector -SteamRoot $steam -UnityPath $unity -ReportRoot (Join-Path $fixture 'dedup-report') -NoAutoDiscovery
$dedup = Get-ChildItem (Join-Path $fixture 'dedup-report') -File | Get-Content -Raw | ConvertFrom-Json
Assert ($dedup.games[1].installations.Count -eq 1) 'Duplicate Unity installation reported'
& $collector -UnityPath (Join-Path $rdr 'RDR2.exe') -ReportRoot (Join-Path $fixture 'wrong-exe-report') -NoAutoDiscovery
$wrong = Get-ChildItem (Join-Path $fixture 'wrong-exe-report') -File | Get-Content -Raw | ConvertFrom-Json
Assert ($wrong.games[1].installations.Count -eq 0) 'Wrong executable accepted as Unity'

if ($env:OS -eq 'Windows_NT') {
    # Simulate WinRAR: only the CMD exists, CWD is elsewhere, reports survive
    # outside the launch directory. Include shell metacharacters and Unicode.
    $unicode = [string][char]0x0418 + [char]0x0433 + [char]0x0440 + [char]0x044B
    $isolated = Join-Path $fixture ("Rar`$Temp & (standalone)! O'Neil " + $unicode)
    [void][IO.Directory]::CreateDirectory($isolated)
    $standalone = Join-Path $isolated 'CHECK-WINDOWS.cmd'
    Copy-Item -LiteralPath (Join-Path $root 'CHECK-WINDOWS.cmd') -Destination $standalone
    Assert (-not (Test-Path -LiteralPath (Join-Path $isolated 'Check-Games.ps1'))) 'Test must not have adjacent PS1'
    $standaloneReports = Join-Path $fixture 'persistent reports'
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $env:ComSpec
    $start.Arguments = '/d /s /c ""' + $standalone + '""'
    $start.WorkingDirectory = $fixture
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.EnvironmentVariables['RDR2_CHECK_REPORT_ROOT'] = $standaloneReports
    $start.EnvironmentVariables['RDR2_CHECK_NONINTERACTIVE'] = '1'
    $start.EnvironmentVariables['RDR2_CHECK_UNITY_PATH'] = Join-Path $unity 'ACU.exe'
    $process = [Diagnostics.Process]::Start($start)
    try {
        if (-not $process.WaitForExit(60000)) { $process.Kill(); throw 'Standalone CMD timed out' }
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        Write-Host $stdout
        Assert ($process.ExitCode -eq 0) ('Standalone CMD failed: ' + $stderr)
    } finally { $process.Dispose() }
    $standaloneFiles = @(Get-ChildItem -LiteralPath $standaloneReports -Filter '*.json')
    Assert ($standaloneFiles.Count -eq 1) 'Standalone report was not saved outside temp launch directory'
    $standaloneReport = Get-Content -LiteralPath $standaloneFiles[0].FullName -Raw | ConvertFrom-Json
    Assert ($standaloneReport.schemaVersion -eq 2) 'Standalone output is not a valid report'
    Assert ($standaloneReport.games[1].installations[0].executables[0].name -eq 'ACU.exe') 'Standalone Unity detection failed'
    Write-Host 'PASS: isolated CMD under Windows PowerShell, with special characters and no adjacent PS1.'
} else {
    Write-Host 'SKIP: cmd.exe integration requires Windows; covered by GitHub Actions.'
}
Write-Host 'PASS: embedded source, Steam RDR2/Unity, x64, privacy, read-only scan, corrupt EXE, missing games, manual Unity, deduplication, forge/mod detection.'
