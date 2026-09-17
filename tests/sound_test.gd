extends SceneTree
## Run: Godot --headless --path . --script res://tests/sound_test.gd
## Deterministic acoustic checks advance the same production physics method.

var _failures: int = 0
var _deliveries: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _on_arrived(event: Dictionary, listener_id: String) -> void:
	if listener_id == "test_listener":
		_deliveries.append(event)


func _find_wall_pair(data: LevelData, field: AcousticField) -> Array[Vector2i]:
	for y: int in range(1, LevelData.HEIGHT - 1):
		for x: int in range(1, LevelData.WIDTH - 1):
			var a := Vector2i(x, y)
			if not data.is_open(a):
				continue
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				if data.is_open(a + offset):
					continue
				for thickness: int in range(2, 7):
					var b: Vector2i = a + offset * thickness
					if not data.is_open(b):
						continue
					var wave: Dictionary = field.build_wave(data.cell_to_world(a), 14.0)
					var distance: float = field.distance_at(wave, data.cell_to_world(b))
					if is_finite(distance) and distance > float(thickness) + 2.0:
						return [a, b]
					break
	return []


func _run() -> void:
	var data := LevelData.new()
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/gameplay.json"))
	var sound := SoundSystem.new()
	root.add_child(sound)
	sound.setup(data, config)
	sound.set_physics_process(false)
	sound.set_playback_volume(0.0)
	sound.sound_arrived.connect(_on_arrived)
	var listener := Node3D.new()
	root.add_child(listener)
	sound.register_listener("test_listener", listener)
	var pair: Array[Vector2i] = _find_wall_pair(data, sound.acoustic_field)
	_check(pair.size() == 2, "地图存在隔墙相邻、经门洞可绕行的格对")
	if pair.size() != 2:
		quit(1)
		return
	var origin: Vector3 = data.cell_to_world(pair[0])
	listener.global_position = data.cell_to_world(pair[1])
	var event: Dictionary = sound.emit_sound("clap", "player", origin)
	var path_distance: float = sound.event_distance(event, listener.global_position)
	var straight_distance: float = origin.distance_to(listener.global_position)
	print("ACOUSTIC_PAIR: ", pair, " straight=", straight_distance, " path=", path_distance)
	_check(path_distance > straight_distance + 2.0, "圆弧传播遇实体墙后，长度计入开放门洞绕行")
	var short_wave: Dictionary = sound.acoustic_field.build_wave(origin, straight_distance + 0.5)
	_check(is_inf(sound.acoustic_field.distance_at(short_wave, listener.global_position)), "近处隔墙格不在短程声波的可达范围")
	var body_radius: float = float(config.get("sound_listener_radius", 0.30))
	var speed: float = float(config["propagation_speed"])
	var before_arrival: float = (path_distance - body_radius - 0.02) / speed
	sound._physics_process(before_arrival)
	_check(_deliveries.is_empty(), "声波到达碰撞体前，远处监听者未收到听觉证据")
	_check(sound.reveal_arrival_time(pair[1]) < -90.0, "门洞路径到达前，墙后环境未提前显形")
	sound._physics_process((body_radius + 0.03) / speed)
	_check(_deliveries.size() == 1, "声波到达后，监听者仅收到一次证据")
	if not _deliveries.is_empty():
		_check(is_equal_approx(float(_deliveries[0]["arrival_time"]), path_distance / speed), "听觉事件的到达时间为路径距离 / 传播速度")
		_check(float(_deliveries[0]["intensity"]) == float(event["intensity"]), "播放静音不改变游戏声强")
		_check(_deliveries[0]["position"] == origin, "听觉只传递该次固定发声位置")
	_check(is_equal_approx(sound.reveal_arrival_time(pair[1]), path_distance / speed), "共享显形数据采用同一可达距离与到达时间")
	# The continuous distance Texture2DArray is the actual shader input.
	# Headless does not upload GPU layers; only graphical runs read them back.
	if DisplayServer.get_name() != "headless":
		var gpu_layer: Image = sound.distance_texture.get_layer_data(int(event["slot"]))
		var cpu_layer: Image = event["distance_image"]
		_check(gpu_layer != null, "Forward+ 可回读该声波所在的 GPU 距离层")
		if gpu_layer != null:
			var resolution: int = int(config.get("acoustic_field_resolution", 4))
			var pixel := Vector2i(pair[1].x * resolution + resolution / 2, pair[1].y * resolution + resolution / 2)
			var max_error: float = 0.0
			for offset: Vector2i in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.UP, Vector2i(-1, -1)]:
				var sample: Vector2i = pixel + offset
				max_error = maxf(max_error, absf(gpu_layer.get_pixelv(sample).r - cpu_layer.get_pixelv(sample).r))
			_check(max_error < 0.00001, "Forward+ GPU 的四个双线性距离样本与听觉使用的数据一致")
	sound._physics_process(0.1)
	_check(_deliveries.size() == 1, "同一个声波不会反复更新监听者证据")

	sound.clear()
	_deliveries.clear()
	listener.global_position = Vector3(-100.0, 0.0, -100.0)
	sound.emit_sound("clap", "player", origin)
	sound._physics_process((path_distance + body_radius + 0.1) / speed)
	listener.global_position = data.cell_to_world(pair[1])
	sound._physics_process(0.01)
	_check(_deliveries.is_empty(), "走进已经扫过的格子不会收到旧声波的新证据")

	sound.clear()
	_deliveries.clear()
	# Both endpoints sit at texture texel centers to isolate the radial rule
	# from sub-texel interpolation. The diagonal is sqrt(8), never 4 meters.
	var open_origin := Vector3(16.125, 0.0, 21.125)
	var diagonal := Vector3(18.125, 0.0, 23.125)
	var radial_event: Dictionary = sound.emit_sound("clap", "player", open_origin)
	var diagonal_distance: float = sound.event_distance(radial_event, diagonal)
	_check(absf(diagonal_distance - sqrt(8.0)) < 0.00001, "空旷区对角传播为欧氏距离，不呈曼哈顿菱形")
	var axial := Vector3(open_origin.x + sqrt(8.0), 0.0, open_origin.z)
	_check(absf(sound.event_distance(radial_event, axial) - diagonal_distance) < 0.01, "同半径轴向与斜向声波几乎同时抵达")
	var higher := Vector3(diagonal.x, 3.0, diagonal.z)
	var higher_distance: float = sound.event_distance(radial_event, higher)
	_check(absf(higher_distance - sqrt(diagonal_distance * diagonal_distance + 9.0)) < 0.00001, "同一地面位置的高处使用半球径向距离")
	listener.global_position = higher
	sound._physics_process(diagonal_distance / speed)
	_check(_deliveries.is_empty(), "地面波前到达时，同一 XZ 的高处尚未收到证据")
	sound._physics_process((higher_distance - diagonal_distance) / speed)
	_check(_deliveries.size() == 1, "半球波前到达高处后才发出听觉证据")
	if not _deliveries.is_empty():
		_check(is_equal_approx(float(_deliveries[0]["arrival_time"]), higher_distance / speed), "高处到达时间包含高度差")

	sound.clear()
	_deliveries.clear()
	var stable_node_count: int = sound.get_child_count()
	for index: int in range(500):
		var moving_origin: Vector3 = origin + Vector3(float(index % 40) * 0.005, 0.0, 0.0)
		sound.emit_sound("run", "player", moving_origin)
		sound._physics_process(0.025)
	_check(sound.active_waves.size() <= int(config["max_waves"]), "持续发声 500 次后活跃声波不超过配置上限")
	_check(sound._field_cache.size() <= int(config.get("max_field_cache", 16)), "移动发声的连续距离纹理缓存受上限约束")
	_check(sound.get_child_count() == stable_node_count, "持续发声不新增音效节点")
	_check(sound.active_voice_count() <= int(config["max_audio_voices"]), "播放音效数量受固定池上限约束")
	sound._physics_process(10.0)
	_check(sound.active_waves.is_empty(), "传播结束后路径缓存与声波事件全部回收")
	sound.clear()
	_check(sound.clock == 0.0 and sound.emitted_count == 0 and sound.active_voice_count() == 0, "重置清空声波计数、时钟和播放状态")
	_check(sound.reveal_arrival_time(pair[1]) == -100.0, "重置清空世界显形缓存")
	_check(sound._field_cache.is_empty() and sound.active_waves.is_empty(), "重置释放旧声波与连续距离缓存")
	print("SOUND_TEST_RESULT: ", "PASS" if _failures == 0 else "FAIL", " failures=", _failures)
	quit(0 if _failures == 0 else 1)
