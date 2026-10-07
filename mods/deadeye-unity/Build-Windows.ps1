#requires -Version 5.1
[CmdletBinding()]
param([string]$WorkRoot = (Join-Path ([IO.Path]::GetTempPath()) ('DeadEyeUnity-build-' + [Guid]::NewGuid().ToString('N'))))
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Windows with Visual Studio 2022 C++ build tools is required.' }
if (Test-Path -LiteralPath $WorkRoot) { throw 'WorkRoot must be a NEW directory, not a game folder or existing checkout.' }
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git is required.' }
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Install Visual Studio 2022 C++ Build Tools first.' }
$vs = & $vswhere -latest -version '[17.0,18.0)' -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $vs) { throw 'Visual Studio 2022 C++ toolchain not found.' }
$msbuild = Join-Path $vs 'MSBuild/Current/Bin/amd64/MSBuild.exe'
if (-not (Test-Path -LiteralPath $msbuild)) { throw 'MSBuild not found.' }
$pin = '80c41d4719362493ddac97e3a4a23b5e23094fa5'
& git clone --no-checkout https://github.com/antr1x/ACUFixes.git $WorkRoot
if ($LASTEXITCODE -ne 0) { throw 'Upstream clone failed.' }
& git -C $WorkRoot checkout --detach $pin
if ($LASTEXITCODE -ne 0) { throw 'Pinned upstream checkout failed.' }
& (Join-Path $PSScriptRoot 'Apply-Integration.ps1') -UpstreamRoot $WorkRoot
# Build the gameplay plugin only; do not build or alter the loader/proxy projects.
$solutionDir = $WorkRoot.TrimEnd('\', '/') + '\'
& $msbuild (Join-Path $WorkRoot 'ACUFixes/ACUFixes.vcxproj') /m /t:Build /p:Configuration=Release /p:Platform=x64 /p:PlatformToolset=v143 "/p:SolutionDir=$solutionDir" /verbosity:minimal
if ($LASTEXITCODE -ne 0) { throw 'Native build failed; no files were installed.' }
$dll = Join-Path $WorkRoot 'build/x64/Release/plugins/ACUFixes.dll'
if (-not (Test-Path -LiteralPath $dll)) { throw 'Build did not produce expected ACUFixes.dll.' }
Write-Host ('Built plugin: ' + $dll)
Write-Host 'Not installed. No game folders or saves changed. In-game validation remains required.'
