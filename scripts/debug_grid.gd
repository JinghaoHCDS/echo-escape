class_name EchoDebugGrid
extends Control

var data: LevelData
var sound: SoundSystem
var player: EchoPlayer

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

func _draw() -> void:
	if data == null or sound == null:
		return
	const SCALE := 5.5
	draw_rect(Rect2(Vector2.ZERO, Vector2(LevelData.WIDTH, LevelData.HEIGHT) * SCALE), Color(0.015, 0.025, 0.04, 0.94))
	var wave: Dictionary = {} if sound.active_waves.is_empty() else sound.active_waves.back()
	var distances: Dictionary = wave.get("distances", {})
	var radius: float = (sound.clock - float(wave.get("time", sound.clock))) * float(player.config.get("propagation_speed", 24.0))
	for cell: Vector2i in data.walkable:
		var color := Color(0.12, 0.18, 0.21)
		if distances.has(cell):
			color = Color(0.2, 0.55, 0.64) if float(distances[cell]) <= radius else Color(0.23, 0.29, 0.3)
		draw_rect(Rect2(Vector2(cell) * SCALE, Vector2.ONE * (SCALE - 0.5)), color)
	draw_circle(Vector2(player.global_position.x, player.global_position.z) * SCALE, 3.0, Color.WHITE)
