extends Control
## 关卡选择。
##
## 关卡列表直接来自 GameConfig，新增关卡不需要改这个界面。
## 未解锁的关卡显示为禁用，并给出"先通关前一关"的提示。

const BG_PATH: String = "res://assets/art/bg_dusk_town.png"
const BGM_PATH: String = "res://assets/audio/bgm/theme.wav"

var _list: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_layout()
	AudioManager.play_bgm(BGM_PATH, 1.0)


func _build_background() -> void:
	if ResourceLoader.exists(BG_PATH):
		var texture_rect := TextureRect.new()
		texture_rect.texture = load(BG_PATH)
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(texture_rect)
	var shade := ColorRect.new()
	shade.color = Color(0.06, 0.06, 0.11, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)


func _build_layout() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 12)
	root.position = Vector2((GameConfig.VIEW_W - 520.0) * 0.5, 118.0)
	root.custom_minimum_size = Vector2(520.0, 0.0)
	add_child(root)

	var title := UITheme.make_label("选择关卡", 34, UITheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 12.0)
	root.add_child(gap)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	root.add_child(_list)

	var unlocked := SaveManager.unlocked_index()
	var levels := GameManager.levels()
	for i in levels.size():
		var data := levels[i]
		var id := String(data.get("id", ""))
		var row := _make_row(i, data, id, i <= unlocked)
		_list.add_child(row)

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0.0, 10.0)
	root.add_child(gap2)

	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(520.0, 44.0)
	UITheme.style_button(back, 20)
	back.pressed.connect(_on_back)
	root.add_child(back)


func _make_row(index: int, data: Dictionary, id: String, unlocked: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var button := Button.new()
	button.text = String(data.get("title", id))
	button.custom_minimum_size = Vector2(320.0, 46.0)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	UITheme.style_button(button, 20)
	button.disabled = not unlocked
	if unlocked:
		button.pressed.connect(_on_level_pressed.bind(index))
	row.add_child(button)

	var record := SaveManager.level_record(id)
	var status := "未解锁"
	if unlocked:
		if bool(record.get("cleared", false)):
			status = "已通关  %s  萤火 %d" % [
				GameManager.format_time(float(record.get("best_time", 0.0))),
				int(record.get("lanterns", 0)),
			]
		else:
			status = "未通关"
	var info := UITheme.make_label(status, 16, UITheme.TEXT_DIM if unlocked else Color(UITheme.TEXT_DIM, 0.5))
	info.custom_minimum_size = Vector2(180.0, 46.0)
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(info)

	return row


func _on_level_pressed(index: int) -> void:
	var scene := String(GameManager.levels()[index].get("scene", ""))
	if scene.is_empty():
		return
	await SceneFlow.goto_scene(scene, 0.5)


func _on_back() -> void:
	await SceneFlow.goto_scene("res://scenes/ui/main_menu.tscn", 0.4)
