# Spine 批量应用规格

> v0.3 · 2026-11-18 · GDD v0.1.0 / 程序0.1.1.0
> v0.3：首批13底模配置定稿；deform迁移到4.3 attachments/skin/slot/attachment/deform，保留顶点与时点、转换时间/比例Bezier，逐套原生动画探针和独立截图验证。
> v0.2：确定扫描字段、原始/派生隔离、分进程运行测试和SpineActor统一接口；批量接入不预先承诺兼容或发行授权。
> v0.1：315编号全库盘点与批量接入基线。

## 可复现管线

`python tools/spine_pipeline.py scan --source-root <源库>` 输出 `reports/spine_catalog.json`。每编号记录目录/导出、原版本、皮肤、动画时长与事件、骨骼/槽位/网格/加权网格/linkedmesh/path/deform统计、atlas纹理及附件路径缺失、许可原文位置和哈希。源工程存在不代表存在可导入JSON；风险保留原始结构证据。

`python tools/spine_pipeline.py import --ids 097,312,314,072,163,...` 将输入独立复制到 `assets/source/d69_NNN`，派生运行文件在 `assets/actors/NNN`，provenance关联每份原文件SHA256、转换器和独立声明。转换无path/linkedmesh候选；deform需显式启用已实现的attachments格式适配并逐套原生验证，path/linkedmesh继续拒绝。按编号重复导入可扩充，不修改外部库。

默认所有13底模均从给定D69源包独立转换；四份历史验证派生只作为`--prefer-previous`可选诊断对照，bootstrap无需旧项目美术文件。原生库可通过`--runtime-from <已安装bin目录>`只读复制，本地素材和库忽略Git。

`python tools/verify_spine.py --ids ...` 调用 `tests/SpineProbe.gd`，每份素材独立Godot进程，记录加载、可见边界、皮肤、所有非空动画与逐帧推进。超时/崩溃/脚本错误均失败；原生返回成功且探针显式结尾才标runtime_pass。视觉与64单位真机性能另验收，runtime_pass不自动升为visual_checked。

`SpineActor.configure(id,facing)` 可入树前后调用；数据Resource静态缓存，实例独立SpineSprite/AnimationState。idle/move循环，attack/skill/hurt按配置时长或调用duration播放后回idle，death停留末帧。脚底偏移和native_facing分开；root-motion按配置骨架骨名约束。缺库/路径显示底圈人物占位并保持using_spine=false。光环/底圈/全局染色是配方辅助，不宣称真实骨架描边。逻辑命中不监听Spine事件，事件只用于校准。

扫描315编号完整源库；一编号不等于独立角色/导出名，皮肤与身份分别记录。输入源根只读，runtime目标`assets/actors/{source_id}/`，`resources/visuals.json`是统一视觉配置。`tools/spine_pipeline.py scan/import`生成catalog、运行资源、原始输入与provenance。

首次优先保留四个已验证源097/312/314/072，新导入163吕布及多套原创角色/敌人底稿。原始JSON/atlas/PNG/声明与运行资产分开；生成SHA256、原导出版本、皮肤、动画/时长/事件、转换告警及用途限制。

状态：cataloged → converted → runtime_pass → visual_checked → performance_checked。deform/path/linked mesh不能因JSON输出成功就判兼容；不支持项在报告列明，不悄悄丢动画。原生加载按一素材一个进程隔离。

配方可复用原皮肤、指定slot tint/attachment visibility、scale、foot、root-motion约束、环形光环、描边（可先用独立轮廓/底圈表现，真实骨架描边须单独验证）。小兵建议80~105px、英雄110~145px、Boss160~200px；最终按实例完整轮廓测量，不能仅按纹理大小推断。碰撞/射程独立于美术尺度。

共享SkeletonDataResource/Atlas，不重复读盘；每单位独立AnimationState；活单位64、完整英雄12作为验证目标。动作空缺用明确替代映射并登记，不把空Active_A当技能；attack命中由逻辑一次结算。离屏/低优先级更新降频方案留待实测，不宣称已池化或已优化。

D69源声明仅学习研究、不可商用；保留免责声明。当前运行库仅Windows64，其他平台需要对应库和重新验收。素材扩充优先工具批量导入/重配，不改战斗代码。

## 首批底模与配方

八玩家 d69_097/312/314/072/163/084/018/168；敌方 d69_253（裂隙小剑幽灵）/254（悬浮快突）/046（棒槌重甲）/285（远程咒师）/271（首章Boss）。英雄125px基准，普通敌兵85~115px，Boss170px；全局染色/地环辅助区分，不更改原纹理。254与163的deform单独实测失败则保留候补状态，由内容配置选择已通过的派生方案。

084的3.8 `twoColor`槽位timeline需改为4.3 `rgba2`；保留light/dark帧内容，Bezier按light RGBA+dark RGB七分量转换。所有输入动作保留，不以删除Attack_A规避加载失败。

独立截图探针保存每套Idle/Move/Attack/Skill/Hurt/Death与双朝向，测量原生bounds和截图有色像素；64实例性能探针测frame时间，runtime_pass不能替代截图可读性。公开Git仅保留管线与元数据，源和运行美术在本地通过bootstrap生成。

## 0.1.1.0 实测

13套各自独立原生进程通过，完整原始动作共计135项，每动作36步都检查有限且非空bounds。`reports/spine_visuals/`七张整表完成双朝向/移动/攻击/技能/受击/死亡抽检，13套正文可见且脚底基线合理。084/018/253/254使用A皮肤，因为default仅含效果；设皮肤后恢复setup slots，防身体为空却误报加载成功。

吕布原Active_A含离鞍跃击，保留原动作位移与分离马身，素材浏览工具可见；当前战斗 cleave 使用Attack_A，Active_A不决定逻辑位置或命中。死亡动作可能横向躺倒超出素材格，属于原动作轮廓，不截断或删除原骨架。阴暗幽灵依靠轮廓和发光双眼区分，在亮战场仍需关卡截图抽检。

GTX1050/OpenGL3.3独占渲染，64真实独立Spine实例（12英雄+52敌兵，移动动作）300帧：平均38.36fps、26.07ms，最终p95 37.43ms、最大46.41ms、静态内存增量约45MB。旧严格p95<33.33ms目标未通过，报告保留`passed=false`。原型参考预算平均>=30fps/p95<50ms可接受；这是视觉压力结果，不能代表64英雄或完整战斗性能。下一编号再做低优先级30Hz、root bone对象缓存、真实战斗性能验收，不提前标performance_checked。

原生atlas loader在未导入纹理时可能崩溃，SpineActor在加载骨架前先检查页Texture2D可用；缺失/未导入时回退占位。bootstrap必须先执行Godot编辑器导入，再跑独立探针，资源复制与原生加载不能并发。

速度使用`set_animation`返回并保存的`SpineTrackEntry.set_time_scale`，不使用当前运行库不存在的`SpineAnimationState.get_current`。`SpinePlayback.gd`逐套断言0/1/2倍率、原生track_time冻结/推进、动作暂停/恢复、重配和释放；验收同时检查stderr，内部JSON或退出码单独不能证明无脚本错误。
