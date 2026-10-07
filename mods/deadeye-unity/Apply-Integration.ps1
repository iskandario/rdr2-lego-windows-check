#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$UpstreamRoot)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$pin = '80c41d4719362493ddac97e3a4a23b5e23094fa5'
$UpstreamRoot = (Resolve-Path -LiteralPath $UpstreamRoot).Path
if (Test-Path -LiteralPath (Join-Path $UpstreamRoot 'ACU.exe')) { throw 'Use a disposable SOURCE checkout, never the game directory.' }
$head = & git -C $UpstreamRoot rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $head -ne $pin) { throw "Expected exact upstream commit $pin" }
$dirty = & git -C $UpstreamRoot status --porcelain
if ($LASTEXITCODE -ne 0 -or $dirty) { throw 'Upstream checkout must be clean; existing changes will not be overwritten.' }

function Replace-Exact([string]$Text, [string]$Before, [string]$After, [int]$Count = 1) {
    if ([regex]::Matches($Text, [regex]::Escape($Before)).Count -ne $Count) { throw ('Unexpected upstream text: ' + $Before) }
    return $Text.Replace($Before, $After)
}
function Replace-Calls([string]$Text, [string]$OldName, [string]$NewName, [int]$Count) {
    $pattern = '(?<!void )' + [regex]::Escape($OldName) + '\(\);'
    if ([regex]::Matches($Text, $pattern).Count -ne $Count) { throw ('Unexpected call count: ' + $OldName) }
    return [regex]::Replace($Text, $pattern, ($NewName + '();'))
}
$framePath = Join-Path $UpstreamRoot 'ACUFixes/src/WhatIsDrawnInImGui.cpp'
$menuPath = Join-Path $UpstreamRoot 'ACUFixes/src/Hacks_ImGuiControl.cpp'
$projectPath = Join-Path $UpstreamRoot 'ACUFixes/ACUFixes.vcxproj'
$frame = [IO.File]::ReadAllText($framePath)
$frame = Replace-Exact $frame '#include "pch.h"' "#include `"pch.h`"`n`nvoid RdrDeadEyeRequestUnload();"
$frame = Replace-Exact $frame 'void DoSlowMotionTrick();' 'void RdrDeadEyeUpdate();'
$frame = Replace-Exact $frame '    DoSlowMotionTrick();' '    RdrDeadEyeUpdate();'
$frame = Replace-Calls $frame 'RequestUnloadThisPlugin' 'RdrDeadEyeRequestUnload' 2
$menu = [IO.File]::ReadAllText($menuPath)
$menu = Replace-Exact $menu 'DrawSlowMotionTrickControls();' 'RdrDeadEyeDrawMenu();' 2
$menu = Replace-Calls $menu 'DrawSlowMotionControls' 'RdrDeadEyeDrawMenu' 1
$project = [IO.File]::ReadAllText($projectPath)
$anchor = '<ClCompile Include="src\WhatIsDrawnInImGui.cpp" />'
$project = Replace-Exact $project $anchor ($anchor + "`n    " + '<ClCompile Include="src\RdrDeadEye.cpp" />')
[xml]$validProject = $project
foreach ($name in @('DeadEyeController.hpp','RdrDeadEye.cpp')) {
    if (Test-Path -LiteralPath (Join-Path $UpstreamRoot ('ACUFixes/src/' + $name))) { throw ('Refusing to overwrite ' + $name) }
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $name))) { throw ('Missing source ' + $name) }
}
# All checks above are completed before making any edits. Only source files change.
$encoding = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($framePath, $frame, $encoding)
[IO.File]::WriteAllText($menuPath, $menu, $encoding)
[IO.File]::WriteAllText($projectPath, $project, $encoding)
foreach ($name in @('DeadEyeController.hpp','RdrDeadEye.cpp')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $UpstreamRoot ('ACUFixes/src/' + $name))
}
Write-Host 'Integrated original Dead Eye prototype into pinned upstream SOURCE only.'
Write-Host 'No loader/protection code changed. No game folders accessed.'
