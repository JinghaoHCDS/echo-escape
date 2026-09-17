extends SceneTree

const FieldScript = preload("res://scripts/acoustic_field.gd")
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	var data := LevelData.new()
	var field := FieldScript.new()
	var start: int = Time.get_ticks_usec()
	field.setup(data)
	print("FIELD_SETUP_MS: ", (Time.get_ticks_usec() - start) / 1000.0, " corners=", field.corners.size())
	var origin := Vector3(19.5, 0.0, 2.5)
	var across_wall := Vector3(24.5, 0.0, 2.5)
	var wave: Dictionary = field.build_wave(origin, 14.0)
	var detour: float = field.distance_at(wave, across_wall)
	var ideal: float = 4.0 + 2.0 * sqrt(0.5 * 0.5 + 1.5 * 1.5)
	_check(not field.segment_clear(Vector2(origin.x, origin.z), Vector2(across_wall.x, across_wall.z)), "隔墙直线确实被墙体阻挡")
	_check(detour > 5.0 and detour < 9.0, "声音绕门洞路径长于直线，短于旧曼哈顿路径")
	_check(absf(detour - ideal) < 0.08, "绕角距离接近连续最短路（厘米级保守余量）")
	_check(is_inf(field.distance_at(field.build_wave(origin, 5.5), across_wall)), "半径不足时隔墙接收点不可达")
	print("FIELD_DETOUR: actual=", detour, " ideal=", ideal)
	# A clear room gives exact Euclidean radial propagation, including targets
	# between cell centers and directions that are neither cardinal nor 45°.
	var clear_origin := Vector3(16.2, 0.0, 21.3)
	var clear_wave: Dictionary = field.build_wave(clear_origin, 14.0)
	for point: Vector3 in [Vector3(19.75, 0.0, 23.17), Vector3(17.1, 0.0, 16.25), Vector3(18.3, 0.0, 20.2)]:
		_check(absf(field.distance_at(clear_wave, point) - clear_origin.distance_to(point)) < 0.00001, "空旷区域使用连续欧氏圆弧 " + str(point))
	_check(is_inf(field.distance_at(clear_wave, Vector3(21.5, 0.0, 18.5))), "实体障碍内部不可显形")
	var isolated := LevelData.new()
	isolated.walkable.clear()
	isolated.walkable[Vector2i(2, 2)] = true
	isolated.walkable[Vector2i(3, 3)] = true
	var corner_field := FieldScript.new()
	corner_field.setup(isolated)
	_check(not corner_field.segment_clear(Vector2(2.5, 2.5), Vector2(3.5, 3.5)), "对角相接的封闭空间没有零宽度漏声")
	_check(is_inf(corner_field.distance_at(corner_field.build_wave(Vector3(2.5, 0.0, 2.5), 14.0), Vector3(3.5, 0.0, 3.5))), "不连通空间不存在声学路径")
	start = Time.get_ticks_usec()
	field.prepare_samples(4)
	print("FIELD_SAMPLE_PREPARE_MS: ", (Time.get_ticks_usec() - start) / 1000.0)
	start = Time.get_ticks_usec()
	var distance_image: Image = field.build_distance_image(wave, 4)
	print("FIELD_IMAGE_MS: ", (Time.get_ticks_usec() - start) / 1000.0)
	_check(distance_image.get_width() == LevelData.WIDTH * 4 and distance_image.get_height() == LevelData.HEIGHT * 4, "显形纹理每米4个采样点")
	var point := Vector3(24.625, 0.0, 2.625)
	_check(absf(distance_image.get_pixel(98, 10).r - field.distance_at(wave, point)) < 0.00001, "GPU距离纹理与听觉查询共用同一连续路径")
	_check(distance_image.get_pixel(84, 12).r == -1.0, "墙体内部距离纹理明确标记不可达")
	var total_us: int = 0
	var worst_us: int = 0
	for index: int in range(20):
		var moving_origin := Vector3(16.2 + float(index) * 0.17, 0.0, 21.3)
		start = Time.get_ticks_usec()
		var moving_wave: Dictionary = field.build_wave(moving_origin, 14.0)
		field.build_distance_image(moving_wave, 4)
		var elapsed: int = Time.get_ticks_usec() - start
		total_us += elapsed
		worst_us = maxi(worst_us, elapsed)
	print("FIELD_WAVE_AND_IMAGE_MS: mean=", total_us / 20000.0, " max=", worst_us / 1000.0)
	print("ACOUSTIC_FIELD_TEST_RESULT: ", "PASS" if _failures == 0 else "FAIL", " failures=", _failures)
	quit(0 if _failures == 0 else 1)
