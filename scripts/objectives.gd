class_name EchoObjectives
extends Node3D

signal activated
signal picked_up
signal escaped

var data: LevelData
var player: EchoPlayer
var sound: SoundSystem
var config: Dictionary
var item: Node3D
var item_material: StandardMaterial3D
var is_activated: bool = false
var has_item: bool = false
var enabled: bool = true
var debug_lit: bool = false

func setup(level: LevelData, actor: EchoPlayer, audio: SoundSystem, settings: Dictionary) -> void:
	data = level
	player = actor
	sound = audio
	config = settings
	item = Node3D.new()
	item.name = "SignalCore"
	add_child(item)
	item.position = data.item_position + Vector3.UP * 1.05
	item_material = StandardMaterial3D.new()
	item_material.albedo_color = Color(0.012, 0.009, 0.005)
	item_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := MeshInstance3D.new()
	var core := CylinderMesh.new()
	core.top_radius = 0.16
	core.bottom_radius = 0.27
	core.height = 0.62
	core.radial_segments = 6
	core.rings = 1
	mesh.mesh = core
	mesh.material_override = item_material
	item.add_child(mesh)
	for i in range(3):
		var ring := MeshInstance3D.new()
		var shape := TorusMesh.new()
		shape.inner_radius = 0.29
		shape.outer_radius = 0.33
		shape.rings = 6
		shape.ring_segments = 4
		ring.mesh = shape
		ring.position.y = -0.25 + float(i) * 0.25
		ring.material_override = item_material
		item.add_child(ring)
	sound.register_listener("item", item)
	sound.sound_arrived.connect(_on_sound_arrived)
	# A restrained physical exit marking, opaque and occluded by walls.
	var exit_mesh := MeshInstance3D.new()
	var exit_box := BoxMesh.new()
	exit_box.size = Vector3(2.2, 0.025, 1.5)
	exit_mesh.mesh = exit_box
	exit_mesh.position = data.exit_position + Vector3.UP * 0.018
	var exit_material := StandardMaterial3D.new()
	exit_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	exit_material.albedo_color = Color(0.065, 0.14, 0.15)
	exit_mesh.material_override = exit_material
	add_child(exit_mesh)

func _on_sound_arrived(event: Dictionary, listener_id: String) -> void:
	if listener_id == "item" and event.get("kind", "") == "clap" and event.get("source", "") == "player" and not is_activated:
		is_activated = true
		activated.emit()

func _physics_process(_delta: float) -> void:
	if not enabled:
		return
	item.visible = not has_item
	item_material.albedo_color = Color(0.86, 0.47, 0.15) if is_activated or debug_lit else Color(0.008, 0.007, 0.005)
	if has_item and horizontal_distance(player.global_position, data.exit_position) < float(config["exit_radius"]):
		escaped.emit()

func can_pick_up() -> bool:
	if not enabled or not is_activated or has_item:
		return false
	if player.camera.global_position.distance_to(item.global_position) > float(config["pickup_distance"]):
		return false
	var query := PhysicsRayQueryParameters3D.create(player.camera.global_position, item.global_position, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func interact() -> bool:
	if not can_pick_up():
		return false
	has_item = true
	item.visible = false
	sound.unregister_listener("item")
	picked_up.emit()
	return true

func interaction_candidate() -> Dictionary:
	if not can_pick_up():
		return {}
	var direction: Vector3 = item.global_position - player.camera.global_position
	if direction.length() > 0.001 and (-player.camera.global_transform.basis.z).dot(direction.normalized()) < float(config.get("hide_view_dot", 0.58)):
		return {}
	return {"distance": direction.length()}

func prompt() -> String:
	if can_pick_up():
		return "[ E ]  取出信标核心"
	if not has_item and horizontal_distance(player.global_position, data.exit_position) < 2.3:
		return "入口 · 尚未取得信标核心"
	if not is_activated and player.global_position.distance_to(data.item_position) < 2.5:
		return "静默的装置 · 用鼓掌回声激活"
	return ""

static func horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
