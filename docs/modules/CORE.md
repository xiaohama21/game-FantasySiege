# 核心规则与接口

> v0.6 · 2026-11-18 · GDD v0.2.0 / 程序0.1.1.0
> v0.6：64单位测量揭示全表索敌与阻挡扫描瓶颈；改为有序阵线、相邻友军与uid索引，保持玩法结论。
> v0.5：Spine播放倍率独立接口，暂停同步冻结动作，新实例继承视觉倍率；补充64单位逻辑性能验收。
> v0.4：三属性与唯一主属性进入首版；以UnitStats统一计算训练、编队和战斗属性，替代每级10%的旧规则。
> v0.3：固定战斗实例字段、视觉事件与Boss半血阶段；增加阶段数值和预警时间配置。
> v0.2：对攻实现细化，固定逻辑步、召唤/波次、辅助规则及无视觉验证边界。
> v0.1：独立原型核心接口与数据边界。

## 数据

`resources/units.json`：字典，每个ID对应名称、简述、role、visual_id、hp、damage、armor、speed、range、attack_interval、hit_delay、cost、cooldown、damage_type、aoe_radius、special、color。`resources/stages.json`：数组，id/name/subtitle、enemy_base_hp/player_base_hp、initial_energy/income/capacity、rewards、waves（time、unit_id、count、interval、hp_mult/damage_mult）。阶段/素材ID稳定，与名称分离。

`Catalog.units()`/`unit(id)`/`stages()`/`stage(id)`/`initial_roster()`是读取唯一出口。前五保留guanyu/zhaoyun/zhugeliang/diaochan/lubu，新增iron_guard/ember_archer/rune_medic；八名初始可用。规划角色不加入当前初始阵容。

## 对攻

左基地x100，右基地x1180，地面y510；角色自动朝敌方基地走。每步找前方最近的有效敌人，射程内攻击，射程外前进，前排碰撞保持约16px间距。伤害锁定目标及命中延迟，失效目标不重定向；范围攻击按半径结算。死亡退出索敌，再播放Death后回收；基地生命归零一次性终止战斗。治疗只能治疗己方伤员，不能治疗敌方或复活。重启/退出停止并清理全部旧单位/延迟攻击。

伤害类型移植旧DamageTypes：物理取全甲、魔法取半甲并叠加智力魔法护甲、真实忽略；`actual=raw*50/(50+effective_armor)`。每秒自动收入，上限配置；召唤成功才扣费启动独立冷却；人数上限64。测试可固定步进，视觉帧与逻辑互不驱动伤害。

逻辑以1/60秒固定步累计推进；`advance(delta)`与自动帧调用同一入口，暂停时不调用，倍速由调用方放大delta。召唤须在阵容内、能量足够、该型号冷却归零且双方存活实例总数小于64；失败不扣费/不启动冷却。开局单位等级夹紧1–20，生命、攻击、速度、攻速与魔法护甲统一由UnitStats结合力量/敏捷/智力和主属性计算；同型号所有重复召唤使用本局等级快照。入场位置在基地内侧；同阵营密集入场向己方后方排队，前排横向最小间距16px。

波次展开为`time + index * interval`，按时间稳定排序；存活人数已满时推迟入场，不丢掉波次。敌人生命/攻击同时接受该波次倍率，玩家等级不影响敌人。普通攻击锁定前方最近存活敌人；没有单位阻挡才选敌方基地，基地忽略护甲。攻击间隔从出手开始计时，命中在独立逻辑延迟后；命中时目标已死则本次取消，范围伤害也不借死目标转移。每次结算后立即检查胜负，终局取消全部待命中攻击、后续波次和收入，仅发送一次结算信号。

`special`可为字符串或字典（`type`）：`heal`优先选择射程内己方缺血实例，按`amount`或基础攻击治疗，不治疗基地/敌人/死亡单位；没有伤员时可普攻。`cleave`采用`aoe_radius`范围命中；`slow`命中后按`ratio`（默认0.65）和`duration`（默认2秒）减速，重复只延长较长时长并保留更强减速，结束恢复。技能只改变逻辑数据；Spine动作状态不提供伤害回调。

角色死亡立即从活单位计数、阻挡及索敌中剔除，随后保留0.8秒Death与淡出；手动测试可禁用视觉创建，战斗结果必须一致。基地被摧毁后的尸体视觉可在自动帧中完成回收，但不再推进战斗时间。`stop()`立即释放全部实例并清空波次/固定步余量；`start()`先执行stop，避免重开残留。

## 实现接口（协作边界）

`SiegeBattle` Node2D：`start(stage_id:String, roster:Array, levels:Dictionary={})`；`try_summon(id:String)->bool`；`advance(delta:float)`；`get_snapshot()->Dictionary`；`stop()`；属性`auto_step=true`、`units:Array`。信号`battle_finished(victory:bool)`。snapshot包括elapsed/energy/capacity/player_hp/player_max_hp/enemy_hp/enemy_max_hp/cooldowns/active_count/outcome（running/victory/defeat）。

`SpineActor` Node2D：`configure(visual_id:String, facing:int=1)`；`play_state(state:String, duration:float=0.0)`；`using_spine()->bool`。动画状态idle/move/attack/skill/hurt/death。配置可在入树前或入树后；缺库/数据用可见占位，不影响战斗。`resources/visuals.json`字典含data/skin/scale/foot/native_facing/animations/durations/source_id/root_motion_*；共享Resource缓存，每实例独立骨架。

主界面场景`scenes/Main.tscn`挂`scripts/ui/Main.gd`：章节/关卡、八角色编队/训练、素材浏览器（选择编号、动作、朝向）、战斗HUD、召唤卡、速度/暂停/重开/返回、胜负结算。玩家界面不暴露兼容技术细节，素材工具单独浏览页。

## 存档

新`user://profile.json`结构schema1、credits、levels、cleared、roster。临时文件+备份，成功后内存提交；败局零收益。奖励只能对一次有效战斗会话提交；测试可设置独立目录。升级资源不足无变动，保存失败不扣费。原项目存档不读取/迁移。

## 验证

Godot解析导入、战斗推进和胜负、资源/冷却边界、死亡目标安全、重开清理、伤害/治疗、存档写盘失败及备份恢复、素材逐套原生加载/动画/朝向、真机截图、64单位性能测量。正式关卡平衡以当前原型实测为准，规划关卡另验收。

战斗独立验收脚本`tests/BattleSmoke.gd`覆盖固定步、召唤边界、护甲三类型、治疗、失效目标、重复终局信号与重开清理，并分别运行三关自动召唤和不召唤败局；`reports/battle_smoke.json`记录时长/基地剩余生命/胜负。`render_visuals=false`仅证明逻辑不依赖Spine，不能标记原生加载或素材验收通过。

### 实例与表现事件

`units` 为字典数组，稳定 `uid` 与内容 `id` 分离。`team` 为1（玩家）或-1（敌军）；`x/hp/max_hp/damage/armor/range/speed/attack_timer/alive/visual` 用于调试与表现。视觉只跟随逻辑x，脚底统一y510；死亡立即设置alive=false，待0.8秒淡出后回收。`combat_event(kind:String, position:Vector2, amount:float, team:int)` 通知attack/hit/heal/death/phase/base_hit，供HUD音效与粒子，不能从该事件再次造成伤害。snapshot附加stage_id、wave_pending。

Boss 的 `special` 字典可包含 `phase_threshold`（生命比例，默认不启用）、`phase_damage_mult`、`phase_speed_mult`、`phase_attack_mult` 与 `phase_name`。第一次跨过阈值时只触发一次；伤害和速度乘对应倍率，攻击间隔乘倍率（如0.8为加快），发phase预警事件。重击的 `hit_delay` 是玩家可见出手到命中的窗口，范围仍由aoe_radius决定。首版半血阶段不额外召唤小兵、不重置生命，换阵容与召唤节奏为主要反制。

### 三属性与中央计算（用户2026-11-18定稿）

每个单位配置 `attributes` 字典（strength/agility/intelligence），`primary_attribute` 为其中恰好一个键，`attribute_growth` 为三个键的每级增量。缺失属性默认0，缺失成长默认主属性+2/级、副属性+1/级；等级夹紧1–20。最终属性 `stats=attributes+(level-1)*growth`。主属性标签由`UnitStats.primary_label()`返回“力量/敏捷/智力”。

`UnitStats.calculate(unit, level)`为唯一计算出口，返回stats/hp/damage/attack_interval/speed/magic_armor/heal_multiplier/level/primary。HP=baseHP×[1+0.06×(lv−1)]×(1+0.015×力量)；攻击=baseDMG×[1+0.05×(lv−1)]×(1+0.012×主属性)；攻击间隔=baseInterval÷(1+0.004×敏捷)；移速=baseSpeed×(1+0.003×敏捷)。物理有效护甲=基础护甲，魔法有效护甲=基础护甲×0.5+智力×0.6，真实伤害忽略。治疗量和减速时长额外乘(1+0.01×智力)。数据中的hp/damage/attack_interval/speed均为属性计算前基础值，界面展示最终值。

所有玩家出战实例从本局等级快照计算；敌人默认等级1并经过同一计算，再应用波次hp_mult/damage_mult，不乘玩家等级、不叠加旧10%成长。属性培养当前随等级自动成长，主属性由角色身份固定，首版没有属性洗点或自由加点。

### 暂停、倍速与性能

`SiegeBattle.set_visual_playback(multiplier)`仅设置视觉动作速率（0暂停，1正常，2倍速），遍历已存在SpineActor并调用set_playback_speed；后续召唤和敌波次新建的视觉继承该倍率。逻辑暂停由调用方停止advance，逻辑倍速由调用方放大delta；两者必须同时设置，不能只冻结UI或动画。结束战斗后的尸体淡出也按视觉倍率推进，0时冻结。逻辑命中时点始终由固定步hit_delay独立控制。

64活单位性能测试在关闭视觉的独立进程中记录推进5秒的CPU墙钟、每逻辑步耗时与实际单位峰值；这只是逻辑性能，不替代64套原生Spine的显卡/动画性能测量。敌人波次保持稳定时间顺序，达到64上限后暂停发送首个待出波次，空出名额后再补发，不允许跳过较早波次。

每个固定步按双方x位置建立从前到后的有序阵线。索敌从敌方前线开始，取首个有效前方目标；友軍阻挡缓存同阵线的前一个单位，前排先推进，因此后排使用其本步新位置。稳定uid字典负责延迟攻击目标查询，死亡后保留至尸体回收，命中仍检查alive。此优化只改变查询成本，不改变射程、间距、命中、死亡或波次规则；须用相同帧分组、三关结果与人数边界回归。
