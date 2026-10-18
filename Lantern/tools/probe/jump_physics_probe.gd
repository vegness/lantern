extends Node
## 无头物理探针：在**真实关卡 + 真实物理**里跑一次跳跃，逐物理帧记录状态。
##
## 为什么需要它（而不是只看 DevCapture 截图）：
##   DevCapture 的帧号采样不可靠 —— 保存 1280×720 PNG 会阻塞渲染，
##   相邻两次捕获之间可能跨过十几个物理帧，于是"蓄力段到底有没有时间播"
##   这个问题用截图根本回答不了（实测一帧就跨过了整个蓄力）。
##   这里关掉渲染、按固定物理步进跑，直接断言：
##     1) 蓄力段（SQUAT）真的持续了 JUMP_SQUAT 秒（≈12 个物理帧），
##        而不是"按下即离地"；
##     2) 蓄力期间角色**在地面**（is_on_floor 为真、y 不变）；
##     3) 蓄力段的精灵帧号走满 0→1→2→3（提踵离地那一帧不能被跳过）；
##     4) 起跳后 y 才开始下降。
##
## 用法：run_project_diagnostics(scene_path="res://tools/probe/jump_physics_probe.tscn")

const LEVEL: String = "res://scenes/levels/level_01.tscn"
## 先等角色从出生点的空中落到地面并站稳。
const SETTLE_TICKS: int = 150
## 起跳后继续记录的物理帧数。
const TRACE_TICKS: int = 90

var _player: Node2D
var _visual: Node2D
var _sprite: AnimatedSprite2D
var _tick: int = 0
var _phase: int = 0  # 0=等待落地 1=追踪
var _pressed: bool = false
var _rows: PackedStringArray = PackedStringArray()
var _start_y: float = 0.0
var _floor_ticks: int = 0


func _ready() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8
	var lvl: Node = load(LEVEL).instantiate()
	add_child(lvl)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_player = get_tree().get_first_node_in_group("player") as Node2D
	if _player == null:
		print("PHYSPROBE|ERROR 未找到玩家")
		get_tree().quit()
		return
	_visual = _player.get_node_or_null("Visual") as Node2D
	_sprite = _player.get_node_or_null("Visual/Frames") as AnimatedSprite2D
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	_tick += 1
	var state: int = int(_player.get("state"))
	var vel: Vector2 = _player.get("velocity")
	var on_floor: bool = _player.is_on_floor()

	if _phase == 0:
		# 等落地站稳（IDLE 且在地面）之后再起跳
		if on_floor and state == 0 and not _pressed:
			_floor_ticks += 1
			if _floor_ticks >= 6:
				_phase = 1
				_tick = 0
				_start_y = _player.global_position.y
				Input.action_press("jump")
				_pressed = true
		else:
			_floor_ticks = 0
		return

	# ── 追踪段 ──
	# 前 60 帧一直按住：一旦中途松开，可变跳跃高度会立刻把上升速度砍到 42%，
	# 整个上升段被压成 3~4 帧，就验证不到完整弧线了（第一版正是这样，
	# 顶点在离地后第 4 帧就到了）。
	if _tick == 60:
		Input.action_release("jump")
	var frame: int = _sprite.frame if _sprite != null else -1
	var anim: String = String(_sprite.animation) if _sprite != null else "?"
	_rows.append("%d,%d,%.1f,%.1f,%d,%s,%d" % [
		_tick, state, _player.global_position.y - _start_y, vel.y,
		1 if on_floor else 0, anim, frame])
	if _tick >= TRACE_TICKS:
		_report()
		# 先释放引用再退出，避免关机时把关卡的贴图算成"仍在引用中"，
		# 污染诊断通道（那会让 run_project_diagnostics 报 ok:false）。
		_player = null
		_visual = null
		_sprite = null
		for child in get_children():
			child.queue_free()
		get_tree().quit()


func _report() -> void:
	# 统计：SQUAT 段占了几个物理帧、期间是否在地面、帧号是否走满
	var squat_ticks: int = 0
	var squat_on_floor: int = 0
	var squat_frames: Array = []
	var first_airborne_after_squat: int = -1
	for row in _rows:
		var f := row.split(",")
		var st := int(f[1])
		if st == 2:  # State.SQUAT
			squat_ticks += 1
			squat_on_floor += int(f[4])
			var fr := int(f[6])
			if not squat_frames.has(fr):
				squat_frames.append(fr)
		elif squat_ticks > 0 and first_airborne_after_squat < 0 and int(f[4]) == 0:
			first_airborne_after_squat = int(f[0])
	squat_frames.sort()
	var max_frame: int = int(squat_frames.max()) if not squat_frames.is_empty() else -1
	print("PHYSPROBE|%s" % JSON.stringify({
		"squat_ticks": squat_ticks,
		"squat_all_on_floor": squat_ticks > 0 and squat_on_floor == squat_ticks,
		"squat_frames": squat_frames,
		"squat_reaches_end": max_frame >= 3,
		"airborne_at_tick": first_airborne_after_squat,
	}))
	print("PHYSPROBE_ROWS|" + " ".join(_rows))
