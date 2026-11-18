# 核心规则与接口

> v0.1 · 2026-11-18 · GDD v0.1.0 / 程序0.1.1.0

## 数据

`resources/units.json`：字典，每个ID对应名称、简述、role、visual_id、hp、damage、armor、speed、range、attack_interval、hit_delay、cost、cooldown、damage_type、aoe_radius、special、color。`resources/stages.json`：数组，id/name/subtitle、enemy_base_hp/player_base_hp、initial_energy/income/capacity、rewards、waves（time、unit_id、count、interval、hp_mult/damage_mult）。阶段/素材ID稳定，与名称分离。

`Catalog.units()`/`unit(id)`/`stages()`/`stage(id)`/`initial_roster()`是读取唯一出口。前五保留guanyu/zhaoyun/zhugeliang/diaochan/lubu，新增iron_guard/ember_archer/rune_medic；八名初始可用。规划角色不加入当前初始阵容。

## 对攻

左基地x100，右基地x1180，地面y510；角色自动朝敌方基地走。每步找前方最近的有效敌人，射程内攻击，射程外前进，前排碰撞保持约16px间距。伤害锁定目标及命中延迟，失效目标不重定向；范围攻击按半径结算。死亡退出索敌，再播放Death后回收；基地生命归零一次性终止战斗。治疗只能治疗己方伤员，不能治疗敌方或复活。重启/退出停止并清理全部旧单位/延迟攻击。

伤害类型移植旧DamageTypes：物理取全甲、魔法取半甲、真实忽略；`actual=raw*50/(50+effective_armor)`。每秒自动收入，上限配置；召唤成功才扣费启动独立冷却；人数上限64。测试可固定步进，视觉帧与逻辑互不驱动伤害。

## 实现接口（协作边界）

`SiegeBattle` Node2D：`start(stage_id:String, roster:Array, levels:Dictionary={})`；`try_summon(id:String)->bool`；`advance(delta:float)`；`get_snapshot()->Dictionary`；`stop()`；属性`auto_step=true`、`units:Array`。信号`battle_finished(victory:bool)`。snapshot包括elapsed/energy/capacity/player_hp/player_max_hp/enemy_hp/enemy_max_hp/cooldowns/active_count/outcome（running/victory/defeat）。

`SpineActor` Node2D：`configure(visual_id:String, facing:int=1)`；`play_state(state:String, duration:float=0.0)`；`using_spine()->bool`。动画状态idle/move/attack/skill/hurt/death。配置可在入树前或入树后；缺库/数据用可见占位，不影响战斗。`resources/visuals.json`字典含data/skin/scale/foot/native_facing/animations/durations/source_id/root_motion_*；共享Resource缓存，每实例独立骨架。

主界面场景`scenes/Main.tscn`挂`scripts/ui/Main.gd`：章节/关卡、八角色编队/训练、素材浏览器（选择编号、动作、朝向）、战斗HUD、召唤卡、速度/暂停/重开/返回、胜负结算。玩家界面不暴露兼容技术细节，素材工具单独浏览页。

## 存档

新`user://profile.json`结构schema1、credits、levels、cleared、roster。临时文件+备份，成功后内存提交；败局零收益。奖励只能对一次有效战斗会话提交；测试可设置独立目录。升级资源不足无变动，保存失败不扣费。原项目存档不读取/迁移。

## 验证

Godot解析导入、战斗推进和胜负、资源/冷却边界、死亡目标安全、重开清理、伤害/治疗、存档写盘失败及备份恢复、素材逐套原生加载/动画/朝向、真机截图、64单位性能测量。正式关卡平衡以当前原型实测为准，规划关卡另验收。
