class_name AcousticField
extends RefCounted
## Continuous ground-plane shortest paths through the LevelData free space.
## Geometry uses a small visibility graph at obstacle/reflex corners, not mesh
## triangles or a raster flood. Image samples encode that same distance field.

const CORNER_MARGIN: float = 0.015
const CROSSING_EPSILON: float = 0.0000001

var corners: PackedVector2Array = PackedVector2Array()
var _open: PackedByteArray = PackedByteArray()
var _edges: Array[PackedInt32Array] = []
var _edge_lengths: Array[PackedFloat32Array] = []
var _sample_caches: Dictionary = {}


func setup(data: LevelData) -> void:
	_open.resize(LevelData.WIDTH * LevelData.HEIGHT)
	_open.fill(0)
	for cell: Vector2i in data.walkable:
		if _in_bounds(cell.x, cell.y):
			_open[cell.y * LevelData.WIDTH + cell.x] = 1
	corners.clear()
	_edges.clear()
	_edge_lengths.clear()
	_sample_caches.clear()
	# Exactly three open quadrants identify a reflex vertex of free space.
	# Offset away from its solid quadrant to keep all graph edges inside open
	# space and conservatively forbid zero-width diagonal cracks.
	for y: int in range(1, LevelData.HEIGHT):
		for x: int in range(1, LevelData.WIDTH):
			var quadrants: Array[Vector2i] = [Vector2i(x - 1, y - 1), Vector2i(x, y - 1), Vector2i(x - 1, y), Vector2i(x, y)]
			var open_count: int = 0
			var solid: Vector2i = Vector2i.ZERO
			for cell: Vector2i in quadrants:
				if _is_open(cell.x, cell.y):
					open_count += 1
				else:
					solid = cell
			if open_count == 3:
				var offset := Vector2(1.0 if solid.x < x else -1.0, 1.0 if solid.y < y else -1.0)
				corners.append(Vector2(x, y) + offset * CORNER_MARGIN)
	for index: int in range(corners.size()):
		_edges.append(PackedInt32Array())
		_edge_lengths.append(PackedFloat32Array())
	for a: int in range(corners.size()):
		for b: int in range(a + 1, corners.size()):
			if segment_clear(corners[a], corners[b]):
				var distance: float = corners[a].distance_to(corners[b])
				_edges[a].append(b)
				_edge_lengths[a].append(distance)
				_edges[b].append(a)
				_edge_lengths[b].append(distance)


func build_wave(origin: Vector3, max_distance: float) -> Dictionary:
	var source := Vector2(origin.x, origin.z)
	var distances := PackedFloat32Array()
	distances.resize(corners.size())
	distances.fill(INF)
	var visited := PackedByteArray()
	visited.resize(corners.size())
	visited.fill(0)
	if _is_open(floori(source.x), floori(source.y)):
		for index: int in range(corners.size()):
			var distance: float = source.distance_to(corners[index])
			if distance <= max_distance and segment_clear(source, corners[index]):
				distances[index] = distance
		for _iteration: int in range(corners.size()):
			var current: int = -1
			var closest: float = INF
			for index: int in range(corners.size()):
				if visited[index] == 0 and distances[index] < closest:
					current = index
					closest = distances[index]
			if current < 0 or closest > max_distance:
				break
			visited[current] = 1
			for edge: int in range(_edges[current].size()):
				var neighbor: int = _edges[current][edge]
				var candidate: float = closest + _edge_lengths[current][edge]
				if candidate <= max_distance and candidate < distances[neighbor]:
					distances[neighbor] = candidate
	return {"origin": origin, "source_2d": source, "max_distance": max_distance, "corner_distances": distances}


func distance_at(wave: Dictionary, point: Vector3) -> float:
	var target := Vector2(point.x, point.z)
	var source: Vector2 = wave["source_2d"]
	var max_distance: float = float(wave["max_distance"])
	if not _is_open(floori(target.x), floori(target.y)):
		return INF
	var straight: float = source.distance_to(target)
	if straight > max_distance:
		return INF
	if segment_clear(source, target):
		return straight
	var distances: PackedFloat32Array = wave["corner_distances"]
	var best: float = INF
	for index: int in range(corners.size()):
		if distances[index] > max_distance:
			continue
		var candidate: float = distances[index] + corners[index].distance_to(target)
		if candidate <= max_distance and candidate < best and segment_clear(corners[index], target):
			best = candidate
	return best


func segment_clear(a: Vector2, b: Vector2) -> bool:
	# Exact cell traversal, not coarse samples that can skip a wall corner.
	var x: int = floori(a.x)
	var y: int = floori(a.y)
	var end_x: int = floori(b.x)
	var end_y: int = floori(b.y)
	if not _is_open(x, y) or not _is_open(end_x, end_y):
		return false
	var delta: Vector2 = b - a
	var step_x: int = 1 if delta.x > 0.0 else -1
	var step_y: int = 1 if delta.y > 0.0 else -1
	var increment_x: float = absf(1.0 / delta.x) if absf(delta.x) > CROSSING_EPSILON else INF
	var increment_y: float = absf(1.0 / delta.y) if absf(delta.y) > CROSSING_EPSILON else INF
	var next_x: float = (float(x + 1) - a.x) * increment_x if step_x > 0 else (a.x - float(x)) * increment_x
	var next_y: float = (float(y + 1) - a.y) * increment_y if step_y > 0 else (a.y - float(y)) * increment_y
	# Avoid 0 * INF when a segment is parallel to an integer grid boundary.
	if is_inf(increment_x):
		next_x = INF
	if is_inf(increment_y):
		next_y = INF
	while x != end_x or y != end_y:
		if absf(next_x - next_y) <= CROSSING_EPSILON:
			if not _is_open(x + step_x, y) or not _is_open(x, y + step_y):
				return false
			x += step_x
			y += step_y
			next_x += increment_x
			next_y += increment_y
		elif next_x < next_y:
			x += step_x
			next_x += increment_x
		else:
			y += step_y
			next_y += increment_y
		if not _is_open(x, y):
			return false
	return true


func prepare_samples(resolution: int = 4) -> void:
	# Call at level setup, outside gameplay. Cache endpoint visibility once;
	# each emitted wave only solves its source distances and direct rays.
	if _sample_caches.has(resolution):
		return
	var sample_positions := PackedVector2Array()
	var sample_pixels := PackedInt32Array()
	var visible_corners: Array[PackedInt32Array] = []
	var corner_lengths: Array[PackedFloat32Array] = []
	var width: int = LevelData.WIDTH * resolution
	for y: int in range(LevelData.HEIGHT * resolution):
		for x: int in range(width):
			if not _is_open(x / resolution, y / resolution):
				continue
			var point := Vector2((float(x) + 0.5) / float(resolution), (float(y) + 0.5) / float(resolution))
			sample_positions.append(point)
			sample_pixels.append(y * width + x)
			var ids := PackedInt32Array()
			var lengths := PackedFloat32Array()
			for index: int in range(corners.size()):
				if segment_clear(corners[index], point):
					ids.append(index)
					lengths.append(corners[index].distance_to(point))
			visible_corners.append(ids)
			corner_lengths.append(lengths)
	_sample_caches[resolution] = {"positions": sample_positions, "pixels": sample_pixels, "corners": visible_corners, "lengths": corner_lengths}


func build_distance_image(wave: Dictionary, resolution: int = 4) -> Image:
	prepare_samples(resolution)
	var width: int = LevelData.WIDTH * resolution
	var height: int = LevelData.HEIGHT * resolution
	var values := PackedFloat32Array()
	values.resize(width * height)
	values.fill(-1.0)
	var cache: Dictionary = _sample_caches[resolution]
	var positions: PackedVector2Array = cache["positions"]
	var pixels: PackedInt32Array = cache["pixels"]
	var visible_corners: Array[PackedInt32Array] = cache["corners"]
	var corner_lengths: Array[PackedFloat32Array] = cache["lengths"]
	var distances: PackedFloat32Array = wave["corner_distances"]
	var source: Vector2 = wave["source_2d"]
	var max_distance: float = float(wave["max_distance"])
	var radius_squared: float = max_distance * max_distance
	for sample: int in range(positions.size()):
		var point: Vector2 = positions[sample]
		var squared: float = source.distance_squared_to(point)
		if squared > radius_squared:
			continue
		if segment_clear(source, point):
			values[pixels[sample]] = sqrt(squared)
			continue
		var best: float = INF
		var ids: PackedInt32Array = visible_corners[sample]
		var lengths: PackedFloat32Array = corner_lengths[sample]
		for endpoint: int in range(ids.size()):
			var candidate: float = distances[ids[endpoint]] + lengths[endpoint]
			if candidate < best:
				best = candidate
		if best <= max_distance:
			values[pixels[sample]] = best
	return Image.create_from_data(width, height, false, Image.FORMAT_RF, values.to_byte_array())


func _in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < LevelData.WIDTH and y < LevelData.HEIGHT


func _is_open(x: int, y: int) -> bool:
	return _in_bounds(x, y) and _open[y * LevelData.WIDTH + x] != 0
