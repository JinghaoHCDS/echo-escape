# Echo Escape 工程入口

- Godot **4.6.1 stable**，纯 typed GDScript，Forward+；主场景 `scenes/main.tscn`，入口 `scripts/main.gd`。
- `config/gameplay.json` 集中玩法参数。`level_data.gd` 是场景、碰撞、寻路、声音可达性唯一地图来源。
- `level_builder.gd` + `shaders/environment.gdshader`：opaque低面数环境、世界空间回声显形。
- `player.gd`：胶囊控制与按实际位移计步；`acoustic_field.gd`：由地图阻挡生成可见性图与连续欧氏路径；`sound_system.gd`：距离场、延迟监听、受限声波/缓存/音频池。
- 声波在开放区为半球扩散，按每个像素的世界位置显形，不按三角面或四邻接格传播。CPU监听与Shader使用相同距离场插值和高度距离；墙体仍阻挡、门洞仍绕行。怪物移动继续用四邻接寻路，勿将其距离用于声学。
- `hiding_system.gd`：家具真实碰撞、门和进出过渡；家具导航阻挡不能填成建筑实心墙。玩家视线/受击点必须跟随实际姿态。
- `max_distance` 是玩法半径，`visual_max_distance` 仅供环境弱光；不得把外圈显形当作听觉、探测、怪物显形或道具激活。闭柜声学双向隔离，经过柜口时判门，开门不补发旧波。
- 躲藏不是无敌：合法目击/探测/信标才可记住躲藏点并检查；检查不直接判死，仍要有效攻击命中。
- `monster.gd`：证据驱动状态机、导航、锁向攻击；`objectives.gd`：激活/拾取/出口；`game_ui.gd`：UI。
- 普通阶段不能偷读被遮挡玩家实时坐标用于追踪；只有警报允许。不能透墙传声、寻路或攻击。播放音量不得改变游戏声强。
- 游戏结束冻结正常逻辑；重开重载整个主场景，释放旧session。
- 不复制第三方游戏素材。所有几何/音频为本项目自制；`tools/generate_audio.py` 可重建音频。
- 检查命令见 `tools/check.sh`；图形QA不可用headless结果替代。结果记录 `docs/VALIDATION.md`。
- 按可运行阶段提交Git；`.godot/` 与 `builds/` 不入库。修改前查 `git status`，不要覆盖其他人的改动。
