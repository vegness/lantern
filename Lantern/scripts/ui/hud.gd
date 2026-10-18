extends CanvasLayer
## 关卡抬头显示。
##
## 刻意做得克制：常态下只显示萤火计数与计时，交互提示仅在靠近可交互物时淡入。
## 控件全部在代码里构建 —— 为三个 Label 维护一个庞大的 .tscn 并不划算，
## 而且程序化创建能保证字体在任何分辨率下都一致应用。

const FONT_PATH: String = "res://assets/fonts/LXGWWenKai-Regular.ttf"

const PANEL_BG := Color(0.09, 0.08, 0.15, 0.42)
const TEXT_COLOR := Color("f6ecdc")

var _font: Font = null

var _counter: Label = null
var _timer: Label = null
var _prompt: Label = null
var _prompt_box: PanelContainer = null
var _flash: ColorRect = null

var _prompt_alpha: float = 0.0


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_font()
	_build()

	GameManager.lantern_changed.connect(_on_lantern_changed)
	_on_lantern_changed(GameManager.lanterns_collected, GameManager.lanterns_total)
	set_process(true)


func _process(delta: float) -> void:
	if _timer != null:
		_timer.text = GameManager.format_time(GameManager.run_time)

	# 交互提示的透明度做平滑过渡，避免靠近时突兀地闪现
	var target := 1.0 if _prompt_target() != null else 0.0
	if not is_equal_approx(_prompt_alpha, target):
		_prompt_alpha = move_toward(_prompt_alpha, target, delta * 6.0)
		if _prompt_box != null:
			_prompt_box.modulate.a = _prompt_alpha


func _prompt_target() -> Node:
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("get_interact_target"):
		return player.call("get_interact_target")
	return null


# ---------------------------------------------------------------------------
# 构建
# ---------------------------------------------------------------------------

func _load_font() -> void:
	if ResourceLoader.exists(FONT_PATH):
		var res := load(FONT_PATH)
		if res is Font:
			_font = res as Font


func _make_label(size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.06, 0.05, 0.1, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	if _font != null:
		label.add_theme_font_override("font", _font)
	return label


func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# 顶部左侧：萤火计数
	var top_left := HBoxContainer.new()
	top_left.position = Vector2(28.0, 22.0)
	top_left.add_theme_constant_override("separation", 8)
	root.add_child(top_left)

	var lantern_icon := LanternCountIcon.new()
	lantern_icon.custom_minimum_size = Vector2(22.0, 22.0)
	top_left.add_child(lantern_icon)

	_counter = _make_label(22, TEXT_COLOR)
	top_left.add_child(_counter)

	# 顶部右侧：计时
	_timer = _make_label(20, Color(TEXT_COLOR, 0.8))
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_timer.position = Vector2(-120.0, 24.0)
	_timer.custom_minimum_size = Vector2(96.0, 28.0)
	root.add_child(_timer)

	# 底部中央：交互提示
	_prompt_box = PanelContainer.new()
	_prompt_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_box.position = Vector2(0.0, -96.0)
	_prompt_box.modulate.a = 0.0
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	_prompt_box.add_theme_stylebox_override("panel", style)
	root.add_child(_prompt_box)

	_prompt = _make_label(18, TEXT_COLOR)
	_prompt_box.add_child(_prompt)

	# 全屏闪烁层（复位时的反馈）
	_flash = ColorRect.new()
	_flash.color = Color(0.85, 0.78, 0.95, 0.0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)


# ---------------------------------------------------------------------------
# 对外接口
# ---------------------------------------------------------------------------

func _on_lantern_changed(collected: int, total: int) -> void:
	if _counter == null:
		return
	if total <= 0:
		_counter.text = "萤火  %d" % collected
	else:
		_counter.text = "萤火  %d / %d" % [collected, total]


## 由 Player 调用，传入当前可交互目标（可为 null）。
func show_for(target: Node) -> void:
	if _prompt == null:
		return
	if target == null:
		return
	var text := ""
	if target.has_method("get_prompt_text"):
		text = String(target.call("get_prompt_text"))
	_prompt.text = text


## 复位 / 受击时的全屏闪烁。
func flash() -> void:
	if _flash == null:
		return
	_flash.color.a = 0.32
	var tween := create_tween()
	tween.tween_property(_flash, "color:a", 0.0, 0.5).set_trans(Tween.TRANS_SINE)


func set_visible_hud(visible_state: bool) -> void:
	for child in get_children():
		if child is Control:
			(child as Control).visible = visible_state


## 萤火计数旁的小图标。用自绘而不是找一张贴图：一个亮点加一圈柔光即可。
class LanternCountIcon:
	extends Control

	const GLOW := Color("ffd88a")

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, 10.0, Color(GLOW, 0.10))
		draw_circle(c, 7.0, Color(GLOW, 0.22))
		draw_circle(c, 4.4, Color("ffcf7a"))
		draw_circle(c + Vector2(-1.2, -1.2), 2.2, Color("fff6d8"))
