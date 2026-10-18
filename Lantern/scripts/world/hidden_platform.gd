class_name HiddenPlatform
extends Platform
## 隐藏平台 —— "显形"机制的载体。
##
## 处于暗处时只剩一个几乎看不见的轮廓，被提灯照到才逐渐显现。
## 玩家由此学会用光源"发现"路径，而不需要任何文字说明。
##
## 判定用"平台与玩家的距离"而不是真实的光照采样：逐像素采样光照贴图
## 在这个体量的游戏里属于过度设计，而距离判定在观感上几乎等价，
## 且开销恒定。

## 判定半径在提灯半径之外再放宽多少，避免边缘的平台"闪烁"。
@export var reveal_margin: float = 55.0
## 未被照亮时的透明度。留一点点轮廓，让玩家隐约感到"这里有东西"。
@export var hidden_alpha: float = 0.13
## 显形 / 消隐的速度。
@export var reveal_speed: float = 2.6

var _reveal: float = 0.0


func _ready() -> void:
	super()
	modulate.a = hidden_alpha
	set_process(true)


func _process(delta: float) -> void:
	var target := 0.0
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("is_lantern_on") and bool(player.call("is_lantern_on")):
		var reach: float = GameConfig.LANTERN_RADIUS + maxf(size.x, size.y) * 0.5 + reveal_margin
		var distance := global_position.distance_to((player as Node2D).global_position)
		target = clampf(1.0 - distance / reach, 0.0, 1.0)
		# 压一下曲线，让光边缘的衰减更快、中心更实
		target = pow(target, 0.75)

	_reveal = move_toward(_reveal, target, delta * reveal_speed)
	modulate.a = lerpf(hidden_alpha, 1.0, _reveal)


## 当前显形程度，0 为完全隐藏，1 为完全显现。
func reveal_amount() -> float:
	return _reveal
