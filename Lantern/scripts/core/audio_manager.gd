extends Node
## 音频管理。
##
## BGM 走单独总线并支持淡入淡出；音效使用固定数量的播放器池轮转复用，
## 避免频繁创建节点。音频总线在运行时创建，不需要额外的总线布局资源。
## 资源缺失时静默跳过，保证美术/音频尚未就位时游戏依然可运行。

const BUS_MASTER: String = "Master"
const BUS_BGM: String = "BGM"
const BUS_SFX: String = "SFX"

## 音效播放器数量。超出时覆盖最早使用的一路。
const SFX_VOICES: int = 10

var _bgm: AudioStreamPlayer
var _sfx: Array[AudioStreamPlayer] = []
var _sfx_cursor: int = 0
var _current_bgm_path: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus(BUS_BGM)
	_ensure_bus(BUS_SFX)

	_bgm = AudioStreamPlayer.new()
	_bgm.name = "BGMPlayer"
	_bgm.bus = BUS_BGM
	_bgm.finished.connect(_on_bgm_finished)
	add_child(_bgm)

	for i in SFX_VOICES:
		var player := AudioStreamPlayer.new()
		player.name = "SFX%02d" % i
		player.bus = BUS_SFX
		add_child(player)
		_sfx.append(player)

	apply_settings()


func _ensure_bus(bus_name: String) -> int:
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		return index
	AudioServer.add_bus()
	index = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, BUS_MASTER)
	return index


## 读取存档中的音量设置并应用。
func apply_settings() -> void:
	_set_bus_db(BUS_MASTER, float(SaveManager.setting("master_db", 0.0)))
	_set_bus_db(BUS_BGM, float(SaveManager.setting("bgm_db", -6.0)))
	_set_bus_db(BUS_SFX, float(SaveManager.setting("sfx_db", -3.0)))


func _set_bus_db(bus_name: String, db: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, db)


## 播放背景音乐。同一路径已在播放时不重复触发。
func play_bgm(path: String, fade: float = 0.8) -> void:
	if path == _current_bgm_path and _bgm.playing:
		return
	var stream := _load_safe(path)
	if stream == null:
		return
	if _bgm.playing and fade > 0.0:
		var tween := create_tween()
		tween.tween_property(_bgm, "volume_db", -40.0, fade * 0.5)
		await tween.finished
	_current_bgm_path = path
	_bgm.stream = stream
	_bgm.volume_db = (-40.0 if fade > 0.0 else 0.0)
	_bgm.play()
	if fade > 0.0:
		var tween_in := create_tween()
		tween_in.tween_property(_bgm, "volume_db", 0.0, fade)


func stop_bgm(fade: float = 0.6) -> void:
	if not _bgm.playing:
		_current_bgm_path = ""
		return
	_current_bgm_path = ""
	if fade <= 0.0:
		_bgm.stop()
		return
	var tween := create_tween()
	tween.tween_property(_bgm, "volume_db", -40.0, fade)
	await tween.finished
	_bgm.stop()


## 程序化合成的 WAV 没有设置循环点，这里在播完后重播，实现无缝循环。
func _on_bgm_finished() -> void:
	if not _current_bgm_path.is_empty():
		_bgm.volume_db = 0.0
		_bgm.play()


## 播放一次性音效。pitch 可用于随机化（如脚步、拾取）。
func play_sfx(path: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream := _load_safe(path)
	if stream == null:
		return
	var player := _sfx[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


## 安全加载：路径为空或资源不存在时返回 null，绝不抛错。
func _load_safe(path: String) -> AudioStream:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var res := load(path)
	if res is AudioStream:
		return res as AudioStream
	return null
