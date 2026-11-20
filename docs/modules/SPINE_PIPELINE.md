# Spine 批量应用规格

> v0.21 · 2026-11-20 · GDD v0.5.8 / 程序0.1.3.0
> v0.21：干净检出完整重建；转换失败非零退出、来源清单与参数绑定、完整21ID门禁，作者状态更新在肖像生成前完成，随后只读冻结验证。
> v0.20：原生验收默认只读生产配方，结果状态独立写报告；作者需显式update-status才改配置，且必须在肖像生成与打包前完成。修正验收重排JSON导致原字节SHA失效的管线边界，不放宽肖像或payload哈希。
> v0.19：区分早期GL/非托管/四组历史测量与当前Mobile/Safe/托管/统一两组候选；实际图形验收采用生产普通日志，verbose宿主诊断单列保留，最终性能与差图仍待本轮报告。
> v0.19补充：按用户先后台验收的要求，SpineMeshRedraw新增background离屏Vulkan差图，Playback新增background播放时钟回归；主窗全程最小化，双SubViewport强制绘制，2624比较与21/220门禁保持不变，不产生性能结论。
> v0.18：性能夹具从ProjectSettings记录生产后端、Safe线程、托管刷新、组数和十二关键预算；逐300帧核对实际策略与人数，差图强制21来源/220动作覆盖，播放回归明确生产与显式对照。
> v0.17：修正后台工具不能隐藏主Window的调用；MODE_MINIMIZED/启动SW_HIDE保留，离屏捕获强制force_draw(false)而不等待主窗自然frame_post_draw，关联FS-024。
> v0.16：十二玩家真实Spine待机透明肖像离线管线；无地圈、双次原生取景和5%边距自适应裁切，输出本地PNG/manifest与配置哈希，静态TextureRect使用，不增加战斗骨架。
> v0.15：实际Main手动测量门先暖机并继续真实渲染，输出READY/独立gate路径后等待computer-use取得稳定前台；120秒内只轮询隔离信号，不启动辅助进程、不反复抢焦点，收到信号再采300帧。
> v0.14：正常GUI/Safe Mobile出现2组候选通过，独立重复受焦点/最小化干扰尚未确认；性能区移除辅助GPU查询，增加真实backend/连续焦点门禁和Main2×诊断入口，生产默认仍不切换。
> v0.13：长暖机抓到最小化窗口绕过呈现限速；性能门禁强制正常可见1280×720窗口，保留早期诊断但不作为最终帧率证据，重新对照2/3/4组。
> v0.12：托管Mesh全21来源/220原动作2624次RGBA差图零差异通过；加入实际Main+默认音效/HUD/背景/飘字性能入口及长暖机复测，暂不以首轮成绩定稿预算。
> v0.11：原生子Mesh每帧刷新根因确认；新增默认关闭的托管redraw候选，先以全220原始动作确定性双视口差图验证，再复测最小分组预算和最终Main场景。
> v0.10：>=40活实例接四组预算；Safe GL/Mobile仍按完整场景继续验收，Separate线程实验结果不替代交付默认；只读探查原生子Mesh/附件几何API是否允许同材质连续批次合并。
> v0.9：进入最终学习版，实现2/3/4帧分组API与低帧率原生时钟回归；报告读取项目程序版本并隔离0.1.3性能目录，人数预算仅按完整场景实测结果采用。
> v0.8：扩展帧分组预算API供高数量场景对照；补齐原生零delta/逻辑/绘制分项、真实renderer门禁与便携包三工具依赖。预算默认仍2组，3/4组未验收前不作为交付配置。
> v0.7：21来源资产/20导出名家族口径；低优先级30Hz为采样上限，奇偶帧错峰避免低帧率下全部骨架同时到期；完整战斗与可见范围性能分开记录。
> v0.6：新增四首通英魂来源；骨架manual时钟、60/30Hz优先级更新、root-motion对象缓存和真实场景性能对照，保留原始基线与原验收门槛。
> v0.5：修复派生JSON/atlas旧import remap依赖与便携包骨架静默为空；重新生成时仅在本项目assets/actors内删除对应旧.import，包内逐套检查真实骨架不能仅看日志/资源对象存在。
> v0.4：修复速度接口的原生TrackEntry调用；13套真渲染0/1/2倍率、暂停冻结与动作恢复严格日志验收通过。
> v0.3：首批13底模配置定稿；deform迁移到4.3 attachments/skin/slot/attachment/deform，保留顶点与时点、转换时间/比例Bezier，逐套原生动画探针和独立截图验证。
> v0.2：确定扫描字段、原始/派生隔离、分进程运行测试和SpineActor统一接口；批量接入不预先承诺兼容或发行授权。
> v0.1：315编号全库盘点与批量接入基线。

## 可复现管线

`python tools/spine_pipeline.py scan --source-root <源库>` 输出 `reports/spine_catalog.json`。每编号记录目录/导出、原版本、皮肤、动画时长与事件、骨骼/槽位/网格/加权网格/linkedmesh/path/deform统计、atlas纹理及附件路径缺失、许可原文位置和哈希。源工程存在不代表存在可导入JSON；风险保留原始结构证据。

`python tools/spine_pipeline.py import --ids 097,312,314,072,163,...` 将输入独立复制到 `assets/source/d69_NNN`，派生运行文件在 `assets/actors/NNN`，provenance关联每份原文件SHA256、转换器和独立声明。转换无path/linkedmesh候选；deform需显式启用已实现的attachments格式适配并逐套原生验证，path/linkedmesh继续拒绝。按编号重复导入可扩充，不修改外部库。

默认所有21来源资产均从给定D69源包独立转换；四份历史验证派生只作为`--prefer-previous`可选诊断对照，bootstrap无需旧项目美术文件。原生库可通过`--runtime-from <已安装bin目录>`只读复制，本地素材和库忽略Git。

`python tools/verify_spine.py --ids ...` 调用 `tests/SpineProbe.gd`，每份素材独立Godot进程，记录加载、可见边界、皮肤、所有非空动画与逐帧推进。超时/崩溃/脚本错误均失败；原生返回成功且探针显式结尾才在本次报告记录runtime_pass结果。默认不写生产配置；作者需要持久更新配方的状态字段时须显式`--update-status`。视觉与64单位真机性能另验收，runtime_pass不自动升为visual_checked。

### 配方冻结与只读验收

生产配方`resources/visuals.json`的原始字节属于肖像和学习包的可复核输入。原生验证、肖像`--check`、后台播放/差图以及包验收只读配置与资产，只更新各自reports中的结果、错误、日志和状态。验证成功不能触发JSON重新序列化、字段重排或状态写回；验证失败同样只在报告留下失败证据，不通过修改包内配方隐藏问题。

作者导入/转换、调整配方或显式`verify_spine.py --update-status`是制作阶段的写入操作，须在肖像生成与打包前完成。顺序为确定运行资产与配方、完成所需作者状态更新、冻结配置原字节、生成并校验肖像manifest、构建payload清单、在包中只读重新验收。冻结后若需要改配置，先重新完成作者阶段并再生成肖像和干净包，不能把旧肖像manifest的SHA直接改成新值来绕过验证。

candidate-3暴露了该边界：native验证虽覆盖21来源/220动作成功，但工具无条件写回visuals.json，使语义相同的配置从16522字节变为17211字节，原配置SHA因此改变，肖像关联与payload检查正确拒绝。修复应去掉默认写回并把作者状态变更放到显式开关；原字节SHA256、文件大小、角色/visual_id关联和包前后资产检查全部保留，不改成仅比较解析后JSON或忽略哈希。

此前21/220原生探针及2624次后台零RGBA差异只证明各自执行时的资源/播放或像素结果，历史报告继续保留；这次包完整性失败不改写那些结果，也不把它们提升为candidate-3完整包通过。修复后的干净候选须以自己的新鲜报告和未经验收改写的payload重新验证，普通窗口Main性能仍是独立待验项。

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

## 派生JSON与便携包依赖

`actor.spine-json.import`可能把读取重定向到`.godot/imported/*.spjson`，`actor.atlas.import`则指向`*.spatlas`。拷贝源.import而不拷贝匹配产物时，PNG/ctex、data.tres及原始JSON均可存在，`load(tres)`仍返回Resource，但原生`get_skeleton()`为空且日志没有错误。0.1.1.1旧便携包的097/312/314/072/084受此影响；其中四名保留角色还缺atlas原生产物。其余八套没有这些.import，原始加载正常。

每次import重写派生JSON/atlas后，仅删除新项目`assets/actors/NNN/actor.spine-json.import`和`actor.atlas.import`旧remap，解析绝对路径确认在允许根内，编号严格三位整数；外部源包和旧项目.import不动。不删除其他纹理.import，纹理仍需先Godot导入。便携包构建从源文件复制时过滤*.import/*.uid，再在包自身目录导入；不能以单个图鉴using_spine、退出码或无ERROR声称所有骨架通过。所有13套需用包内exe/项目根逐套探针，八角色实际战斗实例也须检查using_spine与截图。

## 0.1.2 手动骨架时钟与扩充

四名首通英魂：110 Hellenia A→星槌卫士、023 Ballista A→绞弩炮手、147 Lania A→月灯术士、069 Derik A→灵契兽卫。新增底模先单独原生验证所有原始动画、默认皮肤归一与双朝向动作图检，再登记运行通过；新增敌方底模数量由CONTENT_PLAN与总纲同步定稿。

第二章敌族采用057 Cooper A（普通机偶）/059 Cooper C（精英机偶）/036 Chancellor A（远程司炉）/094 Goblin Chieftain A（Boss），总21来源资产/21 visual IDs、20导出名家族；057/059为同家族A/C皮肤变体。source快照根写.gdignore，只供 provenance/重建，不让Godot尝试导入原3.8工程素材。

新纹理首次导入须先于原生atlas importer。bootstrap在本项目安全暂存目录内临时移走派生actor.atlas/actor.spine-json/actor-data.tres，让第一次编辑器导入仅处理其原路径PNG；finally恢复所有文件，再第二次编辑器导入骨架与atlas，两次均检查退出码和日志。该暂存不触外部库，异常也恢复原路径，避免PNG尚无ctex时atlas导入报错或产生空原生资源。

已复制运行资产的便携包使用`python tools/bootstrap_local.py --import-only --godot <包内引擎exe>`；项目根按工具自身位置确定。打包时同时复制`bootstrap_local.py`、`spine_pipeline.py`、`spine_upgrade_38_to_43.py`到包内tools，第三份是spine_pipeline顶层导入依赖。命令仅执行上述两阶段导入，不扫描/转换外部源、不复制原生库。任何阶段失败返回非零并留下包内reports/bootstrap_*.log，第一阶段异常也恢复全部暂存原生文件。

`SpineActor.set_update_rate(hz:float)`只改变骨架采样频率。原生`SpineSprite.update_mode=2`（Manual），由Actor累计引擎传入delta，达到1/hz时`update_skeleton(累计delta)`，每帧至多一次；移动位置与逻辑命中仍60Hz。默认60Hz，Battle每0.5逻辑秒选最多12名关键交战实例60Hz，其余以30Hz为采样上限；死亡显示可短暂保持高频。低优先级实例按创建序号分到奇偶渲染帧，最多每两渲染帧采样一次；实际渲染不足60fps时采样可低于30Hz，但下次原生更新消耗完整累计delta，动作时间不变。避免慢帧中52个低优先级实例全部每帧到期、产生连续更新峰值。切换频率不清零未消费时长，保持连续；暂停速度0时不累计需补走的时间，恢复不会跳帧。track倍率保留0/1/2，动作结束计时同倍率。

root-motion在configure时缓存骨架Pose对象及setup坐标；无平移timeline的候选root不注册无效回调，减少逐帧查骨骼/get_data/get_setup_pose调用。仅改变渲染约束成本，不改原始动画和战斗数据。

高数量预算API `set_frame_group_count(groups:int)`支持2/3/4组，创建序号在组间均匀分配，关键60Hz实例不受该分组限流。低优先级的30Hz始终是采样上限；3/4组在60fps时分别最多20/15Hz，下次采样仍消耗完整累计delta，位置/命中/暂停倍率语义不变。当前发布默认2组；先用`battle64phase3/phase4`保持64可见原生骨架及完整生命条进行对照，只有测量确认后才把人数阈值和选定组数写入CORE/总纲。当前原生SpineSprite接口无batch/mesh合并开关，不能推测未提供的属性。

工具把`play_state`的零delta原生pose评估单独计数，把真正SiegeBattle的advance、生命条_draw和每0.5s选率分开计时。headless或无显卡适配器的结果必须`passed=false`，不能作为渲染性能结论。GL/Vulkan诊断分别留报告，不能以某后端首轮较快值替代实际交付配置。

## 0.1.3 帧预算与最终场景验收

`SpinePerformance013.gd`从ProjectSettings读取程序版本，报告写入`reports/performance_0.1.3/`，不覆盖0.1.2历史。先比较`battle64phase2/phase3/phase4`，三者均包含64真实可见Spine骨架、相同高HP fixture、真实战斗与生命条；强制分组只用于对照，交付配置须再测实际Main+HUD+背景+设置状态。2组默认不变，>=40活实例采用能通过原门槛的最小组数，具体组数待数据回写CORE与总纲。关键最多12实例仍以60Hz为上限且不受多帧分组限流。

播放回归对21资源逐套测试2/3/4组、30/60Hz、0/1/2倍率与1/60、0.05s两种输入delta，检查原生track时间与实际采样次数，覆盖慢于30fps时不会每帧集体更新。暂停不累计补走时间，重配置保留分组设定；切换组数不删除已积累的真实delta。原始动作/素材不因性能优化删除、替换或合并为静态贴图。

早期CORE v0.14按>=40有视觉的活实例采用4组，否则2组；该历史预算独立于60/30Hz优先级缓存，实例数量跨阈值时重新分组。该轮21资源真实OpenGL播放回归通过；宽画布七张多动作/双朝向图支持完整原轮廓检查。当前CORE v0.15改为ProjectSettings统一两组候选，不再按人数切至四组，实际预算及后端仍需本轮完整Main和播放回归确认。

Pentium G4560（2核4线程）/GTX1050的完整64压力约2000个原生Mesh draw calls。四组降低骨架评估次数，但默认Safe GL的p95仍有未达标轮次；Safe Vulkan/Mobile四组实测44.35fps/p95 35.53ms也未通过。`--render-thread separate`四组50.09fps/p95 26.30ms通过，然而引擎明确提示实验线程可能崩溃/不稳定，另提示`mesh_get_surface`会每帧同步RenderingServer。后者是同步性能提醒，不能推断为Spine线程不安全；实验线程暂不作为默认方案。

`SpineMeshApi.gd`仅记录原生Sprite子节点类型、可访问Mesh数组结构/材质及附件API元数据；不改外部源库、不改原生库、不保存原始几何。若能合并连续同纹理/材质批次，必须保留实时Spine姿态、draw order、双颜色/混合模式/skin/deform/翻转/alpha与完整像素轮廓，先做差图再测性能；未验证前生产SpineActor不切换渲染方案。

### 托管原生Mesh刷新候选（FS-017）

官方4.3 `SpineSprite.cpp`的`SpineMesh2D::_notification`在READY开启internal processing，每次INTERNAL_PROCESS调用queue_redraw，DRAW重新clear/add triangles和update_mesh。Actor的manual骨架即使本帧未采样，子Mesh仍重复提交上次姿态的网格。ClassDB探针确认当前原生子Mesh不公开mesh/vertices getter；不凭空实现GDScript几何合并，也不修改原生库。

`SpineActor.set_managed_mesh_redraw(enabled)`早期候选默认false；当前实例初始化读取ProjectSettings中的managed_mesh_redraw=true候选。该机制缓存本实例所有SpineMesh2D CanvasItem；启用后关闭这些节点的internal processing，每次实际`update_skeleton`（含换动作零delta pose）完成后统一queue_redraw，重配重新发现并应用开关。关闭时恢复原internal processing并立即请求首帧刷新；角色位置、翻转和alpha仍由CanvasItem变换处理。保留原生材质、draw order、UV、双颜色、clip、deform与顶点数据，只改变重复DRAW的请求时机。外部直接修改skin/slot配方后，须推进零delta骨架并显式调用`refresh_native_meshes()`，不能只改数据却遗漏网格刷新。候选配置已用于本轮验收，尚不表示最终通过。

`SpineMeshRedraw.gd`以两套独立透明SubViewport在相同raw动作/track time渲染原始与托管版本；21来源全220动作、左右、全部skin、全局tint/alpha、首帧、多个动作时点、脚底和完整边界逐像素比较。报告必须真实显卡、同track姿态、非空轮廓且差像素为0才通过；保存差异截图仅在ignored本地报告目录。回归再覆盖开关切换、暂停、频率分组及重配。早期Safe GL的battle64phase2/3/4对照用于寻找最小组数；当前Mobile/Safe/托管/两组候选须在同后端重跑完整差图与实际Main+HUD+背景。64压力仍要求p95<33.334ms，24实际场景仍要求平均>=55fps，候选未经这些检查不得登记为最终交付配置。

真实GTX1050/Safe GL差图已通过：21来源、220原始动作、全部skin及双朝向，共2624比较，RGBA差异0；配置选定身体皮肤每项都具有有限非空bounds和未裁切轮廓。备用default皮肤仅含效果的216帧可以身体为空（原生get_bounds为inf/-inf），此时两侧RGBA仍相同，防止旧身体三角形残留。初轮夹具失败报告保留在mesh_redraw_trial1.json：入树前关process被脚本自动启用覆盖，导致track姿态并不相同；修正为入树后关闭，且不把合法无身体备用皮肤的空边界当成资源丢失。

首轮托管完整Battle对照2组p95 21.268ms通过、3组31.726ms通过、4组44.03ms失败，24场p95 17.203ms/59.47fps通过。环境波动与短暖机的战斗阶段差异尚待核查，不挑最好值宣布性能验收；额外steady模式在同fixture推进12.3秒后采300帧，独立重复2组，并记录实际vsync、窗口/视口尺寸、process_id、CLI与唯一引擎进程证据。

2组长暖机复测的vsync=1却测到136/140fps，环境记录确认window_mode=1（最小化）。原生draw calls仍约2000且RGBA渲染有效，但最小化窗口可能跳过呈现限速，不能据此宣称正常窗口帧率；早期缺窗口状态的性能报告也只保留诊断。测试显式将root.mode设WINDOWED并visible=true，必须window_mode=0、window_visible=true、1280×720、真实GTX1050/Safe GL和唯一引擎进程才能通过交付性能门禁；仍用Start-Process Hidden启动外层进程，然后由测试恢复正常游戏窗口。重新长暖机测2/3/4及独立重复2组，再测实际Main，未更改p95/FPS门槛。

最终入口`MainPerformance013.gd -- main24 exclusive`及`main64 exclusive`加载真实Main.tscn，隔离ProfileStore/UserPrefs，只跳过一次性教学弹窗，首关按高HP fixture保留24/64数量；正常12秒叙事自行结束后测300帧。保留实际HUD/生命条、WorldBackdrop、音乐/音效默认音量和真实命中飘字，使用生产默认分组/托管策略，不用纯Battle结果替代；报告写performance_0.1.3/main24.json/main64.json并保存ignored实景图。结束调用实际音频shutdown，外层仍必须检查真实退出码和stderr/verbose无Leak/ERROR。

2026-11-18历史正常GUI.exe（直接Normal启动，不继承console launcher的Hidden状态）初轮Safe Mobile：2组45.92fps/p95 29.640ms，4组59.41fps/p95 22.675ms，均window0/visible/300帧焦点和全64数量；Safe GL关闭VSync并限60fps的3组31.873ms、4组31.046ms也通过。仅列候选，不以单轮较好数据交付：后续2组/24独立进程在采样途中失去焦点或最小化，严格passed=false，但这些不是有效正常前台性能回归依据。临时always_on_top也未保持稳定前台；该轮归还GPU窗口并保留全部原始报告，当时生产仍GL/非托管/高人数四组。2026-11-19已改为明确的Mobile/Safe/托管/统一两组候选，最终结论等待本轮报告。

有效性能报告还要求focused_frames=300、actual_rendering_method与实际backend一致。正常性能路径完全不启动NVSMI等辅助进程；仅显式gpu_diag模式在测量区外查询，其旧诊断保留。暖机后临时置顶只服务验收，结束显式恢复，不能作为生产窗口行为。实际Main的main64_2x调用正常_toggle_speed，另记playback_multiplier=2，不能把1×性能外推2×。最终Mobile采用前必须在Mobile本身重跑完整2624次RGBA比较与实际Main24/64，包使用项目默认renderer同样重验。

最终生产策略集中在ProjectSettings：`fantasy_siege/visuals/managed_mesh_redraw`、`fantasy_siege/visuals/frame_group_count`、`fantasy_siege/visuals/critical_instance_limit`，并显式设置`rendering/driver/threads/thread_model=1`（Safe）。Main性能入口无参数覆盖时完整继承这些设置；显式`managed`/`unmanaged`只作候选/对照，报告标记实际是否偏离生产策略。正常24/64人数fixture每个采样帧必须保留完整native/alive/visible人数、同配置托管实例数、恰好min(十二关键预算,存活人数)个60Hz角色，其余为30Hz且组数全部与生产值一致；`budget_valid_frames=300`、分组人数及关键/托管人数min/max一起记录，不能只验末帧或名义count。报告同时保存生产与实际renderer、项目线程设置及CLI线程覆盖后的有效模型；Separate不能混用Safe门禁。

差图最终PASS同时要求`resource_count=21`、`raw_animation_count=220`、每来源唯一ID及实际遍历的全部raw动作名、非零比较数、真实backend和零RGBA差异；在不同backend重跑时读取实际渲染器，不能用初始化字符串或旧报告替代。播放回归默认构造生产Actor并标记`production`；显式托管/非托管分别标记`managed_candidate`/`unmanaged_control`，另存报告，包含生产默认策略与实际backend。无论生产策略改成何值，两组策略的播放时钟、暂停、重配置和分组回归都须保留。

`SpineMeshRedraw.gd -- background`只在真实Vulkan后端进行双透明SubViewport像素验收。外层以隐藏启动，夹具在初始化即将主Window设为MODE_MINIMIZED；不设visible=true、不grab_focus、不调整置顶。每个姿态等待两个process_frame处理队列，再`RenderingServer.force_draw(false)`绘制离屏视口，直接读取两张1000×760图像，不等待最小化主窗可能不触发的frame_post_draw。全部21来源、220原动作、所有皮肤/左右/变换/开关暂停、共2624次比较与原RGBA/边界检查完整保留。每次捕获核对主窗仍最小化，报告`background=true`、`background_host_valid_captures=2624`、主窗状态、两视口尺寸/透明设置、实际rendering_method/driver与显卡；真实driver必须vulkan，不能由config/features或启动参数猜测。

后台报告明确`performance_measured=false`，只支持托管刷新像素一致与完整资源覆盖结论，不证明普通玩家窗口帧率、焦点或完整Main交付。它仍写当前mesh_redraw.json，必须连同新鲜日志与实际命令审计；最终学习包需要的Main24/64/2×正常窗口性能继续独立保留待验。前台默认差图流程不改，background仅替换窗口与取景调度，不替换原生Skeleton评估、比较算法或通过标准。

`SpinePlayback.gd -- background`与`-- unmanaged background`可后台运行生产与非托管对照。初始化及进入deferred测试时主动MODE_MINIMIZED，避免autoload读取玩家全屏偏好后改变主窗状态；不写玩家偏好、不抢焦点。原21资源、0/1/2倍率、30/60Hz、2/3/4组、两种delta、暂停恢复与重配规则完整保留。每套资源完成后核对后台主窗最小化，报告`background`、主窗与DisplayServer模式、有效最小化资源数、实际backend及`performance_measured=false`；`actual_rendering_driver`同样读取RenderingServer实际driver，后台必须为vulkan，不能以Mobile配置推断。该结果只证明原生播放时钟与生命周期，不能作为像素差图或普通窗口性能证据。

`MainPerformance013.gd -- main64managed manual_gate`（或main24managed）显式启用本批fixture托管，但仍使用ProjectSettings默认组数；本轮默认统一两组，报告按实际是否偏离生产值记录，不以显式模式名替代策略核对。开始删除该mode隔离目录旧measure.ready/performance_ready.json；真实Main/高HP fixture完成暖机后写performance_ready.json并打印MAIN_PERFORMANCE_READY，包含绝对gate/ready路径、process_id、Godot窗口ID和标题、实际renderer。随后上限120秒继续真实渲染/音频，只异步检查隔离tests/.user/<mode>/measure.ready；等待期间不调用外部进程或反复grab_focus。computer-use真实激活游戏窗口后，由Root写此信号，再经过30帧稳定后采300帧；timeout生成明确失败报告并正常shutdown。最终报告记manual_gate、gate_wait_ms与两文件路径，仍必须window0/visible/300连续焦点。自动包验收无manual_gate时仍按正常入口运行，不自动等待人工信号。

实际图形验收按玩家使用的生产普通日志启动，不强制--verbose。verbose只作独立宿主诊断；缺失Steam Vulkan layer的宿主诊断保留原文及范围，不更改Godot ERROR、SCRIPT ERROR与退出泄漏的拒绝门禁。性能、播放、差图和包报告仍须本次生成并匹配生产配置，诊断输出不能替代实际验收结果。

只读后备边界：当前21派生JSON合计692槽位（691 normal、046一处multiply）、151 mesh附件、0 clipping附件。C++可按同Sprite当前drawOrder的连续兼容纹理/材质run聚合既有世界顶点/UV/颜色/索引，但必须保留每顶点light/dark、非normal分段、变更空run和资源重配生命周期；当前GDScript无geometrygetter。动态SubViewport只能作为另候选：分数像素平移/缩放会重采样，透明FBO须正确premul合成，multiply不能以普通RGBA最终纹理无损表达任意背景，不能未经差图就标原始输出一致；当前未实现该路线。

## 静态透明肖像（0.1.3美术反馈）

`python tools/generate_portraits.py --godot <GUI.exe>`调度`tests/SpinePortraits.gd`，或`--check`仅离线校验已生成结果。十二playable unit按各自visual_id/skin/tint/native_facing/foot/root-motion配方构造真实Spine，冻结idle自然时长的25%姿态；专用Actor只覆盖地圈绘制，不改变生产Actor。透明SubViewport使用UPDATE_ALWAYS、2048画布做首次轮廓采样，再按1024×1280最大范围重新原生放大/居中；从最终alpha轮廓逐边加5%透明余量取景，不从atlas拆件、不烘焙UI背景、不以截图放大替代第二次原生渲染。输出保持完整头脸/主武器/轮廓，实际PNG宽高随轮廓比例裁切，由TextureRect KEEP_ASPECT_CENTERED使用。

输出`assets/portraits/<unit_id>.png`和`assets/portraits/manifest.json`均为受限本地派生，忽略Git。manifest含program_version、passed、全resources/visuals.json原字节visuals_sha256，entries记录unit_id/visual_id/png相对文件名、sha256、width/height、native=true、nonempty=true及姿态/完整配方。`reports/portraits_local.json`保存工具校验：真实renderer/原生体、源映射/配置哈希、PNG RGBA/非空/透明边界、文件哈希与新鲜报告、严格进程退出及错误/泄漏日志。失败不把旧manifest标通过。

离线生图可在后台Hidden辅助Godot执行，root保持minimized，不设置visible=true、不抓焦点/warp mouse；只验静态PNG，不计任何FPS。按Root统一GPU调度，不与导入或其他图形验收并行。商业授权口径沿用本地学习版，不上传源/派生PNG及manifest。便携包复制整个assets/portraits目录；工具与`SpinePortraits.gd`随源码/测试目录入包，`--check`在包本身核验十二角色映射及visuals_sha256。其后由Root做实际英魂/编队/召唤/详情卡面和包内视觉抽检。

Godot主Window禁止set visible=false，后台工具也不能调用它（FS-024）；用启动SW_HIDE/CREATE_NO_WINDOW与MODE_MINIMIZED控制，不抢桌面。主窗最小化时自然frame_post_draw可能不触发，捕获先让两个process_frame刷新CanvasItem队列，然后RenderingServer.force_draw(false)完成离屏视口，再读get_texture().get_image()。这只是离线图像流程，不把最小化数据计作游戏性能。

性能重新测24实际场景与64压力：原0.1.1视觉基线38.36fps/p95 37.43ms保留；0.1.2仍要求压力p95<33.33ms，不通过则继续优化或如实待验收。分开列混合底模、全英雄与完整SiegeBattle范围，不把12英雄+52敌兵的测量外推到64英雄。GPU专占，不能与其他QA窗口并行。

性能工具同时记录原生更新次数/耗时、渲染draw calls/图元和有效可见数。`baseline64`使用0.1.1相同八玩家/五敌方来源与12+52实例构成，避免新增大型资产导致测量被误称为原负载回归；`mixed64`覆盖扩充来源，`heroes64`仅英雄，`battle24/64`包含真正战斗逻辑、骨架和生命条，高HP fixture保留样本数量而不代表关卡平衡。截图表使用宽裕的独立素材检查画布，以容纳跃击、长武器和死亡轮廓；游戏视口仍1280×720。

## 干净Git检出与完整bootstrap（本轮设计）

完整bootstrap在当前项目执行扫描、21套结构转换及配方生成，要求本次转换报告恰好覆盖目标ID且全部converted，任何失败非零退出，保留失败结果，不继续原生/肖像步骤。独立import使用已有spine_catalog.json时，清单source_root与当前参数解析后必须一致，目录外的原始文件不得被当成当前来源；不一致应明确拒绝并提示重新scan，不悄悄导入另一源。

带--godot的完整制作流程：两阶段纹理/原生导入→显式21套原生作者验证并--update-status→十二真实透明Spine肖像生成与检查→新肖像编辑器导入→默认只读原生/肖像复核。作者状态更新在派生肖像前完成，冻结之后不再改配方。--import-only保留只导入已复制素材的含义，不扫描来源、不生成新配方、不重新制作肖像；未提供--godot的转换模式只能声明已转换，不能声明完整运行依赖就绪。bootstrap报告记各阶段/目标ID/路径/退出码与冻结配方SHA，失败不发布ready。

复现使用F:/godotProject/FantasySiege/build下的新Git检出，起点记录实际HEAD；初始不得有.godot、assets/actors、assets/portraits或bin。明确只读D69源与原生库捐赠目录；不借主项目缓存、已派生角色或肖像。完成全流程后，在检出自己的exports/windows下创建新空学习包，包内后台/离屏/完整旅程验证；旧项目/D69读取前后校验，受限依赖和衍生文件不入Git。纯Python临时目录验证转换拒绝、清单不一致、缺ID/失败ID、步骤顺序与失败停止；实际Godot由root串行调度。资源盘点/转换/原生/图像/性能范围仍分开，前台Main24/64/2倍速保持用户延期。

制作导入也须复用严格致命错误/退出泄漏日志判断；退出码0不能掩盖ObjectDB泄漏。写入角色和本地源档案之前先验证解析后的目标仍在本项目的对应目录，拒绝目录链接把写入转到旧工程或外部源包。
