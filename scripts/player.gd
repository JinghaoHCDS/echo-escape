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

func setup(settings: Dictionary) -> void:
	config = settings
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.2
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
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
