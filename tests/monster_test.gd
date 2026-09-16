extends SceneTree
## Run: Godot --headless --path . --script res://tests/monster_test.gd
## Uses the real 3D physics world, not a replacement visibility/path model.

var _failures: int = 0
var _checks: int = 0
var _hits: int = 0
var _data: LevelData
var _stage: Node3D
var _sound: SoundSystem
var _player: EchoPlayer
var _monster: EchoMonster
var _config: Dictionary


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_config = JSON.parse_string(FileAccess.get_file_as_string("res://config/gameplay.json")) as Dictionary
	_data = LevelData.new()
	_stage = Node3D.new()
	root.add_child(_stage)
	var level: LevelBuilder = LevelBuilder.new()
	_stage.add_child(level)
	level.setup(_data)
	_sound = SoundSystem.new()
	_stage.add_child(_sound)
	_sound.setup(_data, _config)
	_sound.set_physics_process(false)
	_player = EchoPlayer.new()
	_stage.add_child(_player)
	_player.setup(_config)
	_player.enabled = false
	_monster = EchoMonster.new()
	_stage.add_child(_monster)
	_monster.setup(_data, _player, _sound, _config)
	_monster.set_physics_process(false)
	_monster.player_hit.connect(_on_hit)
	await _settle()

	# Forward view, backwards view and an out-of-range target.
	_place(Vector3(17.5, 0.0, 14.5), Vector3(17.5, 0.0, 16.5), PI)
	await _settle()
	_check(_monster._player_is_visible(), "无遮挡、距离内且前方玩家可见")
	_monster.rotation.y = 0.0
	_check(not _monster._player_is_visible(), "视野角排除背后玩家")
	_place(Vector3(17.5, 0.0, 14.5), Vector3(27.5, 0.0, 14.5), -PI * 0.5)
	await _settle()
	_check(not _monster._player_is_visible(), "视距限制排除远处玩家")
	_place(Vector3(19.5, 0.0, 18.5), Vector3(23.5, 0.0, 18.5), -PI * 0.5)
	await _settle()
	_check(not _monster._player_is_visible(), "实体中枢障碍阻挡视觉射线")

	# A sound callback is one immutable origin, not a live tracking contract.
	_sound.clock = 1.0
	_monster.on_sound_arrived({"source": "monster", "kind": "probe", "position": _monster.global_position}, "monster")
	_check(_monster.state == EchoMonster.PATROL and _monster.last_evidence_time < 0.0, "自身探测声不触发调查或更新玩家证据")
	var heard_origin: Vector3 = Vector3(24.5, 0.0, 18.5)
	_monster.on_sound_arrived({"source": "player", "kind": "clap", "position": heard_origin}, "monster")
	_check(_monster.state == EchoMonster.INVESTIGATE and _monster.last_known_position == heard_origin, "玩家声只触发前往该次发声坐标的调查")
	_monster.on_sound_arrived({"source": "monster", "kind": "probe", "position": _monster.global_position}, "player")
	var confirmed_origin: Vector3 = _player.global_position
	_check(_monster.state == EchoMonster.CHASE and _monster.last_known_position == confirmed_origin, "仅实际探测命中玩家后确认位置并追逐")
	_player.global_position = Vector3(24.5, 0.0, 18.5)
	await _settle()
	_sound.clock = 6.1
	_monster._physics_process(1.0 / 60.0)
	_check(_monster.state == EchoMonster.SEARCH, "连续五秒失去有效证据后进入搜索")
	_check(_monster.last_known_position == confirmed_origin, "隐藏玩家移动不会更新最后已知位置")
	_monster._state_time = 5.1
	_monster._physics_process(1.0 / 60.0)
	_check(_monster.state == EchoMonster.PATROL, "搜索超时后回到巡逻")

	# Wind-up and lock are separate from the one-shot attack decision.
	_place(Vector3(17.5, 0.0, 14.5), Vector3(17.5, 0.0, 13.2), 0.0)
	await _settle()
	_monster.last_known_position = _player.global_position
	_monster._begin_attack()
	_check(_monster.state == EchoMonster.ATTACK_WINDUP and _hits == 0, "进入前摇不立即伤害玩家")
	_monster._state_time = 0.5
	_monster._update_windup(1.0 / 60.0)
	var locked_direction: Vector3 = _monster._attack_direction
	_check(_monster._attack_locked, "前摇结束前0.2秒锁定方向")
	_player.global_position = Vector3(18.7, 0.0, 14.5)
	_monster.last_known_position = _player.global_position
	_monster._state_time = 0.66
	_monster._update_windup(1.0 / 60.0)
	_check(_monster._attack_direction.is_equal_approx(locked_direction), "锁定后不再追随侧移玩家转向")
	_check(_hits == 0 and _monster.attack_reason.contains("偏离"), "范围内侧移到扇形之外可躲避攻击")
	_check(_monster.state == EchoMonster.ATTACK_STRIKE, "落空仍进入独立攻击判定阶段")
	_monster._state_time = 0.13
	_monster._physics_process(1.0 / 60.0)
	_check(_monster.state == EchoMonster.ATTACK_RECOVERY, "攻击落空也必须恢复，不能立即再次攻击")

	# Insert one narrow physical wall so wall occlusion is tested independently
	# of the attack range guard (the map's full-width walls are wider).
	var test_wall: StaticBody3D = StaticBody3D.new()
	test_wall.collision_layer = 1
	test_wall.collision_mask = 0
	var wall_shape: CollisionShape3D = CollisionShape3D.new()
	var wall_box: BoxShape3D = BoxShape3D.new()
	wall_box.size = Vector3(1.8, 2.2, 0.20)
	wall_shape.shape = wall_box
	test_wall.add_child(wall_shape)
	_stage.add_child(test_wall)
	test_wall.global_position = Vector3(17.5, 1.1, 14.0)
	_place(Vector3(17.5, 0.0, 14.6), Vector3(17.5, 0.0, 13.4), 0.0)
	await _settle()
	_monster._attack_direction = Vector3.FORWARD
	_monster._resolve_attack()
	_check(_hits == 0 and _monster.attack_reason.contains("实体墙"), "距离与方向均满足时实体墙仍阻挡攻击")
	test_wall.queue_free()
	await _settle()
	_player.global_position = Vector3(17.5, 0.0, 12.6)
	_monster._resolve_attack()
	_check(_hits == 0 and _monster.attack_reason.contains("距离"), "后退拉开距离可躲避攻击")
	_player.global_position = Vector3(17.5, 0.0, 13.4)
	_monster.last_known_position = _player.global_position
	_monster._begin_attack()
	_monster._state_time = 0.66
	_monster._update_windup(1.0 / 60.0)
	_check(_hits == 1 and _monster.attack_reason.contains("攻击命中"), "仅有限距离、锁定方向、无遮挡条件全通过时命中")
	_monster._state_time = 0.13
	_monster._physics_process(1.0 / 60.0)
	_check(_monster.state == EchoMonster.ATTACK_RECOVERY and _hits == 1, "命中后同样恢复，判定不重复发出")
	_monster._state_time = 1.01
	_monster._physics_process(1.0 / 60.0)
	_check(_monster.state == EchoMonster.CHASE and _hits == 1, "约一秒恢复结束后才能恢复追逐")

	# Traverse the actual map around a solid three-by-three block while the
	# engine performs CharacterBody3D movement and wall collision at 60 Hz.
	_place(Vector3(19.5, 0.0, 18.5), Vector3(24.5, 0.0, 18.5), -PI * 0.5)
	_monster._enter_state(EchoMonster.PATROL)
	_monster.set_alarm(true)
	_check(_monster.state == EchoMonster.CHASE and _monster.alarm_active, "信标独立阶段立即持续追逐")
	var crossed_solid: bool = false
	var went_around: bool = false
	_monster.set_physics_process(true)
	for index: int in range(360):
		await physics_frame
		if not _data.is_open(_data.world_to_cell(_monster.global_position)):
			crossed_solid = true
		if _monster.global_position.z < 17.0 or _monster.global_position.z > 20.0:
			went_around = true
	_monster.set_physics_process(false)
	_check(not crossed_solid and went_around, "实际3D移动沿四邻接路径绕过实体障碍，未穿墙")
	_check(_monster.global_position.distance_to(_player.global_position) < 2.0, "绕行后能到达玩家附近，未卡在墙角")
	_check(_monster.last_known_position == _player.global_position, "信标阶段允许持续更新位置证据")
	# A real game's hit receiver disables Session immediately. Collision bodies
	# leave their physics space synchronously while this attack callback runs.
	_place(Vector3(17.5, 0.0, 14.6), Vector3(17.5, 0.0, 13.4), 0.0)
	await _settle()
	_monster.player_hit.connect(func(_reason: String) -> void: _stage.process_mode = Node.PROCESS_MODE_DISABLED)
	_monster._begin_attack()
	_monster._state_time = 0.66
	var before_final_hit: int = _hits
	_monster._physics_process(1.0 / 60.0)
	_check(_hits == before_final_hit + 1 and not PhysicsServer3D.body_get_space(_monster.get_rid()).is_valid(), "命中同步冻结场景后安全停止物理回调，无移除body继续移动错误")
	print("MONSTER_TEST: %d checks, %d failures" % [_checks, _failures])
	# Re-enable the audio subtree before stopping a cue paused by the final
	# fixture. Let the audio mixing thread release its WAV playback references.
	_sound.process_mode = Node.PROCESS_MODE_ALWAYS
	_sound.clear()
	for voice: AudioStreamPlayer3D in _sound._voices:
		voice.stream_paused = false
		voice.stop()
		voice.stream = null
	await create_timer(0.15, true).timeout
	_stage.queue_free()
	await create_timer(0.05, true).timeout
	quit(0 if _failures == 0 else 1)


func _place(monster_position: Vector3, player_position: Vector3, yaw: float) -> void:
	_monster.global_position = monster_position
	_monster.velocity = Vector3.ZERO
	_monster.rotation = Vector3(0.0, yaw, 0.0)
	_player.global_position = player_position
	_player.velocity = Vector3.ZERO


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


func _on_hit(_reason: String) -> void:
	_hits += 1
