class_name LevelBuilder
extends Node3D
## All architecture is one shared material and one static merged mesh.

var material: ShaderMaterial
var data: LevelData
var _surface: SurfaceTool

func setup(level_data: LevelData) -> void:
	data = level_data
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/environment.gdshader")
	material.set_shader_parameter("grid_size", Vector2(LevelData.WIDTH, LevelData.HEIGHT))
	material.set_shader_parameter("cell_size", LevelData.CELL_SIZE)
	_surface = SurfaceTool.new()
	_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_build_floor_and_walls()
	_build_landmarks()
	_surface.set_material(material)
	var architecture: MeshInstance3D = MeshInstance3D.new()
	architecture.name = "MergedArchitecture"
	architecture.mesh = _surface.commit()
	architecture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(architecture)
	_build_collision()
	_surface = null

func update_view(player_position: Vector3, time: float, debug: bool) -> void:
	material.set_shader_parameter("player_position", player_position)
	material.set_shader_parameter("echo_time", time)
	material.set_shader_parameter("debug_lit", debug)

func _build_floor_and_walls() -> void:
	for value: Variant in data.walkable.keys():
		var cell: Vector2i = Vector2i(value)
		var x: float = float(cell.x)
		var z: float = float(cell.y)
		_quad(Vector3(x, 0, z), Vector3(x, 0, z + 1), Vector3(x + 1, 0, z + 1), Vector3(x + 1, 0, z), Vector3.UP, Color(0.62, 0.77, 0.86))
		for direction: Vector2i in LevelData.NEIGHBORS:
			var neighbor: Vector2i = cell + direction
			if data.is_open(neighbor):
				continue
			var height: float = data.height_at(neighbor)
			var tint: Color = Color(0.77, 0.89, 1.0)
			if data.solid_heights.has(neighbor):
				tint = Color(0.95, 0.86, 0.69)
			if direction == Vector2i.LEFT:
				_quad(Vector3(x, 0, z), Vector3(x, height, z), Vector3(x, height, z + 1), Vector3(x, 0, z + 1), Vector3.RIGHT, tint)
			elif direction == Vector2i.RIGHT:
				_quad(Vector3(x + 1, 0, z + 1), Vector3(x + 1, height, z + 1), Vector3(x + 1, height, z), Vector3(x + 1, 0, z), Vector3.LEFT, tint)
			elif direction == Vector2i.UP:
				_quad(Vector3(x + 1, 0, z), Vector3(x + 1, height, z), Vector3(x, height, z), Vector3(x, 0, z), Vector3.BACK, tint)
			else:
				_quad(Vector3(x, 0, z + 1), Vector3(x, height, z + 1), Vector3(x + 1, height, z + 1), Vector3(x + 1, 0, z + 1), Vector3.FORWARD, tint)
	# Tops remain physical, opaque silhouettes, including from a high viewing angle.
	for value: Variant in data.solid_heights.keys():
		var cell: Vector2i = Vector2i(value)
		var x: float = float(cell.x)
		var z: float = float(cell.y)
		var height: float = data.height_at(cell)
		_quad(Vector3(x, height, z), Vector3(x, height, z + 1), Vector3(x + 1, height, z + 1), Vector3(x + 1, height, z), Vector3.UP, Color(0.55, 0.65, 0.72), _nearest_open_cell(Vector3(x + 0.5, 0, z + 0.5)))

func _build_landmarks() -> void:
	# Three entrance ribs, a distinct destination silhouette during the escape.
	for z: float in [23.0, 24.7, 26.4]:
		_box(Vector3(4.90, 0.0, z), Vector3(0.16, 2.95, 0.18), Color(0.72, 1.0, 0.94))
		_box(Vector3(8.95, 0.0, z), Vector3(0.16, 2.95, 0.18), Color(0.72, 1.0, 0.94))
		_box(Vector3(4.9, 2.82, z), Vector3(4.21, 0.13, 0.18), Color(0.72, 1.0, 0.94))
	# Headers distinguish the four thresholds without permanent glowing signs.
	_box(Vector3(11.8, 2.6, 14.0), Vector3(0.20, 0.34, 4.0), Color(0.9, 0.98, 1.0))
	_box(Vector3(25.0, 2.6, 10.8), Vector3(4.0, 0.34, 0.20), Color(1.0, 0.9, 0.65))
	_box(Vector3(21.8, 2.6, 4.0), Vector3(0.20, 0.34, 4.0), Color(0.85, 0.96, 1.0))
	# A suspended cross above the central block creates a landmark with open
	# space below and on all four sides; it does not change walkable topology.
	_box(Vector3(19.0, 2.85, 18.36), Vector3(5.0, 0.12, 0.28), Color(0.85, 1.0, 1.0))
	_box(Vector3(21.36, 2.85, 16.0), Vector3(0.28, 0.12, 5.0), Color(0.85, 1.0, 1.0))
	# Shelf end-face strips sit just outside their solid cells, making the
	# archive, gallery, and machinery shapes readable during a scan.
	for y: float in [0.45, 1.15, 1.85]:
		_box(Vector3(12.96, y, 4.0), Vector3(0.035, 0.07, 2.0), Color(0.9, 0.96, 1.0))
		_box(Vector3(15.99, y, 4.0), Vector3(0.035, 0.07, 2.0), Color(0.9, 0.96, 1.0))
		_box(Vector3(3.96, y, 14.0), Vector3(0.035, 0.07, 3.0), Color(0.9, 0.96, 1.0))
		_box(Vector3(5.99, y, 14.0), Vector3(0.035, 0.07, 3.0), Color(0.9, 0.96, 1.0))
	for x: float in [28.3, 29.3, 30.3]:
		_box(Vector3(x, 0.2, 5.99), Vector3(0.16, 2.0, 0.035), Color(1.0, 0.82, 0.56))
	# Six flat faces and a tapered cap distinguish the central resonance unit
	# from a plain crate. Everything is above an already-solid footprint.
	_hex_unit(Vector3(21.5, 1.9, 18.5), 0.70, 0.64, Color(0.64, 0.93, 1.0))
	_hex_unit(Vector3(29.5, 2.45, 5.0), 0.43, 0.36, Color(1.0, 0.83, 0.58))

func _hex_unit(center: Vector3, radius: float, height: float, color: Color) -> void:
	for index: int in range(6):
		var angle_a: float = TAU * float(index) / 6.0
		var angle_b: float = TAU * float(index + 1) / 6.0
		var offset_a: Vector3 = Vector3(cos(angle_a), 0, sin(angle_a)) * radius
		var offset_b: Vector3 = Vector3(cos(angle_b), 0, sin(angle_b)) * radius
		var a: Vector3 = center + offset_a
		var b: Vector3 = center + offset_b
		var c: Vector3 = center + offset_b * 0.60 + Vector3.UP * height
		var d: Vector3 = center + offset_a * 0.60 + Vector3.UP * height
		var normal: Vector3 = ((offset_a + offset_b).normalized() + Vector3.UP * 0.4).normalized()
		var sample_cell: Vector2i = _nearest_open_cell(center + (offset_a + offset_b))
		_quad(a, b, c, d, normal, color, sample_cell)
		_quad(d, c, center + Vector3.UP * height, center + Vector3.UP * height, Vector3.UP, color * 0.85, sample_cell)

func _nearest_open_cell(position: Vector3) -> Vector2i:
	var origin: Vector2i = data.world_to_cell(position)
	var nearest: Vector2i = origin
	var closest: float = INF
	for dz: int in range(-4, 5):
		for dx: int in range(-4, 5):
			var cell: Vector2i = origin + Vector2i(dx, dz)
			if data.is_open(cell):
				var distance: float = Vector2(position.x, position.z).distance_squared_to(Vector2(data.cell_to_world(cell).x, data.cell_to_world(cell).z))
				if distance < closest:
					closest = distance
					nearest = cell
	return nearest

func _build_collision() -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "ArchitectureCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	_add_collision_box(body, Vector3(0.0, -0.25, 0.0), Vector3(LevelData.WIDTH, 0.25, LevelData.HEIGHT))
	# Horizontal runs combine adjacent solid cells of equal height. This is
	# more economical than hundreds of individual StaticBody nodes.
	for z: int in range(LevelData.HEIGHT):
		var x: int = 0
		while x < LevelData.WIDTH:
			var cell: Vector2i = Vector2i(x, z)
			if data.is_open(cell):
				x += 1
				continue
			var start: int = x
			var height: float = data.height_at(cell)
			x += 1
			while x < LevelData.WIDTH and not data.is_open(Vector2i(x, z)) and is_equal_approx(data.height_at(Vector2i(x, z)), height):
				x += 1
			_add_collision_box(body, Vector3(start, 0, z), Vector3(x - start, height, 1.0))

func _add_collision_box(body: StaticBody3D, minimum: Vector3, size: Vector3) -> void:
	var collision: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	collision.shape = box
	collision.position = minimum + size * 0.5
	body.add_child(collision)

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color, acoustic_cell: Vector2i = Vector2i(-1, -1)) -> void:
	for point: Vector3 in [a, b, c, a, c, d]:
		_surface.set_normal(normal)
		_surface.set_color(color)
		_surface.set_uv2(Vector2(acoustic_cell))
		_surface.add_vertex(point)

func _box(minimum: Vector3, size: Vector3, color: Color) -> void:
	var p: Vector3 = minimum
	var q: Vector3 = minimum + size
	_quad(Vector3(p.x,p.y,p.z), Vector3(p.x,q.y,p.z), Vector3(p.x,q.y,q.z), Vector3(p.x,p.y,q.z), Vector3.LEFT, color)
	_quad(Vector3(q.x,p.y,q.z), Vector3(q.x,q.y,q.z), Vector3(q.x,q.y,p.z), Vector3(q.x,p.y,p.z), Vector3.RIGHT, color)
	_quad(Vector3(q.x,p.y,p.z), Vector3(q.x,q.y,p.z), Vector3(p.x,q.y,p.z), Vector3(p.x,p.y,p.z), Vector3.FORWARD, color)
	_quad(Vector3(p.x,p.y,q.z), Vector3(p.x,q.y,q.z), Vector3(q.x,q.y,q.z), Vector3(q.x,p.y,q.z), Vector3.BACK, color)
	_quad(Vector3(p.x,q.y,p.z), Vector3(q.x,q.y,p.z), Vector3(q.x,q.y,q.z), Vector3(p.x,q.y,q.z), Vector3.UP, color)
	_quad(Vector3(p.x,p.y,q.z), Vector3(q.x,p.y,q.z), Vector3(q.x,p.y,p.z), Vector3(p.x,p.y,p.z), Vector3.DOWN, color)
