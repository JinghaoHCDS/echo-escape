class_name HidingSystem
extends Node3D
## Furniture, physical transitions and interaction selection share LevelData.
## Hiding is cover, never an invulnerability flag; monster checks real targets.

signal entering(spot_id: String, entry_position: Vector3)
signal door_changed(spot_id: String, closed: bool)
signal feedback(message: String)

var current_spot_id: String = ""
var config: Dictionary
var data: LevelData
var player: EchoPlayer
var sound: SoundSystem
var _material: ShaderMaterial
var _spots: Dictionary = {}
var _doors: Dictionary = {}
var _phase: String = ""
var _route: Array[Vector3] = []
var _exit_destination: Vector3

func setup(level_data: LevelData, actor: EchoPlayer, acoustics: SoundSystem, settings: Dictionary, material: ShaderMaterial) -> void:
	data = level_data
	player = actor
	sound = acoustics
	config = settings
	_material = material
	for definition: Dictionary in data.hiding_spots:
		var spot: Dictionary = definition.duplicate(true)
		var prop := Node3D.new()
		prop.name = String(spot["id"])
		add_child(prop)
		prop.position = Vector3(spot["position"])
		spot["node"] = prop
		_spots[String(spot["id"])] = spot
		if String(spot["kind"]) == "locker":
			_build_locker(spot, prop)
		else:
			_build_table(spot, prop)

func get_spot(id: String) -> Dictionary:
	return _spots.get(id, {})

func is_closed(id: String) -> bool:
	if not _doors.has(id):
		return false
	var door: Dictionary = _doors[id]
	return absf((door["hinge"] as Node3D).rotation.y) < 0.06

func inspection_position(id: String) -> Vector3:
	return Vector3(get_spot(id).get("approach", Vector3.ZERO))

func is_transitioning() -> bool:
	return not _phase.is_empty() and _phase != "hidden"

func candidate() -> Dictionary:
	if not current_spot_id.is_empty() or not player.enabled:
		return {}
	var best: Dictionary = {}
	var best_distance: float = float(config.get("hide_interact_distance", 2.2))
	for value: Variant in _spots.values():
		var spot: Dictionary = value
		var entry: Vector3 = Vector3(spot["entry"])
		var distance: float = player.global_position.distance_to(entry)
		if distance > best_distance:
			continue
		var target: Vector3 = Vector3(spot["portal"]) if String(spot["kind"]) == "locker" else Vector3(spot["position"]) + Vector3.UP
		var direction: Vector3 = player.camera.global_position.direction_to(target)
		if (-player.camera.global_basis.z).dot(direction) < float(config.get("hide_view_dot", 0.58)):
			continue
		var query := PhysicsRayQueryParameters3D.create(player.camera.global_position, target, 1)
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and not (spot["node"] as Node3D).is_ancestor_of(hit["collider"] as Node):
			continue
		best = spot.duplicate()
		best["distance"] = distance
		best_distance = distance
	return best

func prompt() -> String:
	if is_transitioning():
		return "正在进出躲藏处…"
	if not current_spot_id.is_empty():
		return "E 离开柜子 · 关门隔绝探测" if String(get_spot(current_spot_id)["kind"]) == "locker" else "E 离开桌底 · 探测仍可发现你"
	var selected: Dictionary = candidate()
	if selected.is_empty():
		return ""
	return "E 躲进柜子" if String(selected["kind"]) == "locker" else "E 躲到桌底"

func interact() -> bool:
	if is_transitioning():
		return false
	if not current_spot_id.is_empty():
		return _begin_exit()
	var selected: Dictionary = candidate()
	if selected.is_empty():
		return false
	return _begin_entry(String(selected["id"]))

func inspect(id: String) -> bool:
	var spot: Dictionary = get_spot(id)
	if spot.is_empty() or is_transitioning():
		return false
	if String(spot["kind"]) == "locker":
		_set_door(id, false)
		if current_spot_id == id:
			feedback.emit("柜门被打开了！侧移离开，躲避攻击")
		return true
	if current_spot_id == id:
		feedback.emit("怪物正在检查桌底，立刻离开！")
		return _begin_exit()
	return true

func _begin_entry(id: String) -> bool:
	var spot: Dictionary = get_spot(id)
	var entry: Vector3 = Vector3(spot["entry"])
	var inside: Vector3 = Vector3(spot["inside"])
	var height: float = _height_for(spot)
	var excluded: Array[RID] = _excluded(id)
	if not _shape_clear(player.global_position, height, excluded) or not _segment_clear(player.global_position, entry, height, excluded) or not _segment_clear(entry, inside, height, excluded):
		feedback.emit("入口被挡住了，靠近正面再试")
		return false
	# Emit while still outside with the standing eye point: observation is genuine.
	entering.emit(id, entry)
	current_spot_id = id
	player.set_hiding_pose(id, String(spot["kind"]))
	player.hide_transition = true
	_route.assign([entry, inside])
	_phase = "opening_entry"
	_set_door(id, false)
	return true

func _begin_exit() -> bool:
	var spot: Dictionary = get_spot(current_spot_id)
	var entry: Vector3 = Vector3(spot["entry"])
	var height: float = player.capsule.height
	var excluded: Array[RID] = _excluded(current_spot_id)
	for value: Variant in spot["exits"]:
		var destination: Vector3 = Vector3(value)
		if not _shape_clear(destination, float(config.get("hide_standing_height", 1.75)), excluded):
			continue
		if not _segment_clear(player.global_position, entry, height, excluded) or not _segment_clear(entry, destination, height, excluded):
			continue
		_exit_destination = destination
		_route.assign([entry, destination])
		_phase = "opening_exit"
		player.hide_transition = true
		_set_door(current_spot_id, false)
		return true
	feedback.emit("出口被挡住了，暂时无法站起离开")
	return false

func _physics_process(delta: float) -> void:
	_animate_doors(delta)
	if _phase.is_empty() or _phase == "hidden":
		return
	if _phase == "opening_entry" or _phase == "opening_exit":
		if _door_fully_open(current_spot_id):
			_phase = "entering" if _phase == "opening_entry" else "exiting"
		return
	if _route.is_empty():
		_complete_transition()
		return
	var target: Vector3 = _route[0]
	var motion: Vector3 = player.global_position.direction_to(target) * minf(player.global_position.distance_to(target), float(config.get("hide_move_speed", 3.2)) * delta)
	if not _segment_clear(player.global_position, player.global_position + motion, player.capsule.height, _excluded(current_spot_id)) or player.move_and_collide(motion) != null:
		# A newly inserted obstacle must stop motion. Keep the current small pose
		# rather than standing into a tabletop or teleporting through a blocker.
		_phase = "hidden"
		player.hide_transition = false
		_route.clear()
		feedback.emit("通道被挡住了，按 E 尝试离开")
		return
	if _phase == "entering":
		player.rotation.y = lerp_angle(player.rotation.y, PI, minf(1.0, delta * 7.0))
	if player.global_position.distance_to(target) < 0.018:
		_route.pop_front()

func _complete_transition() -> void:
	if _phase == "entering":
		_phase = "hidden"
		player.hide_transition = false
		_set_door(current_spot_id, true)
		feedback.emit("已躲藏：保持安静；被目击进入仍会被检查" if player.hiding_kind == "locker" else "桌底只能遮挡视线，探测声仍能找到你")
	else:
		if not _shape_clear(player.global_position, float(config.get("hide_standing_height", 1.75)), _excluded(current_spot_id)):
			_phase = "hidden"
			player.hide_transition = false
			feedback.emit("上方空间被挡住了，暂时无法站起")
			return
		current_spot_id = ""
		_phase = ""
		player.clear_hiding_pose()
		# Leave the door open: closing an outward-swinging door here would sweep
		# through the player who has just reached its exterior landing.

func _height_for(spot: Dictionary) -> float:
	return float(config.get("hide_crouch_height", 0.78) if String(spot["kind"]) == "table" else config.get("hide_standing_height", 1.75))

func _excluded(id: String) -> Array[RID]:
	var result: Array[RID] = [player.get_rid()]
	if _doors.has(id):
		result.append((_doors[id]["body"] as StaticBody3D).get_rid())
	return result

func _shape_query(at: Vector3, height: float, excluded: Array[RID]) -> PhysicsShapeQueryParameters3D:
	var shape := CapsuleShape3D.new()
	shape.radius = player.capsule.radius
	shape.height = height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, Vector3(at.x, maxf(at.y, 0.02), at.z) + Vector3.UP * (height * 0.5 + 0.015))
	query.collision_mask = 1 | 4
	query.exclude = excluded
	query.margin = 0.003
	return query

func _shape_clear(at: Vector3, height: float, excluded: Array[RID]) -> bool:
	return get_world_3d().direct_space_state.intersect_shape(_shape_query(at, height, excluded), 1).is_empty()

func _segment_clear(from: Vector3, to: Vector3, height: float, excluded: Array[RID]) -> bool:
	if not _shape_clear(to, height, excluded):
		return false
	var query: PhysicsShapeQueryParameters3D = _shape_query(from, height, excluded)
	query.motion = to - from
	var result: PackedFloat32Array = get_world_3d().direct_space_state.cast_motion(query)
	return result.size() >= 2 and result[0] >= 0.999

func _set_door(id: String, closed: bool) -> void:
	if not _doors.has(id):
		return
	var door: Dictionary = _doors[id]
	var angle: float = 0.0 if closed else -PI * 0.56
	if is_equal_approx(float(door["target"]), angle):
		return
	door["target"] = angle
	if sound != null:
		sound.play_cue("cabinet", Vector3(get_spot(id)["portal"]))

func _door_fully_open(id: String) -> bool:
	return not _doors.has(id) or absf((_doors[id]["hinge"] as Node3D).rotation.y + PI * 0.56) < 0.015

func _animate_doors(delta: float) -> void:
	for value: Variant in _doors.keys():
		var id: String = String(value)
		var door: Dictionary = _doors[id]
		var hinge: Node3D = door["hinge"]
		hinge.rotation.y = move_toward(hinge.rotation.y, float(door["target"]), PI * 0.56 * delta / float(config.get("hide_door_duration", 0.28)))
		var closed: bool = is_closed(id)
		if closed != bool(door["reported_closed"]):
			door["reported_closed"] = closed
			door_changed.emit(id, closed)

func _build_locker(spot: Dictionary, prop: Node3D) -> void:
	var size: Vector3 = Vector3(spot["size"])
	var half: Vector3 = size * 0.5
	var color := Color(0.72, 0.95, 0.87)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	prop.add_child(body)
	_box(body, Vector3(-half.x + 0.05, half.y, 0), Vector3(0.1, size.y, size.z), color)
	_box(body, Vector3(half.x - 0.05, half.y, 0), Vector3(0.1, size.y, size.z), color)
	_box(body, Vector3(0, half.y, -half.z + 0.05), Vector3(size.x, size.y, 0.1), color * 0.8)
	_box(body, Vector3(0, size.y - 0.05, 0), Vector3(size.x, 0.1, size.z), color)
	var hinge := Node3D.new()
	prop.add_child(hinge)
	hinge.position = Vector3(-half.x + 0.1, 0, half.z)
	var door_body := StaticBody3D.new()
	door_body.collision_layer = 1
	door_body.collision_mask = 0
	hinge.add_child(door_body)
	var door_width: float = size.x - 0.2
	_box(door_body, Vector3(door_width * 0.5, half.y, 0), Vector3(door_width, size.y - 0.04, 0.08), color * 0.9)
	_box(door_body, Vector3(door_width - 0.15, 1.1, 0.085), Vector3(0.055, 0.3, 0.09), Color(1.0, 0.81, 0.47), false)
	for y: float in [1.70, 1.81, 1.92]:
		_box(door_body, Vector3(door_width * 0.5, y, 0.051), Vector3(door_width * 0.58, 0.035, 0.025), Color(0.32, 0.57, 0.64), false)
	_doors[String(spot["id"])] = {"hinge": hinge, "body": door_body, "target": 0.0, "reported_closed": true}

func _build_table(spot: Dictionary, prop: Node3D) -> void:
	var size: Vector3 = Vector3(spot["size"])
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	prop.add_child(body)
	_box(body, Vector3(0, size.y - 0.08, 0), Vector3(size.x, 0.16, size.z), Color(0.93, 0.83, 0.62))
	for x: float in [-size.x * 0.5 + 0.14, size.x * 0.5 - 0.14]:
		for z: float in [-size.z * 0.5 + 0.14, size.z * 0.5 - 0.14]:
			_box(body, Vector3(x, (size.y - 0.16) * 0.5, z), Vector3(0.18, size.y - 0.16, 0.18), Color(0.55, 0.77, 0.88))
	# A warm beveled-looking edge makes the open underside readable in echoes.
	_box(body, Vector3(0, size.y - 0.035, size.z * 0.5), Vector3(size.x - 0.1, 0.045, 0.035), Color(1.0, 0.78, 0.41), false)

func _box(parent: Node3D, center: Vector3, size: Vector3, color: Color, collision: bool = true) -> void:
	var mesh := MeshInstance3D.new()
	var primitive := BoxMesh.new()
	primitive.size = size
	var arrays: Array = primitive.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	var uv2 := PackedVector2Array()
	colors.resize(vertices.size())
	uv2.resize(vertices.size())
	colors.fill(color)
	uv2.fill(Vector2(-1, -1))
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	var geometry := ArrayMesh.new()
	geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.mesh = geometry
	mesh.material_override = _material
	mesh.position = center
	parent.add_child(mesh)
	if collision:
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collider.shape = shape
		collider.position = center
		parent.add_child(collider)
