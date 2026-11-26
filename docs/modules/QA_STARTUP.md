# 验收进程首次启动隔离

> v0.4 · 2026-11-26 · GDD v0.5.14 / 程序0.1.3.0
> v0.4：验包工具按本包正式文档头读取启动规范版本及文件 SHA-256；缺失、格式错误或清单与实际文档不相符时验收失败。既有运行门槛沿用 v0.3。
> v0.3：指南后台检查与三页离屏图沿首次存档/后台宿主协议；当前完整管线从无缓存检出验证。
> v0.2：候选12首次run_start已是普通窗口而被拒绝；拆分原生窗口初始化、一次最小化设置及之后持续监控，保留实际时序证据。
> v0.1：登记首次自动加载前的存档隔离、独立引擎日志、真实新进程证据与窗口异常诊断；candidate11保持冻结。

## 问题与边界

现有夹具在deferred run中configure_path，晚于UserPrefs、GameAudio和ProfileStore的首次自动加载。Spine夹具未配置存档；引擎日志也在夹具运行前写入默认用户目录。只读检查时实际%APPDATA%/FantasySiege没有profile.json或preferences.json，不能据此声称真实进度被读取或改变，也不能把最小化状态变化归因于设置或用户。

普通玩家不携带QA参数时继续使用user://preferences.json和user://profile.json，实际Windows目录为%APPDATA%\FantasySiege。测试必须在本新项目或新候选包内启动，旧项目和来源只读。候选11及之前证据保留known_startup_isolation_gap=true；修正后的证据单独产生，不修改旧包。

## 启动协议

共享QAStartupContext静态上下文解析OS.get_cmdline_user_args中的--qa-save-root与--qa-startup-report。两者必须各有一个绝对路径，存档根限于当前项目tests/.user，启动报告限于当前项目reports。Python启动器在首个目录/文件写入前校验解析路径及链接，生成每进程独立目录和报告；--log-file置于Godot引擎参数部分，QA参数追加到既有用户参数末尾，保留Spine来源/输出路径等位置参数。

UserPrefs和ProfileStore在首次读取前解析默认路径；独立测试节点预配置的路径保留，但QA中所有后续读写路径仍须在tests/.user内。异常、缺少、重复或越界QA参数进入拒绝状态，跳过存档读写、阻止修改，并返回失败；不得回退真实user://。启动报告包含上下文合法性、实际首次load路径、读取路径/操作、初始设置与进度摘要、拒绝尝试及上下文/两存档脚本指纹。报告失败或证据缺失不得判通过。

后台QA不应用存档中的全屏设置，避免验收初次加载改动窗口；记录跳过原因。普通玩家全屏、音量和保存语义保持。编辑器导入只要求独立引擎日志，明确不承接玩法自动加载证据。引擎日志、stdout/stderr都须严格检查错误/泄漏并保留失败文件。

## 真进程验收

新测试从进程外预置隔离根的偏好和角色进度，再启动引擎，核对自动加载第一次即读指定值；增加future-schema初读保护、非法/重复/越界参数拒绝以及实际拒绝路径证据。只读取并哈希真实用户目录已有文件/日志，运行前后比对；不往真实目录写哨兵。不把仅检查参数文本或deferred configure_path当成首次隔离通过。

run_checks、verify_spine、generate_portraits、bootstrap_local与verify_package所有实际引擎启动采用同一辅助器；每次保存启动报告/引擎日志路径与SHA，并在包审计核对。后台CPU12、独立CampaignJourney、21来源原生探针、双Playback、Mesh2624差图、Art56须在新包复验。窗口状态不合格时保留首次无效的样本编号、时间及主窗/DisplayServer状态；不通过反复最小化隐藏无效取景。原因没有证据时保持未知。

CampaignJourney的独立resume进程同样传QA根和独立引擎日志/启动报告，冻结到旅程报告restart中并由runner审计。异常QA不立即终止引擎，允许拒绝夹具输出只读默认状态和真实拒绝轨迹；普通工具必须拒绝valid=false，预期拒绝仅在专用测试中判定。上下文和启动器覆盖受控测试环境的路径/链接检查，不宣称消除并发外部文件系统替换的所有竞态。

启动器自身的报告创建/删除/写入也在首个操作前预检；完整包独立重审CampaignJourney报告及子进程日志，不能只信runner父进程通过标记。Godot重写报告须恢复契约内整数计数，保持真实浮点数值和严格类型门禁。

本地制作还须在复制前拒绝exports/新候选目标链和bin/windows运行库目标上的现有链接或硬链接；不能等候选包bootstrap才发现已经写出项目。首写前预检与受控运行相配合，外部素材和旧项目始终只读。

本轮不增加玩法/货币/存档schema，不执行用户延期的前台MainFlow、Main24/64/2倍速，也不将本轮后台通过标为delivery_ready、performance_verified或commercial_ready。

## 后台原生窗口启动

candidate12后台阶段通过，两个Playback在run_start/sample0即Window与DisplayServer均为普通窗口、有效资源0/21，Mesh与Art离屏阶段同样被拒绝；包、日志和所有失败取景保留。此前_initialize调用最小化不足以建立采样所需窗口状态，具体引擎时序需独立真实进程确认，不归因于用户或偏好。

共享QABackgroundHost在deferred运行、根Window准备完成后发出一次最小化请求，记录请求前、请求后和布局帧后的模式/ready/时间；两种窗口模式确认最小化后才开始监控/取景。初始化与验收样本明确分开，不能把启动设置前的状态称为中途恢复。开始后不再改变窗口模式；任何实际无效帧/取景继续记录并失败，不重试最小化掩盖。普通前台夹具不调用此后台设置。

独立BackgroundHostSmoke在隐藏原生进程记录旧_initialize请求与run_start状态，再检验ready后的单次请求；不跑前台或帧率验收，不主动制造可见恢复。报告包含共享助手SHA、初始化轨迹、请求数与采样开始标识；工具和包门禁核对助手及状态证据。candidate12/GDD0.5.11冻结，不就地改包；新候选以GDD0.5.12重新导入和后台/离屏/旅程验证。

2026-11-23真实启动探针已复现：legacy_initialize_after时root_ready=false、节点mode=MINIMIZED但DisplayServer仍WINDOWED；run_start时root_ready=true且两者均WINDOWED。ready后共享助手只请求一次，立即得到两者MINIMIZED，下一帧确认后开始监控。最终9项检查、三帧实际监控以及当前GDD/fixture/helper SHA门禁均通过。原生API验证表明早期请求没有改变真实窗口，新请求在窗口准备后生效；不把历史中途变化归于这个已确认的初始时序。

监控保持到视口释放与音频关闭等待结束，随后采终态、停止监控并生成最终报告和退出码。不得先写passed再忽略清理阶段新增失败，末尾真实无效样本继续进入first-invalid证据。

## 候选13实测结果

2026-11-23，0d601c0源码制作的candidate13独立两阶段导入、首次启动8模式98项、后台CPU12/8919、窗口时序Smoke9项、21来源220动作、双Playback、2624次零差RGBA及Art56/13642全部通过；有效最小化取景与所有被监控帧均合格，Mesh监控持续至清理/音频关闭后。12张肖像实际重制24次取景全部合格，PNG与保留的旧字节一致，新manifest含制作宿主证据并在包内冻结。

独立旅程993项通过，首八关及末关重访、十二英魂、3500收益/960训练/2840余额、进程重启首次checkpoint恢复完整。源码复跑997比首次干净包多4次清理既有隔离档文件的检查；九次战斗数据一致，整数/阶段/经济/指纹门禁保持严格，不能硬套复跑计数。177 Python测试176通过/1 Windows文件symlink权限跳过，真实junction/hardlink与制作目标守卫测试均通过。105份包内日志严格致命错误/泄漏审计无异常，真实用户目录46份已有文件/日志、旧工程336哈希/Git及本项目main保持不变。

来源提交dfb2645/b1eab46/0d601c0，候选12失败包保留。此处与后续README/交付结果记录是对冻结包的补充，不就地修改包内设计文档或将其称为后来文档字节。当前known_startup_isolation_gap=false；delivery_ready、foreground_verified、performance_verified和commercial_release_verified仍false。证据reports/startup_candidate_0.1.3.json、startup_verification_local.json及同包frozen/独立报告。

## 源码验证进度

2026-11-23恢复开发后，8个真实新进程模式共98项通过，正常预置音量0.23、全屏偏好与关羽Lv7/731星砂均在首次自动加载时读到；future初读保护和六类非法参数拒绝通过，真实用户目录已有文件/日志哈希不变。CPU12/8919及各用例初读路径/操作证据通过。旅程修复FS061后997项通过，独立resume首次即读到完整checkpoint，末关重访后十二英魂/八关/2840星砂；checks为整数、program_version及子日志SHA独立复核通过。

制作与原生/离屏包内复验尚待新候选，不承接candidate11的通过结论。源码首次旅程997.0被严格拒绝的报告和日志保留startup_campaign_first_*，没有放宽计数门禁或改写失败证据。旧项目336哈希、分支/HEAD/工作区及本项目main保持不变。
