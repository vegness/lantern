extends LevelBase
## 第三关 · 花园。
##
## 教学重点：生长。
## 深沟之上没有任何现成的桥，但沟边的土里埋着种子荚 —— 提灯照住它，
## 藤蔓就会朝着对岸长出去，变成一条可以走的路。
##
## 两个种子串成"照亮 → 长桥 → 走过去 → 照亮下一个"的节奏。
## 玩家在第一次成功后就能自己推理出后续怎么做，不需要提示文字。

const PLATFORM_DATA: Array[Dictionary] = [
	{"pos": Vector2(400, 660), "size": Vector2(1000, 80), "seed": 61},
	{"pos": Vector2(1400, 660), "size": Vector2(140, 220), "seed": 67},
	{"pos": Vector2(2500, 660), "size": Vector2(1300, 80), "seed": 71},
	{"pos": Vector2(3400, 660), "size": Vector2(300, 80), "seed": 73},
]

## 种子荚：位置、生长方向、长度。
const SEED_DATA: Array[Dictionary] = [
	{"pos": Vector2(872, 618), "dir": Vector2(1, 0), "length": 486.0},
	{"pos": Vector2(1452, 548), "dir": Vector2(1, 0), "length": 452.0},
]

const PICKUP_DATA: Array[Vector2] = [
	Vector2(600, 548),
	Vector2(1400, 466),
	Vector2(2560, 548),
]

const PROP_DATA: Array[Dictionary] = [
	{"pos": Vector2(60, 620), "kind": 0, "seed": 301, "scale": 1.2, "sway": 0.5},
	{"pos": Vector2(230, 624), "kind": 1, "seed": 303, "scale": 1.1, "sway": 0.3},
	{"pos": Vector2(430, 624), "kind": 2, "seed": 305, "scale": 0.9, "sway": 0.0},
	{"pos": Vector2(700, 626), "kind": 1, "seed": 307, "scale": 1.25, "sway": 0.32},
	{"pos": Vector2(2050, 620), "kind": 1, "seed": 309, "scale": 1.0, "sway": 0.28},
	{"pos": Vector2(2200, 620), "kind": 0, "seed": 311, "scale": 1.15, "sway": 0.5},
	{"pos": Vector2(2720, 620), "kind": 2, "seed": 313, "scale": 1.0, "sway": 0.0},
	{"pos": Vector2(2920, 624), "kind": 1, "seed": 315, "scale": 0.95, "sway": 0.26},
	{"pos": Vector2(3180, 620), "kind": 0, "seed": 317, "scale": 1.05, "sway": 0.45},
]

const GOAL_POSITION := Vector2(2960, 620)
const CAMERA_LIMITS := Rect2(-400.0, -260.0, 4300.0, 1180.0)


func _setup_level() -> void:
	var world := Node2D.new()
	world.name = "World"
	add_child(world)

	_build_platforms(world)
	_build_props(world)
	_build_pickups(world)
	_build_seeds(world)

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


func _build_pickups(world: Node2D) -> void:
	for pos in PICKUP_DATA:
		var pickup := LanternPickup.new()
		pickup.position = pos
		world.add_child(pickup)


func _build_seeds(world: Node2D) -> void:
	for entry in SEED_DATA:
		var pod := SeedPod.new()
		pod.position = entry["pos"]
		pod.grow_direction = entry["dir"]
		pod.grow_length = float(entry["length"])
		# 桥面比种子略高一点，玩家从地面走上去时不会有台阶感
		pod.z_index = 1
		world.add_child(pod)


func _apply_camera_limits(camera: Camera2D) -> void:
	camera.limit_left = int(CAMERA_LIMITS.position.x)
	camera.limit_top = int(CAMERA_LIMITS.position.y)
	camera.limit_right = int(CAMERA_LIMITS.position.x + CAMERA_LIMITS.size.x)
	camera.limit_bottom = int(CAMERA_LIMITS.position.y + CAMERA_LIMITS.size.y)
