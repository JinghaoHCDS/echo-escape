# v0.1.0 验证记录

执行日期：2026-09-17。以下是实际执行结果，不以无窗口检查替代图形验收。

## 环境

- Godot `4.6.1.stable.official.14d19694e`。
- macOS 26.6.2，arm64，Apple M4（Apple9），Metal 4.0 / **Forward+**。
- 使用本机稳定引擎；未切换 Compatibility 或其他渲染器。
- 本机已安装 4.6.1 导出模板。Blender 位于 `/Applications/Blender.app`；本版 low poly 几何全部由 Godot 生成，不需要外部模型处理。

## 可复现命令

```bash
bash tools/check.sh                 # 导入 + 无窗口逻辑/物理回归
bash tools/check.sh --graphics      # 额外跑 GPU、实际音频、遮挡、输入、完整图形流程
bash tools/run.sh --script tests/playthrough_test.gd -- --no-capture
bash tools/export.sh               # 本机 macOS 导出，需对应版本模板
```

检查脚本同时检查退出码和 `ERROR` / `SCRIPT ERROR` / `FAIL` 日志，避免引擎退出 0 却藏有运行错误。独立图形测试在 headless 模式明确报告 `SKIP`。

## 已通过

| 检查 | 实际结果 |
| --- | --- |
| 资源导入 / 主场景 | 无缺失资源、脚本解析或阻断运行错误；Forward+ Shader 实际编译运行 |
| `phase_a_test.gd` | 5 项：墙阻挡胶囊、地面承重、连通路径、路径格可通行、顶墙无脚步 |
| `sound_test.gd` | headless 18 项；图形 19 项，额外回读 GPU 显形纹理 |
| 声音绕墙 | 直线 5m 的隔墙测试点，通行路径 9m，格中心到达 0.9s；监听者按 0.30m 碰撞体容差命中，前沿未到不发证据 |
| 显形一致性 | 世界时戳取同一通行路径；摄像机不参与传播；已扫过格子不变成新的听觉证据 |
| `monster_test.gd` | 26 项：有限视距/视角/真实射线、自声过滤、声音坐标快照、probe确认、5秒失证、搜索回巡逻、锁向、侧移/后退/墙挡miss、单次hit、恢复、信标、实际绕障、结束生命周期 |
| `gameplay_test.gd` | 23 项：未携带不胜、未激活不拾取、鼓掌激活、无遮挡拾取、警报提示、重复拾取拒绝、出口胜利、3次重开不累积节点/声波/音频/道具/警报 |
| `playthrough_test.gd` | headless 和真实图形各 8 项通过：成功路线全程真实角色移动和AI，无玩家瞬移；实际取物、绕另一侧返回出口；胜利重开；真实攻击前摇、命中失败、失败重开 |
| `audio_test.gd` | 真实 CoreAudio/Master 混音捕获 18 项通过；8种音效 RMS 约 0.113–0.313，峰值小于1；headless跳过 |
| `occlusion_test.gd` | 图形5项通过：黑墙后放洋红亮目标，中心像素暗；debug照明只照墙；隐藏建筑后同像素才变洋红 |
| `input_test.gd` | 图形7项通过：注入相对鼠标事件可转向、Esc暂停释放鼠标、冻结时钟、恢复捕获、F1、E真正拾取、R真正重开 |
| 有界性 | 500次声波和200次音频连发保持上限，传播后释放cache；固定16个音频节点，最多24个波 |
| 原生窗口交互 | 实际点击开始、左键鼓掌、F1、Esc及设置面板；检查画面可读性、冷却与光照切换 |
| macOS 导出 | 已生成 `builds/EchoEscape-macOS.zip` 并解压为 `.app`；本机实际打开首屏、进入游戏并鼓掌，资源正确加载 |

完整取物路线：入口 → 声廊 → 档案室 → 机房核心 → 机房南连廊 → 中枢大厅 → 声廊 → 入口。所有障碍与怪物在成功路线中正常运行。失败场景为可复现夹具，先把角色放到攻击距离内，再由真实视觉、前摇、锁向和攻击判定触发失败；并非调用假失败替代攻击验收。

图形测试生成的关键帧见 `screenshots/`，包括首屏、回声、核心、警报返回、胜利、攻击前摇和失败。`check-output.log` 为完整基础+图形回归，`input-output.log` 和 `playthrough-output.log` 记录最后一轮输入及姿态修正后的复测。

## 性能实测

1080p（1920×1080）原生 Forward+ 图形运行，完整自动路线、正常AI及连续脚步/鼓掌，无截图开销的一次测量：

- 18.939273 秒，渲染 2261 帧，平均 **119.4 FPS**。
- 末段引擎计数 **120 FPS**，1145个物理采样。
- 原始输出：`benchmark-output.log`。

这是当前 Apple M4、当前地图的一次路径测量，不是最低帧率保证；未测其他GPU、长期热降频、独立GPU时间或1% low。headless FPS没有当作图形性能报告。

## 修复与限制

本轮回归修复了攻击命中同步冻结场景后仍移动已移出物理世界的body，以及相关测试夹具的音频线程清理。图形检查还修正了 unshaded 材质危险线条不够可见、双臂抬起方向和回声过亮的问题。E键测试最初在物理帧注入后过早断言，等输入分发完成后通过；生产输入无需绕过交互规则。

- Windows 与其他 macOS 硬件**尚未运行验证**；仅提供 Windows 导出预设，未声称已生成或测试 Windows 安装包。
- macOS 包为本地 ad hoc 签名构建，未做正式发行公证。
- 已验证真实混音非静音；音色主观品质、耳机定位和人类长时间游玩手感未做正式评测。
- 完整路线为可复现的引擎自动控制，不能等同于人类首次盲玩难度验收。熟悉地图后可全程奔跑，第一版不限制体力，后续平衡可据试玩反馈调整。
- 1m四邻接声学保守近似会形成格子式波前；不模拟真实反射、绕射、频率吸收或音频绕墙播放。场景仍为真实3D，碰撞、射线与攻击受实体墙约束。
- 设置只在当前会话有效；无存档、无程序化关卡。程序化low poly占位美术不等于成品美术。

## 版本与来源

Git按基建、白盒、声学、怪物、完整闭环和验收分别提交；交付标签 `v0.1.0`。本地仓库未连接或推送远端。

API核对使用 [Godot 4.6 CharacterBody3D](https://docs.godotengine.org/en/4.6/classes/class_characterbody3d.html)、[ImageTexture](https://docs.godotengine.org/en/4.6/classes/class_imagetexture.html)、[Spatial shader](https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/spatial_shader.html) 官方文档，并以4.6.1实际执行确认。
