extends Node
## 开发期截图助手（Autoload）。
##
## 仅在命令行显式请求时生效，正常游玩时完全惰性，不产生任何开销。
##
## 用法（参数放在 `--` 之后，通过 user args 传入）：
##   Godot_v4.6.1-stable_mono_win64.exe --path <项目目录> -- \
##       --capture=verify/l1.png --capture-frame=90
##
## 第 capture-frame 帧渲染完成后，把整个视口保存为 PNG 并退出。
## 这是本项目"能真正看到画面"的验证手段：其余 MCP 工具都是无头运行，无法出图。
##
## 动作序列验证需要一次运行里抓多个时刻（起跳/顶点/下落/落地），
## 否则每次都要重启进程、还要赌物理步进的相位，所以支持多帧：
##   --capture=verify/jump.png --capture-frames=24,34,44,54 --hold=jump+move_right,4
## 多帧模式下文件名会插入帧号后缀：verify/jump_f024.png、jump_f034.png …
##
## --hold 支持用 `+` 连接多个动作（同时按住），`,` 之后是起始帧。

var _target_path: String = ""
## 需要截取的全部帧号（升序、去重）。
var _target_frames: Array[int] = []
## 请求的帧数（>1 表示多帧模式，文件名带 _fNNN 后缀）。
var _requested_count: int = 0
var _counter: int = 0
var _active: bool = false
var _log_lines: PackedStringArray = PackedStringArray()
## 可选：截图前把玩家传送到指定世界坐标（用于检查关卡中段）。
var _spawn: Vector2 = Vector2.INF
var _spawn_applied: bool = false
## 可选：全程按住的输入动作（可多个，同时按住），用于截取跑动/跳跃这类需要输入的姿态。
var _hold_actions: PackedStringArray = PackedStringArray()
## 可选：从第几帧开始按住（默认第 4 帧，等关卡搭好）。
var _hold_from: int = 4
var _hold_applied: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for arg in args:
		if arg.begins_with("--capture="):
			_target_path = arg.substr("--capture=".length())
		elif arg.begins_with("--capture-frames="):
			for part in arg.substr("--capture-frames=".length()).split(","):
				var f := part.strip_edges().to_int()
				if f > 0 and not _target_frames.has(f):
					_target_frames.append(f)
		elif arg.begins_with("--capture-frame="):
			var single := maxi(1, arg.substr("--capture-frame=".length()).to_int())
			if not _target_frames.has(single):
				_target_frames.append(single)
		elif arg.begins_with("--spawn="):
			var parts := arg.substr("--spawn=".length()).split(",")
			if parts.size() >= 2:
				_spawn = Vector2(parts[0].to_float(), parts[1].to_float())
		elif arg.begins_with("--hold="):
			var hold_parts := arg.substr("--hold=".length()).split(",")
			for a in hold_parts[0].split("+"):
				if not a.is_empty():
					_hold_actions.append(a)
			if hold_parts.size() >= 2:
				_hold_from = maxi(1, hold_parts[1].to_int())
	_target_frames.sort()
	_requested_count = _target_frames.size()
	_active = not _target_path.is_empty() and not _target_frames.is_empty()
	if _active:
		_log("请求截图：帧 %s → %s" % [str(_target_frames), _target_path])


func _process(_delta: float) -> void:
	if not _active:
		return
	_counter += 1
	# 等关卡搭好之后再传送，否则玩家可能还没创建
	if not _spawn_applied and _spawn != Vector2.INF and _counter >= 4:
		_spawn_applied = true
		var player := get_tree().get_first_node_in_group("player")
		if player is Node2D:
			(player as Node2D).global_position = _spawn
			_log("玩家已传送至 %s" % str(_spawn))
	if not _hold_actions.is_empty() and _counter >= _hold_from and not _hold_applied:
		_hold_applied = true
		for action in _hold_actions:
			Input.action_press(action)
		_log("开始按住 %s" % ",".join(_hold_actions))
	if _counter >= _target_frames[-1]:
		_active = false
		_finish()
		return
	if _target_frames.has(_counter):
		_target_frames.erase(_counter)
		_grab(_counter)


## 最后一帧：把剩余帧号写完再退出。
func _finish() -> void:
	await RenderingServer.frame_post_draw
	for index in _target_frames:
		_write(index)
	_target_frames.clear()
	_flush_log()
	get_tree().quit(0)


## 中间帧：只保存，不退出。
func _grab(index: int) -> void:
	await RenderingServer.frame_post_draw
	_write(index)


func _write(index: int) -> void:
	# 逐帧记录"当前播放的是哪条动画的第几帧"，这样一份日志就能证明
	# 分阶段锁帧真的走过了每一个姿势，而不只是看最后一张截图。
	_log_player_screen_rect()
	var image: Image = get_viewport().get_texture().get_image()
	var abs_path: String = ProjectSettings.globalize_path("res://") + _path_for(index)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var err := image.save_png(abs_path)
	if err == OK:
		_log("已保存 %s 尺寸=%s" % [abs_path, str(image.get_size())])
	else:
		_log("保存失败 idx=%d 错误码=%d" % [index, err])


## 单帧模式沿用原文件名；多帧模式在扩展名前插入 _fNNN，避免互相覆盖。
func _path_for(index: int) -> String:
	if _requested_count <= 1:
		return _target_path
	var dot := _target_path.rfind(".")
	if dot <= 0:
		return "%s_f%03d" % [_target_path, index]
	return "%s_f%03d%s" % [_target_path.substr(0, dot), index, _target_path.substr(dot)]


## 记录玩家在**视口像素空间**的矩形。
##
## 为什么需要：截图是整幅视口，而角色只占其中几十像素。后续要做
## "游戏内像素 vs Blender 源帧像素"的定量对比（比如判断角色是否被
## 二次照明提亮），必须知道该去截图的哪一块取样，否则只能靠肉眼猜。
func _log_player_screen_rect() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		_log("未找到玩家节点，跳过屏幕矩形记录")
		return
	var sprite := player.get_node_or_null("Visual/Frames") as AnimatedSprite2D
	var xform := get_viewport().get_canvas_transform()
	var anchor: Vector2 = xform * player.global_position
	if sprite == null:
		_log("玩家屏幕锚点 %s（未取到精灵节点）" % str(anchor))
		return
	var tex: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if tex == null:
		_log("玩家屏幕锚点 %s（精灵当前帧无纹理）" % str(anchor))
		return
	var size_px: Vector2 = tex.get_size() * sprite.scale
	var visual := sprite.get_parent() as Node2D
	# Sprite2D.offset 的单位是**纹理像素**（缩放前的局部空间），
	# 必须乘上「精灵自身缩放 × 父节点缩放」才换算成世界单位。
	# 第一版漏了这个乘法，矩形中心因此偏了 200 多像素，
	# 用它去和源帧做像素对比会得到"完全对不上"的假结论。
	var world_offset: Vector2 = sprite.offset * sprite.scale * visual.scale
	var center_world: Vector2 = visual.global_position + world_offset.rotated(visual.global_rotation)
	var center: Vector2 = xform * center_world
	var half: Vector2 = size_px * 0.5
	_log("玩家屏幕矩形 left=%d top=%d right=%d bottom=%d 尺寸=%dx%d 缩放=%.3f 动画=%s 帧=%d" % [
		int(round(center.x - half.x)), int(round(center.y - half.y)),
		int(round(center.x + half.x)), int(round(center.y + half.y)),
		int(round(size_px.x)), int(round(size_px.y)), sprite.scale.x,
		String(sprite.animation), sprite.frame])


## 把关键信息写入 verify/capture_log.txt。
## 原因：Windows 上的 Godot 是 GUI 子系统进程，stdout 不会回传到调用方，
## 所以必须自行落盘才能读到运行信息。
func _log(message: String) -> void:
	_log_lines.append(message)
	print("[DevCapture] ", message)


func _flush_log() -> void:
	var log_path: String = ProjectSettings.globalize_path("res://") + "verify/capture_log.txt"
	DirAccess.make_dir_recursive_absolute(log_path.get_base_dir())
	var file := FileAccess.open(log_path, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_log_lines))
		file.close()
