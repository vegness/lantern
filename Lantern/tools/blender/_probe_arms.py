"""一次性标定："哪条手臂在画面上可见" + 候选关键姿势的可读性对比。

结论（2026-10-12 实测，改了手臂设计前务必先看这里）：

  · 相机在角色**左前方**（yaw=-74°，cam.x = -5.77），所以 `arm_l` 是近端臂，
    `arm_r`（提灯臂）是远端臂。
  · **左臂抬起（arm_l ≈ −100）极其可读** —— 一条完整的手臂伸到肩高前方。
  · **左臂后摆（arm_l ≈ +70）基本被斗篷吃掉**，只能看到一小截。
  · 提灯臂的任何姿态，手臂本身都被斗篷遮住，但**提灯的高对比轨迹可读**：
    后摆时灯垂到腿后下方，上摆时灯升到胸前 —— 这才是本角色"摆臂"的主读点。
  · 两臂同时上举 = "护脸/投降"，必须避免。

用法：
    blender --background --factory-startup --python tools/blender/_probe_arms.py
输出：<项目>/verify/probe_arms/<tag>.png
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402

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

OUT = os.path.join(ROOT, "verify", "probe_arms")


def P(dz, spine, head, tl, sl, fl, tr, sr, fr, al, fal, ar, far, lamp):
    return {
        "hip_loc": (0, 0, dz),
        "spine": (spine, 0, 0), "head": (head, 0, 0),
        "thigh_l": (tl, 0, 0), "shin_l": (sl, 0, 0), "foot_l": (fl, 0, 0),
        "thigh_r": (tr, 0, 0), "shin_r": (sr, 0, 0), "foot_r": (fr, 0, 0),
        "arm_l": (al, 0, 0), "forearm_l": (fal, 0, 0),
        "arm_r": (ar, 0, 0), "forearm_r": (far, 0, 0),
        "lamp": (lamp, 0, 0),
    }


# 深蹲腿形（thigh -62 / shin +72）下的手臂候选
CROUCH_LEGS = dict(dz=-0.093, spine=9, head=-4,
                   tl=-62, sl=72, fl=-6, tr=-58, sr=68, fr=-6)

TOE_LEGS = dict(dz=0.017, spine=-2, head=2, tl=-6, sl=8, fl=30, tr=-8, sr=10, fr=30)
# 上升峰值那一帧的身体（对应 poses_jump 的图像 6）
PEAK_BODY = dict(dz=0.040, spine=2, head=1, tl=-14, sl=24, fl=20, tr=-28, sr=42, fr=18)

VARIANTS = [
    # ── 自由臂峰值角度扫掠：找"手真正过头顶且不被兜帽吃掉"的角度 ──
    #    骨架里 arm=0 是手下垂，−90 水平前伸，−180 才是垂直向上，
    #    所以"过头顶"要 −135 以上；但兜帽很大，过头后手臂会钻到兜帽后面。
    ("a1_arm090", P(al=-90, fal=-20, ar=-102, far=-26, lamp=0, **PEAK_BODY)),
    ("a2_arm105", P(al=-105, fal=-20, ar=-102, far=-26, lamp=0, **PEAK_BODY)),
    ("a3_arm120", P(al=-120, fal=-20, ar=-102, far=-26, lamp=0, **PEAK_BODY)),
    ("a4_arm135", P(al=-135, fal=-20, ar=-102, far=-26, lamp=0, **PEAK_BODY)),
    ("a5_arm150", P(al=-150, fal=-20, ar=-102, far=-26, lamp=0, **PEAK_BODY)),
    # 屈肘更大时手会向上而非向前，可能反而更清楚
    ("a6_arm135_e45", P(al=-135, fal=-45, ar=-102, far=-26, lamp=0, **PEAK_BODY)),
]


def bind_all(arm) -> None:
    parts = collect_parts()
    if parts["body"] is not None:
        bind_body(parts["body"], arm)
        rigid_bind_ornaments(parts["body"], arm)
    for obj_name, bone_name in RIGID_BINDINGS.items():
        obj = parts["others"].get(obj_name)
        if obj is not None:
            bind_rigid(obj, arm, bone_name)


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    build_character()
    setup_render(400, 480)
    arm_obj = build_armature(bpy.context.scene.collection)
    bind_all(arm_obj)

    scene = bpy.context.scene
    scene.frame_start = 1
    scene.frame_end = 1
    for tag, pose in VARIANTS:
        clear_pose(arm_obj)
        set_pose(arm_obj, pose)
        scene.frame_set(1)
        scene.render.filepath = os.path.join(OUT, "%s.png" % tag)
        bpy.ops.render.render(write_still=True)
        print("PROBE_RENDERED", tag)


if __name__ == "__main__":
    main()
