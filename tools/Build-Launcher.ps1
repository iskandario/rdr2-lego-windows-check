#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$template = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Launcher.cmd.txt'))
$source = [IO.File]::ReadAllText((Join-Path $root 'Check-Games.ps1'))
# Readable embedded source, not a network bootstrap or an encoded payload.
$content = $template.TrimEnd() + "`n" + $source.TrimEnd() + "`n"
$content = $content.Replace("`r`n", "`n").Replace("`n", "`r`n")
[IO.File]::WriteAllText((Join-Path $root 'CHECK-WINDOWS.cmd'), $content, (New-Object Text.UTF8Encoding($false)))
Write-Host 'Built standalone CHECK-WINDOWS.cmd'
