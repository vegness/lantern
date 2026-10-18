class_name Gate
extends StaticBody2D
## 闸门。由信号驱动升降（如压力板 activated / deactivated）。
##
## 用 Tween 做位移，并且只在"完全关闭"时才启用碰撞 —— 避免玩家被正在
## 上升的门顶穿，或正好卡在门与地面之间。

@export var gate_size: Vector2 = Vector2(26.0, 170.0)
## 打开时相对初始位置移动多少（通常是向下沉入地面）。
@export var open_offset: Vector2 = Vector2(0.0, 182.0)
@export var start_open: bool = false
@export var duration: float = 0.75

signal opened()
signal closed()

const BODY_DARK := Color("2b2636")
const BODY := Color("4a4460")
const BODY_LIGHT := Color("6a6383")
const METAL := Color("8d8599")

var is_open: bool = false

var _closed_pos: Vector2
var _collision: CollisionShape2D
var _tween: Tween


func _ready() -> void:
	add_to_group("gate")
	_closed_pos = position
	collision_layer = 1
	collision_mask = 0
	_build_collision()
	if start_open:
		is_open = true
		position = _closed_pos + open_offset
		_collision.disabled = true
	set_process(false)


func _build_collision() -> void:
	var rect := RectangleShape2D.new()
	rect.size = gate_size
	_collision = CollisionShape2D.new()
	_collision.shape = rect
	add_child(_collision)


func open() -> void:
	if is_open:
		return
	is_open = true
	_animate(_closed_pos + open_offset)
	AudioManager.play_sfx("res://assets/audio/sfx/gate.wav", -7.0, 1.0)
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_animate(_closed_pos)
	AudioManager.play_sfx("res://assets/audio/sfx/gate.wav", -7.0, 0.86)
	closed.emit()


func _animate(target: Vector2) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	# 开门时立刻放行碰撞，关门时等门到位再挡人
	_collision.disabled = not is_open
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "position", target, duration)
	if not is_open:
		_tween.tween_callback(func() -> void: _collision.disabled = false)


func _draw() -> void:
	var hw := gate_size.x * 0.5
	var hh := gate_size.y * 0.5
	draw_rect(Rect2(-hw - 2.5, -hh, gate_size.x + 5.0, gate_size.y), BODY_DARK, true)
	draw_rect(Rect2(-hw, -hh, gate_size.x, gate_size.y), BODY, true)
	draw_rect(Rect2(-hw + 3.0, -hh, 4.5, gate_size.y), Color(BODY_LIGHT, 0.7), true)

	# 门面上的横向铆条
	var bars := maxi(2, int(gate_size.y / 34.0))
	for i in bars:
		var y := -hh + gate_size.y * (float(i) + 0.5) / float(bars)
		draw_rect(Rect2(-hw + 1.0, y - 1.6, gate_size.x - 2.0, 3.2), Color(METAL, 0.45), true)

	# 顶部的封檐
	draw_rect(Rect2(-hw - 4.0, -hh - 5.0, gate_size.x + 8.0, 7.0), Color(METAL, 0.8), true)
