# Run only in a disposable GitHub-hosted Windows runner. NEVER on a gaming PC.
param([string]$Package, [string]$Scenario, [string]$Game)
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_OS -ne 'Windows') {
    throw 'Installer integration tests require a disposable GitHub Windows runner.'
}
if ($Scenario) {
    function global:Read-Host { param($Prompt) if ($Scenario -eq 'cancel') { 'CANCEL' } else { 'INSTALL' } }
    & (Join-Path $Package 'Install.ps1') -GameDirectory $Game
    exit $LASTEXITCODE
}
$Package = (Resolve-Path $Package).Path
$taskRoot = Join-Path $env:RUNNER_TEMP ('traversal-installer-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $taskRoot
$docs = [Environment]::GetFolderPath('MyDocuments')
$profiles = Join-Path $docs 'Rockstar Games\Red Dead Redemption 2\Profiles'
if (Test-Path -LiteralPath $profiles) { throw 'Unexpected existing save profile; will not touch it.' }
$null = New-Item -ItemType Directory -Path (Join-Path $profiles 'SyntheticTest') -Force
'synthetic test save, not game data' | Set-Content (Join-Path $profiles 'SyntheticTest\SRDR30000')
$saveHash = (Get-FileHash (Join-Path $profiles 'SyntheticTest\SRDR30000')).Hash
function New-GameFixture([string]$Name, [bool]$Loader = $true) {
    $path = Join-Path $taskRoot $Name
    $null = New-Item -ItemType Directory -Path $path
    'synthetic placeholder; never executed' | Set-Content (Join-Path $path 'RDR2.exe')
    if ($Loader) {
        'synthetic placeholder; never loaded' | Set-Content (Join-Path $path 'ScriptHookRDR2.dll')
        'synthetic placeholder; never loaded' | Set-Content (Join-Path $path 'dinput8.dll')
    }
    return $path
}
function Run-Scenario([string]$Name, [string]$Target, [string]$Source = $Package) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Package $Source -Scenario $Name -Game $Target | Out-Host
    return $LASTEXITCODE
}
$missing = New-GameFixture 'missing-loader' $false
if ((Run-Scenario 'install' $missing) -eq 0) { throw 'Missing loader was accepted' }
if (Test-Path (Join-Path $missing 'AssassinTraversal.asi')) { throw 'Wrote plugin despite missing loader' }
$cancel = New-GameFixture 'cancel'
if ((Run-Scenario 'cancel' $cancel) -eq 0) { throw 'Cancelled installation reported success' }
if (Test-Path (Join-Path $cancel 'AssassinTraversal.asi')) { throw 'Wrote plugin after cancellation' }
$hot = New-GameFixture 'hot-reload'
'' | Set-Content (Join-Path $hot 'ScriptHookRDR2.dev')
if ((Run-Scenario 'install' $hot) -eq 0) { throw 'Accepted developer hot-reload' }
$valid = New-GameFixture 'valid'
$exeHash = (Get-FileHash (Join-Path $valid 'RDR2.exe')).Hash
if ((Run-Scenario 'install' $valid) -ne 0) { throw 'Valid installation failed' }
foreach ($file in @('AssassinTraversal.asi','AssassinTraversal.ini')) {
    if ((Get-FileHash (Join-Path $valid $file)).Hash -ne (Get-FileHash (Join-Path $Package $file)).Hash) {
        throw "Installed file mismatch: $file"
    }
}
if ((Get-FileHash (Join-Path $valid 'RDR2.exe')).Hash -ne $exeHash) { throw 'Game executable changed' }
if ((Get-FileHash (Join-Path $profiles 'SyntheticTest\SRDR30000')).Hash -ne $saveHash) { throw 'Original save changed' }
$backups = @(Get-ChildItem (Join-Path $docs 'RDR2-Traversal-Backups') -Recurse -File -Filter SRDR30000)
if ($backups.Count -ne 1 -or (Get-FileHash $backups[0].FullName).Hash -ne $saveHash) { throw 'Backup missing or corrupted' }
if ((Run-Scenario 'install' $valid) -eq 0) { throw 'Existing mod was overwritten' }
$corrupt = Join-Path $taskRoot 'corrupt-package'
Copy-Item $Package $corrupt -Recurse
'damaged' | Set-Content (Join-Path $corrupt 'AssassinTraversal.asi')
$target = New-GameFixture 'corrupt-target'
if ((Run-Scenario 'install' $target $corrupt) -eq 0) { throw 'Corrupted package accepted' }
if (Test-Path (Join-Path $target 'AssassinTraversal.asi')) { throw 'Corrupt package touched game directory' }
Write-Host 'PASS: installer success, backup hashes, unchanged game/save, cancellation, loader/hot-reload guards, no overwrite and corrupt package.'
