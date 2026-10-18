class_name PressurePlate
extends Area2D
## 压力板 —— 两种触发方式。
##
## WEIGHT：有重物（玩家、可推的箱子）压在上面。
## SHADOW：它被"影子"盖住，即光源与它之间的连线被遮挡。
##
## 影子模式用"从光源向板打一条射线"来判定，而不是逐像素采样光照贴图：
## 射线判定开销恒定、行为完全可预期 —— 对解谜来说"可预期"远比"物理精确"重要，
## 玩家必须能预判自己站到哪里会产生影子。
##
## 关卡通过 activated / deactivated 信号把它连到闸门等目标。

enum Mode { WEIGHT, SHADOW }

@export var mode: Mode = Mode.WEIGHT
## SHADOW 模式下用于投影的光源（指向 FixedLamp）。
@export var light_source: Node2D = null
@export var plate_size: Vector2 = Vector2(62.0, 14.0)
## 锁定模式：一旦被触发就保持激活，不会因为玩家离开而失活。
## 这让"站到光路上挡出影子"成为一个可以走开的开关，而不是必须踩住的按钮。
@export var latch: bool = false

signal activated()
signal deactivated()

const STONE_DARK := Color("332e42")
const STONE := Color("55506a")
const STONE_LIGHT := Color("77718c")
const GLOW := Color("ffd88a")
const SFX_ON: String = "res://assets/audio/sfx/plate_on.wav"
const SFX_OFF: String = "res://assets/audio/sfx/plate_off.wav"

var _active: bool = false
var _press: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	add_to_group("puzzle_component")
	collision_layer = 4
	collision_mask = 2
	monitoring = true

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(plate_size.x, plate_size.y + 18.0)
	shape.shape = rect
	shape.position = Vector2(0.0, -9.0)
	add_child(shape)

	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	var now := _evaluate()
	if latch and _active:
		now = true
	if now != _active:
		_active = now
		if _active:
			AudioManager.play_sfx(SFX_ON, -9.0, 1.0)
			activated.emit()
		else:
			AudioManager.play_sfx(SFX_OFF, -11.0, 0.94)
			deactivated.emit()
	_press = move_toward(_press, 1.0 if _active else 0.0, delta * 6.5)
	queue_redraw()


func _evaluate() -> bool:
	if mode == Mode.WEIGHT:
		for body in get_overlapping_bodies():
			if body.is_in_group("player") or body.is_in_group("weight"):
				return true
		return false
	return _blocked_from_light()


## 光源与板之间是否有遮挡物（玩家或箱子）。
##
## 用三条平行射线（中心 + 两侧各偏移 13px）而不是单条：单条射线只在
## 恰好穿过遮挡物中线时才命中，玩家稍微站偏一点就失效，手感非常糟糕。
## 三条射线把有效遮挡宽度扩展到约 50px，符合"站在光路上"的直觉。
func _blocked_from_light() -> bool:
	if light_source == null or not is_instance_valid(light_source):
		return false
	var from := light_source.global_position
	var to := global_position
	var dir := (to - from).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var space := get_world_2d().direct_space_state
	for offset in [0.0, -13.0, 13.0]:
		var query := PhysicsRayQueryParameters2D.create(from + perp * offset, to + perp * offset)
		query.collision_mask = 2
		query.collide_with_areas = false
		if not space.intersect_ray(query).is_empty():
			return true
	return false


func is_active() -> bool:
	return _active


# ---------------------------------------------------------------------------
# 绘制
# ---------------------------------------------------------------------------

func _draw() -> void:
	var hw := plate_size.x * 0.5
	var sink := _press * 3.6
	var top := -plate_size.y - sink

	# 嵌在地里的凹槽
	draw_rect(Rect2(-hw - 2.5, -plate_size.y - 2.0, plate_size.x + 5.0, plate_size.y + 7.0), STONE_DARK, true)
	# 板面
	draw_rect(Rect2(-hw, top, plate_size.x, plate_size.y), STONE, true)
	draw_rect(Rect2(-hw + 3.0, top + 2.0, plate_size.x - 6.0, 3.0), Color(STONE_LIGHT, 0.6), true)

	# 激活指示：板面上方的暖色光点
	if _active:
		var pulse := 0.65 + 0.35 * sin(_time * 4.2)
		draw_circle(Vector2(0.0, top - 7.0), 13.0, Color(GLOW, 0.15 * pulse))
		draw_circle(Vector2(0.0, top - 5.0), 4.2, Color(GLOW, 0.95))

	# SHADOW 模式：画一条指向光源的虚线，让玩家知道"光是从哪来的"
	if mode == Mode.SHADOW and light_source != null and is_instance_valid(light_source):
		var to_light := light_source.global_position - global_position
		var dir := to_light.normalized()
		var length := minf(to_light.length(), 260.0)
		var steps := 9
		for i in steps:
			if i % 2 == 1:
				continue
			var a := Vector2(0.0, top - 6.0) + dir * (18.0 + length * float(i) / float(steps))
			var b := a + dir * (length / float(steps))
			draw_line(a, b, Color(1.0, 0.85, 0.55, 0.16), 1.2, true)
