extends SceneTree
## Reproducible engine-driven traversal with real input, collision, AI, and audio.
## No player teleport in the successful expedition. The loss fixture places
## actors together only to exercise a real telegraphed attack and scene reload.
var game: EchoGame
var failures: int = 0
var frames: int = 0
var worst_frame_ms: float = 0.0
var elapsed_ms: float = 0.0
var capture: bool = false
var start_usec: int = 0
var start_drawn: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		failures += 1

func snapshot(label: String) -> void:
	if not capture:
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/screenshots/" + label + ".png")

func tick() -> void:
	await physics_frame
	frames += 1
	var frame_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	worst_frame_ms = maxf(worst_frame_ms, frame_ms)
	elapsed_ms += frame_ms
	if game.clap_remaining <= 0.0:
		game.clap()

func walk_to(target: Vector3) -> void:
	var route: Array[Vector3] = game.data.find_path(game.player.global_position, target)
	for point: Vector3 in route:
		var guard: int = 0
		while EchoObjectives.horizontal_distance(game.player.global_position, point) > 0.13 and game.status == "playing":
			var direction: Vector3 = point - game.player.global_position
			game.player.rotation.y = atan2(-direction.x, -direction.z)
			Input.action_press("move_forward")
			Input.action_press("run")
			await tick()
			guard += 1
			if guard > 180:
				check(false, "traversal stuck at " + str(game.player.position))
				return
	Input.action_release("move_forward")
	Input.action_release("run")

func run() -> void:
	capture = DisplayServer.get_name() != "headless" and not "--no-capture" in OS.get_cmdline_user_args()
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1920, 1080)
	if capture:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/screenshots"))
		root.size = Vector2i(1920, 1080)
	game = load("res://scenes/main.tscn").instantiate() as EchoGame
	root.add_child(game)
	current_scene = game
	await snapshot("01-intro")
	game.start_game()
	game.player.camera.rotation.x = -0.13
	await tick()
	await snapshot("02-entry-echo")
	start_usec = Time.get_ticks_usec()
	start_drawn = Engine.get_frames_drawn()
	await walk_to(Vector3(8.5, 0.0, 12.5))
	await walk_to(Vector3(10.5, 0.0, 7.5))
	await walk_to(Vector3(18.5, 0.0, 6.5))
	await snapshot("03-archive")
	await walk_to(Vector3(25.5, 0.0, 6.5))
	await walk_to(game.data.item_position + Vector3(0.0, 0.0, 1.0))
	check(game.status == "playing", "E: real movement reaches deep machine room with active AI")
	for index in range(100):
		await tick()
		if game.objectives.is_activated:
			break
	game.player.rotation.y = 0.0
	await snapshot("04-core")
	check(game.objectives.interact(), "E: reachable clap then real pickup")
	check(game.monster.alarm_active, "E: active pursuer switched to beacon tracking")
	await walk_to(Vector3(32.5, 0.0, 8.5))
	await walk_to(Vector3(26.5, 0.0, 13.5))
	await snapshot("05-beacon-return")
	await walk_to(Vector3(17.5, 0.0, 15.5))
	await walk_to(Vector3(8.5, 0.0, 16.5))
	await walk_to(game.data.exit_position)
	for index in range(3):
		await physics_frame
	check(game.status == "won", "E: full expedition + pickup + alternate return route wins")
	await snapshot("06-victory")
	print("METRICS viewport=", root.size, " physics_samples=", frames, " elapsed_seconds=", float(Time.get_ticks_usec() - start_usec) / 1000000.0, " rendered_frames=", Engine.get_frames_drawn() - start_drawn, " capture=", capture, " last_fps=", Engine.get_frames_per_second(), " renderer=", RenderingServer.get_current_rendering_method())
	game.restart()
	await process_frame
	await process_frame
	game = current_scene as EchoGame
	check(game.status == "intro" and game.sound.active_waves.is_empty(), "E: victory restart produces fresh scene")
	game.start_game()
	game.player.enabled = false
	game.player.position = Vector3(17.5, 0.0, 15.0)
	game.monster.position = Vector3(17.5, 0.0, 16.4)
	game.monster.rotation.y = 0.0
	game.player.rotation.y = PI
	var windup_seen: bool = false
	for index in range(180):
		await physics_frame
		if game.monster.state == "ATTACK_WINDUP" and game.monster._state_time > 0.35 and not windup_seen:
			windup_seen = true
			await snapshot("07-windup")
		if game.status == "lost":
			break
	check(windup_seen, "E: visible attack windup precedes failure")
	check(game.status == "lost", "E: actual attack hit produces failure")
	await snapshot("08-defeat")
	game.restart()
	await process_frame
	await process_frame
	game = current_scene as EchoGame
	check(game.status == "intro" and not game.objectives.has_item, "E: actual defeat restart resets scene")
	paused = false
	game.queue_free()
	await process_frame
	print("PLAYTHROUGH failures=", failures)
	quit(failures)
