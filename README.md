# 幻域对攻（FantasySiege）

独立Godot架空魔幻PvE对攻项目。新目录/仓库/缓存/存档与原《烽火连营》隔离。

## 当前状态

- GDD v0.2.2；程序0.1.1.1，首版开发分支0.1.1。
- 保留关羽、赵云、诸葛亮、貂蝉、吕布；其他角色及敌人从Spine重新设计。
- 八名角色、五种敌军、三关可玩；13套真实Spine，三属性、训练、编队、关卡解锁、胜负结算和独立存档已完成。
- 星灯远征美术体系；所有角色拥有力量、敏捷、智力与一个主属性。
- 当前D69素材用于本地学习开发验证，保留原声明，未视为商用授权。

总纲：[docs/GAME_DESIGN.md](docs/GAME_DESIGN.md)，排期：[ROADMAP](docs/modules/ROADMAP.md)，完整角色/敌人/素材/关卡关联：[CONTENT_PLAN](docs/modules/CONTENT_PLAN.md)。首版是可运行基础，收集解锁和完整章节在后续编号持续推进。

## 本地运行

已接入素材的本机：Godot4.7.1打开`project.godot`运行，或执行`tools/play.ps1`。从Git克隆后需要本地D69学习源包与Spine原生库，运行`tools/bootstrap_local.ps1`；这些受限依赖有意排除Git，详见[THIRD_PARTY](docs/modules/THIRD_PARTY.md)。

本机便携学习包：`exports/windows/FantasySiege-0.1.1.1/开始游戏.cmd`，自带Godot，无需另外安装。包内程序经过真实Spine/训练/编队/暂停/倍速/重开截图验证；包仅本地保留。重新生成执行`tools/build_local.ps1`。

鼠标点击召唤卡；1—8召唤、空格暂停、F切换1×/2×、Esc返回营地。营地可训练、调整编队和查看已导入素材动作。通关依次解锁下一关；新存档有300星砂，训练只在写盘成功后扣除。

## 验证

- BattleSmoke：59项通过，三关一级混合队伍能获胜，不出兵均失败。
- ProfileSmoke：23项通过，包含重复领取、写盘失败、损坏主档恢复与未来schema保护。
- MainFlow：训练/编队/真Spine图鉴/暂停/倍速/重开/返回与五页截图通过。
- 315素材盘点；13套非空原生动画探针通过，视觉抽检独立记录。
- 64单位逻辑约1.93ms/步；GTX1050下64骨架视觉约38fps，完整战斗性能将继续优化验收。
- 旧项目336个文件哈希及Git状态保持不变，证据见docs/reviews/source_verification.json。
- Windows便携包0.1.1.1：等待真实引擎进程退出并拒绝错误日志；独立包内MainFlow运行通过。
