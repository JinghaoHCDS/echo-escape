extends SceneTree
## Graphical audio integration test. Captures the real Master mixer output,
## not WAV file bytes. Does not modify operating-system playback settings.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("AUDIO_TEST_RESULT: SKIP — headless 使用 Dummy 音频；须去掉 --headless 验证真实混音输出。")
		quit(0)
		return
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/gameplay.json"))
	var sound := SoundSystem.new()
	root.add_child(sound)
	sound.setup(LevelData.new(), config)
	sound.set_physics_process(false)
	# The real game has a current first-person Camera3D. A bare SceneTree test
	# must create the same 3D viewport listener before spatial audio is mixed.
	root.audio_listener_enable_3d = true
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 0.4
	var effect_index: int = AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, capture)
	var stable_nodes: int = sound.get_child_count()
	await create_timer(0.08).timeout
	for kind: String in ["walk", "run", "clap", "probe", "windup", "pickup", "victory", "defeat", "inspect", "cabinet"]:
		sound.clear()
		# Let the audio thread drain the previous stream before starting a cue.
		await create_timer(0.06).timeout
		capture.clear_buffer()
		sound.play_cue(kind, Vector3.ZERO)
		await create_timer(0.14).timeout
		var frames: PackedVector2Array = capture.get_buffer(capture.get_frames_available())
		var peak: float = 0.0
		var energy: float = 0.0
		for frame: Vector2 in frames:
			peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
			energy += frame.length_squared() * 0.5
		var rms: float = sqrt(energy / float(maxi(1, frames.size())))
		print("AUDIO_CAPTURE: %s frames=%d rms=%.6f peak=%.6f" % [kind, frames.size(), rms, peak])
		_check(frames.size() > 500 and rms > 0.0001 and peak > 0.001, kind + " 实际 Master 混音输出非静音")
		_check(sound.get_child_count() == stable_nodes, kind + " 播放后音频节点总量不变")
	sound.clear()
	for index: int in range(200):
		sound.play_cue("walk", Vector3.ZERO)
	_check(sound.get_child_count() == stable_nodes and sound.active_voice_count() <= int(config["max_audio_voices"]), "连续触发 200 次音效仍受固定音频池限制")
	sound.clear()
	_check(sound.active_voice_count() == 0, "测试结束停止全部音频")
	AudioServer.remove_bus_effect(0, effect_index)
	print("AUDIO_TEST_RESULT: ", "PASS" if _failures == 0 else "FAIL", " failures=", _failures)
	quit(0 if _failures == 0 else 1)
