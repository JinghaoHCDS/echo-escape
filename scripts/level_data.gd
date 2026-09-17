class_name LevelData
extends RefCounted
## The same 1 m occupancy grid drives architecture, navigation and acoustics.
## Coordinates refer to the ground plane; player / monster roots are feet.

const WIDTH: int = 36
const HEIGHT: int = 30
const CELL_SIZE: float = 1.0
const WALL_HEIGHT: float = 3.2
const NEIGHBORS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var walkable: Dictionary = {}
var solid_heights: Dictionary = {}
var room_names: Dictionary = {}
# Furniture is hollow physical geometry, independent of architectural occupancy.
# Navigation excludes footprints; sound uses locker bounds plus their door portal.
var hiding_spots: Array[Dictionary] = []
var navigation_blocked: Dictionary = {}
var spawn_position: Vector3 = Vector3(6.5, 0.0, 25.5)
var monster_spawn: Vector3 = Vector3(24.5, 0.0, 18.5)
var item_position: Vector3 = Vector3(32.5, 0.0, 3.5)
var exit_position: Vector3 = Vector3(6.5, 0.0, 26.0)
var patrol_points: Array[Vector3] = [
	Vector3(25.5, 0.0, 16.5), Vector3(26.5, 0.0, 7.5),
	Vector3(17.5, 0.0, 6.5), Vector3(8.5, 0.0, 12.5),
	Vector3(17.5, 0.0, 18.5),
]

func _init() -> void:
	# Five rooms. Inclusive coordinates make all physical widths explicit.
	_carve(2, 22, 10, 27, "入口气闸")
	_carve(2, 11, 11, 19, "声廊")
	_carve(15, 13, 27, 24, "中枢大厅")
	_carve(24, 2, 33, 9, "信标机房")
	_carve(10, 2, 19, 8, "档案室")
	# Gallery -> atrium -> machine -> archive -> gallery forms one loop.
	_carve(5, 19, 8, 22, "入口连廊", false)
	_carve(11, 14, 15, 17, "大厅门廊", false)
	_carve(25, 9, 28, 13, "机房连廊", false)
	_carve(19, 4, 24, 7, "档案连廊", false)
	_carve(7, 7, 10, 12, "折角连廊", false)
	# Obstacles are removed from the grid, not merely placed over it.
	_block(4, 14, 5, 16, 2.45)
	_block(20, 17, 22, 19, 1.9)
	_block(25, 21, 26, 22, 1.2)
	_block(13, 4, 15, 5, 2.45)
	_block(28, 4, 30, 5, 2.45)
	_add_hiding_spot("gallery_locker", "locker", Vector3(2.75, 0.0, 18.1), Vector3(1.45, 2.3, 1.3))
	_add_hiding_spot("archive_locker", "locker", Vector3(18.2, 0.0, 2.7), Vector3(1.45, 2.3, 1.3))
	_add_hiding_spot("atrium_table", "table", Vector3(17.5, 0.0, 21.5), Vector3(2.4, 1.25, 1.6))

func _add_hiding_spot(id: String, kind: String, center: Vector3, size: Vector3) -> void:
	var front: float = center.z + size.z * 0.5
	var entry: Vector3 = Vector3(center.x, 0.02, front + 0.68)
	var bounds := AABB(Vector3(center.x - size.x * 0.5, 0.0, center.z - size.z * 0.5), size)
	var exits: Array[Vector3] = [entry, entry + Vector3(0.48, 0.0, 0.35), entry + Vector3(-0.48, 0.0, 0.35)]
	hiding_spots.append({
		"id": id, "kind": kind, "position": center, "size": size,
		"inside": center + Vector3.UP * 0.02, "entry": entry,
		"approach": Vector3(center.x + (0.85 if kind == "locker" else 1.25), 0.0, front + (0.60 if kind == "locker" else 0.75)), "exits": exits,
		"bounds": bounds, "portal": Vector3(center.x, 1.0, front + 0.035),
	})
	for z: int in range(floori(bounds.position.z), ceili(bounds.end.z)):
		for x: int in range(floori(bounds.position.x), ceili(bounds.end.x)):
			navigation_blocked[Vector2i(x, z)] = true

func is_navigation_open(cell: Vector2i) -> bool:
	return is_open(cell) and not navigation_blocked.has(cell)

func navigation_target(position: Vector3) -> Vector3:
	# A sound snapshot inside hollow furniture remains evidence of that exact
	# point, but a standing actor approaches the furniture's reachable entrance.
	var cell: Vector2i = world_to_cell(position)
	if not navigation_blocked.has(cell):
		return position
	for spot: Dictionary in hiding_spots:
		var bounds: AABB = spot["bounds"]
		if cell.x >= floori(bounds.position.x) and cell.x < ceili(bounds.end.x) and cell.y >= floori(bounds.position.z) and cell.y < ceili(bounds.end.z):
			return Vector3(spot["approach"])
	return position

func _carve(x0: int, z0: int, x1: int, z1: int, title: String, overwrite_name: bool = true) -> void:
	for z: int in range(z0, z1 + 1):
		for x: int in range(x0, x1 + 1):
			var cell: Vector2i = Vector2i(x, z)
			walkable[cell] = true
			if overwrite_name or not room_names.has(cell):
				room_names[cell] = title

func _block(x0: int, z0: int, x1: int, z1: int, height: float) -> void:
	for z: int in range(z0, z1 + 1):
		for x: int in range(x0, x1 + 1):
			var cell: Vector2i = Vector2i(x, z)
			walkable.erase(cell)
			solid_heights[cell] = height

func world_to_cell(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / CELL_SIZE), floori(position.z / CELL_SIZE))

func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3((float(cell.x) + 0.5) * CELL_SIZE, 0.0, (float(cell.y) + 0.5) * CELL_SIZE)

func is_open(cell: Vector2i) -> bool:
	return walkable.has(cell)

func room_name(position: Vector3) -> String:
	return String(room_names.get(world_to_cell(position), "边界"))

func height_at(cell: Vector2i) -> float:
	return float(solid_heights.get(cell, WALL_HEIGHT))

func distances_from(position: Vector3, max_distance: float = 1000.0) -> Dictionary:
	var start: Vector2i = world_to_cell(position)
	var result: Dictionary = {}
	if not is_open(start):
		return result
	var ground_position: Vector3 = Vector3(position.x, 0.0, position.z)
	var initial_distance: float = ground_position.distance_to(cell_to_world(start))
	if initial_distance > max_distance:
		return result
	result[start] = initial_distance
	var frontier: Array[Vector2i] = [start]
	var cursor: int = 0
	while cursor < frontier.size():
		var cell: Vector2i = frontier[cursor]
		cursor += 1
		var next_distance: float = float(result[cell]) + CELL_SIZE
		if next_distance > max_distance:
			continue
		for direction: Vector2i in NEIGHBORS:
			var adjacent: Vector2i = cell + direction
			if is_open(adjacent) and not result.has(adjacent):
				result[adjacent] = next_distance
				frontier.append(adjacent)
	return result

func find_path(from: Vector3, to: Vector3) -> Array[Vector3]:
	to = navigation_target(to)
	var start: Vector2i = world_to_cell(from)
	var goal: Vector2i = world_to_cell(to)
	var result: Array[Vector3] = []
	if not is_navigation_open(start) or not is_navigation_open(goal):
		return result
	if start == goal:
		result.append(Vector3(to.x, 0.0, to.z))
		return result
	var previous: Dictionary = {start: start}
	var frontier: Array[Vector2i] = [start]
	var cursor: int = 0
	while cursor < frontier.size() and not previous.has(goal):
		var cell: Vector2i = frontier[cursor]
		cursor += 1
		for direction: Vector2i in NEIGHBORS:
			var adjacent: Vector2i = cell + direction
			if is_navigation_open(adjacent) and not previous.has(adjacent):
				previous[adjacent] = cell
				frontier.append(adjacent)
	if not previous.has(goal):
		return result
	var reverse_cells: Array[Vector2i] = [goal]
	var step: Vector2i = goal
	while step != start:
		step = Vector2i(previous[step])
		reverse_cells.append(step)
	reverse_cells.reverse()
	# Returning to the current cell center avoids clipping a solid corner when
	# a moving actor replans from an off-center position.
	for cell: Vector2i in reverse_cells:
		result.append(cell_to_world(cell))
	var final_position: Vector3 = Vector3(to.x, 0.0, to.z)
	if result[-1].distance_to(final_position) > 0.05:
		result.append(final_position)
	return result
