# 完整体验与学习版验收

> v0.7 · 2026-11-19 · GDD v0.4.8 / 程序0.1.3.0
> v0.7：完整旅程报告从同项目/同包docs/GAME_DESIGN.md读取GDD标题版本行及SHA256，恢复进程核对同一文档，移除硬编码版本元数据；战斗、训练、奖励数量与旅程流程不变。
> v0.6：Boss进入阶段时，中文HUD提示按事件世界位置匹配已触发阶段的Boss，并读取special.phase_name；不以固定名称或尚未触发的附近Boss替代。
> v0.5：精确分离Godot verbose中NVAPI既有配置登记诊断（code -167），其余错误与全部泄漏继续拒绝，原文保留在报告。
> v0.4：模态内独占键盘焦点、底层按钮回调防护；设置写盘失败必须提示，窗口关闭允许重试或明确放弃未保存内容。
> v0.3：退出以WeakRef确认实际Playback排空；验收runner纳入偏好/声音/完整旅程并强制新报告、当前项目版本及零错误/泄漏。
> v0.2：正常窗口关闭先释放音乐/播放器并等混音引用清理；未保存奖励退出必须明确重试或放弃。
> v0.1：定稿引导、原创声音、独立设置、百科和完整玩家旅程。

日志门禁仅将整行 `NVAPI: Error creating application: NVAPI_EXECUTABLE_ALREADY_IN_USE(code -167)` 识别为既有驱动应用配置的verbose诊断，并在diagnostic_log_lines保留原文。它不代表脚本或音频错误；其他NVAPI错误、Godot ERROR、SCRIPT ERROR及所有ObjectDB/Leaked instance继续失败，不按前缀批量忽略。

操作引导采用三页可跳过弹窗，营地“操作指南”可重看；第一次首关展示，暂停逻辑与骨架，关闭后还原打开前暂停状态。指引不扣资源、不强制替换阵容：重复召唤/自动能量→鼠标拖动、边缘与左右键/暂停观察→P脉冲80能量35秒冷却、打断前线重击及右基地胜利。首胜持久保存后提醒训练与八人编队。开场story_intro与已有hint常显，Boss0.75/0.85秒前摇按实际字段解释。

UserPrefs独立preferences.json（schema1），字段master_volume、music_volume、sfx_volume（0–1）、fullscreen、damage_numbers、edge_scroll、tutorial_seen。原子写入与失败提示；不能读写旧项目存档。提供configure_path、get_value、set_value、flush接口供隔离验收。F11全屏，设置窗口支持主/音乐/音效音量、全屏、飘字、边缘滚动；关闭恢复打开前暂停状态。

GameAudio独立自动加载，play_cue(name)、set_context(camp/battle)、stop接口；按UserPrefs调音量，短音效节流与固定播放池。原创Python标准库生成WAV：click、summon、hit、heal、pulse、warning、victory、defeat、train及轻柔循环ambient；生成脚本与原创WAV可入Git，第三方说明标为本项目原创。音乐循环不依赖在线服务或外部播放器。

英魂/敌军百科不显示D69技术ID；角色姓名、职责、技能名称、效果、伤害类型和三属性可读。治疗量/減速时长按UnitStats实际结果计算；物理/魔法/真实伤害与攻城倍率常显。Boss面板显示前摇、范围、半血加成、推退25%及脉冲反制；出现关卡从stages.waves推导。角色详情继续允许未拥有浏览但禁训练。

HUD刷新上限10Hz，按钮操作后立即刷新。飘字最多24个复用Label，离屏命中不创建新实例；状态预警与脉冲环仍保留，所有效果不触发逻辑伤害。Boss阶段提示读取实际触发者的special.phase_name，分别展示“裂甲狂潮”与“过热锻击”；以事件世界位置、队伍和已进入phase状态匹配，未匹配时使用通用首领强化提示，不猜测最近Boss。设置/引导覆盖HUD，期间鼠标与按键不能穿过模态窗口移动地图或触发战斗。

模态打开时暂时禁用底层Control的键盘焦点，焦点只在当前弹窗内流转；关闭按栈恢复原焦点模式与原焦点。底层按钮即使收到程序化pressed信号也不得执行动作。退出确认可叠在设置上，恢复时先回到设置。暂停/倍速入口也显式拒绝模态调用。

F11修改或保存失败常显具体提示。正常关闭仅对有待写变更的设置尝试flush，写盘失败时暂停战斗并显示“设置尚未保存”，可重试或明确放弃；若同时有待领奖胜利，确认说明同时覆盖奖励与设置。未改动的未来版本偏好保持只读，正常退出不因无须写盘而受阻。

CampaignJourney使用隔离存档，训练与编队经Main接口，固定步真实推进并由胜利信号保存奖励。路径：前三关Lv1/8初始；关4前铁卫/烬羽/符医/关羽至2并换入star；关5换rivet；关6四核心至3；关7换moon；关8四核心至4；全通余额2580、拥有12、已通8。重启后换入beast，重访第8关仅获260、无额外角色/首通。加速事务/战斗验收与native图像/播放/性能分开报告范围，不能声称无渲染测试已经验收画面。

旅程报告的gdd_version、gdd_header与gdd_sha256从当前res://docs/GAME_DESIGN.md取得：header保留实际“文档 v…”整行，version解析该行，SHA256对应同文件原始字节。总纲必须随本地包提供，不以源项目的外部文档或硬编码版本替代。独立恢复进程核对报告元数据与同包当前总纲一致；缺少文档、无法解析版本或文件改变时报告失败。该元数据校验不改变角色/关卡/奖励数量、战斗策略或新档→重启→重访流程。

最终包从干净目录构建，复制本地Godot/原生库/21来源资产，先纹理后原生导入；不复制源.import/.uid。包内全部21/220原生验证、完整流程图、设置和引导、64完整场景性能通过后才能称本地学习版完成。原生库/角色纹理和素材截图仍排除Git，主分支只在启动下个编号时同步。

正常窗口关闭由Main接管：保存独立设置，await GameAudio.shutdown()后退出。声音管理器释放播放器/缓存，并以WeakRef每20ms异步确认实际Playback已排空，上限1秒，超时记录error_message；不能仅等待固定时长即称清理成功。Engine强制--quit-after诊断绕过正常关闭流程，不用于声称优雅退出通过。待领奖胜利收到关闭请求时提供“重试领取”或“仍然退出·本次奖励不保存”，不静默失去奖励。

严格验收tools/run_checks.py默认运行BattleSmoke、ProfileSmoke、ProgressionSmoke、PreferencesSmoke、AudioShutdownSmoke五项CPU检查；--visual额外包括实际渲染MainFlow及仍以headless运行的CampaignJourney，--only可选七项中的任一项。每个用例开始前清除其旧报告，记录开始/结束时戳、当前project.godot哈希与程序版本，并检查新报告生成时间及运行期间项目没有变化。进程退出0、正确父级完成标记、新JSON中的passed严格为true且日志无ERROR、Leaked instance、ObjectDB instances才通过；CampaignJourney还须父级完成标记及phase=complete，子进程/中途checkpoint不能替代最终旅程通过。汇总明确单项/逻辑/完整范围，不把历史通过报告或单项结果当成本次全量通过。
