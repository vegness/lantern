extends Node
## 无头探针：验证跳跃分阶段锁帧、提灯锚点查表、以及**状态枚举的镜像映射**。
##
## 为什么需要它：
## 1) `set_motion` 里"先清零、再调用 _play()"的顺序 bug 会让下落 / 落地阶段的
##    计时器被覆盖成哨兵值，帧号被 clamp 到区间末帧。该缺陷不报错、不改状态机、
##    诊断也全绿，只有把每一帧的帧号打出来才能证伪。
## 2) `player_visual.gd` 用 `S_*` 常量镜像 `Player.State` 的枚举顺序。两边靠约定
##    对齐，一旦有人只改了一边就会**静默播错动画**（不报任何错）。这里逐项对拍。
##
## 因此这里关掉引擎的自动 _process，手动喂 delta，记录整个跳跃过程的帧号序列。

const DT: float = 1.0 / 60.0


func _ready() -> void:
	var scr: GDScript = load("res://scripts/player/player_visual.gd")
	var v: Node2D = scr.new()
	add_child(v)
	await get_tree().process_frame
	v.set_process(false)
	var sp: AnimatedSprite2D = v.get_node("Frames")

	var report: Dictionary = {}

	# ① 状态枚举镜像映射：两边必须逐项相等
	report["state_map"] = _check_state_map(scr)

	# ② 四段锁帧是否逐帧推进（修复前 fall/land 会恒定在区间末帧）
	report["squat"] = _record(v, sp, 2, 12)
	report["rise"] = _record(v, sp, 3, 30)
	report["fall"] = _record(v, sp, 4, 30)
	report["land"] = _record(v, sp, 5, 14)

	# ③ 提灯锚点查表：把帧号摆到 run 序列的代表帧，检查锚点确实随帧变化
	var run_pts: Array = []
	for f in [0, 4, 8]:
		sp.frame = f
		v.set_motion(1, 0.0, Vector2(250.0, 0.0))
		run_pts.append(str(v.get("lantern_anchor")))
	report["run_anchor_by_frame"] = run_pts

	print("PROBE|", JSON.stringify(report))
	get_tree().quit()


## 把 player_visual.gd 的 S_* 常量与 Player.State 逐项对拍。
func _check_state_map(scr: GDScript) -> Dictionary:
	var consts: Dictionary = scr.get_script_constant_map()
	var expected: Dictionary = {
		"S_IDLE": Player.State.IDLE,
		"S_RUN": Player.State.RUN,
		"S_SQUAT": Player.State.SQUAT,
		"S_JUMP": Player.State.JUMP,
		"S_FALL": Player.State.FALL,
		"S_LAND": Player.State.LAND,
		"S_LOCKED": Player.State.LOCKED,
	}
	var out: Dictionary = {}
	for key in expected:
		var got: int = consts.get(key, -999)
		var want: int = expected[key]
		out[key] = "OK" if got == want else "MISMATCH(visual=%d player=%d)" % [got, want]
	return out


## 进入指定状态后连续推进 n 帧，返回每帧的精灵帧号。
func _record(v: Node2D, sp: AnimatedSprite2D, state: int, n: int) -> Array:
	v.set_motion(state, 0.0, Vector2(0.0, 300.0))
	var out: Array = []
	for i in n:
		v.call("_process", DT)
		out.append(sp.frame)
	return out
