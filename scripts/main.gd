class_name EchoGame
extends Node3D

var config: Dictionary
var data: LevelData
var level: LevelBuilder
var player: EchoPlayer
var monster: EchoMonster
var sound: SoundSystem
var objectives: EchoObjectives
var hiding: HidingSystem
var ui: EchoUI
var session: Node3D
var status: String = "intro"
var debug_enabled: bool = false
var clap_remaining: float = 0.0
var run_time: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	config = JSON.parse_string(FileAccess.get_file_as_string("res://config/gameplay.json")) as Dictionary
	_bind_inputs()
	_build_session()
	ui = EchoUI.new()
	add_child(ui)
	ui.configure(config)
	ui.grid.data = data
	ui.grid.sound = sound
	ui.grid.player = player
	ui.resume_requested.connect(start_game)
	ui.restart_requested.connect(restart)
	ui.setting_changed.connect(_change_setting)
	ui.modal("intro", "回声撤离", "E C H O   E S C A P E   /   声音潜行实验\n\n鼓掌唤醒机房核心，再带它返回入口。声音给你方向，也给它方向。\nE 进入柜子或桌底，再按 E 离开；先切断视线再躲藏。\n柜门隔绝探测，桌底仍会被探测；信标启动后无法靠躲藏脱身。\n\nWASD 移动 · Shift 奔跑 · 左键鼓掌 · E 交互\n三连脉冲是探测，敲击是检查，抬起双臂时立即侧移。")
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _build_session() -> void:
	session = Node3D.new()
	session.name = "Session"
	session.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(session)
	data = LevelData.new()
	level = LevelBuilder.new()
	session.add_child(level)
	level.setup(data)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.003, 0.006, 0.012)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color(0.4, 0.55, 0.65)
	world.environment.ambient_light_energy = 0.3
	session.add_child(world)
	player = EchoPlayer.new()
	player.name = "Player"
	session.add_child(player)
	player.setup(config)
	player.position = data.spawn_position + Vector3.UP * 0.05
	sound = SoundSystem.new()
	sound.name = "SoundSystem"
	session.add_child(sound)
	sound.setup(data, config)
	sound.bind_material(level.material)
	hiding = HidingSystem.new()
	hiding.name = "HidingSystem"
	session.add_child(hiding)
	hiding.setup(data, player, sound, config, level.material)
	sound.set_hiding_system(hiding)
	hiding.feedback.connect(func(message: String) -> void: ui.toast(message))
	monster = EchoMonster.new()
	monster.name = "Monster"
	session.add_child(monster)
	monster.setup(data, player, sound, config)
	monster.set_hiding_system(hiding)
	sound.register_listener("player", player)
	sound.register_listener("monster", monster)
	objectives = EchoObjectives.new()
	session.add_child(objectives)
	objectives.setup(data, player, sound, config)
	player.footstep.connect(func(kind: String, at: Vector3) -> void: sound.emit_sound(kind, "player", at))
	player.clap_requested.connect(clap)
	player.interact_requested.connect(interact)
	monster.player_hit.connect(func(reason: String) -> void: finish(false, reason))
	objectives.activated.connect(func() -> void:
		ui.toast("回声已唤醒核心 · 靠近并按 E 取出")
		sound.play_cue("pickup", objectives.item.global_position))
	objectives.picked_up.connect(_on_pickup)
	objectives.escaped.connect(func() -> void: finish(true, "信标已安全送达入口"))

func _bind_inputs() -> void:
	var keys: Dictionary = {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "run": KEY_SHIFT, "interact": KEY_E, "pause": KEY_ESCAPE, "restart": KEY_R, "debug": KEY_F1}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var key := InputEventKey.new()
			key.physical_keycode = keys[action]
			InputMap.action_add_event(action, key)
	if not InputMap.has_action("clap"):
		InputMap.add_action("clap")
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("clap", mouse)

func start_game() -> void:
	if status not in ["intro", "paused"]:
		return
	status = "playing"
	get_tree().paused = false
	ui.overlay.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func clap() -> void:
	if status == "playing" and clap_remaining <= 0.0:
		sound.emit_sound("clap", "player", player.acoustic_position())
		clap_remaining = float(config["clap_cooldown"])

func _interaction_target() -> String:
	if not hiding.current_spot_id.is_empty() or hiding.is_transitioning():
		return "hiding"
	var furniture: Dictionary = hiding.candidate()
	var core: Dictionary = objectives.interaction_candidate()
	if not core.is_empty() and (furniture.is_empty() or float(core["distance"]) <= float(furniture["distance"])):
		return "core"
	return "hiding" if not furniture.is_empty() else ""

func interact() -> void:
	if status != "playing":
		return
	match _interaction_target():
		"hiding":
			hiding.interact()
		"core":
			objectives.interact()

func _interaction_prompt() -> String:
	match _interaction_target():
		"hiding":
			return hiding.prompt()
		"core":
			return "[ E ]  取出信标核心"
	return objectives.prompt() if not objectives.can_pick_up() else "看向核心，按 E 取出"

func _on_pickup() -> void:
	monster.set_alarm(true)
	sound.play_cue("pickup", player.global_position)
	ui.toast("信标已启动：怪物将持续追踪，返回入口撤离。", 7.0)

func _physics_process(delta: float) -> void:
	if status != "playing":
		return
	run_time += delta
	clap_remaining = maxf(0.0, clap_remaining - delta)
	level.update_view(player.global_position, sound.clock, debug_enabled)
	ui.update_hud(data.room_name(player.global_position), clap_remaining, float(config["clap_cooldown"]), _interaction_prompt(), objectives.has_item)
	if debug_enabled:
		ui.debug_label.text = "开发照明 / 规则不变   |   %d FPS\n状态 %s · 有效证据 %.1fs 前\n最后位置 %s\n发现/丢失：%s\n攻击：%s\n躲藏 %s · 鼓掌作用 %.0fm / 显形 %.0fm\n声波 %d / %d · 节点 %d\n%s\n网格：青=已到达 / 暗青=弱光 / 框=家具 / 白=玩家" % [Engine.get_frames_per_second(), monster.state, maxf(0.0, sound.clock - monster.last_evidence_time), str(monster.last_known_position), monster.evidence_reason, monster.attack_reason, "无" if hiding.current_spot_id.is_empty() else hiding.current_spot_id, float(config["clap_radius"]), float(config["clap_radius"]) * float(config["visual_range_multiplier"]), sound.active_waves.size(), int(config["max_waves"]), get_tree().get_node_count(), sound.last_debug]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug"):
		debug_enabled = not debug_enabled
		monster.set_debug(debug_enabled)
		objectives.debug_lit = debug_enabled
		ui.debug_label.visible = debug_enabled
		ui.grid.visible = debug_enabled
		level.update_view(player.global_position, sound.clock, debug_enabled)
	if event.is_action_pressed("pause"):
		if status == "playing":
			status = "paused"
			get_tree().paused = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			ui.modal("pause", "静默 / 暂停", "声音、追踪与躲藏动作已暂停。\n\n强回声之外的弱光只帮助辨路，不扩大听觉范围。\n先切断视线，再按 E 躲进柜子；桌底仍会被探测。\n听到敲击检查时及时离开；信标会持续暴露位置。")
		elif status == "paused":
			start_game()
	if event.is_action_pressed("restart") and status in ["won", "lost"]:
		restart()

func finish(won: bool, reason: String) -> void:
	if status != "playing":
		return
	status = "won" if won else "lost"
	player.enabled = false
	objectives.enabled = false
	# Freeze normal logic, but allow the final one-shot sound to finish.
	session.process_mode = Node.PROCESS_MODE_DISABLED
	sound.process_mode = Node.PROCESS_MODE_ALWAYS
	sound.set_physics_process(false)
	sound.clear()
	sound.play_cue("victory" if won else "defeat", player.global_position)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.modal(status, "已撤离 / ESCAPED" if won else "信号中断 / LOST", ("你把黑暗里的信号带了出来。" if won else "它的挥击命中了你。\n听见蓄力声、看到双臂抬起时，侧移或后退。") + "\n\n" + reason + "\n本次探索 %.1f 秒 · R 重新开始" % run_time)

func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _change_setting(key: String, value: float) -> void:
	config[key] = value
	if key == "fov":
		player.camera.fov = value
	elif key == "audio_volume":
		sound.set_playback_volume(value)
