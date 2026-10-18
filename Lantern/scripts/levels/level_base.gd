class_name LevelBase
extends Node2D
## 关卡基类。
##
## 统一负责：解析关卡索引、应用光照氛围、绑定玩家、统计萤火、处理坠落复位、
## 暂停与通关流程。各关卡脚本继承本类并实现 _setup_level() 即可，
## 不必重复这些通用逻辑。
##
## 约定场景结构（顺序即渲染层级）：
##   Level (Node2D, 挂本脚本或其子类)
##   ├── Backdrop       远景 / 天空（视差）
##   ├── CanvasModulate 全局压暗，颜色取自关卡数据
##   ├── World          地形、机关、装饰
##   ├── Player         玩家实例
##   └── (HUD 由本类在运行时挂载)

const HUD_SCENE: String = "res://scenes/ui/hud.tscn"
const PAUSE_SCENE: String = "res://scenes/ui/pause_menu.tscn"
const RESULT_SCENE: String = "res://scenes/ui/level_result.tscn"
## 关卡默认背景音乐。音频是程序化合成的，缺失时 AudioManager 会静默跳过。
const DEFAULT_BGM: String = "res://assets/audio/bgm/theme.wav"

## 关卡 id（对应 GameConfig.LEVELS 中的 id）。留空则按场景路径自动推断。
@export var level_id: String = ""
## 玩家落到这个 Y 值以下即判定坠落并复位。
@export var kill_y: float = 1600.0
## 本关背景音乐。留空则不播放。
@export var bgm_path: String = ""

var player: Player = null
var index: int = 0

var _hud: CanvasLayer = null
var _ui_layer: CanvasLayer = null
var _paused: bool = false
var _finished: bool = false


func _ready() -> void:
	add_to_group("level")
	index = _resolve_index()
	GameManager.start_level(index)
	_apply_theme()
	_bind_player()
	# _setup_level 由子类搭建关卡内容（含萤火等收集物），
	# 因此必须先于收集物统计执行
	_setup_level()
	_register_collectibles()
	_spawn_hud()
	_play_bgm()
	_apply_camera_feel()


## 统一相机手感。
##
## 不做平滑时，角色每一次加速、每一级台阶、每一次落地的速度突变都会让
## 整幅画面硬跟着跳 —— 这是"场景移动看起来很奇怪"的最常见来源。
## 平滑跟随 + 边界软化能让画面稳下来，但速度不能太低，否则操作会显得拖沓。
func _apply_camera_feel() -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.5
	camera.limit_smoothed = true


## 子类覆盖此方法来完成关卡自身的搭建（摆放机关等）。
func _setup_level() -> void:
	pass


func _process(_delta: float) -> void:
	if player != null and is_instance_valid(player):
		if player.global_position.y > kill_y:
			respawn_player()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not _finished:
		toggle_pause()
	elif event.is_action_pressed("restart") and not _finished:
		restart_level()


# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func _resolve_index() -> int:
	if not level_id.is_empty():
		var found := GameConfig.level_index_of(level_id)
		if found >= 0:
			return found
	var path := scene_file_path
	for i in GameConfig.level_count():
		if String(GameConfig.LEVELS[i].get("scene", "")) == path:
			return i
	return GameManager.current_index


func _apply_theme() -> void:
	var data := GameManager.current_level()
	var modulate := get_node_or_null("CanvasModulate") as CanvasModulate
	if modulate != null:
		var ambient: Variant = data.get("ambient", Color.WHITE)
		if ambient is Color:
			modulate.color = ambient


func _bind_player() -> void:
	var node := get_tree().get_first_node_in_group("player")
	if node is Player:
		player = node as Player
	else:
		push_warning("[LevelBase] 场景中未找到玩家（需加入 player 组）")
	if player != null:
		player.lantern_toggled.connect(_on_lantern_toggled)


func _register_collectibles() -> void:
	# 收集物是在 _setup_level 中刚刚 add_child 的，延迟一帧统计更稳妥
	await get_tree().process_frame
	var total := get_tree().get_nodes_in_group("lantern_pickup").size()
	GameManager.register_lanterns(total)


func _spawn_hud() -> void:
	if not ResourceLoader.exists(HUD_SCENE):
		return
	var packed := load(HUD_SCENE) as PackedScene
	if packed == null:
		return
	_hud = packed.instantiate() as CanvasLayer
	if _hud != null:
		add_child(_hud)


## 关卡内的弹出界面（暂停、结算）必须挂在 CanvasLayer 下。
##
## 原因：Control 直接挂在关卡（Node2D）下时，它的绘制会继承父级的
## CanvasItem 变换，也就是会被 Camera2D 带走 —— 界面会被画到世界坐标的
## 某个角落而不是屏幕上，表现为"代码执行了但什么都看不见"。
## CanvasLayer 自成一个 canvas，不受相机影响。
func _ensure_ui_layer() -> CanvasLayer:
	if _ui_layer == null or not is_instance_valid(_ui_layer):
		_ui_layer = CanvasLayer.new()
		_ui_layer.name = "UILayer"
		_ui_layer.layer = 20
		add_child(_ui_layer)
	return _ui_layer


func _play_bgm() -> void:
	var path := bgm_path if not bgm_path.is_empty() else DEFAULT_BGM
	AudioManager.play_bgm(path, 1.0)


# ---------------------------------------------------------------------------
# 运行时事件
# ---------------------------------------------------------------------------

func _on_lantern_toggled(_on: bool) -> void:
	pass


## 玩家坠落后复位。
func respawn_player() -> void:
	if player == null:
		return
	player.respawn()
	_shake_hud()


func _shake_hud() -> void:
	if _hud != null and _hud.has_method("flash"):
		_hud.call("flash")


## 由关卡中的终点灯座调用。
func on_goal_reached(_goal: Node) -> void:
	# 稍作停顿，让玩家看清"灯亮了"这件事，再进入结算
	await get_tree().create_timer(1.25).timeout
	finish_level()


## 由关卡中的终点灯座调用。
func finish_level() -> void:
	if _finished:
		return
	_finished = true
	GameManager.finish_level()
	if player != null:
		player.lock_input(9999.0)
		if _hud != null and _hud.has_method("set_visible_hud"):
			_hud.call("set_visible_hud", false)
	_show_result()


func _show_result() -> void:
	if not ResourceLoader.exists(RESULT_SCENE):
		return
	var packed := load(RESULT_SCENE) as PackedScene
	if packed == null:
		return
	var result := packed.instantiate()
	_ensure_ui_layer().add_child(result)


## 重开本关。
func restart_level() -> void:
	_paused = false
	get_tree().paused = false
	await SceneFlow.reload_current(0.3)


# ---------------------------------------------------------------------------
# 暂停
# ---------------------------------------------------------------------------

func toggle_pause() -> void:
	if _paused:
		resume_game()
	else:
		pause_game()


func pause_game() -> void:
	if _paused:
		return
	_paused = true
	get_tree().paused = true
	if ResourceLoader.exists(PAUSE_SCENE):
		var packed := load(PAUSE_SCENE) as PackedScene
		if packed != null:
			var menu := packed.instantiate()
			menu.name = "PauseMenu"
			menu.tree_exited.connect(_on_pause_menu_closed)
			_ensure_ui_layer().add_child(menu)


func resume_game() -> void:
	_paused = false
	get_tree().paused = false
	if _ui_layer != null and is_instance_valid(_ui_layer):
		var menu := _ui_layer.get_node_or_null("PauseMenu")
		if menu != null:
			menu.queue_free()


func _on_pause_menu_closed() -> void:
	_paused = false
	get_tree().paused = false


func is_finished() -> bool:
	return _finished
