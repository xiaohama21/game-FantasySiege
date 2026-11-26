# Windows本地学习版交付

> v0.25 · 2026-11-26 · GDD v0.5.14 / 程序0.1.3.0
> v0.25：候选15前台终验使用已独立导入、载荷逐字节相同的原始构建包，保留交付目录中已经归档的后台和离屏报告。
> v0.24：归档候选14在独立检出中的制作、指南和章节证据。候选14的验包工具写死了启动隔离规范版本；下一候选须从本包规范正式版本行读取版本，并在阶段报告中保存该文件的 SHA-256。候选重新在主工程 exports/windows 的新目录导入和验收。
> v0.23：统一当前与历史入口，明确源码/包内命令，补完整制作工具闭包及当前无缓存制作验证。
> v0.22：candidate12后台通过、离屏首窗无效拒绝并冻结；新候选核对后台初始化/助手SHA后独立复验。
> v0.21：首次启动隔离和独立引擎日志纳入包门禁；新进程初读/拒绝及真实用户目录哈希待验，candidate11冻结。
> v0.20：Art56新设置失败/临时返回两图与SettingsPanel指纹，增加列表/事务/槽位/冷重读回归；candidate9冻结。
> v0.19：字体调整后Art54增加UI主题/字体文件/manifest指纹与实际字形/字重门禁，旧GDD0.5.8重建包冻结不改。
> v0.18：从干净Git检出完整bootstrap到干净学习包的复现验收，补齐肖像与依赖制作阶段；旧候选包冻结，新增管线必须实证，不替代前台性能。
> v0.17：结算战报新增BattleReportSmoke/ResultUISmoke，CPU12/full14；Art54增加胜利/失败/未保存/恢复四种结算，验证战斗源码及UI指纹。总纲版本从当前同包文档解析，前台性能继续延期。
> v0.16：用户反馈后统一19枚原创SVG和属性组件，敌情/英魂/研修/编队/HUD减少重复文本；Art50追加Main及StatBadge源码SHA，完整Python104项通过。当前生成candidate7，前台项延期。
> v0.15：先登记敌情简报验收，再添加BriefingSmoke与BriefingUISmoke，当前CPU10/full12；ArtReview扩为50张，增加八关上下页与锁定/研修阵容18张必需取景。新增配置、总纲与程序指纹，candidate6仍冻结为GDD0.5.3/CPU8/Art32旧范围。
> v0.14：FS-036统一所有阶段Art32完整门禁；FS-037补实际Vulkan及300帧正常窗口/完整分辨率；FS-038补MainFlow持续窗口/焦点与15张取景证据。仅强化验收，candidate6保持原冻结范围。
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

verify_package的background阶段运行本包十CPU、21/220原生探针与静态payload检查；报告单独写package_background.json，并明确delivery_ready=false，不冒充最终包验证。隐藏窗口可用于离屏肖像/界面图像生成，不能作为性能数据。完整验收render命令读取本包project.godot实际默认backend，不能硬编码GL代替最终生产配置；Main24/64报告须核对采样300帧、完整焦点/正常窗口、真显卡/可见/存活/native/HUD和当前backend。

offscreen阶段单独写package_offscreen.json，串行执行本包生产SpinePlayback background、非托管对照unmanaged background、SpineMeshRedraw background和隐藏ArtReview；全部图形子进程请求SW_HIDE启动，并在原生窗口就绪后确认最小化再取景；这不证明操作系统焦点在启动全程未变。初始及结束均复核payload与十二肖像哈希。两套Playback须background=true、performance_measured=false、真实Vulkan驱动、主窗/DisplayServer均MODE_MINIMIZED且21来源验证期间保持此状态；Mesh还须全部2624次取景均在有效最小化主窗中完成、两1000×760透明2D子视口、21来源220动作及RGBA零差异。ArtReview须主窗最小化、50份1280×720取景与对应文件哈希、十二肖像、零文字溢出和音频排空；八张art_study_locked/unowned/ready/base/sweep/heal/siege/slow以及art_hero_studied、art_gallery_studied必须分别存在，核对研修后英雄详情和图鉴同源属性、技能读数，新增18张敌情取景要求见下文。只检查本阶段生成的日志和报告，不要求未执行的完整runner或MainFlow；已有background原生探针可另行审计并明确标作未重跑证据。

研修养成阶段将candidate4/GDD0.4.9/schema2及其22图、五CPU和988项旅程结果作为旧基线冻结，不就地改包。GDD0.5.4/schema3研修源码验收范围为八CPU（原五项加StudyProfileSmoke、StudyCombatSmoke、StudyUISmoke）及十full（八CPU、MainFlow、CampaignJourney）。研修用例报告同时核对studies.json、UnitStats/SiegeBattle/单位配置或UI脚本指纹，开跑前后这些输入不得变化，包内再次核对报告与真实bundle字节。构建仍复制整个resources/scripts/tests，因此研修配置、实现和专用用例随新包提供；没有构建和运行的增量不承接candidate4通过结论。该增量曾运行的30图报告保留原范围，追加详情/图鉴取景后以新32图报告重验，不改写旧通过依据；新敌情增量采用下文CPU10/full12/Art50范围。

StudyCombatSmoke通过要求matrix_cases为整数108，完整覆盖实际出生的英雄、等级及研修组合，不能沿用早期只校验显式修饰映射的报告。它同时提供studies_sha256，runner开跑前后和包内独立门禁均核对当前resources/studies.json；UnitStats、SiegeBattle及units.json指纹与phase=complete要求继续保留。

GDD0.5.5增加BriefingSmoke与BriefingUISmoke，当前background与CPU runner必须完整十项，full必须完整十二项；上文八CPU/十full/32图为研修及candidate6的历史验收范围。BriefingSmoke要求八关与108个英雄/等级/路线组合，计划时间和敌军配方数值对照真实SiegeBattle；BriefingUISmoke使用真实Main的敌情入口、锁定权限、设置模态、未来schema浏览保护及保存后更新，全部使用隔离存档。两份报告均记录当前总纲版本/哈希、briefings/studies/stages/units配置和BattleBriefing/UnitStats/SiegeBattle脚本SHA，UI另核对Main脚本；runner开跑前后与包审计共同核对，拒绝缺失、伪造或运行期间改动的输入。

当前ArtReview共有50张1280×720真实取景，原十个研修名称继续保留，新增art_briefing_stage_01至08及对应_lower、art_briefing_locked和art_briefing_studied共18个必需名称。报告另提供briefings_sha256与briefing_script_sha256，逐图核对名称唯一、实际PNG尺寸/完整性和SHA、十二肖像、零文字溢出、主窗最小化及音频排空。full/offscreen消费同一50图门禁；candidate6原32图只保留旧范围，不能承接新敌情增量。未来schema提示条与三个敌情按钮须分离，逻辑界面夹具验证其矩形不相交。

v0.11阶段工具边界验证通过79项Python单测；v0.12补日志异常保留和108真实出生组合门禁后，全84项通过；v0.14完整门禁强化后，全96项通过。证据reports/runner_unit_tests.json记录实际discovery命令、程序/项目指纹及起止时间。单测只用临时目录和模拟子进程，不启动Godot，不作为实际战斗、真实取景、旅程或性能通过证据。v0.15按当前CPU10/full12集合另验；旧CPU8/Art32通过记录不能替代新简报验收。

offscreen阶段无帧率、前台操作或真实关卡旅程的通过声明；即使四项全部通过，delivery_ready仍false。完整full阶段仍须原有MainFlow、全部旅程及正常前台Main24/64/2×门禁，并拒绝把background=true的Spine报告作为该阶段当前运行结果。各阶段报告独立保留，offscreen不会覆盖package_verification.json或package_background.json。

ArtReview无论由full还是offscreen阶段执行，均采用同一套最小化主窗、50张独立取景、十个研修与十八个敌情必需名称、studies/briefings配置及BattleBriefing脚本指纹、1280×720尺寸、真实图片SHA、十二肖像、零文字溢出及音频排空门禁。full不能仅凭ArtReview的passed字段跳过这些要求；三份Spine播放/对照/差图在full仍必须为非background报告。图片尺寸同时核对报告声明与实际PNG signature/IHDR，标准库检查PNG数据块及结尾完整性，支持RGB/RGBA而不依赖Pillow；缺失、截断或真实尺寸不符均失败。

Main性能必须actual_rendering_driver为vulkan，normal_window_frames与full_resolution_frames均为严格整数300；前者逐帧核对主窗及DisplayServer均普通窗口且可见，后者逐帧核对主窗与DisplayServer均1280×720。现有末帧尺寸、window_mode/visible、300帧焦点/HUD、全部原生/存活/可见人数、托管预算和FPS/p95门禁继续保留，不能用末帧恢复窗口或分辨率替代全程。

MainFlow报告须记录严格整数且大于0的host_observed_frames，host_normal_window_frames和host_focused_frames均严格等于观察帧数；持续观察要求主窗与DisplayServer非最小化、可见且有焦点，保留真实F11全屏测试。最终音频释放/窗口关闭后停止观察，不把退出后的帧加入窗口通过数。capture_states与screenshots严格对应现有15张取景，每项含name/path/sha256/size/window_mode/display_window_mode/window_visible/focused/actual_rendering_driver；取景时两种窗口模式均为0、可见聚焦、实际vulkan及1280×720，文件在本包reports/runtime中且路径、尺寸、SHA对应。engine_input_dispatch_verified=true仅证明引擎输入派发回归，os_input_verified=false保留范围，不能标人工电脑操作通过。MainFlow独立报告SHA与完整runner记录再次核对，Art32不能替代此15图前台证据。

MainFlow共享门禁位于run_checks.py，单项--only、完整--visual、包full及读取式审计均消费同一窗口/取景/范围约束；包工具不反向导入。15张取景的实际PNG尺寸与SHA同样核对，不能以声明size或重复取景条目冒充正常窗口验收。

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

## GDD0.5.6 图标与敌情增量

用户指出首版敌情信息混乱后，本轮增加19枚可复现原创SVG与StatBadge组件；敌军卡片、属性六格、统一威胁/反制词条及Boss阶段块替代重复长段落。英魂详情、研修收益/代价、编队费用/冷却和HUD脉冲也同步。原Art50=4815仅首版范围，首轮图标Art50=6189保留实际阶段；最终源Art50=6253、零文字溢出、Main/widget/配置指纹匹配，另有实际Main交互/中央数值后台证据。前台流程、24/64/2倍速依用户安排延期。

当前CPU10/full12（包含BriefingSmoke与BriefingUISmoke），包内必须重新运行十个后台案例与独立旅程。Art50在full/offscreen共同核对main_sha256与stat_badge_sha256；只检查配置而不约束UI源码的新报告不能通过。104项Python边界用例覆盖Main/widget缺失、伪造及取景后源码变更。assets/ui与StatBadge随包复制，SVG生成器为源仓库工具，不依赖用户游戏运行环境。

candidate7以GDD0.5.6冻结源码与文档，后台/离屏/旅程结果按实际新包登记；candidate6/GDD0.5.3及原32图证据不改写。两种包均不能以后台通过宣称delivery_ready或商业发行通过。

candidate7实际验收完成：十项CPU8147，原生21来源220动作、十二肖像/完整payload，生产与非托管播放、2624次RGBA零差、Art50/6253及独立新档八关/重启/重访988项均通过。41份日志无致命错误或泄漏，50个核心源码/配置/图标字节与源项目一致。证据为reports/briefing_candidate_0.1.3.json与包内checks_background_frozen/checks_campaign_frozen、package_background/package_offscreen及各独立报告。正常前台MainFlow和Main24/Main64/Main64_2x继续按用户安排延期，delivery_ready=false；该结论为增量本地学习候选通过。

## GDD0.5.7 结算战报验收设计

结算复盘由实际命中、有效生命变化、成功动作与脉冲取消记录生成；BattleReportSmoke与ResultUISmoke将覆盖有效伤害/治疗/攻城、范围归属、召唤和阵亡、脉冲打断、暂停/倍速、结束冻结/重开归零，以及真实Main领奖失败/重试和后续导航。新用例进入CPU12，完整阶段为full14；只登记接口不等于运行通过，实际程序运行由本轮主任务统一安排。

ArtReview由50增至54，新增art_result_victory、art_result_defeat、art_result_unsaved、art_result_recovered四个必需取景。图像需当前Main、StatBadge与SiegeBattle字节指纹一致，所有阶段复用图片完整性、零文字溢出与音频排空门禁。candidate7/GDD0.5.6保持冻结，新增源码不能承接其8147/6253/988通过结论；新候选包再次按后台、独立旅程与离屏范围运行。前台MainFlow、Main24/Main64/2×和商业许可范围仍独立。

2026-11-20 candidate8实际验收：BattleReportSmoke190项、ResultUISmoke221项/3实际胜利与1失败，覆盖有效贡献/归因/结束冻结、领奖失败与成功重试回执、重复渲染不领奖、导航/模态/未来存档保护及图鉴语义。新包CPU12共8558项、Art54共6973项且零文字溢出，原生21/220、双播放和2624次像素零差，以及独立八关/重启/重访988项均通过。43份应用日志无致命错误或泄漏，核心源码/配置/图标与源项目逐字节匹配。证据reports/battle_report_candidate_0.1.3.json与包内frozen checks及各独立报告；candidate7原范围保留。正常前台MainFlow、Main24/Main64/2倍速以及full14仍按用户安排待验，delivery_ready=false。

## 干净Git检出与完整bootstrap（本轮设计）

完整bootstrap在当前项目执行扫描、21套结构转换及配方生成，要求本次转换报告恰好覆盖目标ID且全部converted，任何失败非零退出，保留失败结果，不继续原生/肖像步骤。独立import使用已有spine_catalog.json时，清单source_root与当前参数解析后必须一致，目录外的原始文件不得被当成当前来源；不一致应明确拒绝并提示重新scan，不悄悄导入另一源。

带--godot的完整制作流程：两阶段纹理/原生导入→显式21套原生作者验证并--update-status→十二真实透明Spine肖像生成与检查→新肖像编辑器导入→默认只读原生/肖像复核。作者状态更新在派生肖像前完成，冻结之后不再改配方。--import-only保留只导入已复制素材的含义，不扫描来源、不生成新配方、不重新制作肖像；未提供--godot的转换模式只能声明已转换，不能声明完整运行依赖就绪。bootstrap报告记各阶段/目标ID/路径/退出码与冻结配方SHA，失败不发布ready。

复现使用F:/godotProject/FantasySiege/build下的新Git检出，起点记录实际HEAD；初始不得有.godot、assets/actors、assets/portraits或bin。明确只读D69源与原生库捐赠目录；不借主项目缓存、已派生角色或肖像。完成全流程后，在检出自己的exports/windows下创建新空学习包，包内后台/离屏/完整旅程验证；旧项目/D69读取前后校验，受限依赖和衍生文件不入Git。纯Python临时目录验证转换拒绝、清单不一致、缺ID/失败ID、步骤顺序与失败停止；实际Godot由root串行调度。资源盘点/转换/原生/图像/性能范围仍分开，前台Main24/64/2倍速保持用户延期。

2026-11-20干净检出实际验收完成：从本项目Git提交04244668创建build/repro-04244668，初始.godot、actors、portraits和bin全部不存在。完整bootstrap十阶段成功，21套作者探针更新后冻结配方，十二肖像重新制作/导入及只读复核通过。当前atlas实际引用的84份派生资源与主项目逐字节一致，105个D69原始输入和4个捐赠运行库文件前后SHA不变，档案/来源哈希105项相符；旧工程336文件与Git状态保持不变。21完整配方语义一致，原字节差异实证仅LF/CRLF，两个真实SHA各自保留，未为凑哈希重写资源。主项目097旧纹理别名未被图集引用，未借入新检出。

该检出自行构建exports/windows/FantasySiege-0.1.3.0-rebuilt-1，无主项目缓存/肖像复制。包CPU12/8558、21来源/220原始动作、十二肖像、双播放模式、2624零差像素、Art54/6973零文字溢出和独立完整旅程988均通过；80份当前运行日志无致命错误或泄漏。Python全量130项中129通过、1因Windows符号链接创建权限跳过，5类目录junction和9类hardlink哨兵测试实测通过。报告reports/rebuild_candidate_0.1.3.json，详细原文件/阶段/快照SHA证据本地保留。首次独立汇总把builder新生成reports/.gdignore误认为复制来源文件，失败报告保留；修正来源分类后重核，包及载荷manifest门禁未更改。foreground/performance/commercial/delivery_ready仍false。

GDD0.5.9字体验收设计：ArtReview报告ui_style_sha256、font_manifest_sha256、font_binary_sha256、font_body_sha256、font_emphasis_sha256、ui_font_family、body_weight、emphasis_weight、font_engine_weights、font_engine_coordinates与font_glyph_check；门禁必须与同包实际UIStyle、字体manifest/二进制及400/600一致，拒绝缺字段或旧字体截图。54取景/必要页名/PNG SHA/尺寸、零文字溢出及既有战报、配置、Spine指纹继续有效；原生像素/前台性能范围不外推字体结果。

2026-11-20字体验收实际完成：新字体为本机Noto Sans SC只读副本，原字节SHA763146584cf0710223441356b4395e279021b0806c196614377a7a0174ae074a保持不变，OFL声明含Adobe2014–2021/RFN Source，与嵌入许可一致。实际来源/内部non-release版本及upstream_hash_verified=false如实保留；不冒称下载官方发行版。fontTools核对当前UI/资源797码点全部覆盖。FontVariation以整数OpenType轴标签2003265652应用正文400、标题/按钮/关键数字600，原生TextServer每个RID坐标均证实生效。

candidate9已完成自己的纹理/原生导入及包内CPU12/8558、21来源/220动作、十二头像、双播放、2624零差像素、Art54/13087零缺字/文字溢出，以及独立完整旅程988。137项Python中136通过、1权限相关跳过。49份运行日志（含保留的首轮无效窗口日志）严格致命错误/泄漏审计通过；原字体副本、旧工程336文件及main保持不变。首次字重属性通过但渲染仍Thin的54图/报告保留，FS053修正后重新取景；包首离屏差图虽然像素零差，但窗口在589/2624后恢复被严格拒绝，报告冻结offscreen_first，标准离屏阶段重跑后2624/2624最小化取景全部合格，未放宽门禁。人工抽检确认数字和中文笔画清晰、信息层级保持且无新增遮挡。

可运行包exports/windows/FantasySiege-0.1.3.0-candidate-9，证据reports/font_candidate_0.1.3.json及包内frozen/独立报告，代码提交4594905。candidate8/GDD0.5.7及干净rebuild/GDD0.5.8保留原字体/范围不变。前台MainFlow、Main24/Main64/2倍速、full14和商业许可仍未验收，delivery_ready=false；持续目标保持运行，下一轮继续列表滚动/选中可见及设置临时返回常显后果的界面优化。

## 列表导航与未保存设置（设计先行）

英魂、研修、编队各维护会话内滚动位置，离开、选择角色及成功/失败事务刷新前捕获真实scroll_vertical；布局完成后恢复并合法限幅。选择新角色使当前卡完全进入列表视口；首次进入或其他页改变全局选择时也使新选中卡可见，有记录且选择不变的返回/事务刷新尊重原位置。新任务代次/控件实例保护废弃旧延迟回调，快速切页或开战不能被旧列表恢复改写。状态不入ProfileStore/UserPrefs，不改变三属性、公式、交易原子性、模态权限或存档schema。

编队已出战卡常显实际数组index+1号位，对应战斗1—8召唤键；加入/移出后用真正保存的roster更新号位，保存失败显示原槽位，不增加排序或新规则。必要“至少一名、最多八名、点击即保存”说明保留。

设置保存失败时，错误信息与常显后果分开：当前设置立即生效但尚未保存；若之后仍未保存，重启恢复原保存设置。按钮“暂不保存并返回”说明当前动作，不隐藏后果在tooltip。文案用条件“若之后仍未保存”，因为窗口退出或后续重试仍可能保存成功。保留dirty、运行时值、失败原档和暂停恢复，明确返回不额外flush；未来schema/无服务状态仍只读。正常保存成功、失败后继续调整、明确临时返回及新进程/新Prefs实例读原保存值要验证。

扩展StudyUISmoke：下半部选择、训练/解锁/切路线/恢复基础和编队成功/失败刷新位置、跨页独立状态、选中卡实际视口矩形、快速切页旧回调无效、真实槽位1—8与拒绝事务不变。PreferencesSmoke检查保存失败常显后果、返回dirty/值/磁盘不变和冷重读原值；模态原测试保留。Art从54扩至56，新增art_settings_save_failed、art_settings_temporary_return，原英魂末位/研修/编队下半图重新取景并检查选中可见/真实号位。UIStyle/FontVariation实际400/600、字体与所有既有图片/原生/配置/战报指纹门禁不放宽；新增SettingsPanel原字节SHA。前台MainFlow、Main24/64/2倍速仍延期，离屏不替代前台性能。

视觉抽检补充：研修保存toast与y641页尾规则相交，提示需放在规则下方独立区（例如y678/40px），保留完整规则和可见错误；实际矩形不相交纳入StudyUISmoke与Art56的研修取景。候选10保留发现该缺陷时的冻结范围，修正后新候选重新验收。

2026-11-20本轮实际完成：英魂/研修/编队按真实内容坐标保留会话滚动，末位→首位、重复选择、同步选择/交易重建及快速切页/开战废弃旧任务通过；保存成功/失败不丢位置。编队常显实际已保存1—8号位。设置保存失败常显当前立即生效但未落盘的条件后果，明确返回不flush且保留dirty，冷读原值、后续重试成功及future/no service只读保护均通过。研修toast独立y678区域不遮y641规则；6种真实提示的文字与矩形证据全部符合。

candidate11自行导入并验包：CPU12/8919、StudyUI1514（导航327、6种toast矩形）、Prefs103、Art56/13639零缺字/文字溢出，21来源/220原始动作、十二头像、双播放、2624零差像素、独立完整旅程988全部通过；实际字体400/600不变。144个Python用例143通过/1符号链接权限跳过；49份日志（含保留窗口失效历史）严格致命错误/泄漏审计无异常。代码7e50d61及reports/navigation_candidate_0.1.3.json记录真实范围。candidate10保留旧研修toast与unmanaged窗口失效，candidate11首轮mesh仅2513/2624有效最小化捕获被拒绝，报告保留offscreen_first，标准离屏重跑后全部2624有效，不放宽门禁。首次列表/属性夹具失败和首次自动溢出门禁未发现toast遮挡的图/报告均保留。

上述范围证明显式fixture路径、事务、实际布局及像素与窗口条件；另一次只读审计证实Spine启动夹具未在首次autoload读取前隔离默认user://，引擎日志也仍落入APPDATA/FantasySiege，文档的Godot/app_userdata路径不准确。当前真实目录没有profile/prefs文件，不能声称已读取真实进度，也不能将窗口变化归因于偏好或用户。known_startup_isolation_gap=true，下一轮补首次启动QA路径、独立--log-file、窗口状态转变证据及真实保存位置说明。前台MainFlow/Main24/Main64/2倍速、完整full14与商业许可仍未验收，delivery_ready=false；持续目标保持运行，不以本轮图形/UI通过缩小完成定义。


## 首次启动隔离增量

设计与验收协议见[QA_STARTUP.md](QA_STARTUP.md)。当前登记设计，运行结果和新候选证据另记；candidate11已通过范围及known_startup_isolation_gap=true保持冻结。

## candidate13后台学习包

2026-11-23新增独立包exports/windows/FantasySiege-0.1.3.0-candidate-13，源码0d601c0；两导入阶段及独立引擎日志、8模式98首次存档检查、CPU12/8919、21来源220动作、12肖像、双播放、2624零差像素、56图13642检查和独立新档/重启/重访旅程993项通过。Noto Sans SC实际正文400/强调600、零缺字和文字溢出。177工具测试176通过/1权限跳过，105包内日志严格核验；main和旧项目保持不变。

窗口设置在root ready后的唯一请求完成，原生两API确认后才取景，清理等待也纳入监控。12肖像在源码重新渲染24/24最小化取景通过，PNG不变；新制作manifest随包冻结，包内只读检查不重写资产。候选12因首窗0/0被拒绝，包与全部失败资料保留，未放宽门禁。993与复跑997差异来自四个原本不存在的测试档清理项，实际九战和养成结果一致。

启动“开始游戏.cmd”可体验本地学习版。保存位置%APPDATA%\FantasySiege；QA独立tests/.user和引擎日志。代码/设计/工具在0.1.3同步，未合并main。此增量已关闭首次隔离缺口，完整前台MainFlow/24/64/2倍速及商业许可仍未验收，不能称最终交付或商业就绪。总证据reports/startup_candidate_0.1.3.json；本节是冻结包之后的验收记录，包内原设计源字节不改。


## 候选13交付时的入口与后续制作计划

当时可运行候选为13，历史基础包/候选及失败证据只保留历史标签；README区分源码PS命令和包内Python命令。源码默认build_local会拒绝已有非空目标，须指定新空Destination，不能覆盖任何冻结候选。

完整bootstrap实际调用spine_pipeline、spine_upgrade、tune_visuals、verify_spine、generate_portraits以及run_checks/qa_launch辅助器，显式构建清单必须形成这一闭包；缺工具在首个制作写入前失败。当前待验增量将tune_visuals补入新包，并从无actors/bin/portraits/.godot的Git检出完整制作，记录来源/原生库哈希、作者冻结SHA、24次肖像取景、第三编辑器导入及只读复核。旧转换器两个文件未变，既有105输入/84派生证据仍有效，新的组合绑定必须实际验证。

后台宿主初始化前可能显示/聚焦普通窗口，现有隐藏启动请求不构成全程无焦点变化的证据；只能按确认后的采样窗口状态报告最小化通过。前台与人工操作仍延期。

## 候选14的干净制作与首次指南

独立检出 `c05a36b0` 的初态没有角色、肖像、原生库和 Godot 缓存。105份D69源文件和4份运行库输入的前后哈希一致；十阶段制作完成，21套骨架通过作者与只读两轮逐进程验证，12张肖像共24次取景通过。主检出、独立检出与候选14之间的84份实际派生资源逐字节一致。旧工程336文件及Git状态通过只读比对。

候选14的261项载荷、13个后台用例共9056项、8个隔离启动进程98项、21套/220个原生动作、2624次像素比较、59张离屏截图14260项及独立旅程993项通过。首关指南137项，新增的召唤、镜头与脉冲三页均已逐张查看。107份日志没有致命错误或泄漏。工具单元测试188项中187项通过，1项因Windows文件符号链接权限跳过。

该包两份阶段报告的启动规范标签为0.2，同包文档为0.3，原报告保持冻结。制作、包内交叉检查和三页图像的相对路径与哈希分别见 `reports/guide_authoring_0.1.3.json`、`reports/guide_package_0.1.3.json` 和 `reports/guide_visual_review_0.1.3.json`。正常窗口 MainFlow、24/64人和双倍速性能、人工键鼠和听感另行验收。

## 候选15的本地交付

2026-11-26，从源码 `7eab511`（GDD v0.5.14）建立无共享 Git 对象硬链接的独立检出，从105份只读源文件和4份运行库重新完成十阶段制作。21套骨架和12张肖像均经只读复核，12张重新制作的肖像与候选14逐字节相同。独立检出生成包后，仅按原始清单复制261项交付文件及清单，交付目录重新以自己的引擎完成纹理和原生两次导入。原始清单 SHA-256 为 `d722edc340681d4c3cf102b2e972511abb368ee4f81c759e7501849218a77b04`，两个目录的清单与载荷一致。

本机入口为 `exports/windows/FantasySiege-0.1.3.0-candidate-15/开始游戏.cmd`。在此目录依次完成后台、离屏和独立章节旅程，包内的 `checks_background_frozen.json` 和 `checks_campaign_frozen.json` 保留各自结果。13个后台用例9056项通过，其中指南137项；启动隔离8个进程98项，21套220个原生动作，2624组渲染像素零差异。59张界面图14260项检查通过，零缺字、零文本溢出。九场旅程993项通过，八关首通、独立进程恢复、12名英魂和末关重访后的2840星砂均有记录。107份日志无致命错误或泄漏；旧工程336个文件及Git状态比对通过。

后台和离屏两份报告均绑定包内 QA_STARTUP v0.4 及其 SHA-256。完整文档、截图与运行记录的哈希见 `reports/learning_candidate_0.1.3.json`。正常窗口 MainFlow、24/64人及64人双倍速、实体输入与人工听感仍待验；本地学习包保留在版本分支，D69素材与原生库只在本机使用。

独立查看最终交付目录的三张指南图，召唤快捷键、镜头控制、脉冲消耗与冷却、末页“开始远征”均能完整读到。与候选14相比，三页截图均只有指南面板外的画面像素发生变化。逐图记录见 `reports/learning_guide_review_0.1.3.json`。

### 继续候选15的前台终验

完整验包会重新生成指南、八关旅程、原生动作及画面报告，还会写入与离屏阶段同名的59张截图。直接在交付目录执行会使已经归档的哈希失去对应文件。原始构建包和交付包的261项文件及构建清单已逐项比对，两个包各有自己的导入缓存。原始构建包两份引擎导入日志的路径和哈希已核对，尚无 `package_verification.json`。

桌面可用于前台验收时，在 PowerShell 执行下列命令。工具使用这个构建包的引擎、隔离存档与完整门槛。结果写到 `$qaPackage/reports/package_verification.json`，与本节记录的共同清单哈希对应。

```powershell
$qaPackage = 'F:/godotProject/FantasySiege/build/repro-7eab511898f8-candidate15/exports/windows/FantasySiege-0.1.3.0-candidate-15'
python -B "$qaPackage/tools/verify_package.py" --package "$qaPackage" --phase full
```

人工键鼠与听感在另一场正常游戏中记录。以下命令沿用包内 `qa_launch` 为这场试玩建立新的测试存档及日志。可在首关用鼠标点选、用数字键召唤、拖动镜头，并实际试听音乐、召唤和脉冲音效；另记执行了哪些操作、听到了什么。进程退出后打印的结果仅用于确认隔离路径和日志。

```powershell
@'
import subprocess, sys
from pathlib import Path
package = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(package / 'tools'))
import qa_launch, run_checks
session = qa_launch.prepare_launch([str(package / 'FantasySiege.exe'), '--path', str(package)], package, 'manual_input_audio')
game = subprocess.run(session.command, cwd=package)
result = qa_launch.validate_evidence(session, run_checks.fatal_lines)
print('Isolation:', result['passed'], 'Engine log:', result['engine_log'], 'Errors:', result['errors'])
sys.exit(game.returncode or int(not result['passed']))
'@ | python -B - $qaPackage
```
