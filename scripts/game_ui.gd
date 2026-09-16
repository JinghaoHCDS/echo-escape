class_name EchoUI
extends CanvasLayer

signal resume_requested
signal restart_requested
signal setting_changed(key: String, value: float)

var root: Control
var objective_label: Label
var room_label: Label
var cooldown_label: Label
var hint_label: Label
var toast_label: Label
var debug_label: Label
var cooldown_bar: ProgressBar
var overlay: ColorRect
var modal_title: Label
var modal_body: Label
var action_button: Button
var sliders: VBoxContainer
var grid: EchoDebugGrid
var toast_time: float = 0.0
var modal_kind: String = "intro"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC"])
	theme.default_font = font
	theme.default_font_size = 24
	theme.set_color("font_shadow_color", "Label", Color(0.0, 0.005, 0.01, 0.85))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 2)
	root.theme = theme
	_label("E C H O  /  E S C A P E", Vector2(56, 36), 22, Color(0.48, 0.75, 0.81))
	room_label = _label("01 / 入口", Vector2(56, 78), 35)
	objective_label = _label("深入机房，用鼓掌寻找信标核心", Vector2(56, 132), 25)
	_label("左键 鼓掌   /   WASD 移动   /   Shift 奔跑   /   E 交互", Vector2(56, 981), 22, Color(0.57, 0.67, 0.7))
	_label("Esc 暂停     F1 调试", Vector2(1510, 1008), 20, Color(0.48, 0.59, 0.63))
	cooldown_label = _label("回声就绪", Vector2(56, 893), 25)
	cooldown_bar = ProgressBar.new()
	cooldown_bar.position = Vector2(56, 939)
	cooldown_bar.size = Vector2(285, 5)
	cooldown_bar.show_percentage = false
	cooldown_bar.max_value = 1.0
	root.add_child(cooldown_bar)
	var cross := _label("·", Vector2(950, 514), 30, Color(0.72, 0.85, 0.85))
	cross.size = Vector2(20, 30)
	hint_label = _label("", Vector2(550, 725), 28)
	hint_label.size.x = 820
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label = _label("", Vector2(390, 235), 28, Color(0.96, 0.66, 0.34))
	toast_label.size = Vector2(1140, 120)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	debug_label = _label("", Vector2(1170, 45), 20, Color(0.79, 0.9, 0.93))
	debug_label.size = Vector2(700, 290)
	debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	grid = EchoDebugGrid.new()
	grid.position = Vector2(1620, 330)
	root.add_child(grid)
	grid.hide()
	debug_label.hide()
	_build_overlay()

func _label(text: String, at: Vector2, size: int, color: Color = Color(0.85, 0.91, 0.91)) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(label)
	return label

func _build_overlay() -> void:
	overlay = ColorRect.new()
	overlay.color = Color(0.008, 0.017, 0.028, 0.96)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)
	var line := ColorRect.new()
	line.position = Vector2(275, 220)
	line.size = Vector2(6, 545)
	line.color = Color(0.33, 0.71, 0.76)
	overlay.add_child(line)
	modal_title = Label.new()
	modal_title.position = Vector2(330, 214)
	modal_title.add_theme_font_size_override("font_size", 76)
	overlay.add_child(modal_title)
	modal_body = Label.new()
	modal_body.position = Vector2(335, 350)
	modal_body.size = Vector2(1210, 325)
	modal_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal_body.add_theme_font_size_override("font_size", 28)
	modal_body.add_theme_color_override("font_color", Color(0.65, 0.77, 0.81))
	overlay.add_child(modal_body)
	action_button = Button.new()
	action_button.position = Vector2(335, 722)
	action_button.size = Vector2(350, 70)
	action_button.pressed.connect(func() -> void:
		if modal_kind in ["intro", "pause"]:
			resume_requested.emit()
		else:
			restart_requested.emit())
	overlay.add_child(action_button)
	sliders = VBoxContainer.new()
	sliders.position = Vector2(1010, 490)
	sliders.size = Vector2(460, 200)
	overlay.add_child(sliders)

func configure(settings: Dictionary) -> void:
	for spec: Array in [["fov", "视野角", 65.0, 105.0, 1.0], ["mouse_sensitivity", "鼠标灵敏度", 0.0007, 0.005, 0.0001], ["audio_volume", "播放音量 · 不影响怪物听觉", 0.0, 1.0, 0.05]]:
		var label := Label.new()
		label.text = str(spec[1])
		label.add_theme_font_size_override("font_size", 19)
		sliders.add_child(label)
		var slider := HSlider.new()
		slider.min_value = float(spec[2])
		slider.max_value = float(spec[3])
		slider.step = float(spec[4])
		slider.value = float(settings[str(spec[0])])
		slider.value_changed.connect(func(value: float) -> void: setting_changed.emit(str(spec[0]), value))
		sliders.add_child(slider)

func modal(kind: String, title: String, body: String) -> void:
	modal_kind = kind
	modal_title.text = title
	modal_body.text = body
	action_button.text = "进入静默建筑" if kind == "intro" else ("继续探索" if kind == "pause" else "[ R ]  重新开始")
	sliders.visible = kind == "pause"
	overlay.show()

func toast(message: String, duration: float = 4.0) -> void:
	toast_label.text = message
	toast_time = duration

func _process(delta: float) -> void:
	if not get_tree().paused:
		toast_time = maxf(0.0, toast_time - delta)
	toast_label.visible = toast_time > 0.0

func update_hud(room: String, remaining: float, maximum: float, prompt: String, alarm: bool) -> void:
	room_label.text = room
	objective_label.text = "信标已启动 · 返回入口撤离" if alarm else "深入机房 · 鼓掌激活信标核心"
	objective_label.modulate = Color(1.0, 0.57, 0.31) if alarm else Color.WHITE
	cooldown_label.text = "左键 / 鼓掌就绪" if remaining <= 0.0 else "回声间歇  %.1f s" % remaining
	cooldown_bar.value = 1.0 - remaining / maximum
	hint_label.text = prompt
