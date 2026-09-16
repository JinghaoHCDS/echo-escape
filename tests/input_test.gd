extends SceneTree
var failures: int = 0
func _initialize() -> void:
	call_deferred("run")
func check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		failures += 1
func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	event = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = false
	Input.parse_input_event(event)
func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("INPUT graphical mouse capture: SKIP headless")
		quit()
		return
	var game: EchoGame = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_game()
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100.0, 50.0)
	Input.parse_input_event(motion)
	await process_frame
	check(absf(game.player.rotation.y) > 0.1 and absf(game.player.camera.rotation.x) > 0.05, "input: captured relative mouse motion rotates yaw and pitch")
	key(KEY_ESCAPE)
	await process_frame
	check(game.status == "paused" and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "input: Esc pauses and releases cursor")
	var clock_before: float = game.sound.clock
	await create_timer(0.1).timeout
	check(game.sound.clock == clock_before, "input: pause freezes acoustic and evidence clock")
	key(KEY_ESCAPE)
	await process_frame
	check(game.status == "playing" and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "input: Esc resumes and captures cursor")
	key(KEY_F1)
	await process_frame
	check(game.debug_enabled and game.ui.grid.visible, "input: F1 toggles developer view")
	game.monster.set_physics_process(false)
	game.player.enabled = true
	game.player.position = game.data.item_position + Vector3(0.0, 0.0, 1.0)
	game.objectives.is_activated = true
	await physics_frame
	await physics_frame
	key(KEY_E)
	# Input injected from physics_frame is flushed after the next frame boundary.
	await process_frame
	await process_frame
	check(game.objectives.has_item, "input: E reaches real interaction handler")
	game.finish(false, "input fixture")
	key(KEY_R)
	await process_frame
	await process_frame
	game = current_scene as EchoGame
	check(game.status == "intro" and not game.objectives.has_item, "input: R rebuilds scene from result screen")
	paused = false
	game.queue_free()
	await process_frame
	print("INPUT failures=", failures)
	quit(failures)
