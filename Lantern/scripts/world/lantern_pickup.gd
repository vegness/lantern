class_name LanternPickup
extends Area2D
## 收集物：一小簇漂浮的萤火。
##
## 玩家触碰即收集并计数。视觉用自绘的"多个光点绕行 + 多层柔光"表现，
## 比单个圆点更有生气；上下浮动让静止画面保持呼吸感。

const RADIUS: float = 26.0
const SFX_PICKUP: String = "res://assets/audio/sfx/pickup.wav"
const GLOW := Color("ffd88a")

var _time: float = 0.0
var _base_y: float = 0.0
var _collected: bool = false


func _ready() -> void:
	add_to_group("lantern_pickup")
	collision_layer = 0
	collision_mask = 2
	monitoring = true

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)

	body_entered.connect(_on_body_entered)
	_base_y = position.y
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	if not _collected:
		position.y = _base_y + sin(_time * 1.7) * 4.0
	queue_redraw()


func _draw() -> void:
	var pulse := 1.0 + sin(_time * 3.1) * 0.12

	# 由外向内叠加的柔光
	var radii := [24.0, 19.0, 14.0, 9.0]
	var alpha := 0.045
	for r in radii:
		draw_circle(Vector2.ZERO, r * pulse, Color(GLOW, alpha))
		alpha += 0.065

	# 绕行的三个小光点
	for i in 3:
		var angle := _time * 1.7 + TAU * float(i) / 3.0
		var p := Vector2(cos(angle), sin(angle) * 0.62) * 10.0
		draw_circle(p, 1.6, Color(GLOW, 0.75))

	# 核心
	draw_circle(Vector2.ZERO, 4.6 * pulse, Color(GLOW, 0.6))
	draw_circle(Vector2.ZERO, 3.1 * pulse, Color("fff6d8"))
	draw_circle(Vector2(-0.7, -0.9), 1.5, Color(1, 1, 1, 0.9))


func _on_body_entered(body: Node2D) -> void:
	if _collected or not body.is_in_group("player"):
		return
	_collected = true
	GameManager.collect_lantern()
	AudioManager.play_sfx(SFX_PICKUP, -5.0, randf_range(1.04, 1.14))
	_play_collect()


## 收集动画：放大并淡出，然后移除。
func _play_collect() -> void:
	set_process(false)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.9, 1.9), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.35)
	tween.chain().tween_callback(queue_free)
