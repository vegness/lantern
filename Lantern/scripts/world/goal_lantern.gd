class_name GoalLantern
extends Area2D
## 终点灯座。
##
## 玩家触碰后灯座点亮（光晕扩散 + 灯芯亮起），短暂停顿后触发通关。
## 停顿是必要的：让玩家看清"我点亮了它"，而不是画面立刻被结算面板盖住。

const SFX_LIGHT: String = "res://assets/audio/sfx/goal.wav"
const GLOW := Color("ffd88a")
const STONE_DARK := Color("4a4459")
const STONE := Color("6b6478")
const STONE_LIGHT := Color("8b8399")

## 底座尺寸。
const BASE_SIZE := Vector2(46.0, 14.0)
## 立柱高度。
const POST_HEIGHT: float = 46.0
## 灯罩半径。
const HEAD_RADIUS: float = 15.0

var _lit: bool = false
var _lit_progress: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(52.0, 92.0)
	shape.shape = rect
	shape.position = Vector2(0.0, -40.0)
	add_child(shape)

	body_entered.connect(_on_body_entered)
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	if _lit and _lit_progress < 1.0:
		_lit_progress = minf(_lit_progress + delta * 1.6, 1.0)
	queue_redraw()


func _draw() -> void:
	var breathe := 1.0 + sin(_time * 1.9) * 0.05
	var lit := _lit_progress

	# 点亮时向外扩散的光晕
	if lit > 0.01:
		var reach := 26.0 + lit * 96.0
		draw_circle(Vector2(0.0, -88.0), reach, Color(GLOW, 0.035 * (1.0 - lit * 0.45)))
		draw_circle(Vector2(0.0, -88.0), reach * 0.66, Color(GLOW, 0.05 * (1.0 - lit * 0.4)))

	# 底座：上窄下宽的梯形，带描边与顶面高光
	var half_bottom := BASE_SIZE.x * 0.5
	var half_top := BASE_SIZE.x * 0.38
	var base_pts := PackedVector2Array([
		Vector2(-half_bottom, 0.0),
		Vector2(half_bottom, 0.0),
		Vector2(half_top, -BASE_SIZE.y),
		Vector2(-half_top, -BASE_SIZE.y),
	])
	draw_colored_polygon(_expand(base_pts, 2.0), Color("2b2738"))
	draw_colored_polygon(base_pts, STONE_DARK)
	draw_colored_polygon(_shrink(base_pts, 0.72, Vector2(0.0, -2.0)), STONE)

	# 立柱
	var post_rect := Rect2(-4.0, -BASE_SIZE.y - POST_HEIGHT, 8.0, POST_HEIGHT)
	draw_rect(post_rect.grow(2.0), Color("2b2738"), true)
	draw_rect(post_rect, STONE, true)
	draw_rect(Rect2(-3.0, post_rect.position.y, 2.0, POST_HEIGHT), Color(STONE_LIGHT, 0.5), true)

	# 灯罩：外圈深色骨架 + 内部（点亮后亮起）
	var head_center := Vector2(0.0, -BASE_SIZE.y - POST_HEIGHT - HEAD_RADIUS - 2.0)
	draw_circle(head_center, HEAD_RADIUS + 2.4, Color("2b2738"))
	if lit > 0.01:
		draw_circle(head_center, HEAD_RADIUS * breathe, Color(GLOW, 0.45 + lit * 0.45))
		draw_circle(head_center, HEAD_RADIUS * 0.62 * breathe, Color("fff6d8", 0.6 + lit * 0.4))
	else:
		draw_circle(head_center, HEAD_RADIUS, Color("343046"))
		draw_circle(head_center, HEAD_RADIUS * 0.62, Color("3f3a55"))

	# 灯罩骨架：几根竖线，暗示"灯笼"的结构
	var spokes := 6
	for i in spokes:
		var angle := -PI * 0.5 + PI * 2.0 * float(i) / float(spokes)
		var from := head_center + Vector2(cos(angle), sin(angle)) * (HEAD_RADIUS * 0.4)
		var to := head_center + Vector2(cos(angle), sin(angle)) * HEAD_RADIUS
		draw_line(from, to, Color("2b2738", 0.55), 1.4, true)
	draw_arc(head_center, HEAD_RADIUS, 0.0, TAU, 28, Color("2b2738"), 2.4, true)

	# 顶帽
	draw_rect(Rect2(head_center.x - 3.0, head_center.y - HEAD_RADIUS - 6.0, 6.0, 6.0), Color("2b2738"), true)


## 点集沿质心方向外扩，用于得到均匀的描边。
static func _expand(points: PackedVector2Array, amount: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var centroid := Vector2.ZERO
	for p in points:
		centroid += p
	centroid /= float(points.size())
	for p in points:
		var dir := (p - centroid).normalized()
		out.append(p + dir * amount)
	return out


## 点集朝向某个偏移点缩放，用于画出"内层亮面"。
static func _shrink(points: PackedVector2Array, factor: float, bias: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var centroid := Vector2.ZERO
	for p in points:
		centroid += p
	centroid /= float(points.size())
	for p in points:
		out.append(centroid + (p - centroid) * factor + bias)
	return out


func _on_body_entered(body: Node2D) -> void:
	if _lit or not body.is_in_group("player"):
		return
	_lit = true
	AudioManager.play_sfx(SFX_LIGHT, -4.0, 1.0)

	var level := get_tree().get_first_node_in_group("level")
	if level != null and level.has_method("on_goal_reached"):
		level.call("on_goal_reached", self)
	elif level != null and level.has_method("finish_level"):
		# 兜底：没有专门处理时延时一点直接通关
		await get_tree().create_timer(1.1).timeout
		level.call("finish_level")


## 供关卡或外部查询灯座是否已点亮。
func is_lit() -> bool:
	return _lit
