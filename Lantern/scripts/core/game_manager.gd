extends Node
## 关卡流转与进度中枢。
##
## 负责当前关卡索引、计时、萤火收集计数、通关结算与解锁。
## 各关卡脚本通过 start_level / register_lanterns / collect_lantern / finish_level
## 与这里交互，无需自行维护进度状态。

signal level_started(index: int, data: Dictionary)
signal level_finished(index: int, time_sec: float, lanterns: int)
signal lantern_changed(collected: int, total: int)
signal progress_reset()

## 当前关卡索引（对应 GameConfig.LEVELS）。
var current_index: int = 0
## 本关已收集的萤火数。
var lanterns_collected: int = 0
## 本关萤火总数，由关卡在 _ready 中登记。
var lanterns_total: int = 0
## 本关计时（秒）。
var run_time: float = 0.0

var _running: bool = false


func _process(delta: float) -> void:
	# 暂停时不计时，避免结算用时被暂停菜单拉长。
	if _running and not get_tree().paused:
		run_time += delta


# ---------------------------------------------------------------------------
# 关卡查询
# ---------------------------------------------------------------------------

func levels() -> Array[Dictionary]:
	return GameConfig.LEVELS


func level_count() -> int:
	return GameConfig.level_count()


func current_level() -> Dictionary:
	return GameConfig.level_at(current_index)


func current_id() -> String:
	return String(current_level().get("id", ""))


func has_next() -> bool:
	return current_index + 1 < level_count()


func next_index() -> int:
	return mini(current_index + 1, level_count() - 1)


func is_running() -> bool:
	return _running


# ---------------------------------------------------------------------------
# 关卡流程
# ---------------------------------------------------------------------------

## 开始一关：重置计时与收集计数，并广播关卡开始信号。
func start_level(index: int) -> void:
	current_index = clampi(index, 0, level_count() - 1)
	lanterns_collected = 0
	lanterns_total = 0
	run_time = 0.0
	_running = true
	level_started.emit(current_index, current_level())


## 由关卡登记本关萤火总数。
func register_lanterns(total: int) -> void:
	lanterns_total = maxi(total, 0)
	lantern_changed.emit(lanterns_collected, lanterns_total)


## 收集一枚萤火。
func collect_lantern() -> void:
	lanterns_collected += 1
	lantern_changed.emit(lanterns_collected, lanterns_total)


## 完成本关：写入存档并解锁下一关。
func finish_level() -> void:
	if not _running:
		return
	_running = false
	var id := current_id()
	SaveManager.mark_cleared(id, run_time, lanterns_collected)
	if has_next():
		SaveManager.unlock(current_index + 1)
	level_finished.emit(current_index, run_time, lanterns_collected)


## 清空全部进度（设置菜单使用）。
func reset_all_progress() -> void:
	SaveManager.reset_progress()
	current_index = 0
	lanterns_collected = 0
	lanterns_total = 0
	run_time = 0.0
	_running = false
	progress_reset.emit()


## 把秒数格式化为 m:ss。
static func format_time(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	var minutes := floori(float(total) / 60.0)
	return "%d:%02d" % [minutes, total % 60]
