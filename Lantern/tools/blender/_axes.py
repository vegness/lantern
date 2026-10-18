"""打印骨架各骨骼的局部轴向（世界方向），用来确定"正角度往哪边转"。

为什么需要它：绕 X 轴的正向旋转会把骨骼指向（局部 +Y）推向局部 +Z。
不知道局部 Z 在世界里的朝向，就只能靠"渲染一版看效果"来试符号，
而每次试错都要跑完整套 Blender 渲染。这里几秒钟就能把方向定死。

用法：
    blender --background --factory-startup --python tools/blender/_axes.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402

from build_kid import build_character  # noqa: E402
from animate_kid import build_armature  # noqa: E402

WATCH = [
    "hip", "spine", "head",
    "thigh_l", "shin_l", "foot_l",
    "thigh_r", "shin_r", "foot_r",
    "arm_l", "forearm_l", "arm_r", "forearm_r", "lamp",
]


def main() -> None:
    build_character()
    arm = build_armature(bpy.context.scene.collection)
    print("=== 骨骼局部轴在世界空间的方向（列 = 局部 X / Y / Z）===")
    print("注：局部 +Y 是骨骼指向；绕局部 X 正向旋转会把 +Y 推向 +Z。")
    for name in WATCH:
        pb = arm.pose.bones.get(name)
        if pb is None:
            continue
        m = pb.bone.matrix_local.to_3x3()
        # matrix_local 的列向量即骨骼局部轴在世界（Armature 空间）的表示
        xs = tuple(round(v, 3) for v in m.col[0])
        ys = tuple(round(v, 3) for v in m.col[1])
        zs = tuple(round(v, 3) for v in m.col[2])
        print("AXIS %-10s X=%-22s Y=%-22s Z=%s" % (name, xs, ys, zs))

    print()
    print("=== 实测：给 arm_r 绕局部 X 转 +45°，看手的位置往哪走 ===")
    from animate_kid import set_pose, clear_pose
    base = _hand_world(arm, "forearm_r")
    for ang in (45.0, -45.0):
        clear_pose(arm)
        set_pose(arm, {"arm_r": (ang, 0, 0)})
        bpy.context.view_layer.update()
        pos = _hand_world(arm, "forearm_r")
        d = pos - base
        print("ARM_R_X %+6.1f  手末端位移 = (%.3f, %.3f, %.3f)   %s" % (
            ang, d.x, d.y, d.z,
            "向前(-Y)" if d.y < -0.01 else ("向后(+Y)" if d.y > 0.01 else "无明显前后")))

    print()
    print("=== 实测：forearm_r 绕局部 X 转 ±60°，看手掌往哪走 ===")
    clear_pose(arm)
    base_hand = _tail_world(arm, "forearm_r")
    for ang in (60.0, -60.0):
        clear_pose(arm)
        set_pose(arm, {"forearm_r": (ang, 0, 0)})
        bpy.context.view_layer.update()
        d = _tail_world(arm, "forearm_r") - base_hand
        print("FOREARM_R_X %+6.1f  手掌位移 = (%.3f, %.3f, %.3f)   %s" % (
            ang, d.x, d.y, d.z,
            "向前(-Y)" if d.y < -0.01 else ("向后(+Y)" if d.y > 0.01 else "无明显前后")))

    print()
    print("=== 实测：thigh_r / shin_r 绕局部 X 转 ±40°，看膝/脚往哪走 ===")
    clear_pose(arm)
    base_knee = _tail_world(arm, "thigh_r")
    base_foot = _tail_world(arm, "shin_r")
    for ang in (40.0, -40.0):
        clear_pose(arm)
        set_pose(arm, {"thigh_r": (ang, 0, 0)})
        bpy.context.view_layer.update()
        d = _tail_world(arm, "thigh_r") - base_knee
        print("THIGH_R_X %+6.1f  膝盖位移 = (%.3f, %.3f, %.3f)   %s" % (
            ang, d.x, d.y, d.z,
            "向前(-Y)" if d.y < -0.01 else ("向后(+Y)" if d.y > 0.01 else "无明显前后")))
    for ang in (40.0, -40.0):
        clear_pose(arm)
        set_pose(arm, {"shin_r": (ang, 0, 0)})
        bpy.context.view_layer.update()
        d = _tail_world(arm, "shin_r") - base_foot
        print("SHIN_R_X  %+6.1f  脚踝位移 = (%.3f, %.3f, %.3f)   %s" % (
            ang, d.x, d.y, d.z,
            "向前(-Y)" if d.y < -0.01 else ("向后(+Y)" if d.y > 0.01 else "无明显前后")))


def _tail_world(arm, name: str):
    pb = arm.pose.bones[name]
    return arm.matrix_world @ pb.tail


def _hand_world(arm, name: str):
    return _tail_world(arm, name)


if __name__ == "__main__":
    main()
