extends LevelBase
## 尾声 · 万家灯火。
##
## 一段很短的路：从山脊走向崖边，俯瞰整座镇子已经被一盏盏点亮。
## 这里不再有谜题，只需要玩家安静地走完最后几步 ——
## 把节奏放下来，是收尾该做的事。

const PLATFORM_DATA: Array[Dictionary] = [
	{"pos": Vector2(600, 660), "size": Vector2(1400, 80), "seed": 131},
	{"pos": Vector2(1440, 590), "size": Vector2(220, 56), "seed": 137},
	{"pos": Vector2(1720, 520), "size": Vector2(220, 56), "seed": 139},
	{"pos": Vector2(2020, 660), "size": Vector2(620, 80), "seed": 149},
]

const PICKUP_DATA: Array[Vector2] = [
	Vector2(1720, 456),
]

const PROP_DATA: Array[Dictionary] = [
	{"pos": Vector2(120, 620), "kind": 0, "seed": 501, "scale": 1.25, "sway": 0.5},
	{"pos": Vector2(320, 624), "kind": 1, "seed": 503, "scale": 1.0, "sway": 0.3},
	{"pos": Vector2(820, 622), "kind": 0, "seed": 505, "scale": 1.1, "sway": 0.45},
	{"pos": Vector2(2140, 620), "kind": 1, "seed": 507, "scale": 0.95, "sway": 0.24},
]

const GOAL_POSITION := Vector2(2250, 620)
const CAMERA_LIMITS := Rect2(-200.0, -320.0, 2800.0, 1220.0)


func _setup_level() -> void:
	var world := Node2D.new()
	world.name = "World"
	add_child(world)

	_build_platforms(world)
	_build_props(world)
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
