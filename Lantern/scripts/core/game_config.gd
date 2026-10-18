extends Node
## 全局静态配置中心。
##
## 集中存放视口常量、物理手感参数、提灯参数、关卡清单与调色板。
## 所有需要"整体微调"的数值都应放在这里，避免散落在各个场景与脚本中。

# ---------------------------------------------------------------------------
# 视口
# ---------------------------------------------------------------------------

## 设计分辨率。所有关卡与 UI 均按此尺寸布局，缩放交由 stretch 设置处理。
const VIEW_W: int = 1280
const VIEW_H: int = 720

# ---------------------------------------------------------------------------
# 物理手感
# ---------------------------------------------------------------------------

## 重力加速度（像素/秒²）。数值偏大让下落更干脆，符合平台游戏预期。
const GRAVITY: float = 1900.0
## 下落速度上限，避免长时间加速导致穿透与视觉不适。
const MAX_FALL_SPEED: float = 880.0

## 地面最大水平速度。
const RUN_SPEED: float = 265.0
## 地面加速度。数值高则起步更快，操作更"跟手"。
const GROUND_ACCEL: float = 2400.0
## 地面摩擦。松开方向键后的减速力度。
const GROUND_FRICTION: float = 2800.0
## 空中加速度，略低于地面以保留惯性感。
const AIR_ACCEL: float = 1700.0
## 空中摩擦。数值很低，避免出现"空中急刹"的违和感。
const AIR_FRICTION: float = 700.0

## 起跳初速度（负值表示向上）。
const JUMP_VELOCITY: float = -625.0
## 提前松开跳跃键时保留的上升速度比例，用于实现可变跳跃高度。
const JUMP_CUT: float = 0.42
## 土狼时间：离开平台边缘后仍允许起跳的宽限时长。
const COYOTE_TIME: float = 0.10
## 跳跃缓冲：落地前提前按下的跳跃指令会被记住的时长。
const JUMP_BUFFER: float = 0.12

## 角色在空中的最大水平速度略高于地面，让跳跃更具延展感。
const AIR_SPEED_BONUS: float = 18.0

# ---------------------------------------------------------------------------
# 提灯（光源）
# ---------------------------------------------------------------------------

## 提灯基础照明半径（像素）。直接决定明暗分界的观感。
const LANTERN_RADIUS: float = 258.0
## 提灯能量（Light2D.energy）。高于 1 会让暖色更饱满。
const LANTERN_ENERGY: float = 1.15
## 光边缘柔化程度。
const LANTERN_SOFTNESS: float = 1.25
## 关闭提灯时的照明半径，保留一点微光以免完全看不见路。
const LANTERN_RADIUS_OFF: float = 96.0

# ---------------------------------------------------------------------------
# 调色板（温馨向：暖光 + 低饱和冷夜，明暗对比舒适不刺眼）
# ---------------------------------------------------------------------------

## 深夜底色。用于 CanvasModulate 的全局压暗。
const C_NIGHT_DEEP := Color("1c1a33")
const C_NIGHT := Color("2b2751")
const C_NIGHT_SOFT := Color("3d3668")
## 黄昏暖色，用于中景与远景的过渡。
const C_DUSK_PINK := Color("d98ba0")
const C_DUSK_ORANGE := Color("e8a15e")
## 灯光的核心与外晕。
const C_LAMP_CORE := Color("fff4d9")
const C_LAMP := Color("ffd88a")
const C_LAMP_DEEP := Color("e8a15e")
## 木质结构。
const C_WOOD := Color("9b6b45")
const C_WOOD_DARK := Color("6d4830")
## 植被。
const C_LEAF := Color("7ba86a")
const C_LEAF_DARK := Color("517a4c")
const C_MOSS := Color("8fbc8f")
## 中性。
const C_CREAM := Color("f7efe2")
const C_STONE := Color("8d8fa6")

# ---------------------------------------------------------------------------
# 关卡清单
# ---------------------------------------------------------------------------
# 每关的 ambient 是 CanvasModulate 的颜色，决定整体光照氛围；
# bg_top / bg_bottom 用于程序化天空渐变；fog 是远景雾色。
# 依三幕结构推进：教学 → 显形 → 投影 → 生长 → 尾声。

const LEVELS: Array[Dictionary] = [
	{
		"id": "prologue",
		"title": "序章 · 醒来",
		"subtitle": "一间安静的屋子里，有盏灯刚刚睁开眼。",
		"scene": "res://scenes/levels/prologue.tscn",
		"chapter": "序",
		"ambient": Color(0.92, 0.88, 0.80),
		"bg_top": Color("3d4a66"),
		"bg_bottom": Color("6d7a92"),
		"fog": Color("8d97ad"),
	},
	{
		"id": "level_01",
		"title": "第一关 · 提灯入夜",
		"subtitle": "光照到的地方，世界才肯露出颜色。",
		"scene": "res://scenes/levels/level_01.tscn",
		"chapter": "微光",
		"ambient": Color(0.58, 0.55, 0.72),
		"bg_top": Color("2a2a4d"),
		"bg_bottom": Color("7a5a74"),
		"fog": Color("9a7f96"),
	},
	{
		"id": "level_02",
		"title": "第二关 · 影之廊",
		"subtitle": "影子也是身体的一部分，把它放到该去的地方。",
		"scene": "res://scenes/levels/level_02.tscn",
		"chapter": "光影",
		"ambient": Color(0.40, 0.42, 0.64),
		"bg_top": Color("1d2144"),
		"bg_bottom": Color("47406e"),
		"fog": Color("5f5a86"),
	},
	{
		"id": "level_03",
		"title": "第三关 · 花园",
		"subtitle": "有些东西睡着了，光是叫醒它们的方式。",
		"scene": "res://scenes/levels/level_03.tscn",
		"chapter": "生长",
		"ambient": Color(0.38, 0.50, 0.56),
		"bg_top": Color("16283a"),
		"bg_bottom": Color("2f5a5c"),
		"fog": Color("4a7d78"),
	},
	{
		"id": "epilogue",
		"title": "尾声 · 万家灯火",
		"subtitle": "你走过的地方，一盏一盏地亮了。",
		"scene": "res://scenes/levels/epilogue.tscn",
		"chapter": "归途",
		"ambient": Color(0.88, 0.80, 0.70),
		"bg_top": Color("3a4a72"),
		"bg_bottom": Color("d98b5e"),
		"fog": Color("e8a15e"),
	},
]


## 取关卡数据；索引越界时返回最后一关，避免调用处崩溃。
func level_at(index: int) -> Dictionary:
	if LEVELS.is_empty():
		return {}
	return LEVELS[clampi(index, 0, LEVELS.size() - 1)]


## 按 id 取关卡索引，找不到返回 -1。
func level_index_of(id: String) -> int:
	for i in LEVELS.size():
		if LEVELS[i].get("id", "") == id:
			return i
	return -1


## 关卡总数。
func level_count() -> int:
	return LEVELS.size()
