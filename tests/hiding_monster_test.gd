extends SceneTree
## Evidence/inspection regression with real 3D sight and attack rays. The small
## adapter isolates monster memory from furniture animation (tested separately).

class HidingAdapter extends Node:
	signal entering(spot_id: String, entry_position: Vector3)
	var calls: int = 0
	var lookups: int = 0
	var approach: Vector3 = Vector3(17.5, 0.0, 14.8)
	func get_spot(id: String) -> Dictionary:
		lookups += 1
		return {"id": id, "inside": Vector3(17.5, 0.0, 13.6), "bounds": AABB(Vector3(16.5, 0.0, 12.6), Vector3(2.0, 2.3, 2.0))} if id in ["cabinet", "table"] else {}
	func inspection_position(_id: String) -> Vector3:
		return approach
	func inspect(_id: String) -> bool:
		calls += 1
		return true

var _failures: int = 0
var _checks: int = 0
var _hits: int = 0
var _stage: Node3D
var _player: EchoPlayer
var _monster: EchoMonster
var _sound: SoundSystem
var _hiding: HidingAdapter
var _config: Dictionary

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_config = JSON.parse_string(FileAccess.get_file_as_string("res://config/gameplay.json")) as Dictionary
	_config["probe_interval"] = 10000.0
	var data := LevelData.new()
	_stage = Node3D.new()
	root.add_child(_stage)
	var level := LevelBuilder.new()
	_stage.add_child(level)
	level.setup(data)
	_sound = SoundSystem.new()
	_stage.add_child(_sound)
	_sound.setup(data, _config)
	_sound.set_physics_process(false)
	_player = EchoPlayer.new()
	_stage.add_child(_player)
	_player.setup(_config)
	_player.enabled = false
	_monster = EchoMonster.new()
	_stage.add_child(_monster)
	_monster.setup(data, _player, _sound, _config)
	_monster.set_physics_process(false)
	_monster.player_hit.connect(func(_reason: String) -> void: _hits += 1)
	_hiding = HidingAdapter.new()
	_stage.add_child(_hiding)
	_monster.set_hiding_system(_hiding)
	_place(Vector3(19.5, 0.0, 18.5), Vector3(23.5, 0.0, 18.5), -PI * 0.5)
	await _settle()
	_hiding.entering.emit("cabinet", _player.global_position)
	_check(_monster.known_hiding_spot_id.is_empty() and _hiding.lookups == 0, "未看见入藏不会查询或记录玩家藏点")

	_place(_hiding.approach, Vector3(17.5, 0.0, 13.6), 0.0)
	await _settle()
	_sound.clock = 1.0
	_hiding.entering.emit("cabinet", _player.global_position)
	_player.set_hiding_pose("cabinet", "locker")
	_check(_monster.state == EchoMonster.INSPECT_HIDE and _monster.known_hiding_spot_id == "cabinet", "真实视线目击进入后记住柜子并进入检查状态")
	_check(_monster._chase_target().is_equal_approx(_hiding.approach), "藏点导航使用入口外快照而不是柜内坐标")
	var remembered_position: Vector3 = _monster.last_known_position
	# Leave/move behind the architectural block without sending any event.
	_place(Vector3(19.5, 0.0, 18.5), Vector3(24.5, 0.0, 18.5), -PI * 0.5)
	_player.clear_hiding_pose()
	await _settle()
	_sound.clock = 2.0
	_monster._physics_process(1.0 / 60.0)
	_check(_monster.last_known_position == remembered_position and _monster.known_hiding_spot_id == "cabinet", "玩家未被看见地离开不会通知怪物或刷新位置记忆")
	_sound.clock = 6.1
	_monster._physics_process(1.0 / 60.0)
	_check(_monster.state == EchoMonster.SEARCH, "接近记住的藏点途中五秒无证据仍转入搜索")
	_monster._state_time = 5.1
	_monster._physics_process(1.0 / 60.0)
	_check(_monster.state == EchoMonster.PATROL and _monster.known_hiding_spot_id.is_empty(), "搜索结束清除旧藏点记忆")

	_place(_hiding.approach, Vector3(17.5, 0.0, 13.6), 0.0)
	await _settle()
	_sound.clock = 10.0
	_hiding.entering.emit("cabinet", _player.global_position)
	_player.set_hiding_pose("cabinet", "locker")
	_monster._update_inspection(0.6)
	_check(_hiding.calls == 0 and _hits == 0 and _monster.state == EchoMonster.INSPECT_HIDE, "检查前半段有动作预告且不打开、不判死")
	_monster._update_inspection(0.61)
	_check(_hiding.calls == 1 and _hits == 0 and _monster.state == EchoMonster.CHASE, "1.2秒检查后只请求开柜或退出，仍未判定攻击")
	_monster.set_alarm(true)
	for index: int in range(10):
		_monster._register_confirmed_player("信标")
	_check(_monster.state == EchoMonster.CHASE and _hiding.calls == 1, "同次已检查藏点在持续信标下不会反复重启检查")
	_monster.set_alarm(false)

	var closed_door: StaticBody3D = _box(Vector3(17.5, 1.1, 14.2), Vector3(1.8, 2.2, 0.16))
	await _settle()
	_check(not _monster._player_is_visible(), "关闭柜门的真实实体碰撞阻挡玩家姿态视线")
	_monster._attack_direction = Vector3.FORWARD
	_monster._resolve_attack()
	_check(_hits == 0 and _monster.attack_reason.contains("实体墙"), "柜门阻挡有限距离内的真实攻击射线")
	closed_door.queue_free()
	await _settle()
	_monster._begin_attack()
	_check(_hits == 0 and _monster.state == EchoMonster.ATTACK_WINDUP, "检查后开门仍先进行普通攻击前摇")
	_monster._state_time = 0.66
	_monster._update_windup(1.0 / 60.0)
	_check(_hits == 1, "躲藏状态本身不提供无敌，开门后的有效攻击可以命中")

	_monster._enter_state(EchoMonster.PATROL)
	_player.set_hiding_pose("table", "table")
	_place(Vector3(17.5, 0.0, 15.1), Vector3(17.5, 0.0, 14.0), 0.0)
	var tabletop: StaticBody3D = _box(Vector3(17.5, 1.12, 14.0), Vector3(2.4, 0.16, 1.6))
	await _settle()
	_check(not _monster._player_is_visible(), "桌面确实遮挡斜向下看向桌底的低姿态视线")
	_monster.global_position = Vector3(17.5, 0.0, 17.7)
	await _settle()
	_check(_monster._player_is_visible(), "从开放桌侧看见低姿态玩家仍可发现")
	_monster._physics_process(1.0 / 60.0)
	_check(_monster.known_hiding_spot_id == "table" and _monster.state == EchoMonster.INSPECT_HIDE, "实际看见桌底玩家可形成合法检查证据")
	tabletop.queue_free()
	_monster._enter_state(EchoMonster.PATROL)
	_sound.clock = 20.0
	_monster.on_sound_arrived({"source": "monster", "kind": "probe", "position": _monster.global_position}, "player")
	_check(_monster.known_hiding_spot_id == "table" and _monster.last_evidence_time == 20.0, "已交付的真实探测命中可以确认桌底藏点")
	var newer_hide_snapshot: Vector3 = _monster.last_known_position
	var outside_origin := Vector3(24.5, 0.8, 18.5)
	_monster.on_sound_arrived({"source": "player", "kind": "walk", "position": outside_origin, "time": 19.0}, "monster")
	_check(_monster.known_hiding_spot_id == "table" and _monster.last_known_position == newer_hide_snapshot, "入藏前发出但延迟到达的旧声音不覆盖较新的藏点证据")
	_sound.clock = 20.2
	_monster.on_sound_arrived({"source": "player", "kind": "clap", "position": outside_origin, "time": 20.1}, "monster")
	_check(_monster.known_hiding_spot_id.is_empty() and _monster.state == EchoMonster.CHASE and _monster._chase_target() == outside_origin, "藏点外新听觉证据清除旧藏点并追该次声音快照")
	_check(_monster.last_known_position != _player.global_position, "追新声音仍不读取玩家发声后移动的位置")
	_monster._register_confirmed_player("测试：有效视觉")
	_monster._begin_attack()
	var direction_before: Vector3 = _monster._attack_direction
	_monster.on_sound_arrived({"source": "player", "kind": "run", "position": outside_origin, "time": 20.2}, "monster")
	_check(_monster.known_hiding_spot_id.is_empty() and _monster.state == EchoMonster.ATTACK_WINDUP and _monster._attack_direction == direction_before, "攻击中收到新声可以修正记忆，但不取消前摇或改变锁定方向")

	_monster._enter_state(EchoMonster.PATROL)
	_player.set_hiding_pose("cabinet", "locker")
	_place(Vector3(19.5, 0.0, 18.5), Vector3(23.5, 0.0, 18.5), -PI * 0.5)
	await _settle()
	_monster.set_alarm(true)
	_check(_monster.known_hiding_spot_id == "cabinet" and _monster.state == EchoMonster.INSPECT_HIDE, "信标允许确认遮挡后的藏点并继续检查追踪")
	_monster.set_alarm(false)
	_monster._enter_state(EchoMonster.PATROL)
	_player.clear_hiding_pose()
	_player.global_position = data.spawn_position
	var table: Dictionary = data.hiding_spots[2]
	var table_origin: Vector3 = table["inside"]
	_monster.global_position = table["approach"]
	await _settle()
	_monster.on_sound_arrived({"source": "player", "kind": "walk", "position": table_origin}, "monster")
	_monster._physics_process(1.0 / 60.0)
	_check(_monster.state == EchoMonster.SEARCH and _monster.last_known_position == table_origin, "只听到家具内部声音时调查可到入口结束，不因导航阻挡格永久卡住")


	await _real_cabinet_attack(data, level.material)
	print("HIDING_MONSTER_TEST: %d checks, %d failures" % [_checks, _failures])
	_sound.clear()
	_stage.queue_free()
	await create_timer(0.1, true).timeout
	quit(0 if _failures == 0 else 1)

func _real_cabinet_attack(data: LevelData, material: ShaderMaterial) -> void:
	# Exercise the actual furniture, moving door and monster controller together:
	# an observed locker entry must not become permanent immunity after inspection.
	_monster.set_alarm(false)
	_monster._enter_state(EchoMonster.PATROL)
	_player.clear_hiding_pose()
	_player.enabled = true
	_player.set_physics_process(false)
	var real_hiding := HidingSystem.new()
	_stage.add_child(real_hiding)
	real_hiding.setup(data, _player, _sound, _config, material)
	_monster.set_hiding_system(real_hiding)
	_sound.set_hiding_system(real_hiding)
	var spot: Dictionary = real_hiding.get_spot("gallery_locker")
	var entry: Vector3 = spot["entry"]
	var approach: Vector3 = real_hiding.inspection_position("gallery_locker")
	_place(approach + Vector3(2.0, 0.0, 0.0), entry, 0.0)
	_monster.look_at(entry + Vector3.UP * _monster.global_position.y)
	_monster.rotation.x = 0.0
	_sound.clock = 100.0
	await _settle()
	var entered: bool = real_hiding._begin_entry("gallery_locker")
	_check(entered, "真实柜子：怪物目击时玩家能够沿实体入口进入")
	for frame: int in range(180):
		await physics_frame
		_sound.clock += 1.0 / 60.0
		if not real_hiding.is_transitioning() and real_hiding.is_closed("gallery_locker"):
			break
	_check(real_hiding.is_closed("gallery_locker") and _player.hiding_spot_id == "gallery_locker", "真实柜子：完成入藏并关闭带实体碰撞的门")
	var hits_before: int = _hits
	var saw_open: bool = false
	var saw_windup: bool = false
	_monster.set_physics_process(true)
	for frame: int in range(360):
		await physics_frame
		_sound.clock += 1.0 / 60.0
		if not real_hiding.is_closed("gallery_locker"):
			saw_open = true
		if _monster.state == EchoMonster.ATTACK_WINDUP:
			saw_windup = true
		if _hits > hits_before:
			break
	_monster.set_physics_process(false)
	_check(saw_open and _monster._hide_inspected, "真实怪物沿导航到检查侧位并实际打开柜门")
	_check(saw_windup and _hits == hits_before + 1, "真实开柜后正常前摇能够命中柜内不闪避玩家，无永久无敌")
	_check(_monster.known_hiding_spot_id == "gallery_locker", "普通目击追查能够完成开柜攻击，无需信标持续透视")

func _place(monster_position: Vector3, player_position: Vector3, yaw: float) -> void:
	_monster.global_position = monster_position
	_monster.velocity = Vector3.ZERO
	_monster.rotation = Vector3(0.0, yaw, 0.0)
	_player.global_position = player_position
	_player.velocity = Vector3.ZERO

func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	_stage.add_child(body)
	body.global_position = at
	return body

func _settle() -> void:
	await physics_frame
	await physics_frame

func _check(condition: bool, title: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + title)
	else:
		_failures += 1
		push_error("FAIL: " + title)
