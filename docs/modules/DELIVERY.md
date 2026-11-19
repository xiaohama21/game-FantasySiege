# Windows本地学习版交付

> v0.13 · 2026-11-19 · GDD v0.5.3 / 程序0.1.3.0
> v0.13：candidate6干净导入、八CPU/3351项、21/220原生、2624像素对比、Art32/3826与988项独立旅程通过；前台流程/性能延期，delivery_ready保持false，版本分支本地提交并保留待推。
> v0.12：报告读取或门禁异常时保留Godot原始stdout/stderr，并追加验收异常；超时和启动失败安全记录，失败判定不变；研修战斗固定108项真实出生组合及当前研修配置指纹。
> v0.11：candidate4冻结为研修前基线；新增研修存档/战斗/UI三个CPU用例及源码指纹门禁，当前CPU8/full10；离屏验收扩为32图，要求八张研修状态图及研修后英雄详情/图鉴读数图。
> v0.10：原生验收默认只读素材配方，报告前后SHA与未修改声明；作者显式--update-status才写状态，包验收拒绝改配方及错误/泄漏日志。
> v0.9：新增独立offscreen包验收，隐藏启动并保持主窗最小化，只验证Spine时钟、全动作像素及22张界面图；delivery_ready固定false，不替代前台性能。
> v0.8：真实渲染默认使用生产启动日志，verbose只作可选诊断；保留严格错误/泄漏检查与历史诊断失败结果，报告记录命令和启动模式。
> v0.7：完整包按本包生产配置核对Safe线程、托管Mesh、分组与12个关键实例的逐帧预算；补1×/2×完整Main和21/220逐动作网格差图的严格覆盖门禁。
> v0.6：后台取景维持Godot主窗最小化，用force_draw(false)绘制独立SubViewport；不尝试主窗visible=false，完整包另跑22张真实离屏美术图。
> v0.5：新增十二同源肖像和原创环境资源的包内哈希/关联验收；后台准备阶段单独记录，完整包仍须当前默认渲染器、真实前台性能与视觉复核。
> v0.4：前台不稳定时允许manual_gate测试夹具，由真实窗口点击后启动采样；不在等待阶段计算帧率。
> v0.3：图形验收显式SW_SHOWNORMAL启动交互游戏，记录原生窗口状态与焦点；最小化帧率不作正常游玩证据。
> v0.2：报告目录用.gdignore隔离资源自动导入，正常窗口验收包含模态焦点和保存失败退出。
> v0.1：干净目录构建、两阶段导入、全流程与音频退出门禁，保留失败报告。

构建由 `tools/build_local.ps1` 读取project.godot程序版本，在 `exports/windows/FantasySiege-版本` 创建干净包。目标目录已有内容时明确失败，不覆盖历史包或夹带旧缓存；修复后的再次构建可指定新的空目标目录。全部脚本、场景、配置、本地21来源运行资产、字体、原创音频与Windows原生库独立复制。跳过.import/.uid、测试存档、.godot和Python缓存，不带原始源包。Godot官方程序随包命名FantasySiege.exe，启动无需Python或另装Godot。

构建生成的使用说明常显营地“研修”入口：已契约且达到Lv.3，并首通第四关后，180星砂一次解锁该英魂两条路线，之后免费切换或恢复基础；研修仅在营地进行。该说明与实际八关解锁和营地指南规则一致。

包内同时复制docs/GAME_DESIGN.md与README.md；旅程报告读取同包总纲的header、版本及文件哈希，与实际程序版本共同记录，不能沿用硬编码旧GDD版本。

新增assets/environments原创SVG与assets/portraits十二透明角色肖像随包复制；肖像manifest记录visuals原始配置哈希、角色/visual_id关联、原生状态、非空图像与PNG哈希。构建前缺少十二肖像时明确失败，不能发布全占位面板。包内再次核对manifest与units/visuals/真实文件，肖像来源和原配置一致；全部肖像及其派生manifest忽略Git，原创环境与工具可提交。

verify_package的background阶段运行本包八CPU、21/220原生探针与静态payload检查；报告单独写package_background.json，并明确delivery_ready=false，不冒充最终包验证。隐藏窗口可用于离屏肖像/界面图像生成，不能作为性能数据。完整验收render命令读取本包project.godot实际默认backend，不能硬编码GL代替最终生产配置；Main24/64报告须核对采样300帧、完整焦点/正常窗口、真显卡/可见/存活/native/HUD和当前backend。

offscreen阶段单独写package_offscreen.json，串行执行本包生产SpinePlayback background、非托管对照unmanaged background、SpineMeshRedraw background和隐藏ArtReview；全部图形子进程SW_HIDE，不激活桌面。初始及结束均复核payload与十二肖像哈希。两套Playback须background=true、performance_measured=false、真实Vulkan驱动、主窗/DisplayServer均MODE_MINIMIZED且21来源验证期间保持此状态；Mesh还须全部2624次取景均在有效最小化主窗中完成、两1000×760透明2D子视口、21来源220动作及RGBA零差异。ArtReview须主窗最小化、32份1280×720取景与对应文件哈希、十二肖像、零文字溢出和音频排空；新增八张art_study_locked/unowned/ready/base/sweep/heal/siege/slow以及art_hero_studied、art_gallery_studied必须分别存在，核对研修后英雄详情和图鉴同源属性、技能读数。只检查本阶段生成的日志和报告，不要求未执行的完整runner或MainFlow；已有background原生探针可另行审计并明确标作未重跑证据。

用户延期前台测试后继续研修养成，candidate4/GDD0.4.9/schema2及其22图、五CPU和988项旅程结果作为旧基线冻结，不就地改包。当前GDD0.5.1/schema3源码必须重新运行八CPU（原五项加StudyProfileSmoke、StudyCombatSmoke、StudyUISmoke），full必须完整十项（八CPU、MainFlow、CampaignJourney）；suite校验读取明确案例集合，拒绝旧五项/七项摘要冒充增量通过。研修用例报告同时核对当前studies.json、UnitStats/SiegeBattle/单位配置或UI脚本指纹，开跑前后这些输入不得变化，包内再次核对报告与真实bundle字节。构建仍复制整个resources/scripts/tests，因此研修配置、实现和专用用例随新包提供；没有构建和运行的增量不承接candidate4通过结论。增量中已运行的30图报告保留原范围，追加详情/图鉴取景后以新32图报告重验，不改写旧通过依据。

StudyCombatSmoke通过要求matrix_cases为整数108，完整覆盖实际出生的英雄、等级及研修组合，不能沿用早期只校验显式修饰映射的报告。它同时提供studies_sha256，runner开跑前后和包内独立门禁均核对当前resources/studies.json；UnitStats、SiegeBattle及units.json指纹与phase=complete要求继续保留。

v0.11阶段工具边界验证通过79项Python单测；v0.12补日志异常保留和108真实出生组合门禁后，全84项通过。当前证据reports/runner_unit_tests.json记录实际discovery命令、程序/项目指纹及起止时间；覆盖CPU8/full10完整集合、研修报告缺失/伪造、输入并发改变、嵌套UI源码指纹、Art32必需名称与配置/图片哈希。单测只用临时目录和模拟子进程，不启动Godot，不作为研修实际战斗、真实取景、旅程或性能通过证据。

offscreen阶段无帧率、前台操作或真实关卡旅程的通过声明；即使四项全部通过，delivery_ready仍false。完整full阶段仍须原有MainFlow、全部旅程及正常前台Main24/64/2×门禁，并拒绝把background=true的Spine报告作为该阶段当前运行结果。各阶段报告独立保留，offscreen不会覆盖package_verification.json或package_background.json。

verify_spine默认不写resources/visuals.json，成功或失败都保留原字节、格式、状态来源等级与肖像配方指纹。本次报告仅包含当前选择的资源，记录config_sha256_before/after、config_unchanged及update_status_requested；只有作者显式--update-status阶段可写状态，成功的runtime_pass不降级已独立确认的visual_checked/performance_checked。包内验收不得使用该写入开关，native门禁要求config_unchanged=true、两个SHA均等于本包当前配置真实SHA且未请求写状态。每个原生进程仍隔离运行，完成标记只接受完整行，stdout/stderr共同经过严格ERROR与ObjectDB/Leaked instance检查；旧native失败或旧PASS不能混入本次覆盖。

reports根添加.gdignore，生成的差图和运行截图仅通过FileAccess使用，不参与编辑器资源扫描或重复导入。报告仍作为Git纯数据证据或本地截图保留；包内同样设置此隔离标记。

后台辅助shell保持隐藏，实际图形测试的Godot交互游戏采用正常显示启动；不把Hidden的最小化窗口结果当普通玩家帧率。最终Main性能报告必须记录window_mode、focused_frames、VSync、帧率上限和真实显卡，实际正常窗口、64原生/存活/可见及HUD均保持后才检查p95。

当程序式grab_focus不能稳定取得真实前台时，测试专用manual_gate在实际Main暖机后打印READY并等待隔离measure.ready（最多120秒）；由电脑操作工具点击已经观察到的游戏窗口，再写入gate开始300帧采样。等待帧不加入指标，期间不调用外部GPU查询，不反复抢焦点。夹具只用于验收，不出现在正式玩家流程。

包内保留最小复现工具与验收脚本。bootstrap_local.py、spine_pipeline.py、spine_upgrade_38_to_43.py必须共同复制；从包目录以 `--import-only --godot 包内程序` 执行两阶段导入。原始缓存不能复用，先在纹理最终路径完成PNG导入，再恢复atlas/JSON/TRES进行原生导入；两个阶段都须零错误。复制后清单记录项目版本、源文件SHA256及大小，包内测试报告不得直接拷贝源项目PASS结果。

最终门禁包括完整严格runner（战斗/存档/成长/设置/退出/真实界面/八关旅程）、21资源220原始动作逐进程探针、倍率/暂停/分组回归、普通24与64单位完整Main场景的真实显卡性能，以及原生网格刷新优化的全动作双视口差图。只认本包重新生成的报告；JSON passed、日志、退出码和版本/资源指纹共同检查。所有退出日志拒绝SCRIPT ERROR、ERROR、Leaked instance及ObjectDB instances泄漏。逻辑旅程验收与图像/性能验收分清范围。

生产策略取自本包project.godot：主renderer与mobile override一致，features对应当前renderer，driver/threads/thread_model为Safe；fantasy_siege/visuals的managed_mesh_redraw、frame_group_count和critical_instance_limit是战斗实际使用的同一份配置。验收命令不改变这些生产参数。Main24、Main64和Main64_2x各连续300帧，原生/存活/可见/托管人数、关键60Hz与其他30Hz人数、低优先级分组人数每帧均符合配置；测试覆盖不能只由末帧人数代替。必须保留真实1280×720视口、HUD和战斗飘字。生产策略覆盖或未提供完整逐帧预算时，即使平均帧率通过也拒绝交付。

run_checks的headless逻辑用例继续默认verbose；实际渲染用例默认普通生产日志，命令与玩家启动的日志模式一致。需要驱动/资源诊断时显式使用--verbose-render-diagnostics，逐项报告记录launch_mode与command_line，并在汇总记录诊断选项。verbose可能使宿主Vulkan loader的失效第三方层登记产生额外调试消息；诊断运行仍按原规则拒绝所有未豁免ERROR、SCRIPT ERROR和ObjectDB/Leaked instance，保留原文及FAIL，不把诊断结果重写成生产PASS。生产模式也拒绝同样的错误与泄漏；ObjectDB的普通退出摘要足以触发门禁，verbose仅用于展开细节。不更改Steam、系统注册表或Vulkan层环境，也不扩大错误忽略白名单。

verify_package.execute从开始即初始化安全输出上下文；进程完成后即使报告缺失、JSON损坏或后续门禁读取异常，package_case.log仍先保存本次stdout/stderr原文，再追加异常类型和验收失败原因，不用报告路径异常替代真正的Godot首因。超时保存partial stdout/stderr；进程未启动时记录准备/启动异常且不引用未定义run。所有异常继续FAIL，当前报告、完成标记、退出码、SCRIPT ERROR、ERROR和泄漏门禁保持原规则，失败证据不得重写成通过。

SpinePlayback分别验证生产默认与非托管对照，明确生产/对照身份及真实renderer，覆盖全部21个配置ID、暂停/1×/2×、30/60Hz和2/3/4组。MeshRedraw读取本包每套原始动画和皮肤，逐套核对完整动作名、皮肤集合、两朝向五个取景点及四次切换/暂停额外取景；21来源、220动作、全部2624次RGBA差图必须零差异。仅有总数或沿用旧GL报告不能替代当前生产renderer的覆盖。

MainFlow实际展示三页引导、设置、敌军与Boss规则、训练和编队、宽地图及胜利界面；验证模态打开时逻辑/骨架暂停、镜头和召唤不能穿透，关闭还原原暂停状态。待保存胜利关闭窗口时必须能重试领取或明确放弃；最后用窗口关闭处理函数等待音频实际排空后退出。图片人工复核文字截断、弹窗覆盖、全体真Spine轮廓和固定HUD，不能仅检查控件存在。

使用说明常显鼠标拖动/边缘/左右键、1—8、P、空格、F、F11、设置与指南入口；存档位置为独立Godot用户目录，重新启动保留已有进度。附字体/OFL、Godot/MIT与本地素材/运行库说明。D69及Spine原生库留在本地学习包，Git仅提交代码、原创音画、设计与可复现配置/工具，不上传受限纹理或素材截图。

最终交付提交并推送0.1.3版本分支，报告程序版本、测试范围、包路径与任何实际剩余问题。当前目标完成后不启动下一编号，因此main仍保留开始0.1.3时的同步状态，不把交付作为合并入口。旧TowerDefense及外部源包继续只读，source_guard最后核对336文件和Git状态。
