extends LevelBase
## 序章 · 醒来。
##
## 一间安静的小屋。这一小段不做谜题，只完成三件事：
## 让玩家熟悉左右移动与跳跃的距离感、发现提灯可以开关、
## 以及看到"光会让东西亮起来"这件事本身。
##
## 房间刻意做得小而封闭 —— 玩家不会迷路，也不会掉出去。

const PLATFORM_DATA: Array[Dictionary] = [
	{"pos": Vector2(620, 660), "size": Vector2(1480, 80), "seed": 81},
	{"pos": Vector2(470, 548), "size": Vector2(170, 52), "seed": 83},
	{"pos": Vector2(790, 472), "size": Vector2(170, 52), "seed": 89},
	{"pos": Vector2(1080, 560), "size": Vector2(150, 52), "seed": 97},
]

const PICKUP_DATA: Array[Vector2] = [
	Vector2(790, 408),
]

const PROP_DATA: Array[Dictionary] = [
	{"pos": Vector2(140, 620), "kind": 1, "seed": 401, "scale": 1.0, "sway": 0.2},
	{"pos": Vector2(320, 620), "kind": 2, "seed": 403, "scale": 0.9, "sway": 0.0},
	{"pos": Vector2(960, 620), "kind": 1, "seed": 405, "scale": 0.85, "sway": 0.18},
]

## 屋里的两盏烛台。它们让"被光照亮"这件事在序章就成立。
const CANDLES: Array[Vector2] = [
	Vector2(470, 522),
	Vector2(1080, 534),
]

const GOAL_POSITION := Vector2(1180, 620)
const CAMERA_LIMITS := Rect2(-200.0, -300.0, 1900.0, 1200.0)


func _setup_level() -> void:
	var world := Node2D.new()
	world.name = "World"
	add_child(world)

	_build_platforms(world)
	_build_props(world)
	_build_candles(world)
	_build_pickups(world)

	var goal := GoalLantern.new()
	goal.position = GOAL_POSITION
	goal.z_index = 2
	world.add_child(goal)

	if player != null and player.has_node("Camera"):
		_apply_camera_limits(player.get_node("Camera"))


func _build_platforms(world: Node2D) -> void:
	for entry in PLATFORM_DATA:
		var platform := Platform.new()
		platform.size = entry["size"]
		platform.seed_value = int(entry["seed"])
		platform.position = entry["pos"]
		world.add_child(platform)


func _build_props(world: Node2D) -> void:
	for entry in PROP_DATA:
		var prop := Prop.new()
		prop.kind = int(entry["kind"])
		prop.seed_value = int(entry["seed"])
		prop.shape_scale = float(entry["scale"])
		prop.sway_amount = float(entry["sway"])
		prop.position = entry["pos"]
		prop.z_index = 1
		world.add_child(prop)


func _build_candles(world: Node2D) -> void:
	for pos in CANDLES:
		var lamp := FixedLamp.new()
		lamp.position = pos
		lamp.radius = 205.0
		lamp.energy = 1.05
		lamp.light_color = Color("ffcf8a")
		lamp.lamp_size = 8.0
		lamp.z_index = 3
		world.add_child(lamp)


func _build_pickups(world: Node2D) -> void:
	for pos in PICKUP_DATA:
		var pickup := LanternPickup.new()
		pickup.position = pos
		world.add_child(pickup)


func _apply_camera_limits(camera: Camera2D) -> void:
	camera.limit_left = int(CAMERA_LIMITS.position.x)
	camera.limit_top = int(CAMERA_LIMITS.position.y)
	camera.limit_right = int(CAMERA_LIMITS.position.x + CAMERA_LIMITS.size.x)
	camera.limit_bottom = int(CAMERA_LIMITS.position.y + CAMERA_LIMITS.size.y)
