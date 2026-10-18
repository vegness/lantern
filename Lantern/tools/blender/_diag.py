import os, sys, bpy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_kid import build_character
from animate_kid import build_armature, collect_parts, bind_body
build_character()
parts = collect_parts()
print("DIAG_BODY", parts["body"].name if parts["body"] else None)
arm = build_armature(bpy.context.scene.collection)
body = parts["body"]
bind_body(body, arm)
print("DIAG_GROUPS", len(body.vertex_groups), sorted(g.name for g in body.vertex_groups))
th = body.vertex_groups.get("thigh_l")
cnt = 0
if th:
    for v in body.data.vertices:
        for g in v.groups:
            if g.group == th.index and g.weight > 0.15:
                cnt += 1
print("DIAG_THIGH_VERTS", cnt)
print("DIAG_MODS", [(m.name, m.type, getattr(m, "object", None) is not None) for m in body.modifiers])
