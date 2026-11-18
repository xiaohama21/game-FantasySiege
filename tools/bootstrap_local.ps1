param(
    [string]$GodotPath = 'F:\Godot\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe',
    [string]$ReferenceProject = 'F:\godotProject\TowerDefense',
    [string]$SourceRoot = 'F:\godotProject\D69【spine源文件】【315套Q版卡通角色spine动画】'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw 'Godot executable not found' }
if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) { throw 'Local learning asset library not found' }
Push-Location -LiteralPath $projectRoot
try {
    python tools/bootstrap_local.py --source-root $SourceRoot --runtime-from (Join-Path $ReferenceProject 'bin') --godot $GodotPath
    if ($LASTEXITCODE -ne 0) { throw 'Local asset bootstrap failed' }
} finally { Pop-Location }
