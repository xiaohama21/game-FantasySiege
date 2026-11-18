# 核心规则与接口

> v0.13 · 2026-11-18 · GDD v0.3.2 / 程序0.1.2.0
> v0.13：固定步保持世界坐标，视觉位置在advance末尾合并同步一次，静止位置不重复跨原生桥接；状态与命中仍按原固定步。
> v0.12：最终wide-tail-1八关、四核心养成与脉冲收益通过120项验收；冻结平衡并如实记录较慢案例。
> v0.11：同步schema2拥有/首通/重访接口与旧schema1解锁迁移，角色收集与八槽阵容职责明确。
> v0.10：完整64压力fixture采用十万生命稳定样本，保持真实攻击/状态/骨架处理，区分调试压力与关卡平衡。
> v0.9：完整出手动作的视觉保持时间独立于逻辑命中延迟，避免短hit_delay提前截断攻击。
> v0.8：用户定稿两屏宽地图与固定HUD，基地/前线/事件使用世界坐标；新增明确的真实战斗压力fixture接口。
> v0.7：八关与十二英魂、星灯脉冲晕眩/后推/打断、攻城倍率、关键骨架降频及完整战斗性能接口先行。
> v0.6：64单位测量揭示全表索敌与阻挡扫描瓶颈；改为有序阵线、相邻友军与uid索引，保持玩法结论。
> v0.5：Spine播放倍率独立接口，暂停同步冻结动作，新实例继承视觉倍率；补充64单位逻辑性能验收。
> v0.4：三属性与唯一主属性进入首版；以UnitStats统一计算训练、编队和战斗属性，替代每级10%的旧规则。
> v0.3：固定战斗实例字段、视觉事件与Boss半血阶段；增加阶段数值和预警时间配置。
> v0.2：对攻实现细化，固定逻辑步、召唤/波次、辅助规则及无视觉验证边界。
> v0.1：独立原型核心接口与数据边界。

## 数据

战斗位置为actor.x的世界坐标，不能依赖Node2D读回。每次advance可执行多个60Hz固定步；行军只改actor.x，末尾按缓存render_x一次同步实际变化的视觉位置。新实例、调试fixture和手动脉冲立即设置位置并更新缓存。状态、动画播放时点、逻辑命中和晕眩不延后；不丢固定步和时间。

`resources/units.json`：字典，每个ID对应名称、简述、role、visual_id、hp、damage、armor、speed、range、attack_interval、hit_delay、cost、cooldown、damage_type、aoe_radius、special、color。`resources/stages.json`：数组，id/name/subtitle、enemy_base_hp/player_base_hp、initial_energy/income/capacity、rewards、waves（time、unit_id、count、interval、hp_mult/damage_mult）。阶段/素材ID稳定，与名称分离。

`Catalog.units()`/`unit(id)`/`stages()`/`stage(id)`/`initial_roster()`/`playable_roster()`是读取唯一出口。前五保留guanyu/zhaoyun/zhugeliang/diaochan/lubu，新增iron_guard/ember_archer/rune_medic；八名初始可用。初始八名不变；0.1.2新增四名首通解锁角色，playable_roster列出全部十二玩家型号，敌人不进入该集合。战斗start仅接受playable_roster中的玩家ID，是否已拥有由ProfileStore与UI校验。

## 对攻

两屏世界默认左基地x100，右基地x2460，地面y510（实际按关卡world_width动态确定）；角色自动朝敌方基地走。每步找前方最近的有效敌人，射程内攻击，射程外前进，前排碰撞保持约16px间距。伤害锁定目标及命中延迟，失效目标不重定向；范围攻击按半径结算。死亡退出索敌，再播放Death后回收；基地生命归零一次性终止战斗。治疗只能治疗己方伤员，不能治疗敌方或复活。重启/退出停止并清理全部旧单位/延迟攻击。

伤害类型移植旧DamageTypes：物理取全甲、魔法取半甲并叠加智力魔法护甲、真实忽略；`actual=raw*50/(50+effective_armor)`。每秒自动收入，上限配置；召唤成功才扣费启动独立冷却；人数上限64。测试可固定步进，视觉帧与逻辑互不驱动伤害。

逻辑以1/60秒固定步累计推进；`advance(delta)`与自动帧调用同一入口，暂停时不调用，倍速由调用方放大delta。召唤须在阵容内、能量足够、该型号冷却归零且双方存活实例总数小于64；失败不扣费/不启动冷却。开局单位等级夹紧1–20，生命、攻击、速度、攻速与魔法护甲统一由UnitStats结合力量/敏捷/智力和主属性计算；同型号所有重复召唤使用本局等级快照。入场位置在基地内侧；同阵营密集入场向己方后方排队，前排横向最小间距16px。

波次展开为`time + index * interval`，按时间稳定排序；存活人数已满时推迟入场，不丢掉波次。敌人生命/攻击同时接受该波次倍率，玩家等级不影响敌人。普通攻击锁定前方最近存活敌人；没有单位阻挡才选敌方基地，基地忽略护甲。攻击间隔从出手开始计时，命中在独立逻辑延迟后；命中时目标已死则本次取消，范围伤害也不借死目标转移。每次结算后立即检查胜负，终局取消全部待命中攻击、后续波次和收入，仅发送一次结算信号。

`special`可为字符串或字典（`type`）：`heal`优先选择射程内己方缺血实例，按`amount`或基础攻击治疗，不治疗基地/敌人/死亡单位；没有伤员时可普攻。`cleave`采用`aoe_radius`范围命中；`slow`命中后按`ratio`（默认0.65）和`duration`（默认2秒）减速，重复只延长较长时长并保留更强减速，结束恢复。技能只改变逻辑数据；Spine动作状态不提供伤害回调。

角色死亡立即从活单位计数、阻挡及索敌中剔除，随后保留0.8秒Death与淡出；手动测试可禁用视觉创建，战斗结果必须一致。基地被摧毁后的尸体视觉可在自动帧中完成回收，但不再推进战斗时间。`stop()`立即释放全部实例并清空波次/固定步余量；`start()`先执行stop，避免重开残留。

## 实现接口（协作边界）

`SiegeBattle` Node2D：`start(stage_id:String, roster:Array, levels:Dictionary={})`；`try_summon(id:String)->bool`；`advance(delta:float)`；`get_snapshot()->Dictionary`；`stop()`；属性`auto_step=true`、`units:Array`。信号`battle_finished(victory:bool)`。snapshot包括elapsed/energy/capacity/player_hp/player_max_hp/enemy_hp/enemy_max_hp/cooldowns/active_count/outcome（running/victory/defeat）。

`SpineActor` Node2D：`configure(visual_id:String, facing:int=1)`；`play_state(state:String, duration:float=0.0)`；`using_spine()->bool`。动画状态idle/move/attack/skill/hurt/death。配置可在入树前或入树后；缺库/数据用可见占位，不影响战斗。`resources/visuals.json`字典含data/skin/scale/foot/native_facing/animations/durations/source_id/root_motion_*；共享Resource缓存，每实例独立骨架。

主界面场景`scenes/Main.tscn`挂`scripts/ui/Main.gd`：章节/关卡、十二角色收集/最多八角色编队/训练、素材浏览器（选择编号、动作、朝向）、战斗HUD、召唤卡、速度/暂停/重开/返回、胜负结算。玩家界面不暴露兼容技术细节，素材工具单独浏览页。

## 存档

新`user://profile.json`当前结构schema2、credits、levels、cleared、owned、roster、transactions。临时文件+备份，成功后内存提交；败局零收益。第2/4/6/8关首通各解锁一个角色、只发一次first_clear_credits，重访保留rewards.credits。旧FantasySiege schema1根据cleared回补已达成的owned及等级1，不补发首通货币；不读取旧TowerDefense存档。较新的主档或备份schema仅可浏览，不能降级覆盖。奖励只能对一次有效战斗会话提交；测试可设置独立目录。升级资源不足、未拥有角色、未知ID或保存失败均不扣费。

## 验证

Godot解析导入、战斗推进和胜负、资源/冷却边界、死亡目标安全、重开清理、伤害/治疗、存档写盘失败及备份恢复、素材逐套原生加载/动画/朝向、真机截图、64单位性能测量。正式关卡平衡以当前原型实测为准，规划关卡另验收。

战斗独立验收脚本`tests/BattleSmoke.gd`覆盖固定步、召唤边界、护甲三类型、治疗、失效目标、重复终局信号与重开清理，并分别运行八关推荐等级自动召唤和不召唤败局，附第4/6/8关仅四核心成长案例；`reports/battle_smoke.json`记录时长/基地剩余生命/胜负。`render_visuals=false`仅证明逻辑不依赖Spine，不能标记原生加载或素材验收通过。

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

### 0.1.2 星灯脉冲与八关验收

`try_pulse()->bool`：运行中且存在存活敌军、80能量足够、35秒全局冷却为0才成功；无目标、冷却/能量不足或终局失败，不扣能量、不启动冷却。暂停由主界面停止advance并拒绝P/按钮调用。snapshot提供pulse_cost=80与pulse_cooldown剩余秒数；start/stop重置为0。

脉冲锁定最靠近玩家基地（x最小）的存活敌军为中心，在其180px范围内对全部敌军造成90真实伤害；先取消这些敌军所有待结算攻击，再对仍存活者施加1.2秒晕眩，并将其逻辑x向右后推60px。带phase_threshold的Boss仅后推15px（25%），伤害与晕眩时长不缩减。晕眩期间停止移动和开始攻击；攻击、减速及晕眩计时仍按60Hz安全推进，结束后恢复正常索敌。死亡单位不被晕眩或后推。被后推的单位立即更新视觉位置，重新排列同阵营索引；脉冲与骨架动画事件无伤害耦合。

`combat_event("pulse", center, 180, 1)`通知环形冲击，`combat_event("stun", unit_position, 1.2, -1)`通知晕眩效果。新属性stun_timer与pulse_cooldown只由逻辑步推进，暂停不改变。Boss尚未命中的0.75秒重击可被脉冲明确打断；pulse成功后即使UI事件重入也不能重复扣费或重复生效。

攻城角色的special字典可配置base_damage_multiplier（默认1），仅在命中敌方基地时乘其最终攻击，不影响单位伤害、AoE、治疗或伤害类型。首版不引入角色无限晕眩，月灯术士仍使用现有范围减速，星灯脉冲承担即时打断手段。

战斗验收扩为两章八关。每关混合召唤采用该关recommended_level本局等级快照（前三关等级1，后续2–4），所有关卡空阵线均应失败；原三关的固定步、胜负、目标生命周期和资源边界保持回归。单独验证脉冲无目标/能量/CD/终局失败、真实范围伤害、Boss15px、1.2秒晕眩、预警攻击取消、资源单次提交、晕眩到期与冷却到期。

### 0.1.2 关键骨架更新

每0.5逻辑秒按接敌距离、出手状态与Boss优先级挑选最多十二个关键存活实例，调用SpineActor.set_update_rate(60)；其余存活/尸体实例为30Hz，新实例默认30Hz。移动位置、碰撞、状态与伤害继续60Hz更新；降低骨架更新频率不降低战斗步或丢弃攻击。播放倍率0/1/2仍由set_visual_playback独立控制，暂停不补走停下期间的骨架时钟。

性能场景必须加载真实SiegeBattle与SpineActor并保留实际攻击/伤害/死亡/状态，再测HUD和渲染；记录实际活单位数、原生骨架数和1×/2×倍率。既有render_visuals=false的logic_performance只证明CPU逻辑，不能写成全场景帧率。

### 0.1.2 两屏宽地图与世界坐标

关卡world_width默认2560，player_x默认100，enemy_x默认world_width−100；三个坐标在start时按该关配置确定，不再硬编码右基地1180。snapshot增加world_width/player_x/enemy_x/frontline_x，所有出生点、基地命中、攻击目标、脉冲后推、生命条及combat_event为世界坐标。Root把Backdrop与Battle挂在world_host下移动，HUD固定，鼠标与左右键平移由Root处理，战斗不引入Camera2D依赖。

frontline_x：取最前存活玩家的max_x（无玩家则player_x）；若最近敌军min_x与该玩家前线距离≤900，则返回两线中点，否则返回玩家前线+100，并夹在两基地范围内。远敌未接近时不把镜头跳到空地图中央。stage.move_speed_multiplier（默认1.35）同时乘双方UnitStats最终移速，首轮内容设1.45，基础角色详情仍显示中央计算的单位移速。

后推只增加敌方x，夹至world_width−32的地图边缘；已在边缘之外的队列单位不会被反向拉回。普通兵目标位移60px，Boss15px；挤压后重建有序阵线，后续移动仍按16px最小间距恢复。世界变宽不改变攻击射程、脉冲半径或固定步命中语义。

`seed_performance_units(count:int=24)->bool`为明显标记的调试fixture：只在running战斗使用，清空旧单位/待命中/波次，保留关卡与HUD，绕过玩家费用放置双方各半在世界中央交战线。玩家循环当前阵容，敌军循环全部敌方定义；HP/max_hp统一提高至至少100000以保持稳定压力，攻击与伤害/死亡/状态/Spine逻辑正常执行。该测试不代表正式关卡平衡或普通玩家阵容；性能报告必须注明fixture和真实活单位/native数，不能只报名义count。正常玩家流程不调用此接口。

攻击/治疗的action_timer只控制视觉动作保持，命中仍在hit_delay按固定步结算。视觉保持取现成动作自然时长与attack_interval×0.85的较小值，上限1.2秒，且不短于hit_delay；即使动作较长也不能改变冷却、推迟伤害或阻塞再次出手。逻辑再次攻击若仍处于同一动作状态，先切idle再重播，避免SpineActor的同状态保护使高攻速单位无法启动新动作。短命中延迟不再直接把整段攻击压缩到0.25秒。


ProfileStore.owns(id)校验playable且在owned中；upgrade和set_roster都拒绝未拥有或未知型号。stage_unlocked按required_stage校验章节前置，begin_run不能跳过锁定关卡。reward_preview返回base_credits/bonus_credits/first_clear/unlock_units，结算win成功后last_award给UI展示本次所得。角色解锁与金币奖励在同一写盘事务中提交，写盘失败不部分解锁。当前roster最多八不同ID，收集列表可含十二拥有角色，收集完成不自动替换阵容。

### 0.1.2 逻辑验收结果（wide-tail-1）

`reports/battle_smoke.json`最终120项断言全部通过，含三属性、固定步、死亡目标、治疗、范围/减速、阶段/终局单次、64上限与延期波次、宽地图/玩家身份、脉冲资源/范围/晕眩/后推/打断/到期、新四角色与视觉优先级上限。报告包含units/stages SHA256，历史首版与本轮基线分别留在battle_smoke_0.1.1.0.json、battle_smoke_0.1.2_baseline.json。

推荐等级下8关混合队伍均胜利（秒）：126.7、129.7、174.2、204.6、241.5、246.6、267.9、208.3；所有空阵线均失败。仅四核心（铁卫/烬羽射手/符文医师/关羽）升至推荐等级、其他角色等级1时，第4/6/8关仍分别204.2、219.2、298.9秒胜利。第8低投入队伍约4分59秒，较慢但无需刷取硬门槛；可选培养绞弩提高攻城效率，不虚称所有阵容都2–4分钟。

0.75秒Boss重击在0.2秒发动脉冲可实际避免128.2前排伤害；64活单位无视觉逻辑测量5秒模拟377.7ms、每步约1.26ms。视觉优先级测试使用Mock Node2D只证明最多12关键实例，不能替代Spine原生调用验收。真实HUD/世界/64骨架的帧率与尾帧由独立完整战斗性能脚本测量并单独报告。
