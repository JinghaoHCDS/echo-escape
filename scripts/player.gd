class_name EchoPlayer
extends CharacterBody3D

signal footstep(kind: String, position: Vector3)
signal clap_requested
signal interact_requested

var config: Dictionary
var camera: Camera3D
var enabled: bool = true
var distance_since_step: float = 0.0
var footsteps_emitted: int = 0
var collider: CollisionShape3D
var capsule: CapsuleShape3D
var hiding_spot_id: String = ""
var hiding_kind: String = ""
var hide_transition: bool = false
var motion_locked: bool = false

func setup(settings: Dictionary) -> void:
	config = settings
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.2
	collider = CollisionShape3D.new()
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.75
	collider.shape = capsule
	collider.position.y = 0.89
	add_child(collider)
	camera = Camera3D.new()
	camera.position.y = 1.6
	camera.fov = float(config["fov"])
	camera.near = 0.04
	camera.far = 65.0
	camera.current = true
	add_child(camera)

func _unhandled_input(event: InputEvent) -> void:
	if not enabled or get_tree().paused:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * float(config["mouse_sensitivity"]))
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * float(config["mouse_sensitivity"]), -1.45, 1.45)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_action_pressed("clap"):
		clap_requested.emit()
	if event.is_action_pressed("interact"):
		interact_requested.emit()

func _physics_process(delta: float) -> void:
	if not enabled:
		return
	if motion_locked:
		velocity = Vector3.ZERO
		return
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var running: bool = Input.is_action_pressed("run")
	var speed: float = float(config["run_speed"] if running else config["walk_speed"])
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not is_on_floor():
		velocity.y -= float(config["gravity"]) * delta
	else:
		velocity.y = 0.0
	var before: Vector3 = global_position
	move_and_slide()
	var displacement := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	# Actual displacement, never requested velocity: pushing a wall makes no steps.
	if is_on_floor() and displacement > 0.002:
		distance_since_step += displacement
		var step_length := float(config["run_step_distance"] if running else config["walk_step_distance"])
		if distance_since_step >= step_length:
			distance_since_step = fmod(distance_since_step, step_length)
			footsteps_emitted += 1
			footstep.emit("run" if running else "walk", global_position)

func set_hiding_pose(spot_id: String, kind: String) -> void:
	hiding_spot_id = spot_id
	hiding_kind = kind
	motion_locked = true
	velocity = Vector3.ZERO
	distance_since_step = 0.0
	_set_crouched(kind == "table")

func clear_hiding_pose() -> void:
	hiding_spot_id = ""
	hiding_kind = ""
	hide_transition = false
	motion_locked = false
	_set_crouched(false)

func _set_crouched(crouched: bool) -> void:
	capsule.height = float(config.get("hide_crouch_height", 0.78) if crouched else config.get("hide_standing_height", 1.75))
	collider.position.y = capsule.height * 0.5 + 0.015
	camera.position.y = float(config.get("hide_crouch_eye_height", 0.65) if crouched else config.get("hide_standing_eye_height", 1.6))

func sight_target() -> Vector3:
	return camera.global_position

func attack_target() -> Vector3:
	return global_position + Vector3.UP * (capsule.height * 0.5)

func acoustic_position() -> Vector3:
	return camera.global_position - Vector3.UP * 0.12
