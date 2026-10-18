class_name Prop
extends Node2D
## 场景装饰物：树、灌木、石头。
##
## 全部程序化绘制，同一 seed 下形态稳定。装饰物不参与碰撞 ——
## 它们的职责是让画面有生活感，而不是给玩家增加操作负担。
## 每个装饰物都由"深色描边 + 主体 + 亮面"三层构成，
## 与角色、地形使用同一套配色逻辑，保证整体风格统一。

enum Kind { TREE, BUSH, ROCK }

const OUTLINE := Color("3b2a1d")
const TRUNK := Color("7a5537")
const TRUNK_DARK := Color("5c3f28")
const LEAF_DARK := Color("4a7043")
const LEAF := Color("6b9c58")
const LEAF_LIGHT := Color("8cc272")
const ROCK_DARK := Color("5d6472")
const ROCK := Color("7d8598")
const ROCK_LIGHT := Color("9aa2b2")

@export var kind: Kind = Kind.TREE
@export var seed_value: int = 1
@export var shape_scale: float = 1.0
## 装饰物整体做轻微摆动的幅度，让静态画面有呼吸感。0 表示完全静止。
@export var sway_amount: float = 0.0

var _rng := RandomNumberGenerator.new()
var _time: float = 0.0
var _phase: float = 0.0
var _blobs: Array[Dictionary] = []
var _rock_pts: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	_rng.seed = seed_value * 4099 + 71
	_phase = _rng.randf() * TAU
	_build()
	# 只有需要摆动的装饰才每帧重绘，静态的省下这份开销
	set_process(sway_amount > 0.001)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _build() -> void:
	match kind:
		Kind.TREE:
			_build_tree()
		Kind.BUSH:
			_build_bush()
		Kind.ROCK:
			_build_rock()


func _build_tree() -> void:
	var blobs := 4
	for i in blobs:
		var t := float(i) / float(maxi(blobs - 1, 1))
		_blobs.append({
			"pos": Vector2(_rng.randf_range(-9.0, 9.0), -46.0 - t * 22.0 + _rng.randf_range(-3.0, 3.0)),
			"r": lerpf(17.0, 10.5, t) * _rng.randf_range(0.92, 1.08),
		})


func _build_bush() -> void:
	var blobs := 3 + _rng.randi_range(0, 2)
	for i in blobs:
		_blobs.append({
			"pos": Vector2(_rng.randf_range(-13.0, 13.0), _rng.randf_range(-9.0, 1.0)),
			"r": _rng.randf_range(7.5, 12.0),
		})


func _build_rock() -> void:
	var sides := 7
	_rock_pts = PackedVector2Array()
	for i in sides:
		var angle := -PI * 0.5 + TAU * float(i) / float(sides)
		var r := _rng.randf_range(12.0, 18.0)
		# 压扁一点，让石头看起来是"坐"在地上的
		_rock_pts.append(Vector2(cos(angle) * r, sin(angle) * r * 0.68))


# ---------------------------------------------------------------------------
# 绘制
# ---------------------------------------------------------------------------

func _draw() -> void:
	var sway := 0.0
	if sway_amount > 0.001:
		sway = sin(_time * 1.3 + _phase) * sway_amount

	draw_set_transform(Vector2.ZERO, 0.0, Vector2(shape_scale, shape_scale))
	match kind:
		Kind.TREE:
			_draw_tree(sway)
		Kind.BUSH:
			_draw_bush(sway)
		Kind.ROCK:
			_draw_rock()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_tree(sway: float) -> void:
	# 树干：略带弧度的粗线
	var base := Vector2.ZERO
	var top := Vector2(sway * 2.0, -52.0)
	draw_line(base, top, OUTLINE, 9.0, true)
	draw_line(base, top, TRUNK, 6.4, true)
	draw_line(base + Vector2(-1.6, 0.0), top + Vector2(-1.6, 0.0), Color(TRUNK_DARK, 0.7), 2.2, true)

	# 树冠：先整体描边，再分层上色
	for blob in _blobs:
		var p: Vector2 = blob["pos"] + Vector2(sway * 3.0, sway * 0.6)
		draw_circle(p, float(blob["r"]) + 2.0, OUTLINE)
	for blob in _blobs:
		var p: Vector2 = blob["pos"] + Vector2(sway * 3.0, sway * 0.6)
		draw_circle(p, float(blob["r"]), LEAF_DARK)
	for blob in _blobs:
		var p: Vector2 = blob["pos"] + Vector2(sway * 3.0, sway * 0.6)
		draw_circle(p + Vector2(0.0, -1.6), float(blob["r"]) * 0.78, LEAF)
	for i in _blobs.size():
		var p: Vector2 = _blobs[i]["pos"] + Vector2(sway * 3.0, sway * 0.6)
		if i % 2 == 0:
			draw_circle(p + Vector2(-2.5, -3.4), float(_blobs[i]["r"]) * 0.42, Color(LEAF_LIGHT, 0.85))


func _draw_bush(sway: float) -> void:
	for blob in _blobs:
		draw_circle(blob["pos"] + Vector2(sway * 1.4, 0.0), float(blob["r"]) + 1.8, OUTLINE)
	for blob in _blobs:
		draw_circle(blob["pos"] + Vector2(sway * 1.4, 0.0), float(blob["r"]), LEAF_DARK)
	for blob in _blobs:
		draw_circle(blob["pos"] + Vector2(sway * 1.4, -1.4), float(blob["r"]) * 0.72, LEAF)
	for blob in _blobs:
		draw_circle(blob["pos"] + Vector2(-2.0 + sway * 1.4, -3.0), float(blob["r"]) * 0.34, Color(LEAF_LIGHT, 0.8))


func _draw_rock() -> void:
	var outline := PackedVector2Array()
	var centroid := Vector2.ZERO
	for p in _rock_pts:
		centroid += p
	centroid /= float(_rock_pts.size())
	for p in _rock_pts:
		outline.append(centroid + (p - centroid) * 1.16)

	draw_colored_polygon(outline, OUTLINE)
	draw_colored_polygon(_rock_pts, ROCK_DARK)
	var inner := PackedVector2Array()
	for p in _rock_pts:
		inner.append(centroid + (p - centroid) * 0.82 + Vector2(0.0, -1.4))
	draw_colored_polygon(inner, ROCK)
	var highlight := PackedVector2Array()
	for p in _rock_pts:
		highlight.append(centroid + (p - centroid) * 0.46 + Vector2(-1.4, -3.0))
	draw_colored_polygon(highlight, Color(ROCK_LIGHT, 0.6))
