extends Node
## 存档管理。
##
## 使用 user://lantern_save.json 保存关卡进度、收集情况与音频设置。
## 读档失败或字段缺失时自动回退 / 补齐，保证任何情况下游戏都能正常启动。

const SAVE_PATH: String = "user://lantern_save.json"
const SAVE_VERSION: int = 1

var _data: Dictionary = {}


func _ready() -> void:
	load_game()


## 一份全新的默认存档结构。
func _default_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"unlocked": 0,
		"levels": {},
		"collected": {},
		"settings": {
			"master_db": 0.0,
			"bgm_db": -6.0,
			"sfx_db": -3.0,
			"fullscreen": false,
		},
	}


func load_game() -> void:
	_data = _default_data()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("[SaveManager] 存档无法打开，使用默认数据")
		return
	var raw := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[SaveManager] 存档内容无法解析，使用默认数据")
		return
	_data = _merge_defaults(parsed as Dictionary, _default_data())


## 递归合并：以默认结构为骨架，用存档内容覆盖，并补齐旧版本缺失的字段。
func _merge_defaults(source: Dictionary, defaults: Dictionary) -> Dictionary:
	var result: Dictionary = defaults.duplicate(true)
	for key in source.keys():
		var value: Variant = source[key]
		if result.has(key) and typeof(result[key]) == TYPE_DICTIONARY and typeof(value) == TYPE_DICTIONARY:
			result[key] = _merge_defaults(value as Dictionary, result[key] as Dictionary)
		else:
			result[key] = value
	result["version"] = SAVE_VERSION
	return result


func save_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("[SaveManager] 存档写入失败：%s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(_data, "\t"))
	file.close()


# ---------------------------------------------------------------------------
# 关卡进度
# ---------------------------------------------------------------------------

func unlocked_index() -> int:
	return int(_data.get("unlocked", 0))


func unlock(index: int) -> void:
	if index > unlocked_index():
		_data["unlocked"] = index
		save_game()


func level_record(id: String) -> Dictionary:
	var levels: Dictionary = _data.get("levels", {}) as Dictionary
	return levels.get(id, {}) as Dictionary


func is_cleared(id: String) -> bool:
	return bool(level_record(id).get("cleared", false))


## 记录通关：只在成绩更好时更新最佳用时，萤火数取历史最高。
func mark_cleared(id: String, time_sec: float, lanterns: int) -> void:
	var levels: Dictionary = _data.get("levels", {}) as Dictionary
	var record: Dictionary = levels.get(id, {"cleared": false, "best_time": 0.0, "lanterns": 0}) as Dictionary
	record["cleared"] = true
	record["lanterns"] = maxi(int(record.get("lanterns", 0)), lanterns)
	var best := float(record.get("best_time", 0.0))
	if best <= 0.0 or time_sec < best:
		record["best_time"] = time_sec
	levels[id] = record
	_data["levels"] = levels
	save_game()


# ---------------------------------------------------------------------------
# 收集物
# ---------------------------------------------------------------------------

func collect(key: String) -> void:
	var collected: Dictionary = _data.get("collected", {}) as Dictionary
	collected[key] = true
	_data["collected"] = collected
	save_game()


func has_collected(key: String) -> bool:
	var collected: Dictionary = _data.get("collected", {}) as Dictionary
	return bool(collected.get(key, false))


func collected_count() -> int:
	var collected: Dictionary = _data.get("collected", {}) as Dictionary
	return collected.size()


# ---------------------------------------------------------------------------
# 设置
# ---------------------------------------------------------------------------

func setting(key: String, fallback: Variant = 0.0) -> Variant:
	var settings: Dictionary = _data.get("settings", {}) as Dictionary
	return settings.get(key, fallback)


func set_setting(key: String, value: Variant) -> void:
	var settings: Dictionary = _data.get("settings", {}) as Dictionary
	settings[key] = value
	_data["settings"] = settings
	save_game()


## 只清空进度，保留音频等偏好设置。
func reset_progress() -> void:
	var defaults := _default_data()
	_data["unlocked"] = defaults["unlocked"]
	_data["levels"] = defaults["levels"]
	_data["collected"] = defaults["collected"]
	save_game()
