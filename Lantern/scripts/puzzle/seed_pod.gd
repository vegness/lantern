class_name SeedPod
extends StaticBody2D
## 种子荚 —— "生长"机制的载体。
##
## 被提灯持续照亮一段时间后发芽，沿指定方向长出藤蔓；藤蔓长成后
## 成为可站立的实体平台。
##
## 光照按"与玩家的距离"累积、离开光范围会缓慢回落。玩家必须把灯
## 停在附近等它长，而不是匆匆路过 —— 行为和直觉一致，不需要额外教程。
##
## 生长方向请使用轴对齐向量（(0,-1) / (1,0) 等），碰撞体按轴对齐矩形计算。

@export var grow_direction: Vector2 = Vector2(0.0, -1.0)
@export var grow_length: float = 150.0
@export var vine_width: float = 26.0
## 需要被照亮多久才长成（秒）。
@export var charge_time: float = 1.7
## 离开光照后每秒回落多少（0 表示不回落）。
@export var decay_rate: float = 0.5
## 生长动画时长（秒）。
@export var grow_duration: float = 1.1

signal grown()

const OUTLINE := Color("2b3a24")
const STEM_DARK := Color("3d5f36")
const STEM := Color("5f8a4c")
const STEM_LIGHT := Color("7fb669")
const POD_DARK := Color("6d4c33")
const POD := Color("8a6244")
const BLOOM := Color("f2d06b")
const BLOOM_CORE := Color("fff3d6")

var _charge: float = 0.0
var _grow: float = 0.0
var _grown: bool = false
var _time: float = 0.0
var _leaves: Array[Dictionary] = []

var _rect: RectangleShape2D
var _collision: CollisionShape2D


func _ready() -> void:
	add_to_group("puzzle_component")
	collision_layer = 1
	collision_mask = 0
	_build_collision()
	_build_leaves()
	set_process(true)


func _build_collision() -> void:
	_rect = RectangleShape2D.new()
	_rect.size = Vector2(vine_width, vine_width)
	_collision = CollisionShape2D.new()
	_collision.shape = _rect
	_collision.disabled = true
	add_child(_collision)


## 沿生长方向预先排布叶片的位置与朝向，避免每帧随机。
func _build_leaves() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(global_position.x) * 13.0 + absf(global_position.y) * 7.0) + 5
	var count := maxi(2, int(grow_length / 46.0))
	for i in count:
		var t := (float(i) + 0.6) / float(count)
		_leaves.append({
			"t": t,
			"side": 1.0 if i % 2 == 0 else -1.0,
			"size": rng.randf_range(9.0, 13.5),
			"tilt": rng.randf_range(-0.35, 0.35),
		})


func _process(delta: float) -> void:
	_time += delta

	if not _grown:
		if _is_lit():
			_charge = minf(_charge + delta / maxf(charge_time, 0.05), 1.0)
		elif decay_rate > 0.0:
			_charge = maxf(_charge - delta * decay_rate, 0.0)
		if _charge >= 1.0:
			_start_growth()
	else:
		_grow = minf(_grow + delta / maxf(grow_duration, 0.05), 1.0)
		_update_collision()

	queue_redraw()


func _is_lit() -> bool:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return false
	if player.has_method("is_lantern_on") and not bool(player.call("is_lantern_on")):
		return false
	var reach: float = GameConfig.LANTERN_RADIUS + 46.0
	return global_position.distance_to((player as Node2D).global_position) < reach


func _start_growth() -> void:
	if _grown:
		return
	_grown = true
	AudioManager.play_sfx("res://assets/audio/sfx/grow.wav", -6.0, 1.0)
	grown.emit()


## 碰撞体只覆盖"已经长出来"的那一段，并且要等长到接近完成才启用，
## 否则玩家会被正在生长的藤蔓顶开。
func _update_collision() -> void:
	var extend := grow_length * _grow
	if extend < vine_width * 0.9:
		_collision.disabled = true
		return
	_collision.disabled = false
	var axis := Vector2(1.0, 0.0) if absf(grow_direction.x) >= absf(grow_direction.y) else Vector2(0.0, 1.0)
	if axis.x != 0.0:
		_rect.size = Vector2(extend, vine_width)
		_collision.position = Vector2(extend * 0.5 * signf(grow_direction.x), 0.0)
	else:
		_rect.size = Vector2(vine_width, extend)
		_collision.position = Vector2(0.0, extend * 0.5 * signf(grow_direction.y))


func is_grown() -> bool:
	return _grown and _grow >= 1.0


# ---------------------------------------------------------------------------
# 绘制
# ---------------------------------------------------------------------------

func _draw() -> void:
	var dir := grow_direction.normalized()
	var length := grow_length * _grow

	# 充能指示：种子周围逐渐变亮的光环
	if not _grown and _charge > 0.01:
		var pulse := 0.7 + 0.3 * sin(_time * 5.0)
		draw_circle(Vector2(0.0, -6.0), 16.0 + _charge * 10.0, Color(BLOOM, 0.12 * _charge * pulse))
		draw_arc(Vector2(0.0, -6.0), 15.0, -PI * 0.5, -PI * 0.5 + TAU * _charge, 24,
			Color(BLOOM, 0.85), 2.6, true)

	# 藤蔓主体：沿生长方向的粗线，带轻微的正弦弯曲
	if length > 2.0:
		var points := PackedVector2Array()
		var steps := maxi(4, int(length / 14.0))
		for i in steps + 1:
			var t := float(i) / float(steps)
			var along := dir * (length * t)
			var perp := Vector2(-dir.y, dir.x)
			var wobble := sin(t * PI * 2.4) * 2.2 * t
			points.append(along + perp * wobble)
		draw_polyline(points, OUTLINE, vine_width + 3.5, true)
		draw_polyline(points, STEM_DARK, vine_width, true)
		var inner := PackedVector2Array()
		for p in points:
			inner.append(p * 0.92)
		draw_polyline(inner, STEM, vine_width * 0.72, true)
		var highlight := PackedVector2Array()
		for p in points:
			highlight.append(p * 0.9 + Vector2(-vine_width * 0.22, -vine_width * 0.22))
		draw_polyline(highlight, Color(STEM_LIGHT, 0.55), vine_width * 0.2, true)

		# 叶片
		var perp_axis := Vector2(-dir.y, dir.x)
		for leaf in _leaves:
			if float(leaf["t"]) > _grow:
				continue
			var base := dir * (length * float(leaf["t"]))
			var side := float(leaf["side"])
			var size := float(leaf["size"]) * minf(_grow * 1.6, 1.0)
			var tip := base + perp_axis * side * (size * 1.7) + dir * (size * 0.5)
			var mid_a := base + perp_axis * side * (size * 0.4) + dir * (size * 0.7)
			var mid_b := base + perp_axis * side * (size * 1.5) + dir * (size * 0.2)
			draw_colored_polygon(PackedVector2Array([base, mid_a, tip, mid_b]), OUTLINE)
			var shrink := PackedVector2Array([
				base.lerp(Vector2(base.x, base.y), 0.99),
				base + (mid_a - base) * 0.78,
				base + (tip - base) * 0.78,
				base + (mid_b - base) * 0.78,
			])
			draw_colored_polygon(shrink, STEM)

	# 长成后开一朵小花
	if is_grown():
		var tip_pos := dir * grow_length
		var bloom_pulse := 1.0 + sin(_time * 2.2) * 0.08
		draw_circle(tip_pos, 9.0 * bloom_pulse, Color(BLOOM, 0.18))
		for i in 5:
			var angle := TAU * float(i) / 5.0 + _time * 0.35
			draw_circle(tip_pos + Vector2(cos(angle), sin(angle)) * 4.2, 3.1, BLOOM)
		draw_circle(tip_pos, 3.0, BLOOM_CORE)

	# 种子荚本体
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.86))
	draw_circle(Vector2.ZERO, 9.2, OUTLINE)
	draw_circle(Vector2.ZERO, 7.6, POD_DARK)
	draw_circle(Vector2(-1.6, -1.6), 5.4, POD)
	draw_circle(Vector2(-2.6, -2.6), 2.4, Color(POD, 0.0).lightened(0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
