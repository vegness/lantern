extends Control
## 主菜单。
##
## 背景用序章房间的插画铺满，上面压一层自上而下的暖色渐隐，让标题区
## 有足够的对比度。三个入口的文案会跟随存档状态变化 ——
## 没有进度时不出现"继续"。
##
## 界面在代码里构建：只有几个控件，维护一个 .tscn 反而更麻烦，
## 而且这样能保证字体在所有分辨率下都被一致地套上。

const BG_PATH: String = "res://assets/art/bg_cozy_room.png"
const BGM_PATH: String = "res://assets/audio/bgm/theme.wav"

var _buttons: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_menu()
	AudioManager.play_bgm(BGM_PATH, 1.4)


func _build_background() -> void:
	if ResourceLoader.exists(BG_PATH):
		var texture_rect := TextureRect.new()
		texture_rect.texture = load(BG_PATH)
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(texture_rect)

	# 上深下浅的遮罩：标题区压暗，按钮区保持通透
	var shade := ColorRect.new()
	shade.color = Color(0.07, 0.06, 0.12, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var vignette := ColorRect.new()
	vignette.color = Color(0.06, 0.05, 0.10, 0.35)
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)


func _build_menu() -> void:
	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_TOP_LEFT)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 14)
	center.position = Vector2((GameConfig.VIEW_W - 340.0) * 0.5, 148.0)
	center.custom_minimum_size = Vector2(340.0, 0.0)
	add_child(center)

	var title := UITheme.make_label("提灯人", 56, UITheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(title)

	var subtitle := UITheme.make_label("把光，一盏一盏地还回去", 18, UITheme.TEXT_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 26.0)
	center.add_child(spacer)

	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 10)
	center.add_child(_buttons)

	var unlocked := SaveManager.unlocked_index()
	var has_progress := unlocked > 0 or SaveManager.is_cleared("prologue")

	if has_progress:
		_add_button("继续游戏", _on_continue)
	else:
		_add_button("开始游戏", _on_new_game)
	_add_button("选择关卡", _on_level_select)
	_add_button("重置进度", _on_reset)
	_add_button("退出", _on_quit)


func _add_button(text: String, handler: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(300.0, 48.0)
	UITheme.style_button(button)
	button.pressed.connect(handler)
	_buttons.add_child(button)


# ---------------------------------------------------------------------------
# 动作
# ---------------------------------------------------------------------------

func _current_scene_path() -> String:
	var index := clampi(SaveManager.unlocked_index(), 0, GameManager.level_count() - 1)
	return String(GameManager.levels()[index].get("scene", ""))


func _on_continue() -> void:
	await SceneFlow.goto_scene(_current_scene_path(), 0.6)


func _on_new_game() -> void:
	await SceneFlow.goto_scene(String(GameManager.levels()[0].get("scene", "")), 0.6)


func _on_level_select() -> void:
	await SceneFlow.goto_scene("res://scenes/ui/level_select.tscn", 0.4)


func _on_reset() -> void:
	GameManager.reset_all_progress()
	# 重置后重建按钮，让"重置进度"立刻从界面上消失
	if _buttons != null:
		_buttons.queue_free()
	_build_menu()


func _on_quit() -> void:
	get_tree().quit()
