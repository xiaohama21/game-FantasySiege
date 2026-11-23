# 验收进程首次启动隔离

> v0.1 · 2026-11-20 · GDD v0.5.11 / 程序0.1.3.0
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

## 源码验证进度

2026-11-23恢复开发后，8个真实新进程模式共98项通过，正常预置音量0.23、全屏偏好与关羽Lv7/731星砂均在首次自动加载时读到；future初读保护和六类非法参数拒绝通过，真实用户目录已有文件/日志哈希不变。CPU12/8919及各用例初读路径/操作证据通过。旅程修复FS061后997项通过，独立resume首次即读到完整checkpoint，末关重访后十二英魂/八关/2840星砂；checks为整数、program_version及子日志SHA独立复核通过。

制作与原生/离屏包内复验尚待新候选，不承接candidate11的通过结论。源码首次旅程997.0被严格拒绝的报告和日志保留startup_campaign_first_*，没有放宽计数门禁或改写失败证据。旧项目336哈希、分支/HEAD/工作区及本项目main保持不变。
