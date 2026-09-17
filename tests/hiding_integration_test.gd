extends SceneTree
## Full-session integration: real E dispatch in graphical mode, actual furniture,
## physics transitions, pause, closed-door probe isolation, inspection and reload.
var game: EchoGame
var failures: int = 0
var graphical: bool = false

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok:
		failures += 1

func ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame

func press(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	if graphical:
		Input.parse_input_event(event)
		event = InputEventKey.new()
		event.physical_keycode = code
		event.pressed = false
		Input.parse_input_event(event)
	elif code == KEY_E:
		game.interact()
	else:
		game._unhandled_input(event)
	await process_frame
	await process_frame

func photograph(name: String) -> void:
	if not graphical:
		return
	# F1/input can arrive between physics ticks. Let the HUD reflect this pose.
	await physics_frame
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/screenshots"))
	check(root.get_texture().get_image().save_png("res://docs/screenshots/v0.3-" + name + ".png") == OK, "saved " + name)

func face_entry(id: String) -> void:
	var spot: Dictionary = game.hiding.get_spot(id)
	game.player.global_position = Vector3(spot["entry"])
	game.player.velocity = Vector3.ZERO
	game.player.rotation.y = 0.0
	game.player.camera.rotation = Vector3.ZERO
	await ticks(2)
	game.player.camera.look_at(Vector3(spot["portal"]))

func _run() -> void:
	graphical = DisplayServer.get_name() != "headless"
	if graphical:
		root.size = Vector2i(1920, 1080)
	game = load("res://scenes/main.tscn").instantiate() as EchoGame
	root.add_child(game)
	current_scene = game
	game.start_game()
	game.monster.set_physics_process(false)
	game.monster.global_position = Vector3(32.5, 0.0, 8.5)
	await face_entry("gallery_locker")
	check(game._interaction_target() == "hiding", "E resolves the selected locker only")
	await press(KEY_F1)
	await photograph("locker-front")
	await press(KEY_F1)
	await press(KEY_E)
	await ticks(4)
	await press(KEY_ESCAPE)
	var stopped_position: Vector3 = game.player.global_position
	var stopped_clock: float = game.sound.clock
	await process_frame
	await process_frame
	check(game.status == "paused" and game.player.global_position == stopped_position and game.sound.clock == stopped_clock, "pause freezes entry movement and sound clock")
	await press(KEY_E)
	check(game.hiding.current_spot_id == "gallery_locker", "paused E cannot leave hiding or pick up an object")
	await press(KEY_ESCAPE)
	await ticks(100)
	check(game.hiding.current_spot_id == "gallery_locker" and not game.hiding.is_transitioning() and game.hiding.is_closed("gallery_locker"), "real E enters and closes the hollow locker")
	check(not game.objectives.has_item, "entering never triggers core pickup")
	var hidden_at: Vector3 = game.player.global_position
	var step_count: int = game.player.footsteps_emitted
	Input.action_press("move_forward")
	await ticks(12)
	Input.action_release("move_forward")
	check(game.player.global_position == hidden_at and game.player.footsteps_emitted == step_count, "hidden movement input produces neither displacement nor footsteps")
	var evidence: float = game.monster.last_evidence_time
	game.sound.emit_sound("probe", "monster", Vector3(game.hiding.get_spot("gallery_locker")["entry"]))
	await ticks(25)
	check(game.monster.last_evidence_time == evidence, "actual exterior probe cannot confirm the player inside a closed locker")
	game.clap_remaining = 0.0
	game.clap()
	await ticks(8)
	await photograph("locker-inside")
	await press(KEY_E)
	await ticks(100)
	check(game.hiding.current_spot_id.is_empty() and not game.player.motion_locked, "E exits the locker and restores movement")
	await face_entry("atrium_table")
	await press(KEY_E)
	await ticks(100)
	check(game.hiding.current_spot_id == "atrium_table" and game.player.capsule.height < 0.9 and game.player.camera.position.y < 0.8, "E enters the table with a real short capsule and low camera")
	await press(KEY_F1)
	await photograph("table-inside")
	await press(KEY_F1)
	game.monster.global_position = game.hiding.inspection_position("atrium_table")
	game.monster.set_alarm(true)
	game.monster.set_physics_process(true)
	var inspecting: bool = false
	for index: int in range(240):
		await physics_frame
		if game.monster.state == EchoMonster.INSPECT_HIDE and not inspecting:
			inspecting = true
			await photograph("hide-inspection")
		if game.hiding.current_spot_id.is_empty() or game.status != "playing":
			break
	check(inspecting, "beacon makes the real monster inspect the known hiding entrance")
	check(game.hiding.current_spot_id.is_empty(), "table inspection can complete a collision-safe exit with the monster present")
	check(game.status == "playing", "inspection does not directly cause failure")
	game.monster.set_physics_process(false)
	game.finish(false, "hiding integration reset fixture")
	game.restart()
	await process_frame
	await process_frame
	game = current_scene as EchoGame
	check(game.status == "intro" and game.hiding.current_spot_id.is_empty() and game.player.hiding_spot_id.is_empty() and not game.player.motion_locked, "result restart restores ownership, pose and movement")
	check(game.hiding.is_closed("gallery_locker") and game.hiding.is_closed("archive_locker") and game.monster.known_hiding_spot_id.is_empty(), "result restart resets doors and monster hiding memory")
	paused = false
	game.queue_free()
	await process_frame
	print("HIDING_INTEGRATION_RESULT: failures=", failures, " graphical=", graphical)
	quit(failures)
