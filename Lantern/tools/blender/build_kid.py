"""用 Blender 构建"提灯人"角色，并渲染成 2D 序列帧。

为什么要绕到 3D 再渲回 2D：
  在 Godot 里用几何部件拼骨头，无论怎么调都会残留"零件缝合感" ——
  关节处是几块独立形状的交界，缺少真实体积带来的自然过渡。
  而 3D 网格 + 骨骼形变是**一个连续的曲面**，关节处是曲面弯曲，
  天然不会有接缝。渲染成序列帧后，就是《死亡细胞》那类
  "看起来像手绘、实际是 3D 渲染"的 2D 角色。

关键手法：
  1. metaball 融合出身体主体 —— 球体之间会自动产生有机的过渡曲面；
  2. 骨架 + 自动权重（ARMATURE_AUTO），关节形变连续；
  3. 卡通描边 = 复制一层网格，法线外扩 + 只渲染背面；
  4. 正交相机侧视，渲染成透明背景 PNG 序列。

用法：
    blender --background --factory-startup --python tools/blender/build_kid.py -- <阶段>
    阶段：model（只渲一张静态图，用于检查造型）
          anim （渲完整的动作序列帧）
"""

import math
import os
import sys

import bpy
import mathutils

# ---------------------------------------------------------------------------
# 输出路径
# ---------------------------------------------------------------------------
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "assets", "art", "kid")

# ---------------------------------------------------------------------------
# 造型尺寸（单位：米，1 米 ≈ 42 像素，渲染后按比例缩放）
# ---------------------------------------------------------------------------
HEAD_R = 0.168
HEAD_Z = 0.885
NECK_Z = 0.705
CHEST_Z = 0.560
HIP_Z = 0.368
FOOT_Z = 0.0

SKIN = (0.969, 0.851, 0.722, 1.0)
CLOAK = (0.910, 0.631, 0.369, 1.0)
CLOAK_DARK = (0.769, 0.498, 0.259, 1.0)
SCARF = (0.851, 0.416, 0.353, 1.0)
BOOT = (0.427, 0.290, 0.200, 1.0)
HAIR = (0.353, 0.239, 0.169, 1.0)
OUTLINE = (0.129, 0.098, 0.075, 1.0)
LAMP_GLOW = (1.0, 0.847, 0.541, 1.0)


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_material(name: str, color, emission: float = 0.0,
                  backface: bool = False, toon: bool = True):
    """卡通着色材质。

    纯 Emission 渲染出来是平色块，没有体积 —— 角色会像剪纸。
    这里走"漫反射 → Shader to RGB → ColorRamp 三档 → 乘固有色"，
    得到明确分层的赛璐璐影调：暗部、中间调、亮部各自成块。
    """
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")

    # 调色板里的颜色是按**显示色（sRGB）**定的，而 Blender 的节点颜色
    # 槽是**线性空间**。不转换的话渲染结果会整体偏亮发灰
    # （深棕靴子会渲成浅褐色），且很难从结果反推。
    base = _srgb_to_linear(color)

    if not toon:
        emit = nt.nodes.new("ShaderNodeEmission")
        emit.inputs["Color"].default_value = base
        emit.inputs["Strength"].default_value = max(emission, 1.0)
        nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
        mat.use_backface_culling = backface
        return mat

    diff = nt.nodes.new("ShaderNodeBsdfDiffuse")
    diff.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)

    to_rgb = nt.nodes.new("ShaderNodeShaderToRGB")

    # 暗/中/亮三档直接算好写进 ColorRamp，不接 Mix 节点。
    # 用下标去访问 Mix 的色彩槽（inputs[6]/inputs[7]）太脆弱，
    # 槽位一错颜色就会整体跑亮，且很难从渲染结果反推原因。
    #
    # 坑：elements.new() 插入新色标后，**之前取到的元素引用会失效**，
    # 用旧引用赋 position/color 会静默失败（该档位保持默认白色，
    # 结果角色整个被冲白）。因此每次插入后都按索引重新取元素。
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].position = 0.00
    ramp.color_ramp.elements[1].position = 1.00
    ramp.color_ramp.elements.new(0.70)

    ramp.color_ramp.elements[0].position = 0.00
    ramp.color_ramp.elements[0].color = _shade(base, 0.56)   # 暗部
    ramp.color_ramp.elements[1].position = 0.36
    ramp.color_ramp.elements[1].color = _shade(base, 0.82)   # 中间调
    ramp.color_ramp.elements[2].position = 0.72
    ramp.color_ramp.elements[2].color = _shade(base, 1.06)   # 亮部

    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = 1.0

    nt.links.new(diff.outputs["BSDF"], to_rgb.inputs["Shader"])
    nt.links.new(to_rgb.outputs["Color"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], emit.inputs["Color"])
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])

    mat.use_backface_culling = backface
    return mat


def _shade(color, factor: float):
    """按比例缩放一个线性 RGBA 颜色，得到该色系的明暗变体。"""
    return (
        min(1.0, color[0] * factor),
        min(1.0, color[1] * factor),
        min(1.0, color[2] * factor),
        color[3] if len(color) > 3 else 1.0,
    )


def _srgb_to_linear(color):
    """把显示色（sRGB）转到线性空间，供 Blender 节点颜色槽使用。"""
    def conv(v: float) -> float:
        if v <= 0.04045:
            return v / 12.92
        return ((v + 0.055) / 1.055) ** 2.4

    return (conv(color[0]), conv(color[1]), conv(color[2]),
            color[3] if len(color) > 3 else 1.0)


# ---------------------------------------------------------------------------
# 身体：metaball 融合
# ---------------------------------------------------------------------------

def build_body(collection) -> "bpy.types.Object":
    """用 metaball 摆出身体主体，再转成网格。

    metaball 的价值在于：相邻元素会自动融合成一张连续曲面，
    因此躯干和四肢的连接处天生是平滑过渡，不存在"接缝"这个概念。

    四肢必须用 CAPSULE 元素而不是一串 BALL：球与球之间只要重叠不足，
    渲染出来就是一串可见的球包（"毛毛虫"）。胶囊是一根连续圆管，
    无论多长都只有一条轮廓。
    """
    mball = bpy.data.metaballs.new("KidBody")
    mball.resolution = 0.012
    mball.render_resolution = 0.008
    mball.threshold = 0.6
    obj = bpy.data.objects.new("KidBody", mball)
    collection.objects.link(obj)

    def ball(x, y, z, radius, stiffness=2.0):
        el = mball.elements.new()
        el.co = (x, y, z)
        el.radius = radius
        el.stiffness = stiffness

    def capsule(a, b, radius, stiffness=2.0):
        """从 a 到 b 的一根胶囊。size_x 是圆柱段的半长。"""
        va = mathutils.Vector(a)
        vb = mathutils.Vector(b)
        axis = vb - va
        length = axis.length
        if length < 1e-5:
            ball(a[0], a[1], a[2], radius, stiffness)
            return
        el = mball.elements.new()
        el.type = "CAPSULE"
        el.co = (va + vb) * 0.5
        el.radius = radius
        el.size_x = length * 0.5
        el.stiffness = stiffness
        el.rotation = mathutils.Vector((1.0, 0.0, 0.0)).rotation_difference(
            axis.normalized())

    # 躯干：髋宽、腰收、胸略宽，用胶囊串成一根有腰身的立柱。
    # 半径必须**小于斗篷**——躯干是穿在斗篷里的，斗篷才是外轮廓；
    # 躯干比斗篷粗的话，正面露出的就是皮肤色，斗篷等于白做。
    capsule((0.0, 0.0, HIP_Z - 0.02), (0.0, 0.0, CHEST_Z + 0.02), 0.112)
    ball(0.0, 0.0, HIP_Z + 0.01, 0.125)
    ball(0.0, 0.0, CHEST_Z + 0.03, 0.122)
    # 颈：细一截，让头和躯干之间有明确的"脖子"
    capsule((0.0, 0.0, CHEST_Z + 0.06), (0.0, 0.0, NECK_Z + 0.02), 0.056)
    # 头：主球 + 后脑偏移球，做出前后不对称的颅形
    ball(0.0, -0.010, HEAD_Z, HEAD_R)
    ball(0.0, -0.070, HEAD_Z - 0.015, HEAD_R * 0.86)

    # 腿：髋 → 膝 → 踝，两段胶囊
    for side in (-1.0, 1.0):
        hip_pt = (side * 0.058, 0.0, HIP_Z - 0.03)
        knee_pt = (side * 0.068, 0.0, HIP_Z - 0.22)
        ankle_pt = (side * 0.072, 0.0, 0.055)
        capsule(hip_pt, knee_pt, 0.062)
        capsule(knee_pt, ankle_pt, 0.052)
        ball(side * 0.068, 0.0, HIP_Z - 0.22, 0.060)

    # 手臂：肩 → 肘 → 腕，两段胶囊。
    # 整体前移到 y 为负（相机一侧）—— 贴在斗篷前方，否则会被
    # 斗篷的侧面轮廓吞掉、完全看不见。
    for side in (-1.0, 1.0):
        shoulder_pt = (side * 0.140, -0.052, CHEST_Z + 0.058)
        elbow_pt = (side * 0.186, -0.048, CHEST_Z - 0.062)
        wrist_pt = (side * 0.206, -0.040, CHEST_Z - 0.172)
        capsule(shoulder_pt, elbow_pt, 0.052)
        capsule(elbow_pt, wrist_pt, 0.042)
        ball(side * 0.212, -0.036, CHEST_Z - 0.210, 0.046)

    return obj


def metaball_to_mesh(mball_obj, collection) -> "bpy.types.Object":
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = mball_obj.evaluated_get(depsgraph)
    mesh = bpy.data.meshes.new_from_object(evaluated)
    result = bpy.data.objects.new("KidSkin", mesh)
    collection.objects.link(result)
    bpy.data.objects.remove(mball_obj, do_unlink=True)
    return result


# ---------------------------------------------------------------------------
# 服装饰件
# ---------------------------------------------------------------------------

def add_primitive(kind: str, location, scale, rotation=(0, 0, 0), name="Part"):
    if kind == "sphere":
        bpy.ops.mesh.primitive_uv_sphere_add(
            segments=24, ring_count=16, radius=1.0, location=location)
    elif kind == "cube":
        bpy.ops.mesh.primitive_cube_add(size=2.0, location=location)
    else:
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=20, radius=1.0, depth=2.0, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    obj.rotation_euler = rotation
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return obj


def add_cone(location, r_bottom, r_top, depth, name,
             rotation=(0, 0, 0), scale=(1.0, 1.0, 1.0)):
    """圆台 —— 用来做外扩的斗篷。

    圆柱做不出"上窄下宽"的廓形，而斗篷的辨识度恰恰来自这个外扩。
    """
    bpy.ops.mesh.primitive_cone_add(
        vertices=28, radius1=r_bottom, radius2=r_top, depth=depth,
        location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.rotation_euler = rotation
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return obj


def build_outfit(collection):
    """兜帽、斗篷、围巾、靴子、提灯。

    每一项的职责是"补足辨识度"：兜帽定头型，斗篷定廓形，
    围巾遮住头颈接缝，提灯提供唯一的发光点。
    """
    parts = []

    # 兜帽：包住头顶、两侧与后脑，正面留出**圆形**脸窗。
    # 用球体做切割体而不是方块：方块的平面切在球面上会留下一条
    # 歪斜的直边（脸窗变成斜口）；球体切出来是干净的圆孔。
    hood = add_primitive("sphere", (0.0, 0.016, HEAD_Z + 0.016),
                         (HEAD_R * 1.10, HEAD_R * 1.15, HEAD_R * 1.12),
                         name="Hood")
    cut = add_primitive("sphere", (0.0, -0.160, HEAD_Z - 0.004),
                        (0.150, 0.150, 0.150), name="HoodCut")
    boolean_difference(hood, cut)
    parts.append(("Hood", hood))

    # 兜帽后垂的尖
    tip = add_primitive("sphere", (0.0, 0.150, HEAD_Z - 0.020),
                        (0.062, 0.100, 0.088), name="HoodTip")
    parts.append(("HoodTip", tip))

    # 眼睛：**只画一只**。
    # 3/4 侧视下两只眼睛投影到屏幕上只差约 4 像素，会糊成一个"8"字；
    # 侧视角色的通行做法就是单眼 + 侧脸轮廓。
    eye = add_primitive("sphere", (0.006, -0.152, HEAD_Z + 0.010),
                        (0.032, 0.026, 0.042), name="Eye0")
    parts.append(("Eye0", eye))

    # 围巾：脖子上的一圈。要窄、要低 —— 太宽会把脖子整段盖住，
    # 红色的头部与红色围巾连成一片，头就和身体分不开了。
    collar = add_primitive("cylinder", (0.0, 0.0, NECK_Z - 0.036),
                           (0.082, 0.076, 0.036), name="Collar")
    parts.append(("Collar", collar))
    tail = add_primitive("sphere", (0.086, 0.072, NECK_Z - 0.108),
                         (0.040, 0.076, 0.062), name="ScarfTail")
    parts.append(("ScarfTail", tail))

    # 肩披：胸部上方的一团，给斗篷一条明确的肩线。
    # 只靠圆锥体的话肩膀是方的，整件斗篷会读成"围裙"。
    cape = add_primitive("sphere", (0.0, 0.014, CHEST_Z + 0.046),
                         (0.152, 0.130, 0.082), name="Cape")
    parts.append(("Cape", cape))

    # 斗篷：上窄下宽的圆台，下摆到大腿中段。
    # 半径要**小于手臂所在的位置**，否则会把手臂整条吞掉。
    cloak_top = CHEST_Z + 0.058
    cloak_bottom = HIP_Z - 0.048
    cloak = add_cone((0.0, 0.010, (cloak_top + cloak_bottom) * 0.5),
                     0.192, 0.132, (cloak_top - cloak_bottom), name="Cloak",
                     scale=(1.0, 0.86, 1.0))
    parts.append(("Cloak", cloak))

    # 腰带
    belt = add_primitive("cylinder", (0.0, 0.005, HIP_Z + 0.018),
                         (0.126, 0.112, 0.024), name="Belt")
    parts.append(("Belt", belt))

    # 靴子：脚背鼓起的半椭球 + 一段靴筒。
    # 只有脚背那块的话，小腿整段是裸肤色，读起来像光脚。
    for i, side in enumerate((-1.0, 1.0)):
        boot = add_primitive("sphere", (side * 0.058, -0.016, 0.050),
                             (0.058, 0.090, 0.053), name="Boot%d" % i)
        parts.append(("Boot%d" % i, boot))
        shaft = add_primitive("cylinder", (side * 0.062, -0.006, 0.146),
                              (0.052, 0.052, 0.058), name="BootShaft%d" % i)
        parts.append(("BootShaft%d" % i, shaft))

    # 提灯：三件套（灯身 / 灯盖 / 提环），位于角色右手侧、略靠前
    lamp_x = 0.220
    lamp_y = -0.058
    lamp_c = CHEST_Z - 0.372
    lamp_body = add_cone((lamp_x, lamp_y, lamp_c), 0.050, 0.038, 0.086, name="LampBody")
    parts.append(("LampBody", lamp_body))
    lamp_cap = add_primitive("cone", (lamp_x, lamp_y, lamp_c + 0.056),
                             (0.044, 0.044, 0.028), name="LampCap")
    parts.append(("LampCap", lamp_cap))
    lamp_ring = add_primitive("sphere", (lamp_x, lamp_y, lamp_c + 0.094),
                              (0.019, 0.019, 0.012), name="LampRing")
    parts.append(("LampRing", lamp_ring))

    return parts


def boolean_difference(target, cutter) -> None:
    mod = target.modifiers.new("cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def join_all(objs, name="Kid"):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    result = bpy.context.active_object
    result.name = name
    return result


# ---------------------------------------------------------------------------
# 卡通描边
# ---------------------------------------------------------------------------

def make_silhouette(source_obj, collection) -> "bpy.types.Object":
    """生成用于描边的剪影：沿法线外扩一圈的副本。

    没有用"反向外壳 + 背面剔除"那套经典做法 —— 实测在 EEVEE Next 里
    法线朝向与剔除开关的组合极不可控，外壳会整个盖住角色。

    这里改为**分两次渲染再合成**：先渲剪影、再渲角色，把剪影垫在
    角色下方。剪影比角色大一圈，露出来的那一圈就是描边。这个思路
    与法线朝向无关，因此不会出现"整块盖住"的问题。
    """
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(source_obj.evaluated_get(depsgraph))
    sil = bpy.data.objects.new("KidSilhouette", mesh)
    collection.objects.link(sil)

    solid = sil.modifiers.new("grow", "SOLIDIFY")
    solid.thickness = 0.030
    solid.offset = 1.0
    solid.use_rim = False

    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = sil
    sil.select_set(True)
    bpy.ops.object.modifier_apply(modifier=solid.name)
    for poly in sil.data.polygons:
        poly.use_smooth = True
    return sil


# ---------------------------------------------------------------------------
# 材质与灯光
# ---------------------------------------------------------------------------

def assign_material(obj, mat, slot_color_map=None) -> None:
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def build_lights(collection):
    key = bpy.data.lights.new("Key", type="AREA")
    key.energy = 180.0
    key.size = 3.0
    key_obj = bpy.data.objects.new("Key", key)
    key_obj.location = (-1.4, -2.0, 2.4)
    key_obj.rotation_euler = (math.radians(52), 0.0, math.radians(-34))
    collection.objects.link(key_obj)

    fill = bpy.data.lights.new("Fill", type="AREA")
    fill.energy = 55.0
    fill.size = 4.0
    fill_obj = bpy.data.objects.new("Fill", fill)
    fill_obj.location = (2.0, -1.6, 0.9)
    fill_obj.rotation_euler = (math.radians(78), 0.0, math.radians(58))
    collection.objects.link(fill_obj)

    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.55, 0.62, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.55
    bpy.context.scene.world = world


def build_camera(collection, height: float = 1.72):
    """正交相机，沿轨道摆到侧前方，形成 3/4 侧视。

    注意：3/4 视角必须同时设置**位置**与**朝向**。只旋转不移动的话，
    相机等于原地转头看向旁边的空处 —— 6 米距离上偏 18° 会让主体
    横向平移约 1.85 米，直接飞出正交视野（角色"渲染不出来"的元凶）。

    center_z 取角色竖向中点：造型实测跨度约 [-0.32, 1.24]，
    取景中心 0.47 才能让脚底与头顶都留出余量。
    """
    # yaw = -90° 时相机沿 +X 看，此时"屏幕右方向"正好等于 -Y，
    # 也就是角色正面所朝的方向 —— 横版游戏里角色必须朝屏幕右跑。
    # 取 -74° 是在此基础上退回 16°，保留一点正面信息做出体积感，
    # 这是《奥日》那类横版常用的 3/4 侧视。
    yaw = math.radians(-74.0)
    dist = 6.0
    center_z = 0.47
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = height
    cam_data.clip_start = 0.1
    cam_data.clip_end = 100.0
    cam = bpy.data.objects.new("Cam", cam_data)
    # 前向 = (-sin(yaw), cos(yaw), 0)，相机放在主体前方的反向延长线上
    cam.location = (dist * math.sin(yaw), -dist * math.cos(yaw), center_z)
    cam.rotation_euler = (math.radians(90.0), 0.0, yaw)
    collection.objects.link(cam)
    bpy.context.scene.camera = cam
    return cam


def setup_render(width: int = 220, height: int = 260):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.film_transparent = True
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------

def build_character():
    """完整搭建角色，返回 (合并后的唯一网格, 描边材质)。

    关键约束：**描边壳只能有一层**，而且必须建立在"所有部件已合并"
    之后。若给每个部件各加一层描边壳，部件交界处就会出现两条轮廓线，
    2D 渲染出来正是那种"零件缝合感"。
    """
    clear_scene()
    scene_collection = bpy.context.scene.collection

    # 1) 材质
    mats = {
        "skin": make_material("Skin", SKIN),
        "cloak": make_material("Cloak", CLOAK),
        "cloak_dark": make_material("CloakDark", CLOAK_DARK),
        "scarf": make_material("Scarf", SCARF),
        "ink": make_material("Ink", OUTLINE, toon=False),
        "glow": make_material("Glow", LAMP_GLOW, emission=1.15),
        "outline": make_material("Outline", OUTLINE, backface=True, toon=False),
    }

    # 2) 身体（metaball → 一张连续曲面）
    skin = metaball_to_mesh(build_body(scene_collection), scene_collection)
    assign_material(skin, mats["skin"])
    set_smooth(skin)

    # 3) 服装与配饰
    parts = [skin]
    for name, obj in build_outfit(scene_collection):
        if name.startswith("Hood") or name in ("Collar", "ScarfTail"):
            mat = mats["scarf"]
        elif name.startswith("Eye"):
            mat = mats["ink"]
        elif name in ("Cloak", "Cape"):
            mat = mats["cloak"]
        elif name.startswith("Lamp"):
            mat = mats["glow"]
        else:
            mat = mats["cloak_dark"]
        assign_material(obj, mat)
        set_smooth(obj)
        parts.append(obj)

    # 4) 合并成一个网格 —— 无接缝的前提
    merged = join_all(parts, "Kid")
    set_smooth(merged)

    build_lights(scene_collection)
    build_camera(scene_collection)
    setup_render()
    return merged, mats["outline"]


def set_smooth(obj) -> None:
    for poly in obj.data.polygons:
        poly.use_smooth = True


def render_still(path: str) -> None:
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("RENDERED", path)


def render_outlined(kid_obj, sil_obj, path: str, char_path: str, sil_path: str) -> None:
    """分两次渲染（角色 / 剪影）并保存，供后续合成描边。"""
    kid_obj.hide_render = False
    sil_obj.hide_render = True
    render_still(char_path)

    kid_obj.hide_render = True
    sil_obj.hide_render = False
    render_still(sil_path)

    kid_obj.hide_render = False
    sil_obj.hide_render = False
    print("RENDERED_PAIR", char_path, sil_path)


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    stage = args[0] if args else "model"

    os.makedirs(OUT_DIR, exist_ok=True)
    kid, outline_mat = build_character()
    col = bpy.context.scene.collection
    sil = make_silhouette(kid, col)
    assign_material(sil, outline_mat)

    if stage.startswith("model"):
        char_p = os.path.join(OUT_DIR, "_char.png")
        sil_p = os.path.join(OUT_DIR, "_sil.png")
        render_outlined(kid, sil, os.path.join(OUT_DIR, "_preview.png"), char_p, sil_p)


if __name__ == "__main__":
    main()
