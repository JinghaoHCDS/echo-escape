extends SceneTree
## Real capsule, door and tabletop physics; no replacement collision model.

var failures: int = 0
var checks: int = 0
var stage: Node3D
var data: LevelData
var player: EchoPlayer
var hiding: HidingSystem
var settings: Dictionary
var monster: EchoMonster

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		failures += 1

func settle(count: int = 3) -> void:
	for index: int in range(count):
		await physics_frame

func complete() -> void:
	for index: int in range(150):
		await physics_frame
		if not hiding.is_transitioning():
			return

func place_outside(id: String) -> void:
	player.global_position = Vector3(hiding.get_spot(id)["entry"])
	player.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO

func ray(from: Vector3, to: Vector3) -> Dictionary:
	return stage.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))

func run() -> void:
	for action: String in ["move_left", "move_right", "move_forward", "move_back", "run", "clap", "interact"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	settings = JSON.parse_string(FileAccess.get_file_as_string("res://config/gameplay.json")) as Dictionary
	stage = Node3D.new()
	root.add_child(stage)
	data = LevelData.new()
	var level := LevelBuilder.new()
	stage.add_child(level)
	level.setup(data)
	player = EchoPlayer.new()
	stage.add_child(player)
	player.setup(settings)
	hiding = HidingSystem.new()
	stage.add_child(hiding)
	hiding.setup(data, player, null, settings, level.material)
	var sound := SoundSystem.new()
	stage.add_child(sound)
	sound.set_physics_process(false)
	monster = EchoMonster.new()
	stage.add_child(monster)
	monster.setup(data, player, sound, settings)
	monster.set_physics_process(false)
	await settle()

	check(data.hiding_spots.size() == 3, "HIDE: exactly two lockers and one table from shared data")
	for spot: Dictionary in data.hiding_spots:
		var cell: Vector2i = data.world_to_cell(Vector3(spot["inside"]))
		check(data.is_open(cell) and not data.is_navigation_open(cell), "HIDE: hollow furniture floor remains open while monster footprint is blocked: " + String(spot["id"]))
		check(data.navigation_target(Vector3(spot["inside"])) == Vector3(spot["approach"]) and not data.find_path(data.monster_spawn, Vector3(spot["inside"])).is_empty(), "HIDE: inside evidence resolves to a reachable entrance: " + String(spot["id"]))
		check(not data.find_path(data.monster_spawn, Vector3(spot["approach"])).is_empty(), "HIDE: monster reaches furniture approach without crossing footprint: " + String(spot["id"]))

	place_outside("gallery_locker")
	await settle()
	check(not hiding.candidate().is_empty(), "HIDE: facing nearby locker selects it")
	player.rotation.y = PI
	check(hiding.candidate().is_empty(), "HIDE: looking away does not select locker")
	player.rotation.y = 0.0
	var locker: Dictionary = hiding.get_spot("gallery_locker")
	var entry: Vector3 = Vector3(locker["entry"])
	var inside: Vector3 = Vector3(locker["inside"])
	check(not ray(entry + Vector3.UP, inside + Vector3.UP).is_empty(), "HIDE: closed real door blocks line of sight and attacks")
	check(hiding.interact(), "HIDE: E starts validated locker entry")
	await complete()
	await settle(22)
	check(hiding.current_spot_id == "gallery_locker" and player.global_position.distance_to(inside) < 0.05, "HIDE: capsule physically reaches hollow locker interior")
	check(hiding.is_closed("gallery_locker"), "HIDE: locker door closes after entry")
	var before: Vector3 = player.global_position
	var steps: int = player.footsteps_emitted
	Input.action_press("move_forward")
	await settle(20)
	Input.action_release("move_forward")
	check(player.global_position.distance_to(before) < 0.005 and player.footsteps_emitted == steps, "HIDE: hiding suppresses locomotion and footsteps")
	check(hiding.inspect("gallery_locker"), "HIDE: inspection opens locker without causing damage")
	await settle(22)
	check(not hiding.is_closed("gallery_locker") and ray(entry + Vector3.UP, inside + Vector3.UP).is_empty(), "HIDE: inspected cabinet has a physically open door")
	monster.global_position = hiding.inspection_position("gallery_locker")
	await settle()
	check(hiding.interact(), "HIDE: E starts safe locker exit with real monster at inspection point")
	await complete()
	check(hiding.current_spot_id.is_empty() and player.hiding_spot_id.is_empty() and not player.motion_locked, "HIDE: exit clears posture and movement lock")

	monster.global_position = data.monster_spawn
	place_outside("atrium_table")
	await settle()
	check(hiding.interact(), "HIDE: E starts table entry")
	# Pause must halt motion/door time, with no async tween continuing.
	var paused_at: Vector3 = player.global_position
	paused = true
	for index: int in range(8):
		await process_frame
	check(player.global_position == paused_at, "HIDE: paused transition does not keep moving")
	paused = false
	await complete()
	check(player.hiding_kind == "table" and player.capsule.height < 0.9 and player.camera.position.y < 0.8, "HIDE: table entry shortens real capsule and lowers eye")
	var table: Dictionary = hiding.get_spot("atrium_table")
	check(not hiding._shape_clear(player.global_position, 1.75, [player.get_rid()]), "HIDE: standing under tabletop is rejected by physical query")
	check(hiding._shape_clear(player.global_position, player.capsule.height, [player.get_rid()]), "HIDE: crouched capsule genuinely fits under tabletop")
	check(not ray(player.sight_target() + Vector3.UP * 1.4, player.sight_target()).is_empty(), "HIDE: tabletop occludes elevated sight")
	check(ray(Vector3(table["entry"]) + Vector3.UP * 0.6, player.sight_target()).is_empty(), "HIDE: open table side can expose crouched player")

	var blocker := StaticBody3D.new()
	blocker.collision_layer = 1
	var block_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.2, 2.5, 1.2)
	block_shape.shape = box
	blocker.add_child(block_shape)
	stage.add_child(blocker)
	blocker.position = Vector3(table["entry"]) + Vector3(0, 1.25, 0.35)
	await settle()
	before = player.global_position
	check(not hiding.interact(), "HIDE: blocked standing exits reject leaving")
	await settle()
	check(player.global_position == before and player.hiding_spot_id == "atrium_table", "HIDE: blocked exit neither teleports nor clears cover state")
	blocker.queue_free()
	await settle()
	monster.global_position = hiding.inspection_position("atrium_table")
	await settle()
	check(hiding.inspect("atrium_table"), "HIDE: table inspection safely exits beside real monster at inspection point")
	await complete()
	check(hiding.current_spot_id.is_empty() and is_equal_approx(player.capsule.height, 1.75), "HIDE: forced table exit restores standing capsule")

	# Insert an actual solid partition between two otherwise nearby points.
	monster.global_position = data.monster_spawn
	place_outside("gallery_locker")
	player.set_physics_process(false)
	var partition := StaticBody3D.new()
	partition.collision_layer = 1
	var partition_shape := CollisionShape3D.new()
	var partition_box := BoxShape3D.new()
	partition_box.size = Vector3(2.0, 2.4, 0.12)
	partition_shape.shape = partition_box
	partition.add_child(partition_shape)
	stage.add_child(partition)
	partition.position = player.global_position + Vector3(0, 1.2, -0.35)
	await settle()
	check(hiding.candidate().is_empty(), "HIDE: solid partition blocks interaction through walls")
	stage.queue_free()
	await process_frame
	print("HIDING checks=", checks, " failures=", failures)
	quit(failures)
