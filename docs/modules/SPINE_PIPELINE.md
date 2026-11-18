# Spine 批量应用规格

> v0.1 · 2026-11-18 · GDD v0.1.0 / 程序0.1.1.0

扫描315编号完整源库；一编号不等于独立角色/导出名，皮肤与身份分别记录。输入源根只读，runtime目标`assets/actors/{source_id}/`，`resources/visuals.json`是统一视觉配置。`tools/spine_pipeline.py scan/import`生成catalog、运行资源、原始输入与provenance。

首次优先保留四个已验证源097/312/314/072，新导入163吕布及多套原创角色/敌人底稿。原始JSON/atlas/PNG/声明与运行资产分开；生成SHA256、原导出版本、皮肤、动画/时长/事件、转换告警及用途限制。

状态：cataloged → converted → runtime_pass → visual_checked → performance_checked。deform/path/linked mesh不能因JSON输出成功就判兼容；不支持项在报告列明，不悄悄丢动画。原生加载按一素材一个进程隔离。

配方可复用原皮肤、指定slot tint/attachment visibility、scale、foot、root-motion约束、环形光环、描边（可先用独立轮廓/底圈表现，真实骨架描边须单独验证）。小兵建议80~105px、英雄110~145px、Boss160~200px；最终按实例完整轮廓测量，不能仅按纹理大小推断。碰撞/射程独立于美术尺度。

共享SkeletonDataResource/Atlas，不重复读盘；每单位独立AnimationState；活单位64、完整英雄12作为验证目标。动作空缺用明确替代映射并登记，不把空Active_A当技能；attack命中由逻辑一次结算。离屏/低优先级更新降频方案留待实测，不宣称已池化或已优化。

D69源声明仅学习研究、不可商用；保留免责声明。当前运行库仅Windows64，其他平台需要对应库和重新验收。素材扩充优先工具批量导入/重配，不改战斗代码。
