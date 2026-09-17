extends SceneTree

var failures: int = 0
var game: EchoGame

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		failures += 1

func new_game() -> void:
	game = load("res://scenes/main.tscn").instantiate() as EchoGame
	root.add_child(game)
	current_scene = game
	game.start_game()
	await physics_frame

func run() -> void:
	await new_game()
	game.monster.set_physics_process(false)
	game.player.enabled = false
	await physics_frame
	check(not game.objectives.has_item and game.status == "playing", "D: exit without core never wins")
	game.player.position = game.data.item_position + Vector3(0.0, 0.0, 1.0)
	await physics_frame
	check(not game.objectives.interact(), "D: unactivated core cannot be picked up")
	game.clap()
	for i in range(18):
		await physics_frame
	check(game.objectives.is_activated, "D: real reachable clap activates core")
	check(game.objectives.interact(), "D: activated unobstructed nearby core can be picked up")
	check(game.monster.alarm_active, "D: pickup explicitly enables continuous beacon tracking")
	check(game.ui.toast_label.text.contains("持续追踪"), "D: beacon warning displayed")
	check(not game.objectives.interact(), "D: repeated interaction does not duplicate pickup")
	game.player.position = game.data.exit_position
	await physics_frame
	await physics_frame
	check(game.status == "won", "D: carried core at exit wins immediately")
	var session_count: int = game.session.get_child_count()
	for index in range(3):
		game.restart()
		await process_frame
		await process_frame
		game = current_scene as EchoGame
		check(game != null and game.status == "intro", "D: restart %d returns to intro" % index)
		check(not game.objectives.has_item and not game.objectives.is_activated and not game.monster.alarm_active, "D: restart resets core and alarm")
		check(game.sound.active_waves.is_empty() and game.sound.active_voice_count() == 0, "D: restart clears waves and audio")
		check(game.hiding.current_spot_id.is_empty() and game.player.hiding_spot_id.is_empty() and not game.hiding.is_transitioning(), "D: restart clears hiding ownership and transition")
		check(is_equal_approx(game.player.camera.position.y, float(game.config["hide_standing_eye_height"])), "D: restart restores standing camera")
		check(game.session.get_child_count() == session_count, "D: restart does not accumulate session nodes")
		game.start_game()
		game.finish(false, "test fixture")
		check(game.status == "lost", "D: failure freezes game and presents restart")
	paused = false
	game.queue_free()
	await process_frame
	print("GAMEPLAY failures=", failures)
	quit(failures)
