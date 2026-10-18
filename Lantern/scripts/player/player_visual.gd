extends Node2D
## 角色外观：播放 Blender 渲染的序列帧。
##
## 为什么放弃程序化绘制：横版角色的"有机感"来自每一帧都是一张完整的、
## 连续的形。用几何部件拼装的骨骼，关节交界处无论怎么优化都会残留
## 接缝感，而 3D 网格经骨骼形变后渲染出来是连续曲面，从原理上不存在
## 这个问题。这也是《死亡细胞》一类 2D 游戏的实际做法。
##
## 帧序列由 tools/blender/animate_kid.py 生成，相机与取景参数写在
## 那边的 build_camera / setup_render 里，下面的常量必须与之保持一致。

const CLIP_ROOT: String = "res://assets/art/kid/"

## 渲染设置（与 animate_kid.py 的 setup_render / build_camera 对应）
const IMG_W: float = 400.0
const IMG_H: float = 480.0
## 脚底在图像中的高度比例。相机竖向取景 z ∈ [-0.39, 1.33]，
## 世界 z=0（脚底）落在图像约 77.7% 处 —— 由 idle/001.png 的包围盒实测得出。
const FOOT_RATIO: float = 0.7771
## 角色在渲染图中的实际像素高度与横向中心（同样来自实测）。
## 这两个值必须以图像实测为准，凭相机参数反推会有十几个百分点的偏差。
## 注意：分辨率从 200×240 提到 400×480 时，脚底的像素高度只放大 1.98 倍
## （不是整 2 倍，抗锯齿边缘的 alpha>0 判定会带来约 1% 的差异），
## 所以这里是 307 而非 310。
const RENDERED_HEIGHT: float = 307.0
const RENDERED_CENTER_X: float = 192.0
## 角色在游戏中应有的高度（世界单位）
const TARGET_HEIGHT: float = 47.0

const CLIP_COUNTS := {"idle": 9, "run": 9, "jump": 16}

# jump 序列的分段（0 基帧号）。与 animate_kid.py 的 poses_jump() 四段等分对应：
#   图像 1..4   = 地面蓄力（下沉 → 深蹲/双臂甩到身后 → 蹬伸 → 提踵离地）
#   图像 5..8   = 上升（刚离地 → 双臂过头峰值 → 收腿 → 顶点）
#   图像 9..12  = 下落（向下探 → 加速 → 伸腿 → 触地前）
#   图像 13..16 = 落地（触地 → 缓冲最低点 → 回弹 → 站定）
#
# ⚠️ `JUMP_FALL_END + 1` 就是落地段的第一帧。"触地接触"必须排在落地段首位。
const JUMP_SQUAT_END: int = 3
const JUMP_RISE_END: int = 7
const JUMP_FALL_END: int = 11

# 各阶段推进速率（帧/秒）。速率只影响"同一姿势停留多久"，不影响物理轨迹。
#
# ⚠️ 取 (姿势数 − 1) / 时长 是**错的**：阶段会在"刚好到达末帧"的同一刻结束，
#    末帧显示时长为 0。实测预压段 0.20 s 由 12 次 1/60 累加得到 0.1999999…，
#    int(t × 15) 只到 2，"提踵离地"那一帧整帧被跳过。故速率乘 1.3 的系数，
#    让末帧在阶段结束之前到达并被短暂保持（也符合"关键姿势要稳住一下"的惯例）。
#     预压段 JUMP_SQUAT = 0.22 s → 3 / 0.22 × 1.3 ≈ 18
#     上升段 = JUMP_VELOCITY / GRAVITY = 625 / 1900 ≈ 0.329 s → 3 / 0.329 × 1.3 ≈ 12
#     下落段与上升同高往返，时长相同 → 12
#     落地段 = LAND_HOLD = 0.20 s → 3 / 0.20 × 1.3 ≈ 20
const JUMP_SQUAT_RATE: float = 18.0
const JUMP_RISE_RATE: float = 12.0
const JUMP_FALL_RATE: float = 12.0
const JUMP_LAND_RATE: float = 20.0

## 逐帧提灯锚点（角色本地坐标，原点=脚底，单位与世界一致）。
##
## 为什么需要逐帧：提灯挂在右手，会随手臂摆动；若用一个静态常量，
## PointLight2D 就会脱离灯体（灯在画面上摆、光却不动），明显穿帮。
## 实测摆动幅度：idle x∈[6.2,6.5]；run x∈[−0.1,16.6]；
## jump x∈[−7.1,20.0]、y∈[−9.4,−41.1]（蓄力时灯垂到腿后，离地后随甩臂升到头顶高度）。
## 单帧之间差 27 个世界单位，**单一常量必然穿帮**。
##
## 数值由渲染图实测得出：按提灯独有色（核心 255,222,142；肤色 254,223,189
## 的 G−B 只有 34，故以 G−B ≥ 58、G ≥ 195、且 R−G ≤ 45 分离，最后一条用于
## 排除暖红的兜帽/斗篷）求质心，再按
## (px − RENDERED_CENTER_X) × TARGET_HEIGHT/RENDERED_HEIGHT 与
## (py − IMG_H × FOOT_RATIO) × 同系数 换算到本地世界单位。
## 因为换算已是世界单位，本表**与渲染分辨率无关**（400×480 重渲后实测复核，
## 差值 ≤ 0.2）。
##
## ⚠️ **改了任何动作的手臂角度后必须重跑**：
##     D:/python/python.exe tools/measure_lamp_anchors.py
## 该脚本会打印可直接粘贴的整张表。手臂一改，提灯的像素位置就全变，
## 而这张表错了不报任何错 —— 只看得到"光源跑偏"这种模糊症状。
const LAMP_ANCHORS := {
	"idle": [
		Vector2(6.5, -9.4), Vector2(6.5, -9.4), Vector2(6.4, -9.1), Vector2(6.3, -8.9),
		Vector2(6.2, -8.8), Vector2(6.3, -8.9), Vector2(6.4, -9.1), Vector2(6.5, -9.4),
		Vector2(6.5, -9.4),
	],
	"run": [
		Vector2(-0.1, -10.4), Vector2(0.6, -10.5), Vector2(2.8, -10.2), Vector2(12.3, -11.0),
		Vector2(16.6, -14.4), Vector2(16.2, -14.2), Vector2(13.1, -11.7), Vector2(5.5, -9.1),
		Vector2(-0.1, -10.4),
	],
	"jump": [
		Vector2(4.8, -10.6), Vector2(-7.1, -11.8), Vector2(11.5, -10.8), Vector2(19.7, -24.1),
		Vector2(18.7, -35.0), Vector2(15.8, -41.1), Vector2(17.3, -38.5), Vector2(19.3, -33.5),
		Vector2(20.0, -25.6), Vector2(16.6, -15.7), Vector2(6.6, -10.1), Vector2(4.7, -12.2),
		Vector2(11.3, -10.3), Vector2(14.6, -10.4), Vector2(10.2, -10.0), Vector2(6.5, -9.4),
	],
}

# 与 Player.State 对应。
# ⚠️ 顺序必须与 player.gd 的 `enum State` 完全一致。两边靠"镜像常量"解耦，
# 一旦有人只改了一边就会静默错位（表现为播错动画、且不报任何错）。
# tools/probe/jump_probe.gd 会逐项校验这个映射，改完务必跑一次探针。
const S_IDLE: int = 0
const S_RUN: int = 1
const S_SQUAT: int = 2
const S_JUMP: int = 3
const S_FALL: int = 4
const S_LAND: int = 5
const S_LOCKED: int = 6

## 提灯光源相对角色脚底的锚点，由 Player 每帧读取。
## 初值取 idle 静止时的实测值；运行中由 _update_lantern_anchor() 逐帧刷新。
var lantern_anchor: Vector2 = Vector2(6.2, -9.0)

var _sprite: AnimatedSprite2D
var _state: int = S_IDLE
var _since_squat: float = 99.0
var _since_jump: float = 99.0
var _since_fall: float = 99.0
var _since_land: float = 99.0
var _frames: SpriteFrames


func _ready() -> void:
	_frames = _build_frames()
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Frames"
	_sprite.sprite_frames = _frames
	_sprite.centered = true
	var fit := TARGET_HEIGHT / RENDERED_HEIGHT
	_sprite.scale = Vector2(fit, fit)
	# 让图像中的脚底与横向中心对齐本节点原点（本节点位于角色脚底）
	_sprite.offset = Vector2(
		IMG_W * 0.5 - RENDERED_CENTER_X,
		-(IMG_H * FOOT_RATIO - IMG_H * 0.5))
	# 序列帧在 Blender 里已经烘焙好了明暗，若再被场景的 PointLight2D
	# 照一遍就会二次提亮、颜色被洗成淡黄。所以角色只接受全局调色，
	# 不接收任何 Light2D —— 提灯的光照只作用于场景。
	_sprite.light_mask = 0
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_sprite.material = unshaded
	add_child(_sprite)
	_play("idle")


## 由 Player 每帧调用。
##
## 注意各阶段计时器的复位顺序：必须"先把全部计时器置为无效值，再把当前
## 阶段的那一个清零"。历史版本先清零再调 _play()，而 _play() 内部会把
## _since_fall / _since_land 再次覆盖成 99 —— 结果是下落与落地阶段的
## 计时器永远是 99，_process 里算出的帧号被 clamp 到区间末帧，
## 于是"一进入下落就直接摆出落地姿势、落地回弹从不播放"。
## 这类 bug 不会报错、也不影响状态机，只有逐帧看画面才能发现。
func set_motion(state: int, run_phase: float, velocity: Vector2) -> void:
	if state == _state:
		_update_lantern_anchor()
		return
	_state = state
	match _state:
		S_RUN:
			_clear_phase_timers()
			_play("run")
		S_SQUAT:
			_clear_phase_timers()
			_since_squat = 0.0
			_play("jump")
		S_JUMP:
			_clear_phase_timers()
			_since_jump = 0.0
			_play("jump")
		S_FALL:
			_clear_phase_timers()
			_since_fall = 0.0
			_play("jump")
		S_LAND:
			_clear_phase_timers()
			_since_land = 0.0
			_play("jump")
		_:
			_clear_phase_timers()
			_play("idle")
	_update_lantern_anchor()


func _process(delta: float) -> void:
	_since_squat += delta
	_since_jump += delta
	_since_fall += delta
	_since_land += delta

	# jump 序列是一条完整的"蓄力→离地→顶点→下落→落地"，但每个阶段在空中的
	# 停留时长由物理决定（预压段由 player.gd 的 JUMP_SQUAT 提供地面时间），
	# 所以这里按阶段手动锁帧，而不是让它自己播完。
	if _state == S_SQUAT:
		_sprite.frame = clampi(int(_since_squat * JUMP_SQUAT_RATE), 0, JUMP_SQUAT_END)
	elif _state == S_JUMP:
		_sprite.frame = clampi(JUMP_SQUAT_END + 1 + int(_since_jump * JUMP_RISE_RATE),
			JUMP_SQUAT_END + 1, JUMP_RISE_END)
	elif _state == S_FALL:
		_sprite.frame = clampi(JUMP_RISE_END + 1 + int(_since_fall * JUMP_FALL_RATE),
			JUMP_RISE_END + 1, JUMP_FALL_END)
	elif _state == S_LAND:
		_sprite.frame = clampi(JUMP_FALL_END + 1 + int(_since_land * JUMP_LAND_RATE),
			JUMP_FALL_END + 1, CLIP_COUNTS["jump"] - 1)


## 让 PointLight2D 跟上当前帧里提灯的实际位置。
##
## 存在 1 帧延迟：Player._process 先于子节点 Visual._process 执行，
## 读取的锚点是上一帧写入的。对一盏点光源而言 16 ms 无可感知影响，
## 换取的是"不必把提灯坐标也塞进 Player"这一层解耦。
func _update_lantern_anchor() -> void:
	if _sprite == null:
		return
	var table: Array = LAMP_ANCHORS.get(String(_sprite.animation), [])
	if table.is_empty():
		return
	var p: Vector2 = table[clampi(_sprite.frame, 0, table.size() - 1)]
	lantern_anchor = p


## 把四个阶段计时器全部置为"已结束"的哨兵值。
func _clear_phase_timers() -> void:
	_since_squat = 99.0
	_since_jump = 99.0
	_since_fall = 99.0
	_since_land = 99.0


func _play(clip: String) -> void:
	if _sprite == null or not _sprite.sprite_frames.has_animation(clip):
		return
	_sprite.play(clip)


func _build_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for clip in CLIP_COUNTS.keys():
		frames.add_animation(clip)
		var count: int = CLIP_COUNTS[clip]
		var loop: bool = clip != "jump"
		frames.set_animation_loop(clip, loop)
		frames.set_animation_speed(clip, 12.0)
		for i in range(1, count + 1):
			var path := "%s%s/%03d.png" % [CLIP_ROOT, clip, i]
			if ResourceLoader.exists(path):
				frames.add_frame(clip, load(path))
	return frames
