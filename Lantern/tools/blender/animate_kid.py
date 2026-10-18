"""给"提灯人"加骨架并渲染动作序列帧。

核心思路：
  角色主体是 metaball 融合出的**一张连续曲面**，因此骨骼形变时
  关节处是曲面弯曲，而不是几块独立形状的交界 —— 这正是消除
  "零件缝合感"的关键。饰件（兜帽、靴子、提灯等）用刚性顶点组
  绑到对应骨骼，保证跟随且不产生多余形变。

动作按需求方给的规范拆解：
  · 跳跃分四阶段：起跳压低 → 空中展开 → 下落收紧 → 落地回弹；
  · 重心驱动：先给髋部与躯干的位移/倾角定调，四肢跟随；
  · 循环动作首尾帧完全一致，保证无缝衔接。

用法：
    blender --background --factory-startup --python tools/blender/animate_kid.py -- <动作名>
    动作名：idle / run / jump / all
"""

import math
import os
import sys

import bpy
import mathutils

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from build_kid import OUT_DIR, setup_render, build_character  # noqa: E402

# ---------------------------------------------------------------------------
# 骨架定义：(名称, 父级, head 坐标, tail 坐标)
# 侧视角色 —— 朝向为 -Y，所以"前"是 -Y 方向。
# ---------------------------------------------------------------------------
HIP_Z = 0.40
CHEST_Z = 0.62
NECK_Z = 0.86
HEAD_Z = 0.98

BONES = [
    ("hip", None, (0.0, 0.0, HIP_Z), (0.0, 0.0, HIP_Z + 0.14)),
    ("spine", "hip", (0.0, 0.0, HIP_Z + 0.14), (0.0, 0.0, CHEST_Z + 0.06)),
    ("head", "spine", (0.0, 0.0, CHEST_Z + 0.06), (0.0, 0.0, HEAD_Z + 0.10)),

    ("thigh_l", "hip", (-0.062, 0.0, HIP_Z - 0.02), (-0.066, 0.0, HIP_Z - 0.17)),
    ("shin_l", "thigh_l", (-0.066, 0.0, HIP_Z - 0.17), (-0.070, 0.0, 0.055)),
    ("foot_l", "shin_l", (-0.070, 0.0, 0.055), (-0.070, -0.115, 0.030)),

    ("thigh_r", "hip", (0.062, 0.0, HIP_Z - 0.02), (0.066, 0.0, HIP_Z - 0.17)),
    ("shin_r", "thigh_r", (0.066, 0.0, HIP_Z - 0.17), (0.070, 0.0, 0.055)),
    ("foot_r", "shin_r", (0.070, 0.0, 0.055), (0.070, -0.115, 0.030)),

    ("arm_l", "spine", (-0.150, 0.0, CHEST_Z + 0.055), (-0.185, 0.0, CHEST_Z - 0.06)),
    ("forearm_l", "arm_l", (-0.185, 0.0, CHEST_Z - 0.06), (-0.200, 0.0, CHEST_Z - 0.20)),

    ("arm_r", "spine", (0.150, 0.0, CHEST_Z + 0.055), (0.185, 0.0, CHEST_Z - 0.06)),
    ("forearm_r", "arm_r", (0.185, 0.0, CHEST_Z - 0.06), (0.200, 0.0, CHEST_Z - 0.20)),

    # 提灯：挂在右手前臂末端，独立骨骼方便做钟摆
    ("lamp", "forearm_r", (0.235, 0.0, CHEST_Z - 0.30), (0.235, 0.0, CHEST_Z - 0.44)),
]

# 饰件 -> 绑定的骨骼（刚性跟随）
RIGID_BINDINGS = {
    "Hood": "head",
    "HoodTip": "head",
    "Eye0": "head",
    "Collar": "spine",
    "ScarfTail": "spine",
    "Belt": "hip",
    "Boot0": "foot_l",
    "Boot1": "foot_r",
    "LampBody": "lamp",
    "LampRing": "lamp",
}


def build_armature(collection):
    arm_data = bpy.data.armatures.new("KidArm")
    arm = bpy.data.objects.new("KidArmature", arm_data)
    collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")

    created = {}
    for name, parent, head, tail in BONES:
        bone = arm_data.edit_bones.new(name)
        bone.head = head
        bone.tail = tail
        if parent:
            bone.parent = created[parent]
            bone.use_connect = False
        created[name] = bone

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def bind_body(body, arm) -> None:
    """主体走自动权重 —— metaball 出来的是连续曲面，权重过渡自然。"""
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")


def bind_rigid(obj, arm, bone_name: str) -> None:
    """饰件刚性绑定：整个物体绑到一根骨骼，不参与形变。"""
    if not obj.data.vertices:
        return
    vg = obj.vertex_groups.new(name=bone_name)
    vg.add([v.index for v in obj.data.vertices], 1.0, "REPLACE")
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    obj.parent = arm


def rigid_bind_ornaments(obj, arm) -> None:
    """把饰件从"分散权重"改成"刚性跟随单根骨骼"。

    为什么需要这一步：自动权重会把兜帽的顶点分摊到 head / spine / 甚至手臂上，
    于是头部一转动，兜帽就被朝几个方向同时拉扯、发生形变，渲染出来时有时
    露出脸、有时整个糊住 —— 看起来像角色在"扭头"。

    合并之后没法再用对象名区分部件，但每个 polygon 仍保留原材质索引，
    因此可以用材质反查"这块几何原本属于谁"，再用高度把同材质的不同
    部件（兜帽 vs 领口）分开。

    注意必须同时把这些顶点从**其它**顶点组里移除，否则自动权重的
    残留会影响结果。
    """
    HEAD_ZONE = 0.84
    COLLAR_ZONE = 0.70
    BOOT_ZONE = 0.15

    def target_bone(co, mat_name: str) -> str:
        x, _y, z = co
        # 提灯单独走材质判断：它悬在躯干高度区间内，靠高度分不出来
        if mat_name.startswith("Glow"):
            return "lamp"
        if z > HEAD_ZONE:
            return "head"          # 兜帽、兜帽尖、眼睛
        if z > COLLAR_ZONE:
            return "spine"         # 领口、围巾尾
        if z < BOOT_ZONE:
            return "foot_l" if x < 0.0 else "foot_r"
        return ""

    mat_names = [s.material.name if s.material else "" for s in obj.material_slots]
    # 只处理饰件材质；身体本体（Skin / Cloak）保持自动权重，保留关节形变
    ornament_prefixes = ("Scarf", "Ink", "Glow", "CloakDark")

    buckets: dict = {}
    for poly in obj.data.polygons:
        idx = poly.material_index
        if idx >= len(mat_names):
            continue
        if not mat_names[idx].startswith(ornament_prefixes):
            continue
        for vi in poly.vertices:
            bone = target_bone(obj.data.vertices[vi].co, mat_names[idx])
            if bone:
                buckets.setdefault(bone, set()).add(vi)

    for bone, verts in buckets.items():
        vlist = list(verts)
        for vg in obj.vertex_groups:
            if vg.name != bone:
                vg.remove(vlist)
        group = obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
        group.add(vlist, 1.0, "REPLACE")
    print("RIGID_ORNAMENTS", {k: len(v) for k, v in buckets.items()})


def collect_parts():
    """把场景里的角色网格按名字分类。

    注意：build_character() 最终会把本体与所有饰件 join 成**单个** `Kid`
    网格，所以这里不能去找某个子部件名 —— 找不到就会静默跳过绑定，
    表现为"关键帧写了但角色一动不动"。
    """
    parts = {"body": None, "others": {}}
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        if obj.name.startswith("Kid"):
            parts["body"] = obj
        else:
            parts["others"][obj.name] = obj
    return parts


# ---------------------------------------------------------------------------
# 姿态关键帧
# ---------------------------------------------------------------------------
# 角度单位为度，绕 X 轴旋转即"前后摆动"（侧视平面内）。

def set_pose(arm, pose: dict) -> None:
    """pose: {骨骼名: (rx, ry, rz)}，另外支持 'hip_loc' 做重心升降。

    坐标系陷阱：pose bone 的 `location` 是**骨骼局部空间**，不是世界空间。
    hip 骨骼沿世界 +Z 伸展，因此它的局部 Y 轴对应世界上下方向；
    若按世界直觉写成 (0, 0, dz)，实际会把角色沿前后方向推出去。
    """
    for name, rot in pose.items():
        if name == "hip_loc":
            pb = arm.pose.bones["hip"]
            pb.location = mathutils.Vector((0.0, rot[2], 0.0))
            continue
        pb = arm.pose.bones.get(name)
        if pb is None:
            continue
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = (math.radians(rot[0]), math.radians(rot[1]), math.radians(rot[2]))


def clear_pose(arm) -> None:
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.location = mathutils.Vector((0.0, 0.0, 0.0))


def keyframe(arm, frame: int) -> None:
    for pb in arm.pose.bones:
        pb.keyframe_insert(data_path="rotation_euler", frame=frame)
        pb.keyframe_insert(data_path="location", frame=frame)


# ---------------------------------------------------------------------------
# 动作库
# ---------------------------------------------------------------------------

def poses_idle() -> list:
    """待机：极轻微的呼吸起伏。规范里强调"少即是多"。"""
    return [
        (1, {"hip_loc": (0, 0, 0.0), "spine": (2.0, 0, 0), "head": (-2.0, 0, 0),
             "arm_l": (3.0, 0, 0), "arm_r": (-3.0, 0, 0), "forearm_r": (2.0, 0, 0)}),
        (5, {"hip_loc": (0, 0, -0.012), "spine": (3.5, 0, 0), "head": (-3.5, 0, 0),
             "arm_l": (4.0, 0, 0), "arm_r": (-4.0, 0, 0), "forearm_r": (3.0, 0, 0)}),
        (9, {"hip_loc": (0, 0, 0.0), "spine": (2.0, 0, 0), "head": (-2.0, 0, 0),
             "arm_l": (3.0, 0, 0), "arm_r": (-3.0, 0, 0), "forearm_r": (2.0, 0, 0)}),
    ]


def poses_run() -> list:
    """奔跑：八帧循环。躯干前倾固定，四肢与重心按步态相位交替。"""
    lean = 14.0
    frames = []
    # (帧, 左腿髋, 左膝, 右腿髋, 右膝, 重心高度, 左臂, 右臂, 提灯摆)
    keys = [
        (1, 38, -18, -26, 34, -0.020, -34, 30, 10),
        (3, 12, 6, -32, 18, -0.006, -18, 16, 4),
        (5, -26, 34, 38, -18, -0.020, 30, -34, -10),
        (7, -32, 18, 12, 6, -0.006, 16, -18, -4),
        (9, 38, -18, -26, 34, -0.020, -34, 30, 10),
    ]
    for frame, lh, lk, rh, rk, drop, al, ar, lamp in keys:
        frames.append((frame, {
            "hip_loc": (0, 0, drop),
            "spine": (lean, 0, 0),
            "head": (-lean * 0.55, 0, 0),
            "thigh_l": (lh, 0, 0), "shin_l": (lk, 0, 0),
            "thigh_r": (rh, 0, 0), "shin_r": (rk, 0, 0),
            "arm_l": (al, 0, 0), "forearm_l": (-18, 0, 0),
            "arm_r": (ar, 0, 0), "forearm_r": (-22, 0, 0),
            "lamp": (lamp, 0, 0),
        }))
    return frames


# 腿骨几何（与上面的 BONES 表一致）：髋→膝 0.17，膝→踝 0.175，直立时踝在髋下 0.345。
THIGH_LEN = 0.17
SHIN_LEN = 0.175
LEG_REST = THIGH_LEN + SHIN_LEN

# 靴子形状（抄 build_kid.py 的 Boot 球体），相对脚踝换算；半轴 (y, z)
BOOT_CY = -0.016
BOOT_CZ = -0.005
BOOT_AY = 0.090
BOOT_AZ = 0.053


def _boot_low(theta: float) -> float:
    """靴子绕脚踝转 theta 弧度后，鞋底最低点相对脚踝的高度（负值）。"""
    cy = BOOT_CY * math.cos(theta) - BOOT_CZ * math.sin(theta)
    cz = BOOT_CY * math.sin(theta) + BOOT_CZ * math.cos(theta)
    r = math.sqrt((BOOT_AY * math.sin(theta)) ** 2 + (BOOT_AZ * math.cos(theta)) ** 2)
    return cz - r


_BOOT_LOW0 = _boot_low(0.0)


def leg_dz(thigh_deg: float, shin_deg: float, foot_deg: float = 0.0) -> float:
    """双脚贴地时髋部应取的位移（米）。正 = 抬高，负 = 下沉。

    为什么必须算而不是手填：髋位移填得比腿骨几何允许值更深，脚就穿到地板
    以下；更浅，脚悬空。两者都不报错，只在画面上表现为"蹲不下去"或
    "陷进地里"。**判据是把该帧 alpha>16 的包围盒底边与地面线 373 对比**
    （旧版深蹲帧低了 16 像素）。
    """
    a1 = math.radians(thigh_deg)
    a2 = math.radians(thigh_deg + shin_deg)
    return (THIGH_LEN * math.cos(a1) + SHIN_LEN * math.cos(a2) - LEG_REST
            + (_BOOT_LOW0 - _boot_low(math.radians(foot_deg))))


def poses_jump() -> list:
    """跳跃：预压 → 蹬伸 → 顶点 → 下落 → 触地缓冲 → 回弹 → 站定。

    ── 这一版是照真人视频逐帧比对出来的，不是凭关节角文献反推 ──
    参考素材：`verify/ref_jump/BV1JfnwzVEnW.mp4`（【增强式训练】摆臂连续纵跳，
    1280×720 / 28 fps，侧面全身入镜）。逐帧图见
    `verify/ref_jump/sheet_cycle2.png` 与 `verify/ref_jump/sheet_key2.png`。
    参考里一个完整跳跃的读法：

      f040~f047  深蹲蓄力：膝屈约 80°、**髋大幅后坐**、躯干前倾约 25°，
                 **双臂向后并向上甩到髋以上、肘几乎伸直** —— 整段最可读的姿势
      f048~f051  蹬伸：腿快速打直，双臂从体侧向前甩过髋
      f052~f055  离地：**双臂继续向上甩到头顶以上，双手过头**
      f056~f060  滞空：手臂保持高位，两腿收拢
      f061~f067  落地缓冲 → 起身，手臂放下

    ── 上一版"像僵尸"的根因只有一条 ──
    上一版为了不让提灯甩到头顶以上，把提灯臂峰值人为限制在 −48、自由臂 −94
    —— **手臂根本没抬起来，最可读的那个动作被自己掐掉了**。参考里手臂是明确
    过头的。本版改回"手臂真正甩起来"：
      · 近端自由臂（左）峰值 −122（过头）
      · 提灯臂（右）峰值 −92（手到头部高度，灯升到胸/下颌，不越过头顶）
    既补回完整的甩臂弧线，又保住"灯不越过头顶"这条造型约定。

    ── 第二条：斗篷不能再"向前走" ──
    斗篷刚性绑在 spine 上，spine 一旦后仰，斗篷下摆就会向前甩出去
    （上一版离地帧写了 spine −2/−4，下摆就被吹到身前）。本版**空中段 spine
    一律 ≥ 0**，"身体拉开"改由手臂过头 + 腿蹬直来表现，不靠后仰。

    ── 第三条：后摆在本造型上读不出来，别再指望它 ──
    3/4 视角 + 长斗篷实测（`_probe_arms.py`）：手臂后摆时贴在斗篷上，
    是浅色压浅色，几乎不可见；抬到身前上方则是浅色压暗背景，极清晰。
    所以甩臂的重心放在**前上摆**，后摆只做到姿态正确即可。

    符号（`_axes.py` 实测）：thigh 负 = 膝向前；shin 正 = 膝正常弯曲；
    foot 正 = 提踵；arm 正 = 手向后；forearm 负 = 屈肘；spine 正 = 前倾。
    """
    # ── 帧预算（16 帧，四段等分，对齐参考的四个阶段）────────────────────
    # 图像 1..4  = 地面蓄力（由 player.gd 的 JUMP_SQUAT 提供真实地面时间）
    #              下沉 → 深蹲/双臂甩到身后并抬起 → 蹬伸 → 提踵离地
    # 图像 5..8  = 上升   刚离地 → 双臂甩到头顶以上（峰值）→ 收腿 → 顶点
    # 图像 9..12 = 下落   向下探 → 加速 → 伸腿 → 触地前
    # 图像 13..16= 落地   触地 → 缓冲最低点 → 回弹 → 站定
    #
    # ⚠️ 图像 13 是落地段的第一帧（引擎里 fall_end+1 就是它）。"触地接触"必须
    #    排在落地段首位，排在下落段末尾会被直接跳过。
    #
    # 双臂的节奏对齐参考：f2 甩到身后并抬起（+78/+64）→ f4 已甩到身前（−74/−58）
    # → f5/f6 继续甩到过头（−112/−122），**峰值出现在离地之后**，与参考一致。
    # 提灯臂全程比自由臂少约 25~30°，保证灯不越过头顶。
    # 空中段 spine 一律 ≥ 0（参见上面"斗篷不能再向前走"）。
    # 地面帧的 dz 传 None，由 leg_dz() 按腿骨几何反推，保证脚踩在地上。
    # (f, spine, head, tl, sl, fl, tr, sr, fr, al, fal, ar, far, lamp, dz)
    keys = [
        # ── 地面蓄力（图像 1..4）──
        # 1 下沉起始：膝开始弯、髋开始后坐、双臂起摆向后
        (1, 6, -3, -16, 26, -2, -14, 24, -2, 30, -16, 26, -20, -8, None),
        # 2 深蹲蓄力（≈参考 f040~f047）：膝屈 68°、髋大幅后坐，
        #   双臂向后**并抬起**到髋以上、肘几乎伸直 —— 整段最可读的姿势。
        #   ⚠️ 躯干前倾只敢给 9°：斗篷刚性绑在 spine 上，参考里真人前倾 25°
        #   是躯干的事，我们这里多出来的倾角会整块甩到斗篷下摆上，
        #   12° 以上就开始像"跳水"。
        (2, 9, -8, -56, 68, -8, -53, 65, -8, 78, -12, 64, -16, -14, None),
        # 3 蹬伸（≈参考 f048）：腿快速打直，双臂**已经甩到体前、肘明显屈**，
        #   不能停在体侧 —— 停在体侧会让"甩臂"读成两段不相干的动作
        (3, 8, -4, -26, 32, 12, -23, 29, 12, -8, -34, 0, -34, 12, None),
        # 4 提踵离地：髋膝踝三关节伸展、脚尖下压，双臂已甩到身前肩高
        (4, 2, 0, -6, 8, 30, -8, 10, 30, -66, -24, -54, -26, 12, None),

        # ── 上升（图像 5..8，物理时长 = JUMP_VELOCITY/GRAVITY ≈ 0.329 s）──
        # 空中帧的 dz 手填：不能用 leg_dz（那等于把髋拽回"脚踩地"的高度）
        # 5 刚离地：腿几乎伸直、脚尖仍下压；双臂继续向上甩
        (5, 0, 2, 4, 6, 28, -10, 14, 28, -100, -24, -80, -28, 8, 0.030),
        # 6 双臂峰值（≈参考 f052~f055，但角度受造型限制）
        #   ⚠️ 参考里双手是**过头顶**的，本造型做不到：兜帽太大，
        #   手臂一过 −125 就钻进兜帽后面消失（实测 verify/probe_armpeak.png：
        #   −90/−105/−120 手清清楚楚，−135/−150 被兜帽吃掉）。
        #   故峰值取 −118：上臂抬到肩以上约 25°，手到头部高度、清清楚楚。
        (6, 2, 1, -14, 24, 20, -28, 42, 18, -118, -20, -100, -26, 0, 0.040),
        # 7 开始收腿，躯干立起，双臂开始回落
        (7, 4, -2, -32, 50, 14, -44, 68, 12, -104, -28, -88, -30, -10, 0.040),
        # 8 顶点：两腿收拢（前后错开），双臂下压到胸肩高度配平
        (8, 6, -4, -38, 56, 10, -48, 74, 8, -86, -32, -74, -32, -8, 0.032),

        # ── 下落（图像 9..12，物理时长同上升）──
        # 9 下落起始：双腿向下探，双臂继续下行
        (9, 7, -5, -26, 38, 12, -32, 48, 10, -60, -34, -54, -32, -2, 0.022),
        # 10 加速下落：腿接近伸直、脚尖微压准备触地
        (10, 9, -6, -16, 24, 14, -20, 30, 12, -28, -30, -26, -30, 4, 0.012),
        # 11 双腿向下伸、双臂向后打开（落地前的反向准备）
        #    空中帧的 dz 要保证包围盒底边 < 373（脚仍离地），实测该帧腿形
        #    "贴地"时 dz≈−0.006，故取 +0.008 让脚明确悬在地面线上方。
        (11, 10, -7, -12, 18, 16, -16, 22, 14, 14, -26, 12, -26, 8, 0.008),
        # 12 触地前瞬间：脚尖已基本够到地面，躯干前倾最大
        (12, 11, -8, -10, 14, 18, -12, 16, 16, 26, -24, 22, -24, 8, 0.010),

        # ── 落地（图像 13..16，物理时长 = LAND_HOLD）──
        # 13 触地：前脚掌先着地，膝开始屈曲，双臂前伸配平
        (13, 12, -8, -24, 34, 8, -26, 36, 6, -8, -28, -6, -28, 6, None),
        # 14 缓冲最低点：比预压更深，髋膝踝同步吸收
        (14, 14, -9, -54, 62, -4, -52, 60, -4, -22, -34, -16, -32, -6, None),
        # 15 回弹：起身，双臂收回
        (15, 6, -4, -24, 32, 2, -22, 30, 2, 2, -22, 0, -24, 6, None),
        # 16 站定：与 idle 首帧完全一致，保证无缝接回待机
        (16, 2, -2, 0, 0, 0, 0, 0, 0, 3, 0, -3, 2, 0, None),
    ]

    frames = []
    for (f, spine, head, tl, sl, fl, tr, sr, fr,
         al, fal, ar, far, lamp, dz) in keys:
        if dz is None:
            # 双脚贴地：取两腿各自所需髋位移的平均。两腿角度接近时误差远小于 1 像素。
            dz = 0.5 * (leg_dz(tl, sl, fl) + leg_dz(tr, sr, fr))
        frames.append((f, {
            "hip_loc": (0, 0, dz),
            "spine": (spine, 0, 0), "head": (head, 0, 0),
            "thigh_l": (tl, 0, 0), "shin_l": (sl, 0, 0), "foot_l": (fl, 0, 0),
            "thigh_r": (tr, 0, 0), "shin_r": (sr, 0, 0), "foot_r": (fr, 0, 0),
            "arm_l": (al, 0, 0), "forearm_l": (fal, 0, 0),
            "arm_r": (ar, 0, 0), "forearm_r": (far, 0, 0),
            "lamp": (lamp, 0, 0),
        }))
    return frames


CLIPS = {
    "idle": poses_idle,
    "run": poses_run,
    "jump": poses_jump,
}

# 渲染分辨率。必须与 scripts/player/player_visual.gd 的 IMG_W / IMG_H 一致。
# 相机是正交的且 ortho_scale 作用在长边，所以改分辨率不改变取景，
# 只改变过采样倍率：角色在 720p 画面里高约 94 px，200×240 的源图
# 只有 1.65 倍过采样，轮廓会发软；400×480 提到 3.3 倍。
# 提灯锚点表（player_visual.gd 的 LAMP_ANCHORS）以世界单位记录，
# 与分辨率无关，改分辨率后无需重测。
RENDER_W = 400
RENDER_H = 480

# 渲染结束后把"带骨架 + 全部关键帧"的场景另存一份，供人在 Blender 界面里
# 直接拖关键帧微调动作（命令行渲染无法交互，而手感调优最终要人眼判断）。
# 放在 tools/ 下，导出预设已排除该目录，不会进游戏包。
BLEND_PATH = os.path.join(ROOT, "tools", "blender", "kid_rigged.blend")


def render_clip(arm, name: str, frames: list) -> None:
    out = os.path.join(OUT_DIR, name)
    os.makedirs(out, exist_ok=True)
    scene = bpy.context.scene
    last = max(f for f, _ in frames)
    scene.frame_start = 1
    scene.frame_end = last

    # 一次性把关键帧全部写上
    clear_pose(arm)
    for frame, pose in frames:
        set_pose(arm, pose)
        keyframe(arm, frame)

    # 线性插值会让动作发死，用贝塞尔缓入缓出更接近手绘的节奏
    for action in bpy.data.actions:
        for fcurve in action.fcurves:
            for kp in fcurve.keyframe_points:
                kp.interpolation = "BEZIER"
                kp.easing = "AUTO"

    for frame in range(1, last + 1):
        scene.frame_set(frame)
        scene.render.filepath = os.path.join(out, "%03d.png" % frame)
        bpy.ops.render.render(write_still=True)
    print("CLIP_DONE", name, last)


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    which = args[0] if args else "all"

    os.makedirs(OUT_DIR, exist_ok=True)
    build_character()
    setup_render(RENDER_W, RENDER_H)

    collection = bpy.context.scene.collection
    parts = collect_parts()

    arm = build_armature(collection)
    if parts["body"] is not None:
        bind_body(parts["body"], arm)
        rigid_bind_ornaments(parts["body"], arm)
    for obj_name, bone_name in RIGID_BINDINGS.items():
        obj = parts["others"].get(obj_name)
        if obj is not None:
            bind_rigid(obj, arm, bone_name)

    target = CLIPS.keys() if which == "all" else [which]
    for name in target:
        render_clip(arm, name, CLIPS[name]())

    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print("SAVED_BLEND", BLEND_PATH)


if __name__ == "__main__":
    main()
