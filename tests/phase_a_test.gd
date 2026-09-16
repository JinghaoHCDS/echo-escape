extends SceneTree

var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		failures += 1

func run() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/gameplay.json"))
	var data := LevelData.new()
	var level := LevelBuilder.new()
	root.add_child(level)
	level.setup(data)
	var player := EchoPlayer.new()
	root.add_child(player)
	player.setup(config)
	player.position = Vector3(2.5, 0.05, 25.5)
	player.enabled = false
	for index in range(120):
		player.velocity = Vector3(-2.8, -1.0, 0.0)
		player.move_and_slide()
		await physics_frame
	check(player.global_position.x >= 2.27, "A: capsule blocked by west wall")
	check(player.global_position.y > -0.1, "A: floor blocks gravity")
	var path: Array[Vector3] = data.find_path(data.spawn_position, data.item_position)
	check(path.size() > 20, "A: entry and deep item connected")
	var valid: bool = true
	for point: Vector3 in path:
		valid = valid and data.is_open(data.world_to_cell(point))
	check(valid, "A: every navigation waypoint is in physical open grid")
	# Real input at a wall must produce zero steps after initial movement settles.
	InputMap.add_action("move_left")
	InputMap.add_action("move_right")
	InputMap.add_action("move_forward")
	InputMap.add_action("move_back")
	InputMap.add_action("run")
	InputMap.add_action("clap")
	InputMap.add_action("interact")
	player.enabled = true
	player.distance_since_step = 0.0
	Input.action_press("move_left")
	for index in range(90):
		await physics_frame
	Input.action_release("move_left")
	check(player.footsteps_emitted == 0, "A: pushing into wall does not emit footsteps")
	player.queue_free()
	level.queue_free()
	await process_frame
	print("PHASE A failures=", failures)
	quit(failures)
