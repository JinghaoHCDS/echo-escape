extends SceneTree
## Graphical depth regression: a bright, already-revealed object must remain
## hidden behind an opaque, unrevealed wall. Headless execution cannot test GPU
## pixels and reports SKIP rather than a fabricated pass.

var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		failures += 1

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP OCCLUSION: headless display has no graphical depth / pixel verification")
		quit(0)
		return
	root.size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.title = "Echo Escape - opaque wall regression"
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var data: LevelData = LevelData.new()
	var level: LevelBuilder = LevelBuilder.new()
	world.add_child(level)
	level.setup(data)
	var dark_image: Image = Image.create(LevelData.WIDTH, LevelData.HEIGHT, false, Image.FORMAT_RGBAF)
	dark_image.fill(Color(-100.0, -100.0, 0.0, 1.0))
	level.set_reveal_texture(ImageTexture.create_from_image(dark_image))
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(19.5, 1.6, 2.5)
	camera.fov = 60.0
	camera.current = true
	camera.look_at(Vector3(25.5, 1.6, 2.5), Vector3.UP)
	level.update_view(camera.position, 10.0, false)
	var target: MeshInstance3D = MeshInstance3D.new()
	var shape: BoxMesh = BoxMesh.new()
	shape.size = Vector3(1.5, 1.5, 1.5)
	target.mesh = shape
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.0, 1.0, 1.0)
	target.material_override = material
	world.add_child(target)
	target.position = Vector3(25.5, 1.6, 2.5)
	var dark_wall_pixel: Color = await center_pixel()
	print("OCCLUSION dark wall center RGB=", Vector3(dark_wall_pixel.r, dark_wall_pixel.g, dark_wall_pixel.b))
	check(maxf(dark_wall_pixel.r, maxf(dark_wall_pixel.g, dark_wall_pixel.b)) < 0.10,
		"unrevealed opaque wall hides a bright target across the wall")
	# Keep the wall visible but reveal normal lighting: this distinguishes a
	# genuinely rendered wall from a missing camera / entirely black viewport.
	level.update_view(camera.position, 10.0, true)
	var lit_wall_pixel: Color = await center_pixel()
	print("OCCLUSION debug wall center RGB=", Vector3(lit_wall_pixel.r, lit_wall_pixel.g, lit_wall_pixel.b))
	check(lit_wall_pixel.g > dark_wall_pixel.g + 0.12,
		"developer lighting reveals the same wall surface")
	check(lit_wall_pixel.g > lit_wall_pixel.r * 0.55,
		"developer lighting still occludes the magenta target")
	# Remove only the architecture's visual meshes. The target and camera do
	# not move; the formerly blocked bright object must now occupy the pixel.
	level.visible = false
	var exposed_pixel: Color = await center_pixel()
	print("OCCLUSION exposed target center RGB=", Vector3(exposed_pixel.r, exposed_pixel.g, exposed_pixel.b))
	check(exposed_pixel.r > 0.70 and exposed_pixel.b > 0.70 and exposed_pixel.g < 0.15,
		"hiding architecture exposes the bright magenta target at the same pixel")
	check(exposed_pixel.r - dark_wall_pixel.r > 0.60,
		"black wall depth, rather than target brightness or camera orientation, caused occlusion")
	world.queue_free()
	await process_frame
	print("OCCLUSION graphical failures=", failures)
	quit(failures)

func center_pixel() -> Color:
	# Let scene visibility and shader uniforms reach the renderer, then sample
	# the completed graphical frame instead of assuming process timing.
	for index: int in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var capture: Image = root.get_texture().get_image()
	if capture == null or capture.is_empty():
		check(false, "graphical viewport capture produced image pixels")
		return Color(0.0, 1.0, 0.0, 1.0)
	var center: Vector2i = capture.get_size() / 2
	var total: Color = Color(0.0, 0.0, 0.0, 0.0)
	for y: int in range(center.y - 2, center.y + 3):
		for x: int in range(center.x - 2, center.x + 3):
			total += capture.get_pixel(x, y)
	return total / 25.0
