extends SceneTree
## Deterministic portal-wave tests use the production fields and per-wave gate
## state. No sound/visual evidence may leak through a closed locker shell.

class DoorFixture extends Node:
	var closed: bool = true
	func is_closed(_id: String) -> bool:
		return closed

var _failures: int = 0
var _received: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	print(("PASS: " if condition else "FAIL: ") + message)
	if not condition:
		_failures += 1

func _on_arrival(event: Dictionary, listener: String) -> void:
	if listener == "fixture":
		_received.append(event)

func _run() -> void:
	var data := LevelData.new()
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/gameplay.json"))
	var sound := SoundSystem.new()
	root.add_child(sound)
	sound.setup(data, config)
	sound.set_physics_process(false)
	sound.set_playback_volume(0.0)
	var doors := DoorFixture.new()
	root.add_child(doors)
	sound.set_hiding_system(doors)
	sound.sound_arrived.connect(_on_arrival)
	var listener := Node3D.new()
	root.add_child(listener)
	sound.register_listener("fixture", listener)
	var spot: Dictionary = data.hiding_spots[0]
	var inside: Vector3 = (spot["inside"] as Vector3) + Vector3.UP
	var portal: Vector3 = spot["portal"]
	var outside: Vector3 = portal + Vector3(2.0, 0.0, 0.0)
	var speed: float = float(config["propagation_speed"])
	var node_count: int = sound.get_child_count()

	listener.global_position = inside
	var blocked_in: Dictionary = sound.emit_sound("probe", "monster", outside)
	sound._physics_process(0.5)
	_check(_received.is_empty() and is_inf(sound.event_distance(blocked_in, inside)), "关门柜阻挡外部探测，柜内不产生听觉证据")
	_check((sound._wave_portals[int(blocked_in["slot"])] as Vector4).x < 0.0, "显形 Shader 的柜内区域与探测一起阻断")
	doors.closed = false
	sound._physics_process(0.05)
	_check(_received.is_empty() and is_inf(sound.event_distance(blocked_in, inside)), "波前被关门阻挡后再开门，不补发旧探测与旧显形")

	sound.clear()
	_received.clear()
	doors.closed = true
	listener.global_position = outside
	var blocked_out: Dictionary = sound.emit_sound("clap", "player", inside)
	sound._physics_process(0.5)
	_check(_received.is_empty() and is_inf(sound.event_distance(blocked_out, outside)), "关门时柜内鼓掌不能向外提供玩家位置证据")
	_check(sound.event_distance(blocked_out, inside + Vector3(0.1, 0.0, 0.0)) < 0.11, "被封闭的柜内声波仍能显形内部空间")
	_check((sound._wave_regions[int(blocked_out["slot"])] as Vector4).y == 0.0, "柜内鼓掌的外部显形层保持禁用")
	doors.closed = false
	sound._physics_process(0.05)
	_check(is_inf(sound.event_distance(blocked_out, outside)), "内部波前经过柜口后开门，不让过去的鼓掌重新外泄")

	sound.clear()
	_received.clear()
	doors.closed = true
	listener.global_position = inside
	var crossing: Dictionary = sound.emit_sound("probe", "monster", outside)
	var prefix: float = sound.acoustic_field.distance_at(crossing["field"], portal)
	var local_distance: float = Vector2(portal.x, portal.z).distance_to(Vector2(inside.x, inside.z))
	var expected: float = prefix + local_distance
	sound._physics_process(prefix * 0.45 / speed)
	doors.closed = false
	sound._physics_process((prefix * 0.55 + 0.01) / speed)
	_check(is_finite(sound.event_distance(crossing, inside)), "波前抵达柜口时门已打开，允许向柜内继续传播")
	_check(absf(sound.event_distance(crossing, inside) - expected) < 0.001, "柜内距离累计外部声路与柜口到内部距离")
	_check(_received.is_empty(), "抵达柜口不等于立即抵达柜内玩家")
	doors.closed = true
	sound._physics_process((local_distance + 0.01) / speed)
	_check(_received.size() == 1, "已过柜口的波继续传播，关门不会删除柜内世界状态")
	if _received.size() == 1:
		_check(absf(float(_received[0]["arrival_time"]) - expected / speed) < 0.001, "柜口传播保留准确累计延迟")
		_check(_received[0]["position"] == outside, "经柜口的听觉仍提供原始发声位置")

	sound.clear()
	_received.clear()
	doors.closed = false
	listener.global_position = outside
	var escaping: Dictionary = sound.emit_sound("clap", "player", inside)
	var inside_prefix: float = float(escaping["source_prefix"])
	sound._physics_process((inside_prefix - 0.01) / speed)
	_check(_received.is_empty() and is_inf(sound.event_distance(escaping, outside)), "柜内声波尚未抵达开口时，外部仍无显形或听觉")
	sound._physics_process(0.02 / speed)
	var escape_distance: float = sound.event_distance(escaping, outside)
	_check(escape_distance > inside_prefix + 1.9 and escape_distance < inside_prefix + 2.1, "开门柜内鼓掌通过柜口向外传播，累计路径长度")
	sound._physics_process((escape_distance - inside_prefix + 0.01) / speed)
	_check(_received.size() == 1, "外部监听者在开门传播到达后收到一次原始鼓掌")
	_check(sound.emitted_count == 1 and sound.active_waves.size() == 1, "柜口传播复用一个事件和距离层，不增殖声波或重复播放")
	_check(sound.get_child_count() == node_count, "柜口开合不分配额外音效节点")

	# A sound behind the cabinet must travel around its body to its only door.
	var bounds: AABB = spot["bounds"]
	var behind := Vector3(bounds.end.x + 0.3, 1.0, bounds.position.z - 0.2)
	var side_field: Dictionary = sound.acoustic_field.build_wave(behind, 14.0)
	var routed: float = sound.acoustic_field.distance_at(side_field, portal)
	var direct: float = Vector2(behind.x, behind.z).distance_to(Vector2(portal.x, portal.z))
	_check(routed > direct + 0.1, "柜背与侧板阻挡声路，声音必须绕到正面柜口")

	sound.clear()
	_received.clear()
	var table: Dictionary = data.hiding_spots[2]
	var under: Vector3 = (table["inside"] as Vector3) + Vector3(0.0, 0.6, 0.0)
	listener.global_position = under
	sound.emit_sound("probe", "monster", under + Vector3(2.0, 0.0, 0.0))
	sound._physics_process(0.15)
	_check(_received.size() == 1, "桌底保持声路开放，探测可确认桌下玩家")
	sound.clear()
	_check(sound.active_waves.is_empty() and sound._field_cache.is_empty(), "重置清除柜口判定与声波缓存")
	if DisplayServer.get_name() != "headless":
		await _gpu_checks(sound, doors, spot, inside, outside)
	else:
		print("CABINET_GPU_RESULT: SKIP — headless cannot validate cabinet pixels")
	sound.queue_free()
	doors.queue_free()
	listener.queue_free()
	await process_frame
	print("CABINET_SOUND_RESULT: %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit.call_deferred(0 if _failures == 0 else 1)


func _gpu_checks(sound: SoundSystem, doors: DoorFixture, spot: Dictionary, inside: Vector3, outside: Vector3) -> void:
	root.size = Vector2i(960, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.title = "Echo Escape - cabinet acoustic region regression"
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color.BLACK
	world.add_child(env)
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/environment.gdshader")
	material.set_shader_parameter("player_position", Vector3(-100.0, 0.0, -100.0))
	sound.bind_material(material)
	# Deliberately omit cabinet walls for these floor samples. Black interior
	# pixels must come from acoustic region rejection, not a camera occluder.
	var inside_floor: Vector3 = inside * Vector3(1.0, 0.0, 1.0)
	var outside_floor: Vector3 = outside * Vector3(1.0, 0.0, 1.0)
	for center: Vector3 in [inside_floor, outside_floor]:
		world.add_child(_quad([
			center + Vector3(-0.3, 0.0, -0.3), center + Vector3(0.3, 0.0, -0.3),
			center + Vector3(0.3, 0.0, 0.3), center + Vector3(-0.3, 0.0, 0.3),
		], Vector3.UP, material))
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.0
	camera.position = (inside_floor + outside_floor) * 0.5 + Vector3.UP * 8.0
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	camera.current = true
	var source: Vector3 = outside + Vector3(0.0, 0.0, -1.0)
	sound.clear()
	var baseline: Image = await _capture()
	var interior_base: Color = _pixel_color(baseline, camera, inside_floor)
	var exterior_base: Color = _pixel_color(baseline, camera, outside_floor)
	print("CABINET_GPU baseline interior=%.4f exterior=%.4f" % [_pixel(baseline, camera, inside_floor), _pixel(baseline, camera, outside_floor)])
	doors.closed = true
	sound.clear()
	sound.emit_sound("clap", "player", source)
	sound._physics_process(0.4)
	var closed_capture: Image = await _capture()
	var interior_dark: float = _pixel(closed_capture, camera, inside_floor)
	var exterior_lit: float = _pixel(closed_capture, camera, outside_floor)
	print("CABINET_GPU closed interior=%.4f exterior=%.4f" % [interior_dark, exterior_lit])
	_check(_color_delta(_pixel_color(closed_capture, camera, inside_floor), interior_base) < 1.0 / 255.0 and exterior_lit > 0.15, "GPU：闭柜内保持黑暗，外部环境照常显形")
	doors.closed = false
	sound._physics_process(0.05)
	var reopened: Image = await _capture()
	print("CABINET_GPU reopened interior=%.4f exterior=%.4f" % [_pixel(reopened, camera, inside_floor), _pixel(reopened, camera, outside_floor)])
	_check(_color_delta(_pixel_color(reopened, camera, inside_floor), interior_base) < 1.0 / 255.0, "GPU：错过柜口的波不会因稍后开门而补画柜内")
	sound.clear()
	sound.emit_sound("clap", "player", source)
	sound._physics_process(0.4)
	var open_capture: Image = await _capture()
	var interior_lit: float = _pixel(open_capture, camera, inside_floor)
	print("CABINET_GPU open interior=%.4f exterior=%.4f" % [interior_lit, _pixel(open_capture, camera, outside_floor)])
	_check(interior_lit > 0.15, "GPU：开门时波经柜口进入，柜内连续显形")
	doors.closed = true
	sound.clear()
	sound.emit_sound("clap", "player", inside)
	sound._physics_process(0.3)
	var internal_capture: Image = await _capture()
	print("CABINET_GPU internal interior=%.4f exterior=%.4f" % [_pixel(internal_capture, camera, inside_floor), _pixel(internal_capture, camera, outside_floor)])
	_check(_pixel(internal_capture, camera, inside_floor) > 0.15 and _color_delta(_pixel_color(internal_capture, camera, outside_floor), exterior_base) < 1.0 / 255.0, "GPU：关门后内部鼓掌只照亮柜内，外部不漏光")
	# Regression: a side can fall onto a texel whose center is inside the
	# cupboard. The exterior-side projection must still reveal the real face.
	var bounds: AABB = spot["bounds"]
	world.add_child(_quad([
		Vector3(bounds.end.x, 0.0, bounds.position.z), Vector3(bounds.end.x, 0.0, bounds.end.z),
		Vector3(bounds.end.x, bounds.end.y, bounds.end.z), Vector3(bounds.end.x, bounds.end.y, bounds.position.z),
	], Vector3.RIGHT, material))
	var side_point := Vector3(bounds.end.x, 1.1, (bounds.position.z + bounds.end.z) * 0.5)
	camera.position = side_point + Vector3(5.0, 0.0, 0.0)
	camera.look_at(side_point)
	camera.size = 3.0
	sound.clear()
	var side_baseline: Image = await _capture()
	var side_base: float = _pixel(side_baseline, camera, side_point)
	sound.emit_sound("clap", "player", outside)
	sound._physics_process(0.3)
	var side_capture: Image = await _capture()
	var side_lit: float = _pixel(side_capture, camera, side_point)
	print("CABINET_GPU side baseline=%.4f lit=%.4f" % [side_base, side_lit])
	_check(side_lit > 0.15, "GPU：柜外侧面不会因距离纹理采进柜内而整面永黑")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/screenshots"))
	_check(side_capture.save_png("res://docs/screenshots/v0.3-cabinet-side.png") == OK, "保存柜侧显形图形证据")
	sound.clear()
	sound._materials.erase(material)
	material = null
	world.queue_free()
	await process_frame
	await process_frame
	print("CABINET_GPU_RESULT: completed actual Forward+ pixel checks")


func _quad(points: Array[Vector3], normal: Vector3, material: ShaderMaterial) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in [0, 1, 2, 0, 2, 3]:
		surface.set_normal(normal)
		surface.set_color(Color.WHITE)
		surface.set_uv2(Vector2(-1.0, -1.0))
		surface.add_vertex(points[index])
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface.commit()
	mesh.material_override = material
	return mesh


func _capture() -> Image:
	for frame: int in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _pixel(capture: Image, camera: Camera3D, point: Vector3) -> float:
	var color: Color = _pixel_color(capture, camera, point)
	return maxf(color.r, maxf(color.g, color.b))


func _pixel_color(capture: Image, camera: Camera3D, point: Vector3) -> Color:
	var screen: Vector2 = camera.unproject_position(point)
	var pixel := Vector2i(roundi(screen.x), roundi(screen.y))
	var total := Color(0.0, 0.0, 0.0, 0.0)
	for y: int in range(pixel.y - 1, pixel.y + 2):
		for x: int in range(pixel.x - 1, pixel.x + 2):
			total += capture.get_pixel(clampi(x, 0, capture.get_width() - 1), clampi(y, 0, capture.get_height() - 1))
	return total / 9.0


func _color_delta(actual: Color, baseline: Color) -> float:
	return maxf(absf(actual.r - baseline.r), maxf(absf(actual.g - baseline.g), absf(actual.b - baseline.b)))
