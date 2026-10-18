"""一次性标定：把"上臂/前臂角度"与"画面观感"对应起来。

背景：骨架里骨骼尾部朝下，绕局部 X 旋转到底在画面上转多少，只能实测。
与其"改一版渲染一版"地试符号与量级（每轮要跑整套构建 + 渲染），
不如一次把候选角度全渲出来横向对比。

用法：
    blender --background --factory-startup --python tools/blender/_sweep.py
输出：<项目>/verify/sweep_arm.png
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import mathutils  # noqa: E402

from build_kid import ROOT, build_character, setup_render  # noqa: E402
from animate_kid import (  # noqa: E402
    RIGID_BINDINGS,
    bind_body,
    bind_rigid,
    build_armature,
    clear_pose,
    collect_parts,
    rigid_bind_ornaments,
    set_pose,
)

OUT = os.path.join(ROOT, "verify", "sweep")


def bind_all(arm) -> None:
    """把角色网格绑到骨架。

    ⚠️ 漏掉这一步的后果极具欺骗性：网格不受骨架变形，渲染出来永远是
    静置姿势 —— 看起来像"改了角度但画面没反应"，很容易被误判成
    "角度符号不对"而去乱调数值。必须与 animate_kid.main() 的绑定流程一致。
    """
    parts = collect_parts()
    if parts["body"] is not None:
        bind_body(parts["body"], arm)
        rigid_bind_ornaments(parts["body"], arm)
    for obj_name, bone_name in RIGID_BINDINGS.items():
        obj = parts["others"].get(obj_name)
        if obj is not None:
            bind_rigid(obj, arm, bone_name)


# 蹬伸瞬间的身体（取 poses_jump 的 f4 躯干/腿），只让手臂角度变化
BODY = {
    "hip_loc": (0, 0, 0.055),
    "spine": (-8, 0, 0), "head": (5, 0, 0),
    "thigh_l": (6, 0, 0), "shin_l": (8, 0, 0),
    "thigh_r": (-18, 0, 0), "shin_r": (14, 0, 0),
}

# (标签, 上臂角度, 前臂角度)
VARIANTS = []
for arm in (-60.0, -80.0, -100.0, -115.0, -130.0, -145.0):
    VARIANTS.append(("a%03d_e15" % int(-arm), arm, -15.0))
for arm in (-80.0, -100.0, -115.0):
    VARIANTS.append(("a%03d_e45" % int(-arm), arm, -45.0))


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    build_character()
    setup_render(400, 480)
    arm_obj = build_armature(bpy.context.scene.collection)
    bind_all(arm_obj)

    scene = bpy.context.scene
    scene.frame_start = 1
    scene.frame_end = 1
    for label, a, f in VARIANTS:
        clear_pose(arm_obj)
        pose = dict(BODY)
        pose["arm_l"] = (a + 4.0, 0, 0)
        pose["arm_r"] = (a, 0, 0)
        pose["forearm_l"] = (f, 0, 0)
        pose["forearm_r"] = (f + 2.0, 0, 0)
        pose["lamp"] = (0, 0, 0)
        set_pose(arm_obj, pose)
        scene.frame_set(1)
        scene.render.filepath = os.path.join(OUT, "%s.png" % label)
        bpy.ops.render.render(write_still=True)
        print("SWEEP_RENDERED", label, a, f)


if __name__ == "__main__":
    main()
