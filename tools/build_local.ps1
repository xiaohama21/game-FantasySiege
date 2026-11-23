param(
    [string]$GodotPath = 'F:\Godot\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe',
    [string]$PythonPath = 'python',
    [string]$Destination = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$config = Get-Content -LiteralPath (Join-Path $projectRoot 'project.godot') -Raw
$version = [regex]::Match($config, 'config/version="([^"]+)"').Groups[1].Value
if (-not $version) { throw 'Project version is missing' }
$exportsRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'exports\windows'))
if (-not $Destination) { $Destination = Join-Path $exportsRoot ('FantasySiege-' + $version) }
$packageRoot = [IO.Path]::GetFullPath($Destination)
if (-not $packageRoot.StartsWith($exportsRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Package destination must be a subdirectory of this project exports/windows'
}
# Reject existing junctions before any package directory or payload is written.
function Assert-UnlinkedPackagePath([string]$Target) {
    $anchor = [IO.Path]::GetFullPath($projectRoot).TrimEnd([char[]]@('\', '/'))
    $absolute = [IO.Path]::GetFullPath($Target)
    if (-not $absolute.StartsWith($anchor + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Package path must remain inside this project'
    }
    $cursor = $anchor
    $parts = @('') + @($absolute.Substring($anchor.Length).TrimStart([char[]]@('\', '/')).Split([char[]]@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries))
    foreach ($part in $parts) {
        if ($part) { $cursor = Join-Path $cursor $part }
        try { $entry = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop }
        catch [System.Management.Automation.ItemNotFoundException] { continue }
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw ('Refusing reparse point in package destination: ' + $cursor)
        }
    }
}
Assert-UnlinkedPackagePath $packageRoot
if ((Test-Path -LiteralPath $packageRoot) -and (Get-ChildItem -LiteralPath $packageRoot -Force | Select-Object -First 1)) {
    throw ('Package destination is not empty; preserve this build and select a new empty Destination: ' + $packageRoot)
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw 'Godot executable not found' }
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'assets\actors') -PathType Container)) { throw 'Run bootstrap_local.ps1 first' }
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'assets\portraits\manifest.json') -PathType Leaf)) { throw 'Generate and validate the twelve local character portraits before building this version' }
if (-not (Get-Command $PythonPath -ErrorAction SilentlyContinue)) { throw 'Python is required only for building/importing this package' }
$payloadTools = @('bootstrap_local.py', 'spine_pipeline.py', 'spine_upgrade_38_to_43.py', 'tune_visuals.py', 'verify_spine.py', 'run_checks.py', 'verify_package.py', 'generate_portraits.py', 'qa_launch.py', 'verify_qa_startup.py')
foreach ($name in $payloadTools) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $name) -PathType Leaf)) {
        throw ('Missing package tool dependency: tools/' + $name)
    }
}

function Copy-PayloadTree([string]$Name) {
    $sourceRoot = Join-Path $projectRoot $Name
    if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) { return }
    foreach ($payloadFile in (Get-ChildItem -LiteralPath $sourceRoot -Recurse -File)) {
        if ($payloadFile.Extension -in @('.import', '.uid', '.pyc', '.log', '.err')) { continue }
        $relativeFile = $payloadFile.FullName.Substring($sourceRoot.Length).TrimStart([char[]]@('\', '/'))
        if ($relativeFile -match '(^|[\\/])(\.user|\.godot|__pycache__)([\\/]|$)') { continue }
        $targetFile = Join-Path $packageRoot ($Name + '\' + $relativeFile)
        New-Item -ItemType Directory -Path (Split-Path -Parent $targetFile) -Force | Out-Null
        Copy-Item -LiteralPath $payloadFile.FullName -Destination $targetFile -Force
    }
}

New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
foreach ($name in @('scripts', 'scenes', 'resources', 'bin', 'assets\actors', 'assets\portraits', 'assets\environments', 'assets\fonts', 'assets\audio', 'assets\ui', 'tests', 'docs\modules')) {
    Copy-PayloadTree $name
}
New-Item -ItemType Directory -Path (Join-Path $packageRoot 'tools') -Force | Out-Null
foreach ($name in $payloadTools) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $packageRoot 'tools') -Force
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'project.godot') -Destination $packageRoot -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'README.md') -Destination $packageRoot -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\GAME_DESIGN.md') -Destination (Join-Path $packageRoot 'docs') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets\icon.svg') -Destination (Join-Path $packageRoot 'assets') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets\GODOT_LICENSE.txt') -Destination $packageRoot -Force
Copy-Item -LiteralPath $GodotPath -Destination (Join-Path $packageRoot 'FantasySiege.exe') -Force
@'
@echo off
start "Star Lantern Expedition" "%~dp0FantasySiege.exe" --path "%~dp0."
'@ | Set-Content -LiteralPath (Join-Path $packageRoot '开始游戏.cmd') -Encoding ascii
@'
星灯远征 · Windows本地学习版
双击“开始游戏.cmd”启动，无需Python、Godot编辑器或网络连接。
战场两屏宽：按住左键拖动、鼠标移到边缘、←/→巡视，点击“跟随战线”回到交战处。
1—8召唤，P星灯脉冲（80能量/35秒冷却），空格暂停，F切换1×/2×，F11全屏，Esc返回营地。
营地“操作指南”可重看；“设置”可调音量、全屏、飘字及边缘滚动。
从300星砂开始，依次远征八关；第2/4/6/8关契约新英魂，星砂用于训练，编队最多八人。
营地“研修”：已契约且Lv.3、首通第四关后，180星砂一次解锁该英魂两条路线，之后免费切换/恢复基础，仅营地。
关卡卡片“敌情”可查看敌军计划出场、加强波次数值、首领反制和已保存编队的战术提醒；未解锁关卡可浏览，仍需按顺序通关后出征。
关闭后重新启动会恢复进度。独立存档位于 %APPDATA%\FantasySiege，不与旧游戏混用。
本包已完成纹理与原生素材导入；请完整保留文件夹，不单独搬动FantasySiege.exe。
D69角色素材仅供本地学习研究，请保留本包在本地，不作商业用途。
Godot Engine https://godotengine.org/license/ (MIT)，完整声明见GODOT_LICENSE.txt。
字体许可见assets/fonts/OFL.txt。声音与背景为本项目原创。
Spine原生运行库与角色素材的商业再分发条件须单独核实，详情见docs/modules/THIRD_PARTY.md。
可复现导入工具及隔离测试随包提供；运行游戏不需要使用它们。
'@ | Set-Content -LiteralPath (Join-Path $packageRoot '使用说明.txt') -Encoding utf8

New-Item -ItemType Directory -Path (Join-Path $packageRoot 'reports') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $packageRoot 'reports\.gdignore') -Value '' -Encoding ascii
$files = foreach ($payloadFile in (Get-ChildItem -LiteralPath $packageRoot -Recurse -File)) {
    [ordered]@{
        path = $payloadFile.FullName.Substring($packageRoot.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
        bytes = $payloadFile.Length
        sha256 = (Get-FileHash -LiteralPath $payloadFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
[ordered]@{
    program_version = $version
    created_utc = [DateTime]::UtcNow.ToString('o')
    source_project = $projectRoot
    package_root = $packageRoot
    source_import_metadata_copied = $false
    files = @($files)
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $packageRoot 'reports\build_manifest.json') -Encoding utf8

# The package imports its own PNGs before the native atlas importer sees them.
& $PythonPath (Join-Path $packageRoot 'tools\bootstrap_local.py') --import-only --godot (Join-Path $packageRoot 'FantasySiege.exe')
if ($LASTEXITCODE -ne 0) { throw 'Portable two-phase import failed; preserve the package reports for diagnosis' }
Write-Output $packageRoot
