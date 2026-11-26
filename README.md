# 幻域对攻（FantasySiege）

独立Godot架空魔幻PvE对攻项目。新目录/仓库/缓存/存档与原《烽火连营》隔离。

## 当前状态

Windows 学习包内可直接双击同目录的 **开始游戏.cmd**。以下路径和验收记录以源码仓库为起点，随包 README 是构建时的快照。

- 当前本地学习包为 **0.1.3.0 候选15**（GDD v0.5.14，分支 `0.1.3`）。[双击开始游戏](exports/windows/FantasySiege-0.1.3.0-candidate-15/开始游戏.cmd)。

- 候选15从干净检出完成十阶段制作，在上述目录自行导入并通过9056项后台检查、59张界面取景和993项章节旅程检查。八关首通后重启读档，12名英魂与全部通关进度恢复，重访末关后余额2840星砂。8种启动隔离场景通过，验包报告的规范版本及哈希与同包文档一致。前台操作、24/64人及双倍速性能、人工听感待验。[候选15验收报告](reports/learning_candidate_0.1.3.json)。
- 保留关羽、赵云、诸葛亮、貂蝉、吕布；其他角色及敌人从Spine重新设计。
- 十二英魂、九种敌军、两章八关；四次首通解锁、首通/重访收益、三属性训练、八人编队、schema1/2至3迁移与独立存档已完成。
- 星灯远征美术体系；所有角色拥有力量、敏捷、智力与一个主属性。
- 当前D69素材用于本地学习开发验证，保留原声明，未视为商用授权。
- 0.1.3引导、音效、独立设置、中文百科、十二肖像、分层环境与十二英魂双路线研修已实现。candidate-6包内八CPU共3351项、原生21套/220动作、2624次零差像素对比、32张界面图和988项完整旅程通过。正常前台流程与战斗性能按用户安排待后续；candidate-4/5保留各自冻结范围。
- 八关战前敌情、19枚原创属性/战术图标和统一属性格已实现；英魂/研修/编队/召唤卡同步精简。candidate-7包内CPU10/8147项、Art50/6253项、原生21/220及2624次零差对比、完整旅程988项通过；前台流程/性能仍延期。
- 结算有效战报、领奖重试回执、敌情/编队导航及图鉴最终治疗/首领阶段已完成。candidate-8包内CPU12/8558项、Art54/6973项、旅程988项与原生/像素验证通过；正常前台流程与性能继续待验。

- 干净检出04244668已从源包完整重建角色/十二头像并自行构建学习包：CPU12/8558、Art54/6973、旅程988通过。105原文件、4运行库和旧工程336文件保持不变；证据见reports/rebuild_candidate_0.1.3.json，前台/性能仍延期。

- 历史字体增量（candidate9）：按用户反馈改为Noto Sans SC正文400、标题/按钮/数字600。candidate-9包内CPU12/8558、Art54/13087零缺字溢出、旅程988及原生/像素检查通过，启动exports/windows/FantasySiege-0.1.3.0-candidate-9/开始游戏.cmd；证据reports/font_candidate_0.1.3.json。该次网络同步失败，之后的程序修复已同步，前台/性能仍延期。

- 历史界面导航增量（candidate11）：CPU12/8919、Art56/13639、旅程988及原生/像素范围通过，历史启动exports/windows/FantasySiege-0.1.3.0-candidate-11/开始游戏.cmd。证据reports/navigation_candidate_0.1.3.json；该候选首次自动加载/引擎日志隔离缺口当时待补，candidate13已补齐，前台与性能未验收。

总纲：[docs/GAME_DESIGN.md](docs/GAME_DESIGN.md)，排期：[ROADMAP](docs/modules/ROADMAP.md)，角色/敌人/素材/关卡关联：[CONTENT_PLAN](docs/modules/CONTENT_PLAN.md)，双路线规则：[TRAINING](docs/modules/TRAINING.md)，战前准备：[BATTLE_BRIEFING](docs/modules/BATTLE_BRIEFING.md)。0.1.3继续完整体验开发及学习包验收。

## 本地运行

已接入素材的本机：Godot4.7.1打开`project.godot`运行，或执行`tools/play.ps1`。从Git克隆后需要本地D69学习源包与Spine原生库，运行`tools/bootstrap_local.ps1`；这些受限依赖有意排除Git，详见[THIRD_PARTY](docs/modules/THIRD_PARTY.md)。

完整重建须提供Godot：`python tools/bootstrap_local.py --source-root <本地D69目录> --runtime-from <只读Spine运行库bin目录> --godot <Godot控制台exe>`。工具完成21套转换、原生作者验证、十二透明肖像制作/导入及冻结后的只读复核，任何一步失败均停止并保留reports/bootstrap_local.json证据。省略--godot只完成转换；--import-only只导入已经存在的素材。生成完成后执行`tools/build_local.ps1 -Destination <本项目exports/windows下的新空目录>`，包使用自己的缓存，保留旧候选。

在 Windows 学习包内，双击与本说明同目录的 **开始游戏.cmd**。包自带 Godot，保留整个文件夹即可离线游玩。玩家存档位于 `%APPDATA%\FantasySiege`；验收从首次加载就使用项目内的 `tests/.user` 和独立引擎日志。源码检出的本机包入口见上方“当前状态”。

历史基础包 `0.1.1.2` 和候选4至14保留各自的验收记录。候选13的[首次启动隔离](reports/startup_candidate_0.1.3.json)、候选14的[干净制作](reports/guide_authoring_0.1.3.json)、[包内验收](reports/guide_package_0.1.3.json)及[指南目检](reports/guide_visual_review_0.1.3.json)可独立追溯。

源码工程包含`play.ps1`、`bootstrap_local.ps1`及`build_local.ps1`；这些源码命令不是包内启动步骤。包内`tools`提供Python制作/验收工具，完整制作需要另提供本地学习源包/运行库，运行游戏无需调用。后台复验可在本包根目录执行`python tools/verify_package.py --package <本包绝对目录> --phase background`或`--phase offscreen`；不得把这两个阶段当作前台完整验收。

战场宽2560px、视野1280px；鼠标左键拖动、边缘移动或←/→巡视，点击“跟随战线”恢复自动跟随。1—8召唤、P释放星灯脉冲、空格暂停、F切换1×/2×、Esc返回营地。营地可训练、调整编队和查看已导入素材动作。第2/4/6/8关首通各契约一名新英魂；通关依次解锁下一关；新存档有300星砂，训练只在写盘成功后扣除。

营地“研修”：已契约且Lv.3、首通第四关后，180星砂一次解锁该英魂两条路线；之后免费切换或恢复基础。每条路线都有收益与代价，基础八关不要求研修。

## 验证

- BattleSmoke：120项通过，八关推荐队伍能获胜，不出兵均失败；四核心养成足够完成后期，脉冲可实际打断重击。
- ProfileSmoke：24项通过，包含重复领取、写盘失败、损坏主档恢复与未来schema保护。
- ProgressionSmoke：34项通过，包含schema1迁移、拥有权与首通/重访收益。
- MainFlow（0.1.2历史范围）：96项通过，含两屏摄像机、固定HUD、两次实际胜利和首通角色、失败结算重试及八张真实截图；当前0.1.3正常前台复验尚未完成。
- 315素材盘点；21套来源资产（20导出名家族）220原始动画原生探针通过，0/1/2倍率和暂停验证通过。
- 64单位纯逻辑约1.26ms/步；骨架错峰采样后的64压力场景已改善，完整战斗性能正在最终优化，实测报告保留所有历史失败。
- 旧项目336个文件哈希及Git状态保持不变，证据见docs/reviews/source_verification.json。
- Windows便携包0.1.1.2：全体战场实例真实Spine、13套135原始动作、流程和截图通过；已修复源导入记录指向缺缓存造成的静默空骨架。
