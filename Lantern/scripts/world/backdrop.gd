class_name Backdrop
extends Node2D
## 关卡远景。
##
## 由两层构成：
##   1. 插画层 —— AI 生成的整体背景（天空 + 远景），以很低的视差系数跟随；
##   2. 剪影层 —— 程序化生成的三层山峦轮廓，视差稍高，制造景深。
##
## 为什么自己做视差而不是用 ParallaxBackground：后者是独立的 CanvasLayer，
## 不在 CanvasModulate 所在的 canvas 上，无法被全局压暗，会导致远景比近景亮、
## 破坏夜晚氛围的一致性。自己算视差还能让背景参与同一套光照。
##
## 视差公式（k = parallax 系数）：
##   屏幕位置 = 基准位置 + cam_pos * (1 - k)
##   k = 0 → 完全贴屏不动（最远）；k = 1 → 与世界一起移动（最近）。
## 本节点固定在世界原点，所有偏移都在 _draw 中实时计算。

## AI 生成的插画纹理。
@export var art_texture: Texture2D
## 插画在世界坐标中的尺寸。
@export var art_world_size: Vector2 = Vector2(1500.0, 1016.0)
## 插画的基准位置（世界坐标）。
@export var art_offset: Vector2 = Vector2(-352.0, 250.0)
## 插画的视差系数。Y 分量默认 1.0 —— 垂直方向不视差，
## 避免玩家上下跳动时远景跟着漂移，那样会让人眩晕。
@export var art_parallax: Vector2 = Vector2(0.14, 1.0)

## 是否绘制山峦剪影。
@export var silhouette_enabled: bool = true
## 剪影的视差系数（应大于插画层，形成层次）。
@export var silhouette_parallax: Vector2 = Vector2(0.36, 1.0)
## 剪影基色。三层会在此基础上逐层变亮。
@export var silhouette_color: Color = Color("241d33")
## 山脊基准高度（世界 Y）。
@export var silhouette_horizon: float = 300.0
## 起伏幅度。
@export var silhouette_amplitude: float = 95.0
## 随机种子。同一关卡固定不变，保证每次运行的远景完全一致。
@export var seed_value: int = 7

## 关卡的可行走范围（世界 X），用于把剪影铺满整条路径。
@export var world_span: Vector2 = Vector2(-3200.0, 9600.0)

var _camera: Camera2D = null
var _hills: Array[PackedVector2Array] = []
var _hill_colors: Array[Color] = []


func _ready() -> void:
	z_index = -100
	if silhouette_enabled:
		_build_silhouette()
	set_process(true)
	print("[Backdrop] texture=", art_texture, " size=", art_world_size, " offset=", art_offset, " hills=", _hills.size())


func _process(_delta: float) -> void:
	# 相机可能在关卡加载后才创建，这里做一次惰性获取
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_2d()
	queue_redraw()


var _drew_once: bool = false


func _draw() -> void:
	var cam := _camera.global_position if _camera != null else Vector2.ZERO
	if not _drew_once:
		_drew_once = true
		print("[Backdrop] _draw cam=", cam, " art_offset=", art_offset, " hills=", _hills.size())

	if art_texture != null:
		var offset := Vector2(cam.x * (1.0 - art_parallax.x), cam.y * (1.0 - art_parallax.y))
		draw_texture_rect(art_texture, Rect2(art_offset + offset, art_world_size), false)
		if not _drew_once:
			print("[Backdrop] art rect=", Rect2(art_offset + offset, art_world_size))

	if silhouette_enabled:
		var offset := Vector2(cam.x * (1.0 - silhouette_parallax.x), cam.y * (1.0 - silhouette_parallax.y))
		for i in _hills.size():
			var shifted := PackedVector2Array()
			for p in _hills[i]:
				shifted.append(p + offset)
			draw_colored_polygon(shifted, _hill_colors[i])


## 生成三层山脊。由远及近：更高、更暗、起伏更缓。
func _build_silhouette() -> void:
	_hills.clear()
	_hill_colors.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 6151 + 29

	var layer_count := 3
	for layer in layer_count:
		var depth := float(layer) / float(maxi(layer_count - 1, 1))
		var y_base := silhouette_horizon - (1.0 - depth) * 70.0
		var amp := silhouette_amplitude * (0.45 + depth * 0.75)
		var freq := 0.0014 * (0.65 + depth * 0.5)
		var phase := rng.randf() * TAU
		var step := 90.0

		var pts := PackedVector2Array()
		var x := world_span.x
		while x <= world_span.y:
			# 两个频率叠加，避免出现规则的等距波峰
			var wave := sin(x * freq + phase) * 0.62 + sin(x * freq * 2.5 + phase * 1.7) * 0.38
			pts.append(Vector2(x, y_base - wave * amp))
			x += step
		# 向下收口成实心块
		pts.append(Vector2(world_span.y, y_base + 1400.0))
		pts.append(Vector2(world_span.x, y_base + 1400.0))
		_hills.append(pts)

		# 越近越亮一点，形成空气透视
		var tint := silhouette_color.lightened(depth * 0.16)
		_hill_colors.append(Color(tint, 1.0))
