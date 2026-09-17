class_name SoundSystem
extends Node3D
## Bounded continuous-distance acoustic fronts, independent of mesh triangles. Gameplay propagation, world reveal data,
## and audible playback are separate consumers of the same immutable origin.

signal sound_emitted(event: Dictionary)
signal sound_arrived(event: Dictionary, listener_id: String)

const CUES: Dictionary = {
	"walk": preload("res://assets/audio/walk.wav"),
	"run": preload("res://assets/audio/run.wav"),
	"clap": preload("res://assets/audio/clap.wav"),
	"probe": preload("res://assets/audio/probe.wav"),
	"windup": preload("res://assets/audio/windup.wav"),
	"pickup": preload("res://assets/audio/pickup.wav"),
	"victory": preload("res://assets/audio/victory.wav"),
	"defeat": preload("res://assets/audio/defeat.wav"),
	"inspect": preload("res://assets/audio/inspect.wav"),
	"cabinet": preload("res://assets/audio/cabinet.wav"),
}

var active_waves: Array[Dictionary] = []
var clock: float = 0.0
var reveal_texture: ImageTexture
var distance_texture: Texture2DArray
var acoustic_field: AcousticField

const SHADER_WAVES: int = 24
var _materials: Array[ShaderMaterial] = []
var _wave_origins := PackedVector4Array()
var _wave_parameters := PackedVector4Array()
var _wave_regions := PackedVector4Array()
var _wave_portals := PackedVector4Array()
var _regions: Array[Dictionary] = []
var _hiding: Node
const MAX_REGIONS: int = 4
var _field_resolution: int = 4
var _field_cache: Dictionary = {}
var _cache_order: Array[String] = []
var last_debug: String = "尚无声波：开放空间为圆形波前，实体墙使声路经门洞绕行。"
var emitted_count: int = 0
var arrival_count: int = 0
var peak_waves: int = 0

var _data: LevelData
var _config: Dictionary = {}
var _listeners: Dictionary = {}
var _image: Image
var _voices: Array[AudioStreamPlayer3D] = []
var _next_id: int = 1
var _voice_serial: int = 0
var _playback_volume: float = 0.8


func setup(data: LevelData, config: Dictionary) -> void:
	_data = data
	_config = config
	for spot: Dictionary in data.hiding_spots:
		if String(spot["kind"]) == "locker" and _regions.size() < MAX_REGIONS:
			_regions.append(spot)
	_field_resolution = maxi(2, int(config.get("acoustic_field_resolution", 4)))
	acoustic_field = AcousticField.new()
	acoustic_field.setup(data)
	acoustic_field.prepare_samples(_field_resolution)
	var layers: Array[Image] = []
	for slot: int in range(SHADER_WAVES):
		var blank := Image.create(LevelData.WIDTH * _field_resolution, LevelData.HEIGHT * _field_resolution, false, Image.FORMAT_RF)
		blank.fill(Color(-1.0, 0.0, 0.0))
		layers.append(blank)
		_wave_origins.append(Vector4.ZERO)
		_wave_parameters.append(Vector4.ZERO)
		_wave_regions.append(Vector4.ZERO)
		_wave_portals.append(Vector4(-1.0, -1.0, -1.0, -1.0))
	distance_texture = Texture2DArray.new()
	distance_texture.create_from_images(layers)
	_image = Image.create(LevelData.WIDTH, LevelData.HEIGHT, false, Image.FORMAT_RGBAF)
	_image.fill(Color(-100.0, -100.0, 0.0, 1.0))
	reveal_texture = ImageTexture.create_from_image(_image)
	_playback_volume = float(_config.get("audio_volume", 0.8))
	# Audio nodes are pooled once; continual running cannot allocate more voices.
	for index: int in range(int(_config.get("max_audio_voices", 16))):
		var voice := AudioStreamPlayer3D.new()
		voice.name = "Voice%02d" % index
		voice.max_distance = 30.0
		voice.unit_size = 4.0
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		voice.volume_db = linear_to_db(maxf(_playback_volume, 0.0001))
		voice.set_meta("serial", -1)
		add_child(voice)
		_voices.append(voice)


func set_hiding_system(hiding: Node) -> void:
	_hiding = hiding
	_sync_materials()


func register_listener(id: String, node: Node3D) -> void:
	_listeners[id] = node


func unregister_listener(id: String) -> void:
	_listeners.erase(id)


func set_playback_volume(linear: float) -> void:
	# This deliberately does not change event intensity, range, or listeners.
	_playback_volume = clampf(linear, 0.0, 1.0)
	for voice: AudioStreamPlayer3D in _voices:
		voice.volume_db = linear_to_db(maxf(_playback_volume, 0.0001))


func bind_material(material: ShaderMaterial) -> void:
	if not _materials.has(material):
		_materials.append(material)
	material.set_shader_parameter("wave_distances", distance_texture)
	material.set_shader_parameter("field_resolution", float(_field_resolution))
	material.set_shader_parameter("wave_front_width", float(_config.get("wave_front_width", 1.5)))
	material.set_shader_parameter("wave_core_transition_start", float(_config.get("wave_core_transition_start", 0.8)))
	material.set_shader_parameter("wave_outer_intensity", float(_config.get("wave_outer_intensity", 0.18)))
	var bounds := PackedVector4Array()
	var portals := PackedVector4Array()
	for index: int in range(MAX_REGIONS):
		if index < _regions.size():
			var box: AABB = _regions[index]["bounds"]
			var portal: Vector3 = _regions[index]["portal"]
			bounds.append(Vector4(box.position.x, box.position.z, box.end.x, box.end.z))
			portals.append(Vector4(portal.x, portal.z, box.end.y, 1.0))
		else:
			bounds.append(Vector4.ZERO)
			portals.append(Vector4.ZERO)
	material.set_shader_parameter("acoustic_region_count", _regions.size())
	material.set_shader_parameter("acoustic_region_bounds", bounds)
	material.set_shader_parameter("acoustic_region_portals", portals)
	_sync_materials()


func _sync_materials() -> void:
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("wave_origin_time", _wave_origins)
		material.set_shader_parameter("wave_parameters", _wave_parameters)
		material.set_shader_parameter("wave_region_parameters", _wave_regions)
		material.set_shader_parameter("wave_portal_distances", _wave_portals)


func _field_for(position: Vector3, radius: float) -> Dictionary:
	var key: String = "%.5f/%.5f/%.3f" % [position.x, position.z, radius]
	if _field_cache.has(key):
		_cache_order.erase(key)
		_cache_order.append(key)
		return _field_cache[key]
	# Extra coverage keeps filtering smooth at the wave's outer radius. Only
	# gameplay listeners retain max_distance; the weak tail uses visual_max_distance.
	var field: Dictionary = acoustic_field.build_wave(position, radius + 1.0)
	var image: Image = acoustic_field.build_distance_image(field, _field_resolution)
	if image.get_format() != Image.FORMAT_RF:
		image.convert(Image.FORMAT_RF)
	var cached: Dictionary = {"field": field, "image": image}
	_field_cache[key] = cached
	_cache_order.append(key)
	while _cache_order.size() > maxi(1, int(_config.get("max_field_cache", 16))):
		_field_cache.erase(_cache_order.pop_front())
	return cached


func emit_sound(kind: String, source: String, position: Vector3) -> Dictionary:
	if _data == null:
		return {}
	var radius: float = float(_config.get(kind + "_radius", 4.0))
	var visual_radius: float = radius * maxf(1.0, float(_config.get("visual_range_multiplier", 1.5)))
	var source_region: int = _region_at(position)
	var field_origin: Vector3 = position
	var source_prefix: float = 0.0
	if source_region >= 0:
		field_origin = _regions[source_region]["portal"]
		source_prefix = Vector2(position.x, position.z).distance_to(Vector2(field_origin.x, field_origin.z))
	var cached: Dictionary = _field_for(field_origin, maxf(0.0, visual_radius - source_prefix))
	var portal_paths := PackedFloat32Array()
	for spot: Dictionary in _regions:
		portal_paths.append(acoustic_field.distance_at(cached["field"], spot["portal"]) + source_prefix)
	var event: Dictionary = {
		"id": _next_id, "source": source, "position": position, "time": clock,
		"kind": kind, "intensity": float(_config.get(kind + "_intensity", 1.0)),
		"max_distance": radius, "visual_max_distance": visual_radius, "reveal_duration": float(_config.get("reveal_duration", 2.0)),
		"field": cached["field"], "distance_image": cached["image"],
		"heard": {}, "revealed": {}, "previous_radius": -0.001,
		"source_region": source_region, "source_prefix": source_prefix,
		"exterior_enabled": source_region < 0, "portal_checked": {}, "portal_path_distances": portal_paths,
		"portal_distances": Vector4(-1.0, -1.0, -1.0, -1.0),
	}
	var capacity: int = clampi(int(_config.get("max_waves", 24)), 1, SHADER_WAVES)
	while active_waves.size() >= capacity:
		var removed: Dictionary = active_waves.pop_front()
		_wave_parameters[int(removed["slot"])] = Vector4.ZERO
	var slot: int = 0
	for index: int in range(SHADER_WAVES):
		if _wave_parameters[index].x <= 0.0:
			slot = index
			break
	event["slot"] = slot
	_update_debug_distances(event)
	_next_id += 1
	emitted_count += 1
	active_waves.append(event)
	peak_waves = maxi(peak_waves, active_waves.size())
	distance_texture.update_layer(event["distance_image"], slot)
	_wave_origins[slot] = Vector4(position.x, position.y, position.z, clock)
	# Negative speed is a compact source-color flag, not a different rule.
	var speed: float = maxf(0.1, float(_config.get("propagation_speed", 24.0)))
	_wave_parameters[slot] = Vector4(radius, -speed if source == "monster" else speed, float(event["reveal_duration"]), visual_radius)
	_update_region_uniforms(event)
	_sync_materials()
	play_cue(kind, position)
	sound_emitted.emit(event)
	return event


func horizontal_distance(event: Dictionary, at: Vector3) -> float:
	var target_region: int = _region_at(at)
	if target_region >= 0:
		if int(event["source_region"]) == target_region:
			var source: Vector3 = event["position"]
			return Vector2(source.x, source.z).distance_to(Vector2(at.x, at.z))
		var prefix: float = (event["portal_distances"] as Vector4)[target_region]
		if prefix < 0.0:
			return INF
		var portal: Vector3 = _regions[target_region]["portal"]
		return prefix + Vector2(portal.x, portal.z).distance_to(Vector2(at.x, at.z))
	if not bool(event["exterior_enabled"]):
		return INF
	return _exterior_distance(event, at)


func _exterior_distance(event: Dictionary, at: Vector3) -> float:
	# The exact same wall-aware, normalized bilinear filter is used in the
	# fragment shader. Blocked texels never interpolate through a solid cell.
	if not _data.is_open(_data.world_to_cell(at)):
		return INF
	var image: Image = event["distance_image"]
	var nearest := Vector2i(floori(at.x * _field_resolution), floori(at.z * _field_resolution))
	if image.get_pixelv(nearest).r < 0.0:
		return INF
	var sample_at := Vector2(at.x, at.z) * float(_field_resolution) - Vector2(0.5, 0.5)
	var base := Vector2i(floori(sample_at.x), floori(sample_at.y))
	var fraction := sample_at - Vector2(base)
	var total: float = 0.0
	var weight_sum: float = 0.0
	for y: int in range(2):
		for x: int in range(2):
			var pixel: Vector2i = base + Vector2i(x, y)
			if pixel.x < 0 or pixel.y < 0 or pixel.x >= image.get_width() or pixel.y >= image.get_height():
				continue
			var distance: float = image.get_pixel(pixel.x, pixel.y).r
			if distance < 0.0:
				continue
			var weight: float = (fraction.x if x else 1.0 - fraction.x) * (fraction.y if y else 1.0 - fraction.y)
			total += distance * weight
			weight_sum += weight
	return total / weight_sum + float(event.get("source_prefix", 0.0)) if weight_sum > 0.00001 else INF


func event_distance(event: Dictionary, at: Vector3) -> float:
	var horizontal: float = horizontal_distance(event, at)
	var height: float = at.y - (event["position"] as Vector3).y
	return sqrt(horizontal * horizontal + height * height)


func play_cue(kind: String, position: Vector3) -> void:
	if not CUES.has(kind) or _voices.is_empty():
		return
	var selected: AudioStreamPlayer3D = _voices[0]
	for voice: AudioStreamPlayer3D in _voices:
		if not voice.playing:
			selected = voice
			break
		if int(voice.get_meta("serial", 0)) < int(selected.get_meta("serial", 0)):
			selected = voice
	selected.stop()
	selected.stream = CUES[kind] as AudioStream
	selected.global_position = position
	selected.set_meta("serial", _voice_serial)
	_voice_serial += 1
	selected.play()


func _physics_process(delta: float) -> void:
	if _data == null or _image == null:
		return
	clock += delta
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("echo_time", clock)
	var image_changed: bool = false
	var speed: float = maxf(0.1, float(_config.get("propagation_speed", 24.0)))
	for index: int in range(active_waves.size() - 1, -1, -1):
		var event: Dictionary = active_waves[index]
		var radius: float = (clock - float(event["time"])) * speed
		var previous_radius: float = float(event["previous_radius"])
		_advance_portals(event, radius)
		var distances: Dictionary = event["distances"]
		var revealed: Dictionary = event["revealed"]
		for key: Variant in distances:
			var cell: Vector2i = key
			var distance: float = float(distances[cell])
			if distance <= radius and not revealed.has(cell):
				var old: Color = _image.get_pixel(cell.x, cell.y)
				# Coarse cell-center inspection data for F1/tests only. Visuals
				# evaluate the continuous per-wave distance layers, not this grid.
				var arrival_time: float = float(event["time"]) + distance / speed
				if String(event["source"]) == "monster":
					old.g = maxf(old.g, arrival_time)
				else:
					old.r = maxf(old.r, arrival_time)
				_image.set_pixel(cell.x, cell.y, old)
				revealed[cell] = true
				image_changed = true
		_deliver_listeners(event, previous_radius, radius, speed)
		event["previous_radius"] = radius
		# Retain each bounded distance layer through its world-space residue.
		# No mesh-face state and no camera-dependent reveal history is involved.
		if clock - float(event["time"]) > float(event["visual_max_distance"]) / speed + float(event["reveal_duration"]):
			_wave_parameters[int(event["slot"])] = Vector4.ZERO
			active_waves.remove_at(index)
			_sync_materials()
	if image_changed:
		reveal_texture.update(_image)


func _deliver_listeners(event: Dictionary, previous_radius: float, radius: float, speed: float) -> void:
	var heard: Dictionary = event["heard"]
	var body_radius: float = float(_config.get("sound_listener_radius", 0.30))
	for key: Variant in _listeners.keys():
		var id: String = String(key)
		if heard.has(id):
			continue
		var listener: Node3D = _listeners[id] as Node3D
		if not is_instance_valid(listener):
			_listeners.erase(id)
			continue
		var at: Vector3 = listener.call("acoustic_position") if listener.has_method("acoustic_position") else listener.global_position
		var distance: float = event_distance(event, at)
		if distance > float(event["max_distance"]):
			continue
		# Test the swept front against the current collision footprint. Entering
		# an already-passed cell must never turn old residue into fresh evidence.
		if radius < distance - body_radius or previous_radius > distance + body_radius:
			continue
		heard[id] = true
		var delivered: Dictionary = event.duplicate(false)
		delivered["received_distance"] = distance
		delivered["arrival_time"] = float(event["time"]) + distance / speed
		delivered["received_intensity"] = float(event["intensity"]) * maxf(0.0, 1.0 - distance / maxf(0.01, float(event["max_distance"])))
		arrival_count += 1
		last_debug = "声波 #%d %s → %s：声路 %.2f m / %.0f m/s；证据 %.1f m / 弱光 %.1f m" % [int(event["id"]), String(event["kind"]), id, distance, speed, float(event["max_distance"]), float(event["visual_max_distance"])]
		sound_arrived.emit(delivered, id)


func clear() -> void:
	active_waves.clear()
	_field_cache.clear()
	_cache_order.clear()
	for slot: int in range(_wave_parameters.size()):
		_wave_parameters[slot] = Vector4.ZERO
		_wave_regions[slot] = Vector4.ZERO
		_wave_portals[slot] = Vector4(-1.0, -1.0, -1.0, -1.0)
	_sync_materials()
	clock = 0.0
	_next_id = 1
	emitted_count = 0
	arrival_count = 0
	peak_waves = 0
	last_debug = "声波缓存已清空。"
	for voice: AudioStreamPlayer3D in _voices:
		voice.stop()
	if _image != null:
		_image.fill(Color(-100.0, -100.0, 0.0, 1.0))
		reveal_texture.update(_image)


func active_voice_count() -> int:
	var count: int = 0
	for voice: AudioStreamPlayer3D in _voices:
		if voice.playing:
			count += 1
	return count


func reveal_arrival_time(cell: Vector2i, danger: bool = false) -> float:
	## Inspect an actual cell-center arrival (diagnostics, not render input).
	if _image == null or cell.x < 0 or cell.y < 0 or cell.x >= LevelData.WIDTH or cell.y >= LevelData.HEIGHT:
		return -100.0
	var value: Color = _image.get_pixel(cell.x, cell.y)
	return value.g if danger else value.r


func _region_at(at: Vector3) -> int:
	for index: int in range(_regions.size()):
		var bounds: AABB = _regions[index]["bounds"]
		# Include the floor boundary, but leave the exterior top face outside.
		if at.x >= bounds.position.x and at.x < bounds.end.x and at.z >= bounds.position.z and at.z < bounds.end.z and at.y >= bounds.position.y - 0.01 and at.y < bounds.end.y:
			return index
	return -1


func _door_closed(index: int) -> bool:
	return not is_instance_valid(_hiding) or bool(_hiding.call("is_closed", String(_regions[index]["id"])))


func _advance_portals(event: Dictionary, radius: float) -> void:
	# Each wave tests each cupboard opening exactly once when its front arrives.
	# Opening a door afterwards cannot resurrect a missed front or replay audio.
	var changed: bool = false
	var checked: Dictionary = event["portal_checked"]
	var source: int = int(event["source_region"])
	if source >= 0 and not checked.has(source) and radius >= float(event["source_prefix"]):
		checked[source] = true
		event["exterior_enabled"] = not _door_closed(source)
		changed = true
	if bool(event["exterior_enabled"]):
		var distances: Vector4 = event["portal_distances"]
		for index: int in range(_regions.size()):
			if index == source or checked.has(index):
				continue
			var distance: float = (event["portal_path_distances"] as PackedFloat32Array)[index]
			if distance <= float(event["visual_max_distance"]) and radius >= distance:
				checked[index] = true
				if not _door_closed(index):
					distances[index] = distance
				changed = true
		event["portal_distances"] = distances
	if changed:
		_update_region_uniforms(event)
		_update_debug_distances(event)
		_sync_materials()


func _update_region_uniforms(event: Dictionary) -> void:
	var slot: int = int(event["slot"])
	_wave_regions[slot] = Vector4(float(int(event["source_region"]) + 1), 1.0 if bool(event["exterior_enabled"]) else 0.0, float(event["source_prefix"]), 0.0)
	_wave_portals[slot] = event["portal_distances"]


func _update_debug_distances(event: Dictionary) -> void:
	# Coarse F1 diagnostics only; the actual world reveal is continuous per pixel.
	var distances: Dictionary = {}
	for cell: Vector2i in _data.walkable:
		var distance: float = event_distance(event, _data.cell_to_world(cell))
		if distance <= float(event["visual_max_distance"]):
			distances[cell] = distance
	event["distances"] = distances


func visual_attenuation(event: Dictionary, distance: float) -> float:
	# Same continuous envelope as the shader; useful to inspect the actual
	# gameplay/visual split without treating the visual tail as evidence.
	var core: float = float(event["max_distance"])
	var outer: float = float(event["visual_max_distance"])
	var transition: float = core * float(_config.get("wave_core_transition_start", 0.8))
	var weak: float = float(_config.get("wave_outer_intensity", 0.18))
	if distance <= transition:
		return lerpf(1.0, 0.55, smoothstep(0.0, transition, distance))
	if distance <= core:
		return lerpf(0.55, weak, smoothstep(transition, core, distance))
	return weak * (1.0 - smoothstep(core, maxf(core + 0.001, outer), distance))
