extends LevelBase
## 第二关 · 影之廊。
##
## 教学重点：投影。
## 走廊中段被一道闸门封锁，唯一的开关是一块"影子压力板" —— 它不认踩踏，
## 只认阴影：只要它处于墙灯与自身连线被遮挡的位置，就会触发。
##
## 玩家要做的推理是：看懂墙上那盏灯到自己脚下的几何关系，然后站到光路中间。
## 板是锁定式的（触发一次就保持），所以谜题的关键是"找到那个位置"，
## 而不是"踩住不放"—— 后者会退化成手感考试。

const PLATFORM_DATA: Array[Dictionary] = [
	{"pos": Vector2(1500, 660), "size": Vector2(3400, 80), "seed": 41},
	{"pos": Vector2(1360, 500), "size": Vector2(150, 60), "seed": 43},
	{"pos": Vector2(3880, 660), "size": Vector2(400, 80), "seed": 47},
	{"pos": Vector2(3480, 560), "size": Vector2(200, 60), "seed": 53},
]

const PICKUP_DATA: Array[Vector2] = [
	Vector2(700, 548),
	Vector2(1780, 452),
	Vector2(2620, 548),
]

const PROP_DATA: Array[Dictionary] = [
	{"pos": Vector2(120, 620), "kind": 2, "seed": 201, "scale": 1.0, "sway": 0.0},
	{"pos": Vector2(460, 620), "kind": 1, "seed": 203, "scale": 0.9, "sway": 0.22},
	{"pos": Vector2(900, 620), "kind": 2, "seed": 205, "scale": 1.15, "sway": 0.0},
	{"pos": Vector2(1900, 620), "kind": 1, "seed": 207, "scale": 1.0, "sway": 0.2},
	{"pos": Vector2(2450, 620), "kind": 2, "seed": 209, "scale": 0.95, "sway": 0.0},
	{"pos": Vector2(2980, 620), "kind": 1, "seed": 211, "scale": 0.85, "sway": 0.2},
	{"pos": Vector2(3300, 620), "kind": 2, "seed": 213, "scale": 1.05, "sway": 0.0},
]

## 墙上的灯。它的位置决定了影子压力板的"光路"。
const LAMP_POSITION := Vector2(1300, 350)
const LAMP_RADIUS: float = 298.0
## 影子压力板。latch = true：触发一次即保持。
const PLATE_POSITION := Vector2(1462, 618)
## 闸门。打开时会向下沉入地面。
const GATE_POSITION := Vector2(2200, 530)
const GATE_SIZE := Vector2(30, 180)

const GOAL_POSITION := Vector2(3060, 620)
const CAMERA_LIMITS := Rect2(-400.0, -260.0, 4600.0, 1180.0)


func _setup_level() -> void:
	var world := Node2D.new()
	world.name = "World"
	add_child(world)

	_build_platforms(world)
	_build_props(world)
	_build_pickups(world)

	var lamp := FixedLamp.new()
	lamp.position = LAMP_POSITION
	lamp.radius = LAMP_RADIUS
	lamp.light_color = Color("ffd9a0")
	lamp.z_index = 3
	world.add_child(lamp)

	var gate := Gate.new()
	gate.position = GATE_POSITION
	gate.gate_size = GATE_SIZE
	gate.open_offset = Vector2(0.0, GATE_SIZE.y + 14.0)
	gate.z_index = 2
	world.add_child(gate)

	var plate := PressurePlate.new()
	plate.mode = PressurePlate.Mode.SHADOW
	plate.light_source = lamp
	plate.position = PLATE_POSITION
	plate.latch = true
	plate.z_index = 2
	world.add_child(plate)

	# 压力板一旦被影子触发，就永久打开闸门
	plate.activated.connect(gate.open)

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
