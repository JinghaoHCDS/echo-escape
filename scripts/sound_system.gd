class_name SoundSystem
extends Node3D
## A bounded, grid-path acoustic model. Gameplay propagation, world reveal data,
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
}

var active_waves: Array[Dictionary] = []
var clock: float = 0.0
var reveal_texture: ImageTexture
var last_debug: String = "尚无声波：通行网格决定距离，距离 / 速度决定到达时间。"
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


func register_listener(id: String, node: Node3D) -> void:
	_listeners[id] = node


func unregister_listener(id: String) -> void:
	_listeners.erase(id)


func set_playback_volume(linear: float) -> void:
	# This deliberately does not change event intensity, range, or listeners.
	_playback_volume = clampf(linear, 0.0, 1.0)
	for voice: AudioStreamPlayer3D in _voices:
		voice.volume_db = linear_to_db(maxf(_playback_volume, 0.0001))


func emit_sound(kind: String, source: String, position: Vector3) -> Dictionary:
	if _data == null:
		return {}
	var radius: float = float(_config.get(kind + "_radius", 4.0))
	var strength: float = float(_config.get(kind + "_intensity", 1.0))
	var event: Dictionary = {
		"id": _next_id,
		"source": source,
		"position": position,
		"time": clock,
		"kind": kind,
		"intensity": strength,
		"max_distance": radius,
		"reveal_duration": float(_config.get("reveal_duration", 2.0)),
		"distances": _data.distances_from(position, radius),
		"heard": {},
		"revealed": {},
		"previous_radius": -0.001,
	}
	_next_id += 1
	emitted_count += 1
	while active_waves.size() >= maxi(1, int(_config.get("max_waves", 24))):
		active_waves.pop_front()
	active_waves.append(event)
	peak_waves = maxi(peak_waves, active_waves.size())
	play_cue(kind, position)
	sound_emitted.emit(event)
	return event


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
	var image_changed: bool = false
	var speed: float = maxf(0.1, float(_config.get("propagation_speed", 10.0)))
	for index: int in range(active_waves.size() - 1, -1, -1):
		var event: Dictionary = active_waves[index]
		var radius: float = (clock - float(event["time"])) * speed
		var previous_radius: float = float(event["previous_radius"])
		var distances: Dictionary = event["distances"]
		var revealed: Dictionary = event["revealed"]
		for key: Variant in distances:
			var cell: Vector2i = key
			var distance: float = float(distances[cell])
			if distance <= radius and not revealed.has(cell):
				var old: Color = _image.get_pixel(cell.x, cell.y)
				# Store the actual path arrival time rather than frame time. The
				# GPU evaluates age globally, including behind the camera.
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
		# World residue lives only in the fixed-size texture. Once the front
		# ends, discard this event's path cache and delivery bookkeeping.
		if radius > float(event["max_distance"]) + 0.5:
			active_waves.remove_at(index)
	if image_changed:
		reveal_texture.update(_image)


func _deliver_listeners(event: Dictionary, previous_radius: float, radius: float, speed: float) -> void:
	var distances: Dictionary = event["distances"]
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
		var cell: Vector2i = _data.world_to_cell(listener.global_position)
		if not distances.has(cell):
			continue
		var distance: float = float(distances[cell])
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
		last_debug = "声波 #%d %s → %s：通行距离 %.1f m / %.1f m/s；传播 %.2f s" % [int(event["id"]), String(event["kind"]), id, distance, speed, clock - float(event["time"])]
		sound_arrived.emit(delivered, id)


func clear() -> void:
	active_waves.clear()
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
	## Read authoritative world reveal data without requiring GPU readback.
	if _image == null or cell.x < 0 or cell.y < 0 or cell.x >= LevelData.WIDTH or cell.y >= LevelData.HEIGHT:
		return -100.0
	var value: Color = _image.get_pixel(cell.x, cell.y)
	return value.g if danger else value.r
