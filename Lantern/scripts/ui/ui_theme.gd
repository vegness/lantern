class_name UITheme
extends RefCounted
## UI 共用的字体与配色工具。
##
## 字体只加载一次并缓存 —— 霞鹜文楷接近 25MB，反复 load 会明显拖慢界面切换。
## 所有界面统一走这里，避免每个脚本各写一套 add_theme_*_override。

const FONT_PATH: String = "res://assets/fonts/LXGWWenKai-Regular.ttf"

const TEXT := Color("f6ecdc")
const TEXT_DIM := Color("c9bda9")
const ACCENT := Color("ffd88a")
const ACCENT_DEEP := Color("e8a15e")
const PANEL := Color(0.10, 0.09, 0.16, 0.86)
const PANEL_HOVER := Color(0.20, 0.17, 0.28, 0.94)
const OUTLINE := Color(0.05, 0.04, 0.09, 0.9)

static var _font: Font = null


## 取共用字体。资源缺失时返回 null，调用方应容忍（Label 会用引擎默认字体）。
static func font() -> Font:
	if _font == null and ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH) as Font
	return _font


## 把一个 Label 调成游戏内统一风格（带描边，保证在明亮背景上也读得清）。
static func style_label(label: Label, size_px: int, color: Color = TEXT) -> void:
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", OUTLINE)
	label.add_theme_constant_override("outline_size", 5)
	var f := font()
	if f != null:
		label.add_theme_font_override("font", f)


## 新建一个已套好样式的 Label。
static func make_label(text: String, size_px: int, color: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = text
	style_label(label, size_px, color)
	return label


## 给按钮套上统一的字体与配色。
static func style_button(button: Button, size_px: int = 22) -> void:
	var f := font()
	if f != null:
		button.add_theme_font_override("font", f)
	button.add_theme_font_size_override("font_size", size_px)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", ACCENT)
	button.add_theme_color_override("font_pressed_color", ACCENT_DEEP)
	button.add_theme_color_override("font_disabled_color", Color(TEXT_DIM, 0.45))
	button.add_theme_color_override("font_focus_color", ACCENT)

	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		match state:
			"hover":
				box.bg_color = PANEL_HOVER
			"pressed":
				box.bg_color = Color(0.28, 0.22, 0.30, 0.95)
			"focus":
				box.bg_color = PANEL_HOVER
				box.border_color = Color(ACCENT, 0.7)
				box.set_border_width_all(2)
			"disabled":
				box.bg_color = Color(0.12, 0.11, 0.16, 0.5)
			_:
				box.bg_color = PANEL
		box.corner_radius_top_left = 10
		box.corner_radius_top_right = 10
		box.corner_radius_bottom_left = 10
		box.corner_radius_bottom_right = 10
		box.content_margin_left = 22.0
		box.content_margin_right = 22.0
		box.content_margin_top = 9.0
		box.content_margin_bottom = 9.0
		button.add_theme_stylebox_override(state, box)
