param([string]$GodotPath = 'F:\Godot\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$config = Get-Content -LiteralPath (Join-Path $projectRoot 'project.godot') -Raw
$version = [regex]::Match($config, 'config/version="([^"]+)"').Groups[1].Value
$destination = Join-Path $projectRoot ('exports\windows\FantasySiege-' + $version)
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw 'Godot executable not found' }
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'assets\actors') -PathType Container)) { throw 'Run bootstrap_local.ps1 first' }
New-Item -ItemType Directory -Path $destination -Force | Out-Null
foreach ($name in @('scripts','scenes','resources','bin')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $name) -Destination $destination -Recurse -Force
}
New-Item -ItemType Directory -Path (Join-Path $destination 'assets') -Force | Out-Null
foreach ($name in @('actors','fonts','audio')) {
    $sourcePath = Join-Path $projectRoot ('assets\' + $name)
    if (Test-Path -LiteralPath $sourcePath) { Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $destination 'assets') -Recurse -Force }
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'project.godot') -Destination $destination -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets\icon.svg') -Destination (Join-Path $destination 'assets') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets\GODOT_LICENSE.txt') -Destination $destination -Force
Copy-Item -LiteralPath $GodotPath -Destination (Join-Path $destination 'FantasySiege.exe') -Force
@'
@echo off
start "Star Lantern Expedition" "%~dp0FantasySiege.exe" --path "%~dp0."
'@ | Set-Content -LiteralPath (Join-Path $destination '开始游戏.cmd') -Encoding ascii
@'
星灯远征 · 本地学习版
双击“开始游戏.cmd”启动。1—8召唤，空格暂停，F切换倍速，Esc返回营地。
本包附带本机Godot可执行程序，首次导入已经完成，无需另外安装引擎。
存档保存在Godot用户目录/FantasySiege，与旧游戏完全独立。
D69角色素材仅学习研究使用，本包请留在本地，不作商业用途。
Godot Engine https://godotengine.org/license/ (MIT)
字体许可见 assets/fonts/OFL.txt。
Spine原生运行库与角色素材的商业再分发条件须单独核实。
'@ | Set-Content -LiteralPath (Join-Path $destination '使用说明.txt') -Encoding utf8
& (Join-Path $destination 'FantasySiege.exe') --headless --path $destination --editor --quit
if ($LASTEXITCODE -ne 0) { throw 'Portable project import failed' }
Write-Output $destination
