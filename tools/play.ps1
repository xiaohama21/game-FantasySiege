param([string]$GodotPath = 'F:\Godot\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw 'Godot executable not found. Pass -GodotPath.' }
& $GodotPath --path $projectRoot
