class_name FixedLamp
extends Node2D
## 固定光源。
##
## 双重职责：一是制造投影（配合 PressurePlate 的 SHADOW 模式），
## 二是给场景提供氛围照明。光贴图在代码里用 GradientTexture2D 生成，
## 不依赖任何外部素材，因此可以随时调整半径与颜色。

@export var radius: float = 300.0
@export var energy: float = 0.95
@export var light_color: Color = Color("ffd9a0")
## 灯体大小。
@export var lamp_size: float = 10.0
## 是否绘制吊灯造型（否则只留一个发光点）。
@export var show_fixture: bool = true

const METAL_DARK := Color("2b2636")
const METAL := Color("5a5470")
const BULB := Color("fff3d6")

var _light: PointLight2D
var _time: float = 0.0


func _ready() -> void:
	_light = PointLight2D.new()
	_light.texture = _make_radial_texture()
	_light.color = light_color
	_light.energy = energy
	_light.texture_scale = (radius * 2.0) / 512.0
	# 第 1 层 = 照亮场景；第 2 层 = 对玩家的遮挡体投影（见 player.tscn 的 Occluder）
	_light.range_item_cull_mask = 3
	add_child(_light)
	set_process(show_fixture)
	queue_redraw()


## 生成一张中心不透明、边缘完全透明的径向渐变贴图。
## 中间几个控制点让衰减更接近真实灯泡（近处平缓、远处快速收敛）。
static func _make_radial_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.34, 0.66, 1.0])
	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 1.0),
		Color(1, 1, 1, 0.74),
		Color(1, 1, 1, 0.28),
		Color(1, 1, 1, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 512
	texture.height = 512
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	return texture


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if not show_fixture:
		return
	# 灯体：一个悬吊的小灯笼，随时间轻微呼吸
	var pulse := 1.0 + sin(_time * 1.6) * 0.06
	draw_circle(Vector2.ZERO, lamp_size * 0.5, BULB.lerp(light_color, 0.35))
	draw_circle(Vector2(-lamp_size * 0.16, -lamp_size * 0.16), lamp_size * 0.24, Color(1, 1, 1, 0.85))
	draw_arc(Vector2.ZERO, lamp_size * 0.66 * pulse, 0.0, TAU, 20, METAL, 2.0, true)
	draw_line(Vector2(0.0, -lamp_size * 0.66), Vector2(0.0, -lamp_size * 1.7), METAL, 2.0, true)
	draw_circle(Vector2(0.0, -lamp_size * 1.8), 2.6, METAL_DARK)
