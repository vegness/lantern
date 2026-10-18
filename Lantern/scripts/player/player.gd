class_name Player
extends CharacterBody2D
## 提灯人（玩家角色）。
##
## 运动部分实现平台游戏的标准手感要素：
## 加速度与摩擦分离、土狼时间、跳跃缓冲、可变跳跃高度、落地挤压反馈。
##
## 关于状态机的取舍：这里用内联枚举而非独立状态类。原因是平台游戏的状态
## 几乎全部由物理量（是否着地、垂直速度正负）直接推导，拆成多个文件后
## "改一个数值要翻三个文件"，维护成本反而高于收益。状态逻辑集中在
## _update_state 中，一眼可以看全。

## 状态枚举。
## ⚠️ 这个顺序是 scripts/player/player_visual.gd 里 S_* 常量的镜像，
## 改顺序必须同步改那边（探针 tools/probe/jump_probe.gd 会校验两者一致）。
enum State { IDLE, RUN, SQUAT, JUMP, FALL, LAND, LOCKED }

## 玩家触发交互时发出，携带被交互的节点。
signal interacted(target: Node)
## 提灯开关状态变化。
signal lantern_toggled(on: bool)

const SFX_JUMP: String = "res://assets/audio/sfx/jump.wav"
const SFX_LAND: String = "res://assets/audio/sfx/land.wav"
const SFX_LANTERN: String = "res://assets/audio/sfx/lantern.wav"

## 判定为"有效移动"的最小速度，低于此值视为站立。
const RUN_EPSILON: float = 8.0
## 落地挤压的恢复速度（每秒）。
const SQUASH_RECOVER: float = 5.5
## 落地后保持 LAND 状态的时长，让视觉层有机会播放回弹。
## 0.20 s 对应真实跳动的落地缓冲；期间仍可用跳跃键起跳（SQUAT 优先于 LAND）。
const LAND_HOLD: float = 0.20
## 起跳预压（SQUAT）时长。按下跳跃后先在地面压低这么久，再施加上升速度。
##
## 为什么必须有这一段：`_handle_jump` 原先在**同一物理帧**就把 velocity.y 设为
## JUMP_VELOCITY，角色立刻离地 —— 于是序列帧里的"蓄力 → 蹬伸"两段只能在空中
## 播放，任何手臂动作都会被读成"跳起来之后才刻意做动作"。
##
## ⚠️ 这个值**必须与动画的蓄力段时长匹配**。参考真人纵跳（见
## animate_kid.py::poses_jump 的注释）："深蹲蓄力"是整个动作里最长的一段。
## 0.083 s 只有 5 个显示帧，蓄力姿势各显示不到 2 帧 —— 姿势再对也读不出来。
## 0.22 s（13 帧 @60fps）让"下沉 → 深蹲 → 蹬伸 → 提踵"各占约 3~4 个显示帧。
##
## 这是全项目唯一的**输入延迟**来源。想更跟手就调小（0.14 仍看得见），
## 想更"蓄力"就调大（0.28 接近真人）；改成 0 即回到"按下即离地"。
## 改这个值要同步改 player_visual.gd 的 JUMP_SQUAT_RATE（= 3 / JUMP_SQUAT × 1.3）。
const JUMP_SQUAT: float = 0.22

@onready var visual: Node2D = $Visual
@onready var lantern: PointLight2D = $Lantern
@onready var interact_area: Area2D = $InteractArea
@onready var ground_probe: RayCast2D = $GroundProbe

## 当前状态。
var state: State = State.IDLE
## 朝向：1 为右，-1 为左。
var facing: int = 1
## 是否接受输入。过场、结算、死亡动画期间会被置为 false。
var input_enabled: bool = true

var _coyote: float = 0.0
var _jump_buffer: float = 0.0
## 预压剩余时间。> 0 时角色停留在地面播放蓄力段，归零那一下才真正起跳。
var _squat_timer: float = 0.0
## 预压计时已归零、等待本帧施加起跳速度。
## 单独用布尔量是为了避免"设置计时的同一帧就离地"（那样预压一帧都放不出来）。
var _squat_ready: bool = false
var _lock_timer: float = 0.0
var _land_timer: float = 0.0
var _squash: float = 0.0
var _bob_phase: float = 0.0
var _lantern_on: bool = true
var _was_on_floor: bool = true
var _visual_scale: Vector2 = Vector2.ONE
var _current_target: Node = null

## 出生点，用于坠落后复位。
var spawn_point: Vector2 = Vector2.ZERO


func _ready() -> void:
	spawn_point = global_position
	add_to_group("player")
	_apply_lantern_state()


func _physics_process(delta: float) -> void:
	_tick_timers(delta)

	if _lock_timer > 0.0 or not input_enabled:
		# 锁定时仅保留重力，让角色自然落地；未完成的预压直接取消
		_squat_timer = 0.0
		_squat_ready = false
		_apply_gravity(delta)
		velocity.x = move_toward(velocity.x, 0.0, GameConfig.GROUND_FRICTION * delta)
		_state_locked(delta)
	else:
		_apply_gravity(delta)
		_handle_jump(delta)
		_handle_horizontal(delta)

	var was_floor := is_on_floor()
	move_and_slide()

	_detect_landing(was_floor)
	_update_state(delta)
	_update_visual(delta)
	_update_interaction()


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event.is_action_pressed("toggle_light"):
		_toggle_lantern()
	elif event.is_action_pressed("interact"):
		_try_interact()


# ---------------------------------------------------------------------------
# 计时器
# ---------------------------------------------------------------------------

func _tick_timers(delta: float) -> void:
	if is_on_floor():
		_coyote = GameConfig.COYOTE_TIME
	else:
		_coyote = maxf(_coyote - delta, 0.0)

	if _jump_buffer > 0.0:
		_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if _squat_timer > 0.0:
		_squat_timer = maxf(_squat_timer - delta, 0.0)
		if _squat_timer <= 0.0:
			_squat_ready = true
	if _lock_timer > 0.0:
		_lock_timer = maxf(_lock_timer - delta, 0.0)
	if _land_timer > 0.0:
		_land_timer = maxf(_land_timer - delta, 0.0)


# ---------------------------------------------------------------------------
# 垂直运动
# ---------------------------------------------------------------------------

func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	velocity.y = minf(velocity.y + GameConfig.GRAVITY * delta, GameConfig.MAX_FALL_SPEED)
	# 可变跳跃高度：上升途中松开跳跃键立刻截断剩余升力
	if velocity.y < 0.0 and not Input.is_action_pressed("jump"):
		velocity.y *= GameConfig.JUMP_CUT


func _handle_jump(_delta: float) -> void:
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = GameConfig.JUMP_BUFFER

	# 预压结束 → 本帧真正起跳
	if _squat_ready:
		_squat_ready = false
		_launch()
		return
	# 预压中：脚一旦离开地面（走出平台边缘）就立刻起跳，不要"踩着空气蓄力"
	if _squat_timer > 0.0:
		if not is_on_floor():
			_launch()
		return

	if _jump_buffer > 0.0 and _coyote > 0.0:
		_jump_buffer = 0.0
		if JUMP_SQUAT > 0.0:
			_squat_timer = JUMP_SQUAT
		else:
			_launch()


## 真正施加起跳速度。预压期与预压结束后都走这里，保证只有一处改速度。
func _launch() -> void:
	_squat_timer = 0.0
	_squat_ready = false
	# 预压期间可能刚好落地（_land_timer 正在跑）；不清掉的话离地后会被判成
	# LAND 状态，结果一边上升一边播落地回弹。
	_land_timer = 0.0
	_coyote = 0.0
	velocity.y = GameConfig.JUMP_VELOCITY
	_squash = -0.35  # 负值表示起跳时的纵向拉伸
	AudioManager.play_sfx(SFX_JUMP, -8.0, randf_range(0.95, 1.05))


func _detect_landing(was_on_floor: bool) -> void:
	if not was_on_floor and is_on_floor():
		# 下落速度越大，落地反馈越明显
		var impact := clampf(absf(velocity.y) / GameConfig.MAX_FALL_SPEED, 0.0, 1.0)
		_squash = maxf(_squash, 0.35 + impact * 0.65)
		_land_timer = LAND_HOLD
		if impact > 0.25:
			AudioManager.play_sfx(SFX_LAND, -10.0 + impact * 4.0, randf_range(0.97, 1.03))
	_was_on_floor = is_on_floor()


# ---------------------------------------------------------------------------
# 水平运动
# ---------------------------------------------------------------------------

func _handle_horizontal(delta: float) -> void:
	var dir := Input.get_axis("move_left", "move_right")
	var on_floor := is_on_floor()
	var accel := GameConfig.GROUND_ACCEL if on_floor else GameConfig.AIR_ACCEL
	var friction := GameConfig.GROUND_FRICTION if on_floor else GameConfig.AIR_FRICTION
	var top_speed := GameConfig.RUN_SPEED
	if not on_floor:
		top_speed += GameConfig.AIR_SPEED_BONUS

	if absf(dir) > 0.01:
		velocity.x = move_toward(velocity.x, dir * top_speed, accel * delta)
		facing = 1 if dir > 0.0 else -1
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)


# ---------------------------------------------------------------------------
# 状态机
# ---------------------------------------------------------------------------

func _update_state(_delta: float) -> void:
	if _lock_timer > 0.0 or not input_enabled:
		state = State.LOCKED
		return
	# 预压：脚还在地面、正在蓄力。优先级高于 LAND，这样落地回弹期间
	# 再次按跳能立刻转入下一次起跳。
	if _squat_timer > 0.0:
		state = State.SQUAT
		return
	# 落地回弹优先于其它状态，保证它总能完整播完
	if _land_timer > 0.0:
		state = State.LAND
		return
	if not is_on_floor():
		state = State.JUMP if velocity.y < 0.0 else State.FALL
	elif absf(velocity.x) > RUN_EPSILON:
		state = State.RUN
	else:
		state = State.IDLE


func _state_locked(_delta: float) -> void:
	state = State.LOCKED


## 锁定输入一段时间（用于过场、被机关捕获等）。
func lock_input(duration: float) -> void:
	_lock_timer = maxf(_lock_timer, duration)


# ---------------------------------------------------------------------------
# 视觉反馈
# ---------------------------------------------------------------------------

func _update_visual(delta: float) -> void:
	# 跑动相位驱动步态循环。周期与水平速度挂钩，慢走时步频自然放慢，
	# 避免"以恒定频率滑动"的违和感。
	if state == State.RUN and is_on_floor():
		var speed_ratio := clampf(absf(velocity.x) / GameConfig.RUN_SPEED, 0.4, 1.25)
		_bob_phase = fmod(_bob_phase + delta * 10.5 * speed_ratio, TAU)
	else:
		_bob_phase = fmod(_bob_phase, TAU)

	_squash = move_toward(_squash, 0.0, SQUASH_RECOVER * delta * (1.0 + absf(_squash)))

	# 姿态与绘制完全交给视觉层，这里只负责喂运动状态。
	# 朝向通过 X 缩放实现（骨架按"朝右"设计）。
	visual.scale = Vector2(float(facing), 1.0)
	if visual.has_method("set_motion"):
		visual.call("set_motion", state, _bob_phase, velocity)

	# 提灯点光源跟随视觉层算出的手部位置，保证"光从灯里发出来"
	if lantern != null:
		var anchor: Variant = visual.get("lantern_anchor")
		if anchor is Vector2:
			var local: Vector2 = anchor
			lantern.position = Vector2(0.0, 23.0) + Vector2(local.x * float(facing), local.y)


# ---------------------------------------------------------------------------
# 提灯
# ---------------------------------------------------------------------------

func _toggle_lantern() -> void:
	_lantern_on = not _lantern_on
	_apply_lantern_state()
	AudioManager.play_sfx(SFX_LANTERN, -6.0, 1.0 if _lantern_on else 0.86)
	lantern_toggled.emit(_lantern_on)


func _apply_lantern_state() -> void:
	if lantern == null:
		return
	lantern.enabled = _lantern_on
	var radius := GameConfig.LANTERN_RADIUS if _lantern_on else GameConfig.LANTERN_RADIUS_OFF
	lantern.texture_scale = (radius * 2.0) / 512.0
	lantern.energy = GameConfig.LANTERN_ENERGY if _lantern_on else 0.5


## 当前提灯是否点亮。
func is_lantern_on() -> bool:
	return _lantern_on


## 强制设置提灯（关卡过场使用），不播放音效。
func set_lantern(on: bool) -> void:
	if _lantern_on == on:
		return
	_lantern_on = on
	_apply_lantern_state()
	lantern_toggled.emit(_lantern_on)


# ---------------------------------------------------------------------------
# 交互
# ---------------------------------------------------------------------------

func _update_interaction() -> void:
	var found: Node = null
	var best_distance := INF
	for area in interact_area.get_overlapping_areas():
		if not area.is_in_group("interactable"):
			continue
		if area.has_method("can_interact") and not area.call("can_interact", self):
			continue
		var d := global_position.distance_squared_to((area as Node2D).global_position)
		if d < best_distance:
			best_distance = d
			found = area

	if found != _current_target:
		_set_prompt_target(found)
	_current_target = found


func _set_prompt_target(target: Node) -> void:
	var prompt := get_tree().get_first_node_in_group("interact_prompt")
	if prompt != null and prompt.has_method("show_for"):
		prompt.call("show_for", target)


func _try_interact() -> void:
	if _current_target == null:
		return
	if _current_target.has_method("interact"):
		_current_target.call("interact", self)
		interacted.emit(_current_target)


## 当前可交互目标（供 UI 查询）。
func get_interact_target() -> Node:
	return _current_target


# ---------------------------------------------------------------------------
# 复位
# ---------------------------------------------------------------------------

## 回到出生点（坠落或落入危险区时调用）。
func respawn() -> void:
	global_position = spawn_point
	velocity = Vector2.ZERO
	_squash = 0.6
