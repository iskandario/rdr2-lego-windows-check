# Windows PowerShell 5.1. No downloads, network access, elevation or game launch.
[CmdletBinding()]
param([string]$GameDirectory)
$ErrorActionPreference = 'Stop'
try {
    Write-Host 'Assassin Traversal 0.1.0 - EXPERIMENTAL, NOT TESTED IN GAME' -ForegroundColor Yellow
    Write-Host 'Story Mode only. NOT a full Assassin Creed parkour port.'
    Write-Host 'This installs only AssassinTraversal.asi and AssassinTraversal.ini.'
    foreach ($file in @('AssassinTraversal.asi', 'AssassinTraversal.ini', 'SHA256SUMS.txt')) {
        if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $file) -PathType Leaf)) {
            throw "Missing $file. Download the Windows release ZIP and extract ALL files first."
        }
    }
    # Detect a damaged or incomplete download before touching the destination.
    $expected = @{}
    foreach ($line in Get-Content -LiteralPath (Join-Path $PSScriptRoot 'SHA256SUMS.txt')) {
        if ($line -match '^([A-Fa-f0-9]{64})  (.+)$') { $expected[$Matches[2]] = $Matches[1] }
    }
    foreach ($file in @('AssassinTraversal.asi', 'AssassinTraversal.ini')) {
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $PSScriptRoot $file)).Hash
        if (-not $expected.ContainsKey($file) -or $actual -ne $expected[$file]) { throw "Checksum mismatch: $file" }
    }
    if ([string]::IsNullOrWhiteSpace($GameDirectory)) {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = 'Select RDR2.exe (Steam > Manage > Browse local files)'
        $dialog.Filter = 'RDR2 executable (RDR2.exe)|RDR2.exe'
        try {
            if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { throw 'Cancelled; no game files changed.' }
            $GameDirectory = Split-Path -Parent $dialog.FileName
        } finally { $dialog.Dispose() }
    }
    $GameDirectory = (Resolve-Path -LiteralPath $GameDirectory).Path
    if (-not (Test-Path -LiteralPath (Join-Path $GameDirectory 'RDR2.exe') -PathType Leaf)) { throw 'Not an RDR2 installation directory.' }
    if (Get-Process -Name RDR2 -ErrorAction SilentlyContinue) { throw 'Exit RDR2 before installing.' }
    if (Test-Path -LiteralPath (Join-Path $GameDirectory 'ScriptHookRDR2.dev')) {
        throw 'Developer hot-reload is enabled. Remove ScriptHookRDR2.dev with the game closed before using this prototype.'
    }
    $hook = Test-Path -LiteralPath (Join-Path $GameDirectory 'ScriptHookRDR2.dll') -PathType Leaf
    $loader = (Test-Path -LiteralPath (Join-Path $GameDirectory 'dinput8.dll') -PathType Leaf) -or
              (Test-Path -LiteralPath (Join-Path $GameDirectory 'version.dll') -PathType Leaf)
    if (-not $hook -or -not $loader) {
        Write-Host 'First install the current official ScriptHookRDR2 runtime and its ASI loader.' -ForegroundColor Yellow
        Write-Host 'https://www.dev-c.com/rdr2/scripthookrdr2/'
        throw 'Dependency missing. Nothing installed. See README.md; do not download DLLs from random sites.'
    }
    Write-Host 'Loader file presence is checked; authenticity/compatibility cannot be confirmed by this installer.'
    foreach ($file in @('AssassinTraversal.asi', 'AssassinTraversal.ini')) {
        if (Test-Path -LiteralPath (Join-Path $GameDirectory $file)) { throw "$file already exists. Back up and remove the old mod first; it will not be overwritten." }
    }
    $documents = [Environment]::GetFolderPath('MyDocuments')
    $profiles = Join-Path $documents 'Rockstar Games\Red Dead Redemption 2\Profiles'
    if (-not (Test-Path -LiteralPath $profiles -PathType Container)) {
        throw 'Save Profiles folder not found in Documents. Make a save in Story Mode first, then retry. No files installed.'
    }
    Write-Host "Game folder: $GameDirectory"
    Write-Host 'A timestamped copy of your Profiles (saves/settings) will be made in Documents\RDR2-Traversal-Backups.'
    Write-Host 'Do NOT use Red Dead Online. Disable autosave and test on a separate save. Falling can injure/kill the character.'
    if ((Read-Host 'Type INSTALL to back up saves and install this experimental mod') -cne 'INSTALL') {
        throw 'Cancelled; no game files changed.'
    }
    $backup = Join-Path (Join-Path $documents 'RDR2-Traversal-Backups') ([DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff'))
    if (Test-Path -LiteralPath $backup) { throw 'Backup path collision. Retry.' }
    $null = New-Item -ItemType Directory -Path $backup
    Copy-Item -LiteralPath $profiles -Destination (Join-Path $backup 'Profiles') -Recurse
    # Verify every source file before installing any plugin file.
    foreach ($source in Get-ChildItem -LiteralPath $profiles -Recurse -File) {
        $relative = $source.FullName.Substring($profiles.Length).TrimStart('\')
        $copy = Join-Path (Join-Path $backup 'Profiles') $relative
        if ((Get-FileHash -LiteralPath $source.FullName).Hash -ne (Get-FileHash -LiteralPath $copy).Hash) {
            throw 'Backup verification failed; plugin not installed.'
        }
    }
    foreach ($file in @('AssassinTraversal.asi', 'AssassinTraversal.ini')) {
        # File.Copy(overwrite:false) refuses races and unintended overwrites.
        [IO.File]::Copy((Join-Path $PSScriptRoot $file), (Join-Path $GameDirectory $file), $false)
    }
    Write-Host 'Installed. Launch your normal RDR2 through Steam and choose STORY MODE.' -ForegroundColor Green
    Write-Host 'F8 enable | Stand facing a low wall, G grab | E climb | Q drop | F9 off'
    Write-Host "Verified saves backup: $backup"
    Write-Host 'Uninstall: exit RDR2, remove only AssassinTraversal.asi and AssassinTraversal.ini.'
    Write-Host 'Send AssassinTraversal.log from the game folder and a short video if something fails.'
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host 'If copying failed part-way: with RDR2 closed, inspect/remove only AssassinTraversal.asi and AssassinTraversal.ini.'
    exit 1
}
