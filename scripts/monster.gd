class_name EchoMonster
extends CharacterBody3D
## One evidence-driven pursuer. All navigation targets are evidence snapshots,
## except the explicit post-pickup beacon phase.

signal player_hit(reason: String)
signal state_changed(new_state: String)

const PATROL: String = "PATROL"
const INVESTIGATE: String = "INVESTIGATE"
const CHASE: String = "CHASE"
const SEARCH: String = "SEARCH"
const ATTACK_WINDUP: String = "ATTACK_WINDUP"
const ATTACK_STRIKE: String = "ATTACK_STRIKE"
const ATTACK_RECOVERY: String = "ATTACK_RECOVERY"

var state: String = PATROL
var last_known_position: Vector3 = Vector3.ZERO
var last_evidence_time: float = -1000.0
var evidence_reason: String = "尚未获得玩家位置证据"
var attack_reason: String = "尚未攻击"
var alarm_active: bool = false

var _data: LevelData
var _player: CharacterBody3D
var _sound: SoundSystem
var _config: Dictionary = {}
var _ready_to_run: bool = false
var _debug: bool = false
var _visual_contact: bool = false
var _confirmed: bool = false
var _state_time: float = 0.0
var _probe_timer: float = 0.0
var _probe_flash: float = 0.0
var _reveal_remaining: float = 0.0
var _patrol_index: int = 0
var _search_index: int = 0
var _path: Array[Vector3] = []
var _path_index: int = 0
var _path_goal: Vector3 = Vector3.INF
var _repath_timer: float = 0.0
var _attack_direction: Vector3 = Vector3.FORWARD
var _attack_locked: bool = false
var _body_material: StandardMaterial3D
var _edge_material: StandardMaterial3D
var _face_material: StandardMaterial3D
var _visual_root: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _head: MeshInstance3D


func setup(data: LevelData, player: CharacterBody3D, sound: SoundSystem, config: Dictionary) -> void:
	_data = data
	_player = player
	_sound = sound
	_config = config
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 0.25
	global_position = data.monster_spawn
	last_known_position = global_position
	_build_body()
	if not _sound.is_connected("sound_arrived", on_sound_arrived):
		_sound.connect("sound_arrived", on_sound_arrived)
	_ready_to_run = true
	_update_visuals(0.0)


func on_sound_arrived(event: Dictionary, listener_id: String) -> void:
	if not _ready_to_run:
		return
	var source: String = str(event.get("source", ""))
	var kind: String = str(event.get("kind", event.get("type", "")))
	if listener_id == "monster":
		reveal(_number("monster_reveal_duration", 0.7))
		# The monster hears only player-originated evidence, never its own ping.
		if source == "player":
			var origin: Vector3 = event.get("position", Vector3.ZERO)
			_register_evidence(origin, "听觉：%s 声到达；目标为发声瞬间的位置" % kind, false)
	elif listener_id == "player" and source == "monster" and kind == "probe":
		# This callback is delivered only after the reachable wave hits the
		# player's collision footprint. Reading the hit position is now valid.
		_register_evidence(_player.global_position, "探测：声波沿通路实际命中玩家", true)


func set_alarm(active: bool) -> void:
	alarm_active = active
	if active and _ready_to_run:
		_register_evidence(_player.global_position, "信标：警报阶段持续位置证据", true)


func set_debug(active: bool) -> void:
	_debug = active
	if _ready_to_run:
		_update_visuals(0.0)


func reveal(duration: float = 0.7) -> void:
	_reveal_remaining = maxf(_reveal_remaining, duration)


func _physics_process(delta: float) -> void:
	if not _ready_to_run or not is_instance_valid(_player):
		return
	if not is_inside_tree() or not PhysicsServer3D.body_get_space(get_rid()).is_valid():
		return
	_state_time += delta
	_repath_timer -= delta
	_reveal_remaining = maxf(0.0, _reveal_remaining - delta)
	_probe_flash = maxf(0.0, _probe_flash - delta)
	_probe_timer += delta
	if _probe_timer >= _number("probe_interval", 3.0):
		_probe_timer = 0.0
		_probe_flash = 0.48
		_sound.emit_sound("probe", "monster", global_position)

	# Player coordinates below are used only for legitimate sight tests. A
	# failed test never updates last_known_position or the navigation target.
	_visual_contact = _player_is_visible()
	if alarm_active:
		_register_evidence(_player.global_position, "信标：警报阶段持续位置证据", true)
	elif _visual_contact:
		_register_evidence(_player.global_position, "视觉：距离、视角与无遮挡射线均通过", true)

	velocity.x = 0.0
	velocity.z = 0.0
	match state:
		PATROL:
			_update_patrol(delta)
		INVESTIGATE:
			_move_toward_target(last_known_position, _number("investigate_speed", 2.4), delta)
			if _flat_distance(global_position, last_known_position) < 0.55:
				_enter_state(SEARCH)
		CHASE:
			if not alarm_active and _now() - last_evidence_time >= _number("evidence_timeout", 5.0):
				evidence_reason = "丢失：连续 %.1f 秒没有新证据；搜索最后已知位置" % _number("evidence_timeout", 5.0)
				_enter_state(SEARCH)
			elif _can_start_attack():
				_begin_attack()
			else:
				_move_toward_target(last_known_position, _number("monster_speed", 3.6), delta)
		SEARCH:
			_update_search(delta)
		ATTACK_WINDUP:
			_update_windup(delta)
		ATTACK_STRIKE:
			if _state_time >= _number("attack_strike_duration", 0.12):
				_enter_state(ATTACK_RECOVERY)
		ATTACK_RECOVERY:
			if _state_time >= _number("attack_recovery", 1.0):
				if alarm_active or (_confirmed and _now() - last_evidence_time < _number("evidence_timeout", 5.0)):
					_enter_state(CHASE)
				else:
					_enter_state(SEARCH)

	# player_hit is synchronous. Its receiver can finish the game and disable
	# Session during the attack above, immediately removing this collision body
	# from its physics space. Do not continue this already-running callback.
	if not is_inside_tree() or not PhysicsServer3D.body_get_space(get_rid()).is_valid():
		return
	if not is_on_floor():
		velocity.y -= _number("gravity", 20.0) * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	_update_visuals(delta)


func _register_evidence(at: Vector3, reason: String, confirms: bool) -> void:
	last_known_position = at
	last_evidence_time = _now()
	evidence_reason = reason
	if confirms:
		_confirmed = true
	if _is_attacking():
		return
	if confirms or state == CHASE:
		_enter_state(CHASE)
	else:
		_confirmed = false
		_enter_state(INVESTIGATE)


func _enter_state(next_state: String) -> void:
	if state == next_state:
		return
	state = next_state
	_state_time = 0.0
	_path.clear()
	_path_index = 0
	_repath_timer = 0.0
	_path_goal = Vector3.INF
	if next_state == SEARCH:
		_search_index = 0
	elif next_state == PATROL:
		_confirmed = false
	state_changed.emit(state)


func _update_patrol(delta: float) -> void:
	if _data.patrol_points.is_empty():
		return
	var goal: Vector3 = _data.patrol_points[_patrol_index % _data.patrol_points.size()]
	if _flat_distance(global_position, goal) < 0.6:
		_patrol_index = (_patrol_index + 1) % _data.patrol_points.size()
		goal = _data.patrol_points[_patrol_index]
	_move_toward_target(goal, _number("patrol_speed", 1.6), delta)


func _update_search(delta: float) -> void:
	if _state_time >= _number("search_duration", 5.0):
		evidence_reason = "搜索结束：回到巡逻；未读取隐藏玩家的位置"
		_enter_state(PATROL)
		return
	var offsets: Array[Vector3] = [Vector3.ZERO, Vector3(2.0, 0.0, 0.0), Vector3(0.0, 0.0, 2.0), Vector3(-2.0, 0.0, 0.0), Vector3(0.0, 0.0, -2.0)]
	var goal: Vector3 = last_known_position + offsets[_search_index % offsets.size()]
	if _flat_distance(global_position, goal) < 0.65 or (_state_time > float(_search_index + 1)):
		_search_index += 1
		goal = last_known_position + offsets[_search_index % offsets.size()]
	_move_toward_target(goal, _number("patrol_speed", 1.6), delta)


func _move_toward_target(target: Vector3, speed: float, delta: float) -> void:
	if _flat_distance(global_position, target) < 0.18:
		return
	var route_needs_update: bool = _path.is_empty() or _path_index >= _path.size() or _flat_distance(_path_goal, target) > 0.7
	if _repath_timer <= 0.0 and route_needs_update:
		_path = _data.find_path(global_position, target)
		_path_index = 0
		_path_goal = target
		_repath_timer = _number("monster_repath_interval", 0.45)
		# A replan includes the current cell center for safe corners. If already
		# travelling along the same cardinal edge, that center is behind us and
		# can be skipped without cutting a corner or repeatedly walking backward.
		if _path.size() >= 2:
			var axis: Vector3 = (_path[1] - _path[0]).normalized()
			var offset: Vector3 = global_position - _path[0]
			offset.y = 0.0
			var progress: float = offset.dot(axis)
			var perpendicular: Vector3 = offset - axis * progress
			if progress > 0.0 and perpendicular.length() <= 0.09:
				_path_index = 1
	while _path_index < _path.size() and _flat_distance(global_position, _path[_path_index]) < 0.09:
		_path_index += 1
	if _path_index >= _path.size():
		return
	var direction: Vector3 = _path[_path_index] - global_position
	direction.y = 0.0
	var distance: float = direction.length()
	if distance < 0.001:
		return
	direction /= distance
	var frame_speed: float = minf(speed, distance / maxf(delta, 0.001))
	velocity.x = direction.x * frame_speed
	velocity.z = direction.z * frame_speed
	_turn_toward(direction, delta, 8.0)


func _player_is_visible() -> bool:
	var difference: Vector3 = _player.global_position - global_position
	difference.y = 0.0
	var distance: float = difference.length()
	if distance > _number("sight_range", 8.0):
		return false
	if distance > 0.001:
		var forward: Vector3 = -global_transform.basis.z
		forward.y = 0.0
		var cosine: float = forward.normalized().dot(difference / distance)
		if cosine < cos(deg_to_rad(_number("sight_fov_degrees", 80.0) * 0.5)):
			return false
	return _clear_wall_ray(global_position + Vector3.UP * 1.45, _player.global_position + Vector3.UP * 1.0)


func _can_start_attack() -> bool:
	# Even during the beacon phase there must be physical proximity, a forward
	# target and an unobstructed ray. Contact itself is never a loss condition.
	var difference: Vector3 = _player.global_position - global_position
	difference.y = 0.0
	var distance: float = difference.length()
	if distance > _number("attack_start_range", _number("attack_range", 1.65) + 0.12):
		return false
	if not _visual_contact and not alarm_active:
		return false
	if distance > 0.001 and (-global_transform.basis.z).dot(difference / distance) < cos(deg_to_rad(_number("sight_fov_degrees", 80.0) * 0.5)):
		return false
	return _clear_wall_ray(global_position + Vector3.UP, _player.global_position + Vector3.UP)


func _begin_attack() -> void:
	_enter_state(ATTACK_WINDUP)
	_attack_locked = false
	_attack_direction = -global_transform.basis.z
	_attack_direction.y = 0.0
	_attack_direction = _attack_direction.normalized()
	attack_reason = "前摇：抬臂蓄力；末段锁定方向，可侧移或后退躲避"
	_sound.play_cue("windup", global_position)
	reveal(_number("attack_windup", 0.65) + 0.15)


func _update_windup(delta: float) -> void:
	var duration: float = _number("attack_windup", 0.65)
	var lock_before: float = _number("attack_lock_before", 0.2)
	if not _attack_locked:
		if _state_time < duration - lock_before:
			var direction: Vector3 = last_known_position - global_position
			direction.y = 0.0
			if direction.length_squared() > 0.001:
				_turn_toward(direction.normalized(), delta, 5.0)
		else:
			_attack_locked = true
			_attack_direction = -global_transform.basis.z
			_attack_direction.y = 0.0
			_attack_direction = _attack_direction.normalized()
			attack_reason = "方向已锁定：不会继续转向追着玩家命中"
	if _state_time >= duration:
		_enter_state(ATTACK_STRIKE)
		_resolve_attack()


func _resolve_attack() -> void:
	var difference: Vector3 = _player.global_position - global_position
	difference.y = 0.0
	var distance: float = difference.length()
	var cosine: float = 1.0 if distance < 0.001 else _attack_direction.dot(difference / distance)
	var angle: float = rad_to_deg(acos(clampf(cosine, -1.0, 1.0)))
	if distance > _number("attack_range", 1.65):
		attack_reason = "攻击落空：距离 %.2f m 超出 %.2f m" % [distance, _number("attack_range", 1.65)]
		return
	if angle > _number("attack_half_angle_degrees", 36.0):
		attack_reason = "攻击落空：玩家偏离锁定方向 %.1f°" % angle
		return
	if not _clear_wall_ray(global_position + Vector3.UP, _player.global_position + Vector3.UP):
		attack_reason = "攻击落空：实体墙阻挡命中射线"
		return
	attack_reason = "攻击命中：距离 %.2f m，偏角 %.1f°，无遮挡；方向在前摇末段已锁定" % [distance, angle]
	player_hit.emit(attack_reason)


func _clear_wall_ray(from: Vector3, to: Vector3) -> bool:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [get_rid(), _player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _turn_toward(direction: Vector3, delta: float, rate: float) -> void:
	var wanted_yaw: float = atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, wanted_yaw, minf(1.0, delta * rate))


func _is_attacking() -> bool:
	return state == ATTACK_WINDUP or state == ATTACK_STRIKE or state == ATTACK_RECOVERY


func _now() -> float:
	return _sound.clock if is_instance_valid(_sound) else 0.0


func _number(key: String, fallback: float) -> float:
	return float(_config.get(key, fallback))


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _build_body() -> void:
	var collider: CollisionShape3D = CollisionShape3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.8
	collider.shape = capsule
	collider.position.y = 0.9
	add_child(collider)
	_visual_root = Node3D.new()
	add_child(_visual_root)
	_body_material = _make_material()
	_edge_material = _make_material()
	_face_material = _make_material()
	var torso: CylinderMesh = CylinderMesh.new()
	torso.top_radius = 0.32
	torso.bottom_radius = 0.22
	torso.height = 0.85
	torso.radial_segments = 8
	_mesh(torso, Vector3(0.0, 1.02, 0.0), _body_material, _visual_root)
	for side: float in [-1.0, 1.0]:
		var leg: BoxMesh = BoxMesh.new()
		leg.size = Vector3(0.18, 0.65, 0.22)
		_mesh(leg, Vector3(side * 0.16, 0.34, 0.0), _body_material, _visual_root)
		var foot: BoxMesh = BoxMesh.new()
		foot.size = Vector3(0.2, 0.12, 0.37)
		_mesh(foot, Vector3(side * 0.16, 0.08, -0.07), _edge_material, _visual_root)
		var arm_pivot: Node3D = Node3D.new()
		arm_pivot.position = Vector3(side * 0.37, 1.35, 0.0)
		_visual_root.add_child(arm_pivot)
		var arm: BoxMesh = BoxMesh.new()
		arm.size = Vector3(0.16, 0.7, 0.17)
		_mesh(arm, Vector3(0.0, -0.27, 0.0), _body_material, arm_pivot)
		var hand: BoxMesh = BoxMesh.new()
		hand.size = Vector3(0.19, 0.23, 0.23)
		_mesh(hand, Vector3(0.0, -0.6, -0.03), _edge_material, arm_pivot)
		if side < 0.0:
			_left_arm = arm_pivot
		else:
			_right_arm = arm_pivot
	var skull: BoxMesh = BoxMesh.new()
	skull.size = Vector3(0.3, 0.32, 0.27)
	_head = _mesh(skull, Vector3(0.0, 1.61, -0.015), _body_material, _visual_root)
	var face_slit: BoxMesh = BoxMesh.new()
	face_slit.size = Vector3(0.23, 0.038, 0.018)
	_mesh(face_slit, Vector3(0.0, 1.64, -0.163), _face_material, _visual_root)
	for index: int in range(3):
		var rib: BoxMesh = BoxMesh.new()
		rib.size = Vector3(0.5 - float(index) * 0.055, 0.035, 0.03)
		_mesh(rib, Vector3(0.0, 1.22 - float(index) * 0.13, -0.31), _edge_material, _visual_root)
	var crest: BoxMesh = BoxMesh.new()
	crest.size = Vector3(0.065, 0.28, 0.08)
	var crest_mesh: MeshInstance3D = _mesh(crest, Vector3(0.0, 1.87, 0.01), _edge_material, _visual_root)
	crest_mesh.rotation.x = -0.35


func _make_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.001, 0.002, 0.003)
	material.emission_enabled = true
	material.emission = Color.BLACK
	material.roughness = 1.0
	# Opaque geometry always writes depth, including while visually black.
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	return material


func _mesh(mesh: Mesh, at: Vector3, material: Material, parent: Node3D) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance


func _update_visuals(_delta: float) -> void:
	var illumination: float = 1.0 if _debug else clampf(_reveal_remaining / 0.22, 0.0, 1.0)
	var danger: bool = state == CHASE or _is_attacking() or alarm_active
	var edge_color: Color = Color(1.0, 0.18, 0.065) if danger else Color(0.45, 0.74, 0.81)
	_body_material.albedo_color = Color(0.002, 0.003, 0.005).lerp(Color(0.13, 0.19, 0.22), illumination)
	_body_material.emission = Color(0.04, 0.085, 0.105) * illumination
	# Unshaded materials must carry readable color in albedo too; depending on
	# the rendering path, emission alone does not brighten their silhouette.
	_edge_material.albedo_color = Color(0.002, 0.003, 0.005).lerp(edge_color * 0.7, illumination)
	_edge_material.emission = edge_color * illumination * 0.9
	_face_material.albedo_color = Color(0.002, 0.003, 0.005).lerp(edge_color * 0.9, illumination)
	_face_material.emission = edge_color * illumination * 1.5
	var arm_angle: float = 0.0
	var body_tilt: float = 0.0
	if state == ATTACK_WINDUP:
		var progress: float = clampf(_state_time / _number("attack_windup", 0.65), 0.0, 1.0)
		arm_angle = 2.15 * progress
		body_tilt = 0.10 * progress
	elif state == ATTACK_STRIKE:
		arm_angle = 1.25
		body_tilt = -0.22
	elif state == ATTACK_RECOVERY:
		var remaining: float = 1.0 - clampf(_state_time / _number("attack_recovery", 1.0), 0.0, 1.0)
		arm_angle = 1.25 * remaining
		body_tilt = -0.22 * remaining
	else:
		# A small arm gait affects the monster only; the player's camera stays still.
		var moving: bool = Vector2(velocity.x, velocity.z).length() > 0.1
		arm_angle = sin(_now() * 5.0) * 0.18 if moving else 0.0
	_left_arm.rotation.x = arm_angle
	_right_arm.rotation.x = arm_angle if _is_attacking() else -arm_angle
	_visual_root.rotation.x = body_tilt
	var pulse: float = sin((0.48 - _probe_flash) * 25.0) * 0.06 if _probe_flash > 0.0 else 0.0
	_head.scale = Vector3.ONE * (1.0 + pulse)
