# 战前敌情与编队准备

> v0.2 · 2026-11-19 · GDD v0.5.6 / 程序0.1.3.0
> v0.2：用户反馈信息混乱；按敌軍独立卡片、图标属性格、战术短词条与醒目Boss反制重排，必要中文和中央数值常显。
> v0.1：用户继续开发并延期前台性能；在现有八关内加入只读敌情、实际波次与研修编队建议，沿用原出征和存档权限。

每张远征关卡卡片提供“敌情”入口。未抵达的关卡也可浏览，出征仍由stage_unlocked和can_modify决定；不借浏览领取奖励、补等级、改编队或写盘。独立准备页显示关卡名、推荐等级、基地生命、初始能量/恢复/容量，以及返回远征、调整编队、出征按钮。不替换直接出征入口。返回保持原章节；设置/指南覆盖时，底层按钮仍受Main模态保护。

BattleBriefing为只读RefCounted数据服务。summarize(stage_id)将实际waves按战斗相同规则展开：count不小于0，出场时间max(0,time+index*max(0,interval))，同时间按原配置顺序排序。出场时刻为配置的计划时间，不是抵达我方基地的时间；64活单位上限可能延后实际入场，页面明确提示。按敌军ID分组，登记总数、最早/最晚计划出场；同ID不同hp_mult/damage_mult单独列数值配方，不用基础值代表加强波次。敌方固定Lv1、空玩家研修，波次倍率使用UnitStats.modifier_value的边界与UnitStats.calculate唯一计算；阵容、技能、护甲、魔抗、前摇和Boss阶段说明均读取同一结果。

敌军名、中文职责、技能名称和counter_hint读取units.json，不露出开发来源编号。敌军卡片列各配方人数、生命/伤害、物理护甲/魔抗、射程/前摇/范围，以及实际控制或Boss阶段规则。Boss展示触发生命比例、阶段名、伤害/间隔/速度倍率；P脉冲的80能量、35秒冷却、打断前摇和Boss推退减弱使用现有战斗常量与规则。不可把建议或基础八关通关证明写成特定阵容必胜。

信息分三级：敌军名字/人数和威胁词条最醒目，属性六格以原创SVG和短中文标签显示生命、伤害、护甲、魔抗、射程、前摇，计划时段与附加技能为次级内容。同一属性只出现一次；范围攻击用单一“范围”词条及半径，不再重复单体/范围技能段落。每个敌軍卡片底部仅留一组配置化应对短词条；Boss另有琥珀阶段块和P打断提示，不能靠颜色或tooltip独占必要含义。不同配方仍分别显示人数及完整数值，不省略加强敌軍。配置中的enemies只承载tags/counters中文表现，不改变单位技能和战斗。

右栏用紧凑编队清单和带图标的建议卡片。“已配备”采用青绿状态，“可补充”采用琥珀状态；同一能力以统一词条、图标、简短本关原因和合法候选表示，不重复整段缺口/候选名字。P脉冲使用单独的操作卡片常显能量/冷却和反制重点。英魂详情与研修中的重复属性句亦逐步改用同一属性图标组件，编队与HUD采用相同能量、冷却、职责标识；保持三属性与主属性、技能关键值和规则的中文可读性。页面底部提示区仍与固定按钮分离。

编队准备读取当前成功保存的一至八名英魂、等级和研修路线，逐人以UnitStats.calculate计算最终值。resources/briefings.json登记中文能力名、十二英魂的守线身份及八关建议能力；实际范围/伤害类型/治疗/减速/攻城能力根据最终计算值判断。低费近战补线要求非治疗、正伤害，费用不高于low_cost_max=90且最终射程不高于low_cost_range_max=100；不能用廉价治疗或远程输出冒充近战补位。守线以显式身份并排除治疗者，范围要求实际aoe_radius>0。对应能力展示当前拥有该能力的队员和本关建议原因；缺口建议只列已契约且不在阵容中的英魂，不把未契约单位当成可用推荐。没有可用英魂时说明当前可先训练/调整召唤节奏，不能生成越权阵容。

这些为可选战术提醒，不新增强制阵容、货币、存档schema或数值收益，不改变原waves、战斗和研修配方。编队/研修修改后重新打开敌情必须反映新值。未知关卡返回空摘要，页面回到远征并提示，不执行开战。

| 接口 / 配置 | 约定 |
|---|---|
| summarize(stage_id) | stage_id/stage/enemies/total_count/timeline/last_time；enemies含id/name/role/count/first_time/last_time/variants，变体含count/hp_mult/damage_mult/stats |
| readiness(stage_id, roster, levels, study_modifiers, owned) | members/capabilities/recommendations；members含id/name/level/stats/capabilities，推荐含capability/label/present/alternatives/reason/message |
| briefings.json | schema_version=1；capabilities为中文label/description，units登记frontline身份，stages登记recommendations的capability/reason，低费阈值为low_cost_max和low_cost_range_max |
| 能力ID | frontline、low_cost、aoe、magic、true_damage、healing、slow、siege；只在开发配置使用，玩家页面常显中文 |
| Main入口 | _open_briefing(stage_id)；selected_briefing与tab=敌情；Briefing_<stage_id>/BriefingStart/BriefingReturn/BriefingSquad用于实际按钮回归 |

后台验收覆盖所有八关、每个敌军波次配方与真实SiegeBattle._spawn中央结果一致、计划时序与真实_waves一致、Boss阶段数值、读取深拷贝及无副作用；界面验证关卡入口、锁定出征、未来schema保护、模态阻挡、已保存研修/编队更新与无意外写盘。离屏画面另用真实Main及1280×720检查文字完整和两章页面；后台与离屏只代表各自范围。前台MainFlow及24/64/2倍速性能仍按用户安排留待后续，新源码另建候选包并保存版本指纹，不改写candidate6冻结证据。

2026-11-19本轮实现与candidate7验收：BriefingSmoke通过2945项，八关计划时序、28种实际敌军配方、108玩家等级/研修实例及两个Boss阶段一致；BriefingUISmoke通过1419项，核对实际SVG、六个可见数值/中文标签及输入穿透，并通过保存/模态/未来schema边界。StudyUISmoke为1180项，六个属性格读数包含最终治疗量，不只检查隐藏元数据。十项后台总8147，完整旅程988，Art50/6253零文字溢出；全部为本包实际运行，50个源码/配置/图标核心文件与源项目一致。首轮UI夹具将正常设置关闭的preferences备份误判为浏览写盘，失败报告保留，修正后单独核对模态期间全部文件与关闭后的角色档。前台验收、性能及商业授权仍未完成。
