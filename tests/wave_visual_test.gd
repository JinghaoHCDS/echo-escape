extends SceneTree
## Forward+ pixel regression for a continuous circular / hemispherical front.
## The fixture uses two triangles per plane: propagation must be independent
## of mesh tessellation. Headless explicitly skips actual GPU validation.

const CAPTURE_DIRECTORY: String = "res://docs/screenshots"
const ORIGIN: Vector3 = Vector3(12.5, 0.0, 12.5)

var _failures: int = 0
var _camera: Camera3D
var _material: ShaderMaterial
var _sound: SoundSystem


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		_failures += 1


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("WAVE_VISUAL_RESULT: SKIP — headless cannot verify curved fronts in GPU pixels")
		quit(0)
		return
	root.size = Vector2i(960, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.title = "Echo Escape - continuous wavefront regression"
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	world.add_child(environment)
	# Open fixture deliberately avoids the production map's doorways and
	# landmarks, so equal Euclidean radii must have equal arrival times.
	var data := LevelData.new()
	data.walkable.clear()
	data.solid_heights.clear()
	data.room_names.clear()
	for z: int in range(2, 25):
		for x: int in range(2, 25):
			data.walkable[Vector2i(x, z)] = true
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/gameplay.json"))
	_sound = SoundSystem.new()
	world.add_child(_sound)
	_sound.setup(data, config)
	_sound.set_physics_process(false)
	_sound.set_playback_volume(0.0)
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/environment.gdshader")
	_material.set_shader_parameter("grid_size", Vector2(LevelData.WIDTH, LevelData.HEIGHT))
	_material.set_shader_parameter("cell_size", LevelData.CELL_SIZE)
	_material.set_shader_parameter("player_position", Vector3(-100.0, 0.0, -100.0))
	_material.set_shader_parameter("debug_lit", false)
	_sound.bind_material(_material)
	var floor_mesh: MeshInstance3D = _plane([
		Vector3(2.0, 0.0, 2.0), Vector3(25.0, 0.0, 2.0),
		Vector3(25.0, 0.0, 25.0), Vector3(2.0, 0.0, 25.0),
	], Vector3.UP)
	world.add_child(floor_mesh)
	_camera = Camera3D.new()
	world.add_child(_camera)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 16.0
	_camera.position = Vector3(12.5, 20.0, 12.5)
	_camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_camera.current = true
	_sound.emit_sound("clap", "player", ORIGIN)
	var speed: float = float(config["propagation_speed"])
	_sound._physics_process(5.0 / speed)
	var circular_capture: Image = await _capture()
	for index: int in range(8):
		var angle: float = float(index) * TAU / 8.0
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var inside: Color = _sample(circular_capture, ORIGIN + direction * 4.2)
		var outside: Color = _sample(circular_capture, ORIGIN + direction * 6.0)
		print("WAVE_PIXEL angle=%d inside=%.4f outside=%.4f" % [index * 45, _brightness(inside), _brightness(outside)])
		_check(_brightness(inside) > 0.17, "radius 4.2 m reached at %d degrees, including diagonals" % (index * 45))
		_check(_brightness(outside) < 0.10, "radius 6.0 m remains dark at %d degrees" % (index * 45))
	_save_capture(circular_capture, "v0.2-circular-front.png")
	# A single vertical quad crosses the hemisphere: low portions have been
	# reached at radius 5 m while higher portions have a longer spatial path.
	floor_mesh.visible = false
	var wall_mesh: MeshInstance3D = _plane([
		Vector3(5.0, 0.0, 16.5), Vector3(20.0, 0.0, 16.5),
		Vector3(20.0, 7.0, 16.5), Vector3(5.0, 7.0, 16.5),
	], Vector3.FORWARD)
	world.add_child(wall_mesh)
	_camera.size = 9.0
	_camera.position = Vector3(12.5, 3.2, 8.0)
	_camera.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	var hemisphere_capture: Image = await _capture()
	var low_point := Vector3(12.5, 0.5, 16.5)
	var high_point := Vector3(12.5, 4.0, 16.5)
	var low: float = _brightness(_sample(hemisphere_capture, low_point))
	var high_before: float = _brightness(_sample(hemisphere_capture, high_point))
	print("HEMISPHERE_PIXEL radius=5 low=%.4f high=%.4f" % [low, high_before])
	_check(low > 0.17, "hemisphere has reached the lower part of one continuous wall face")
	_check(high_before < 0.10, "upper part of that same face remains dark until the hemisphere arrives")
	_save_capture(hemisphere_capture, "v0.2-hemisphere-wall.png")
	_sound._physics_process(1.2 / speed)
	var later_capture: Image = await _capture()
	var high_after: float = _brightness(_sample(later_capture, high_point))
	print("HEMISPHERE_PIXEL radius=6.2 high=%.4f" % high_after)
	_check(high_after > 0.17 and high_after > high_before + 0.10,
		"the high point lights later as radius expands; wall height is not lit all at once")
	_sound.clear()
	world.queue_free()
	await process_frame
	print("WAVE_VISUAL_RESULT: %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


func _plane(corners: Array[Vector3], normal: Vector3) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in [0, 1, 2, 0, 2, 3]:
		surface.set_normal(normal)
		surface.set_color(Color.WHITE)
		surface.set_uv2(Vector2(-1.0, -1.0))
		surface.add_vertex(corners[index])
	var instance := MeshInstance3D.new()
	instance.mesh = surface.commit()
	instance.material_override = _material
	return instance


func _capture() -> Image:
	_material.set_shader_parameter("echo_time", _sound.clock)
	for index: int in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _sample(capture: Image, position: Vector3) -> Color:
	var screen: Vector2 = _camera.unproject_position(position)
	var pixel := Vector2i(roundi(screen.x), roundi(screen.y))
	var total := Color(0.0, 0.0, 0.0, 0.0)
	for y: int in range(pixel.y - 1, pixel.y + 2):
		for x: int in range(pixel.x - 1, pixel.x + 2):
			total += capture.get_pixel(clampi(x, 0, capture.get_width() - 1), clampi(y, 0, capture.get_height() - 1))
	return total / 9.0


func _brightness(color: Color) -> float:
	return maxf(color.r, maxf(color.g, color.b))


func _save_capture(capture: Image, filename: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIRECTORY))
	var result: Error = capture.save_png(CAPTURE_DIRECTORY.path_join(filename))
	_check(result == OK, "saved graphical evidence " + filename)
