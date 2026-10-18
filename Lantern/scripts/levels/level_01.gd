extends LevelBase
## 第一关 · 提灯入夜。
##
## 教学重点：光照显形。
## 前段是常规平台跳跃，用来建立基本手感与"我能跳多远"的直觉；
## 中段进入黑暗区域，路径只由"被提灯照到才显形"的平台构成 ——
## 玩家会自然学会用光找路，全程不需要一句文字说明。
##
## 关卡内容用数据表描述而不是在场景树里手摆节点：坐标、尺寸、随机种子
## 集中在一处，调跳跃间距时不必逐个点开节点，也便于写回归脚本。

const PLATFORM_DATA: Array[Dictionary] = [
	{"pos": Vector2(420, 640), "size": Vector2(960, 80), "seed": 3},
	{"pos": Vector2(1080, 600), "size": Vector2(240, 70), "seed": 5},
	{"pos": Vector2(1400, 545), "size": Vector2(220, 70), "seed": 7},
	{"pos": Vector2(1700, 490), "size": Vector2(200, 70), "seed": 11},
	{"pos": Vector2(2600, 450), "size": Vector2(220, 70), "seed": 13},
	{"pos": Vector2(2880, 520), "size": Vector2(200, 70), "seed": 17},
	{"pos": Vector2(3400, 640), "size": Vector2(700, 80), "seed": 19},
]

## 只在光照下显形的平台，构成中段的"看不见的路"。
const HIDDEN_DATA: Array[Dictionary] = [
	{"pos": Vector2(1990, 435), "size": Vector2(200, 70), "seed": 23},
	{"pos": Vector2(2290, 400), "size": Vector2(200, 70), "seed": 29},
]

const PICKUP_DATA: Array[Vector2] = [
	Vector2(1700, 396),
	Vector2(2180, 292),
	Vector2(3210, 540),
]

const PROP_DATA: Array[Dictionary] = [
	{"pos": Vector2(60, 600), "kind": 0, "seed": 101, "scale": 1.15, "sway": 0.5},
	{"pos": Vector2(150, 604), "kind": 1, "seed": 103, "scale": 1.0, "sway": 0.25},
	{"pos": Vector2(300, 606), "kind": 2, "seed": 105, "scale": 1.0, "sway": 0.0},
	{"pos": Vector2(620, 602), "kind": 1, "seed": 107, "scale": 1.2, "sway": 0.3},
	{"pos": Vector2(780, 600), "kind": 0, "seed": 109, "scale": 1.3, "sway": 0.6},
	{"pos": Vector2(880, 606), "kind": 2, "seed": 111, "scale": 0.85, "sway": 0.0},
	{"pos": Vector2(1440, 508), "kind": 1, "seed": 113, "scale": 0.8, "sway": 0.25},
	{"pos": Vector2(2660, 412), "kind": 2, "seed": 115, "scale": 0.9, "sway": 0.0},
	{"pos": Vector2(3060, 600), "kind": 0, "seed": 117, "scale": 1.2, "sway": 0.55},
	{"pos": Vector2(3180, 604), "kind": 1, "seed": 119, "scale": 1.0, "sway": 0.3},
	{"pos": Vector2(3620, 600), "kind": 0, "seed": 121, "scale": 1.0, "sway": 0.5},
	{"pos": Vector2(3700, 606), "kind": 2, "seed": 123, "scale": 0.9, "sway": 0.0},
]

const GOAL_POSITION := Vector2(3540, 600)
## 相机与关卡的可行性范围。
const CAMERA_LIMITS := Rect2(-300.0, -320.0, 4400.0, 1220.0)


func _setup_level() -> void:
	var world := Node2D.new()
	world.name = "World"
	add_child(world)

	_build_platforms(world)
	_build_props(world)
	_build_pickups(world)
	_build_goal(world)

	if player != null and player.has_node("Camera"):
		_apply_camera_limits(player.get_node("Camera"))


func _build_platforms(world: Node2D) -> void:
	for entry in PLATFORM_DATA:
		var platform := Platform.new()
		platform.size = entry["size"]
		platform.seed_value = int(entry["seed"])
		platform.position = entry["pos"]
		world.add_child(platform)

	for entry in HIDDEN_DATA:
		var hidden := HiddenPlatform.new()
		hidden.size = entry["size"]
		hidden.seed_value = int(entry["seed"])
		hidden.position = entry["pos"]
		world.add_child(hidden)


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


func _build_goal(world: Node2D) -> void:
	var goal := GoalLantern.new()
	goal.position = GOAL_POSITION
	goal.z_index = 2
	world.add_child(goal)


func _apply_camera_limits(camera: Camera2D) -> void:
	camera.limit_left = int(CAMERA_LIMITS.position.x)
	camera.limit_top = int(CAMERA_LIMITS.position.y)
	camera.limit_right = int(CAMERA_LIMITS.position.x + CAMERA_LIMITS.size.x)
	camera.limit_bottom = int(CAMERA_LIMITS.position.y + CAMERA_LIMITS.size.y)
