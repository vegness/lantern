extends Control
## 暂停菜单。
##
## 以 PROCESS_MODE_ALWAYS 运行 —— 否则 get_tree().paused = true 之后
## 这个界面本身也会被冻结，按钮就点不动了。

var _root: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 父级是关卡（Node2D）而非 Control，必须用带 offsets 的预设才会算出尺寸
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.04, 0.09, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	_root = VBoxContainer.new()
	# 绝对定位而非 CENTER 预设，理由同 level_result.gd
	_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_root.position = Vector2((GameConfig.VIEW_W - 300.0) * 0.5, 232.0)
	_root.custom_minimum_size = Vector2(300.0, 0.0)
	_root.add_theme_constant_override("separation", 12)
	add_child(_root)

	var title := UITheme.make_label("已暂停", 40, UITheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(title)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 16.0)
	_root.add_child(gap)

	_add_button("继续", _on_resume)
	_add_button("重开本关", _on_restart)
	_add_button("返回主菜单", _on_main_menu)

	var hint := UITheme.make_label("按 Esc 继续", 15, UITheme.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(hint)


func _add_button(text: String, handler: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(300.0, 46.0)
	UITheme.style_button(button, 20)
	button.pressed.connect(handler)
	_root.add_child(button)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		accept_event()
		_on_resume()


func _on_resume() -> void:
	queue_free()


func _on_restart() -> void:
	get_tree().paused = false
	queue_free()
	await SceneFlow.reload_current(0.35)


func _on_main_menu() -> void:
	get_tree().paused = false
	queue_free()
	await SceneFlow.goto_scene("res://scenes/ui/main_menu.tscn", 0.5)
