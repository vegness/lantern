extends Control
## 关卡结算。
##
## 淡入显示本关成绩，并根据是否还有下一关调整按钮 —— 最后一关（尾声）
## 给出"返回主菜单"而不是"下一关"，避免走进死路。

const FADE_IN: float = 0.55
const PANEL_WIDTH: float = 420.0

var _panel: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 本界面由关卡的 CanvasLayer 承载（见 LevelBase._ensure_ui_layer），
	# 因此这里的 anchors 会基于视口正确算出尺寸。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modulate.a = 0.0

	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.04, 0.09, 0.0)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	_build_panel()

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, FADE_IN)
	tween.tween_property(shade, "color:a", 0.74, FADE_IN)


func _build_panel() -> void:
	_panel = VBoxContainer.new()
	# 用绝对定位而不是 CENTER 预设：预设依赖父级 anchorable rect，
	# 在不同父级类型下的表现不一致，而本项目的逻辑分辨率是固定的。
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2((GameConfig.VIEW_W - PANEL_WIDTH) * 0.5, 186.0)
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	_panel.add_theme_constant_override("separation", 10)
	add_child(_panel)

	var title := UITheme.make_label("本关完成", 42, UITheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(title)

	var subtitle := UITheme.make_label(GameManager.current_level().get("title", ""), 18, UITheme.TEXT_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(subtitle)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 14.0)
	_panel.add_child(gap)

	_panel.add_child(_make_stat("用时", GameManager.format_time(GameManager.run_time)))
	_panel.add_child(_make_stat("萤火", "%d / %d" % [GameManager.lanterns_collected, GameManager.lanterns_total]))

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0.0, 18.0)
	_panel.add_child(gap2)

	if GameManager.has_next():
		_add_button("下一关", _on_next)
	_add_button("重玩本关", _on_retry)
	_add_button("返回主菜单", _on_main_menu)


func _make_stat(label_text: String, value_text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var key := UITheme.make_label(label_text, 20, UITheme.TEXT_DIM)
	key.custom_minimum_size = Vector2(120.0, 0.0)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(key)
	var value := UITheme.make_label(value_text, 22, UITheme.TEXT)
	value.custom_minimum_size = Vector2(150.0, 0.0)
	row.add_child(value)
	return row


func _add_button(text: String, handler: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(420.0, 46.0)
	UITheme.style_button(button, 20)
	button.pressed.connect(handler)
	_panel.add_child(button)


func _on_next() -> void:
	var index := GameManager.next_index()
	var scene := String(GameManager.levels()[index].get("scene", ""))
	if scene.is_empty():
		await _on_main_menu()
		return
	await SceneFlow.goto_scene(scene, 0.5)


func _on_retry() -> void:
	await SceneFlow.reload_current(0.4)


func _on_main_menu() -> void:
	await SceneFlow.goto_scene("res://scenes/ui/main_menu.tscn", 0.5)
