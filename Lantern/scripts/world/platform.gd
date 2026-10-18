class_name Platform
extends StaticBody2D
## 可复用的地形块。
##
## 刻意避免"纯矩形"的观感：顶部是正弦扰动的草皮（大小两个频率叠加，
## 避免出现机械的等距波峰），土里嵌着石子，草皮上长出草须。
## 尺寸用 size 导出，形态用 seed_value 控制 —— 同一关卡里每块平台都长得
## 不一样，但给定同一个 seed 后完全可复现，便于回归验证。
##
## 根部节点即碰撞体中心：size 就是碰撞矩形的尺寸，草皮的起伏在视觉上
## 略微高出碰撞顶边，角色踩上去时脚会没进草里一点，符合直觉。

enum Style { GRASS, STONE, WOOD }

@export var size: Vector2 = Vector2(180.0, 44.0)
@export var style: Style = Style.GRASS
@export var seed_value: int = 1

const OUTLINE := Color("3b2a1d")
const SOIL_DARK := Color("6b4a33")
const SOIL := Color("8a6244")
const SOIL_LIGHT := Color("a3785a")
const GRASS_DARK := Color("48703f")
const GRASS := Color("6da35a")
const GRASS_LIGHT := Color("93c876")
const STONE_DARK := Color("5d6472")
const STONE_MAIN := Color("8b93a3")
const STONE_LIGHT := Color("aeb6c4")

var _body_pts: PackedVector2Array = PackedVector2Array()
var _body_outline: PackedVector2Array = PackedVector2Array()
var _top_pts: PackedVector2Array = PackedVector2Array()
var _blades: Array[Dictionary] = []
var _pebbles: Array[Dictionary] = []
## 表层（草皮）厚度。在 _build_visual 中算好后供 _draw 使用。
var _surface_depth: float = 10.0


func _ready() -> void:
	_build_visual()
	_build_collision()
	queue_redraw()


func _build_collision() -> void:
	var shape := RectangleShape2D.new()
	shape.size = size
	var node := CollisionShape2D.new()
	node.name = "Shape"
	node.shape = shape
	add_child(node)
	collision_layer = 1
	collision_mask = 0


# ---------------------------------------------------------------------------
# 形状生成
# ---------------------------------------------------------------------------

func _build_visual() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 13

	var hw := size.x * 0.5
	var hh := size.y * 0.5
	var top := -hh

	# 主体：圆角矩形，圆角随厚度自适应，薄平台不至于被圆角吃掉
	_body_pts = _rounded_rect(size.x, size.y, minf(7.0, size.y * 0.28))
	var grown := Geometry2D.offset_polygon(_body_pts, 2.0, Geometry2D.JOIN_ROUND)
	_body_outline = grown[0] if grown.size() > 0 else _body_pts.duplicate()

	# 表层（草皮 / 石檐 / 木沿）：上边缘用两个频率叠加的波，避免等距感
	_surface_depth = clampf(size.y * 0.42, 9.0, 17.0)
	var depth := _surface_depth
	var steps := maxi(6, int(size.x / 9.0))
	var phase := rng.randf() * TAU
	var freq := 1.5 + rng.randf() * 1.1
	_top_pts = PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / float(steps)
		var x := lerpf(-hw, hw, t)
		var wave := sin(t * TAU * freq + phase) * 2.3 + sin(t * TAU * freq * 2.4 + phase * 1.7) * 1.0
		_top_pts.append(Vector2(x, top + wave))
	_top_pts.append(Vector2(hw, top + depth))
	_top_pts.append(Vector2(-hw, top + depth))

	# 草须：从表层向上长出的小草，带随机倾斜
	_blades.clear()
	var blade_count := clampi(int(size.x / 14.0), 3, 26)
	for i in blade_count:
		var t := (float(i) + rng.randf()) / float(blade_count)
		var x := lerpf(-hw + 3.0, hw - 3.0, t)
		var wave := sin(t * TAU * freq + phase) * 2.3
		_blades.append({
			"x": x,
			"y": top + wave,
			"h": 3.5 + rng.randf() * 4.5,
			"tilt": rng.randf_range(-1.4, 1.4),
		})

	# 石子：只出现在足够厚的平台里
	_pebbles.clear()
	if size.y >= 34.0:
		var stone_count := clampi(int(size.x / 46.0), 1, 5)
		for i in stone_count:
			_pebbles.append({
				"pos": Vector2(
					rng.randf_range(-hw + 12.0, hw - 12.0),
					rng.randf_range(top + depth + 8.0, hh - 7.0)
				),
				"r": 1.3 + rng.randf() * 1.9,
			})


## 生成圆角矩形的点集（顺时针）。
static func _rounded_rect(w: float, h: float, radius: float, segments: int = 5) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var hw := w * 0.5
	var hh := h * 0.5
	var r := minf(radius, minf(hw, hh))
	if r <= 0.01:
		pts.append(Vector2(-hw, -hh))
		pts.append(Vector2(hw, -hh))
		pts.append(Vector2(hw, hh))
		pts.append(Vector2(-hw, hh))
		return pts
	var corners := [
		[Vector2(hw - r, -hh + r), -PI * 0.5],
		[Vector2(hw - r, hh - r), 0.0],
		[Vector2(-hw + r, hh - r), PI * 0.5],
		[Vector2(-hw + r, -hh + r), PI],
	]
	for corner in corners:
		var center: Vector2 = corner[0]
		var start: float = corner[1]
		for i in segments + 1:
			var a: float = start + (PI * 0.5) * float(i) / float(segments)
			pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts


# ---------------------------------------------------------------------------
# 绘制
# ---------------------------------------------------------------------------

func _draw() -> void:
	match style:
		Style.STONE:
			_draw_stone()
		_:
			_draw_grass()


func _draw_grass() -> void:
	var hh := size.y * 0.5
	var top := -hh

	# 泥土主体
	draw_colored_polygon(_body_outline, OUTLINE)
	draw_colored_polygon(_body_pts, SOIL_DARK)
	draw_set_transform(Vector2(0.0, -2.0), 0.0, Vector2(0.94, 0.90))
	draw_colored_polygon(_body_pts, SOIL)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 石子
	for pebble in _pebbles:
		draw_circle(pebble["pos"], float(pebble["r"]), Color(SOIL_LIGHT, 0.55))

	# 草皮：外描边 + 主体 + 随波浪起伏的受光带
	var grown := Geometry2D.offset_polygon(_top_pts, 1.6, Geometry2D.JOIN_ROUND)
	if grown.size() > 0:
		draw_colored_polygon(grown[0], OUTLINE)
	draw_colored_polygon(_top_pts, GRASS_DARK)

	var band := _top_band(_surface_depth * 0.46)
	if band.size() > 2:
		draw_colored_polygon(band, GRASS)
	var band_top := _top_band(_surface_depth * 0.20)
	if band_top.size() > 2:
		draw_colored_polygon(band_top, Color(GRASS_LIGHT, 0.8))

	# 草须
	for blade in _blades:
		var base := Vector2(float(blade["x"]), float(blade["y"]) + 1.0)
		var tip := base + Vector2(float(blade["tilt"]), -float(blade["h"]))
		draw_line(base, tip, GRASS_LIGHT, 1.5, true)

	# 与泥土的交界线
	draw_line(Vector2(-size.x * 0.5 + 3.0, top + _surface_depth + 1.5), Vector2(size.x * 0.5 - 3.0, top + _surface_depth + 1.5),
		Color(0.0, 0.0, 0.0, 0.14), 1.2, true)


## 取草皮上缘的一条"跟随波浪"的条带，用于绘制受光面。
## 相比对整个多边形做质心缩放，这样得到的高光厚度均匀，不会被压成一条细缝。
func _top_band(thickness: float) -> PackedVector2Array:
	var wave_count := _top_pts.size() - 2
	if wave_count < 2:
		return PackedVector2Array()
	var band := PackedVector2Array()
	for i in wave_count:
		band.append(_top_pts[i])
	for i in range(wave_count - 1, -1, -1):
		band.append(_top_pts[i] + Vector2(0.0, thickness))
	return band


func _draw_stone() -> void:
	var hh := size.y * 0.5
	var top := -hh
	draw_colored_polygon(_body_outline, OUTLINE)
	draw_colored_polygon(_body_pts, STONE_DARK)
	draw_set_transform(Vector2(0.0, -2.0), 0.0, Vector2(0.95, 0.90))
	draw_colored_polygon(_body_pts, STONE_MAIN)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var outline := PackedVector2Array(_top_pts)
	outline.append(outline[0])
	draw_colored_polygon(_top_pts, OUTLINE)
	var centroid := Vector2.ZERO
	for p in _top_pts:
		centroid += p
	centroid /= float(_top_pts.size())
	var inner := PackedVector2Array()
	for p in _top_pts:
		inner.append(centroid + (p - centroid) * 0.88)
	draw_colored_polygon(inner, STONE_LIGHT)

	for pebble in _pebbles:
		draw_circle(pebble["pos"], float(pebble["r"]), Color(STONE_LIGHT, 0.5))
