extends CanvasLayer
## 场景转场。
##
## 用一个全屏 ColorRect 覆盖层实现淡入淡出，避免关卡切换时的硬切。
## 覆盖层鼠标穿透，并以 PROCESS_MODE_ALWAYS 运行，暂停时依然有效。

## 遮罩颜色。取夜空的深色而非纯黑，转场时更柔和。
const FADE_COLOR := Color("0e0c1c")

var _cover: ColorRect
var _busy: bool = false


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cover = ColorRect.new()
	_cover.name = "FadeCover"
	_cover.color = FADE_COLOR
	_cover.color.a = 1.0
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cover)
	_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	await fade_in(0.7)


## 遮罩淡入至透明。
func fade_in(duration: float = 0.6) -> void:
	if _cover == null:
		return
	if duration <= 0.0:
		_cover.color.a = 0.0
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_cover, "color:a", 0.0, duration)
	await tween.finished


## 遮罩淡出至不透明。
func fade_out(duration: float = 0.45) -> void:
	if _cover == null:
		return
	if duration <= 0.0:
		_cover.color.a = 1.0
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(_cover, "color:a", 1.0, duration)
	await tween.finished


## 完整转场：淡出 → 切换场景 → 淡入。
func goto_scene(path: String, fade: float = 0.5) -> void:
	if _busy:
		return
	if not ResourceLoader.exists(path):
		push_error("[SceneFlow] 场景不存在：%s" % path)
		return
	_busy = true
	await fade_out(fade)
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("[SceneFlow] 切换场景失败（错误码 %d）：%s" % [err, path])
	await get_tree().process_frame
	await get_tree().process_frame
	await fade_in(fade)
	_busy = false


## 重新载入当前场景（用于重开本关）。
func reload_current(fade: float = 0.35) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var path := scene.scene_file_path
	if path.is_empty():
		return
	await goto_scene(path, fade)


## 转场是否进行中。
func is_busy() -> bool:
	return _busy
