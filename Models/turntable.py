"""Builds the turntable model and exports it for the app.

Run through scripts/build-model.sh:
    Blender --background --python Models/turntable.py -- <out.usdz> [preview.png]

The layout follows a classic direct-drive DJ deck (reference: Audio-Technica AT-LP140XP), without branding.

Coordinates. The app's table plane is x right, z toward the viewer, y up. Blender is x right, y away, z up,
so a table point (x, tz) is Blender (x, -tz). The top of the plinth is z = 0. Units are metres.

Named parts the app drives (keep in sync with TurntableScene.swift and TurntableGeometry.standard):
    Spin       platter, slipmat and spindle; origin at the spindle
    Arm        the moving tonearm, modelled along the app's +z (Blender -y); origin at the pivot
    BtnStart, BtnPrev, BtnNext   pressable buttons
    StrobeLamp the lamp that lights the strobe dots
"""

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

# --- Geometry shared with the app -------------------------------------------------------------------------------
SPINDLE = (-0.048, 0.0)
PIVOT = (0.164, -0.088)
ARM_LENGTH = 0.2305
REST_SWING = math.radians(52)
PLATTER_RADIUS = 0.166
PLATTER_TOP = 0.022  # top of the slipmat
ARM_AXIS_HEIGHT = 0.040  # tube axis above the plinth when the needle is down
STYLUS_DROP = 0.016

PLINTH = (0.452, 0.352, 0.060)


def table(x, tz, z=0.0):
    return Vector((x, -tz, z))


# --- Materials --------------------------------------------------------------------------------------------------
GRAIN_TILE = 0.022  # metres covered by one repeat of the grain texture
_grain = None


def grain_image():
    """A tileable normal map of fine pebbly grain, like powder coat or soft-touch plastic."""
    global _grain
    if _grain is not None:
        return _grain
    import numpy as np

    size = 512
    noise = np.random.default_rng(7).standard_normal((size, size))
    fx = np.fft.fftfreq(size)[:, None]
    fy = np.fft.fftfreq(size)[None, :]
    radius = np.sqrt(fx**2 + fy**2)
    band = np.exp(-(((radius - 0.11) / 0.07) ** 2))  # band-pass: grains of similar size, no large blotches
    height = np.real(np.fft.ifft2(np.fft.fft2(noise) * band))
    height /= height.std()
    nx = -(np.roll(height, -1, 1) - np.roll(height, 1, 1)) * 0.30
    ny = -(np.roll(height, -1, 0) - np.roll(height, 1, 0)) * 0.30
    length = np.sqrt(nx**2 + ny**2 + 1)
    pixels = np.stack([nx / length * 0.5 + 0.5, ny / length * 0.5 + 0.5, 1 / length * 0.5 + 0.5, np.ones_like(nx)], axis=-1)

    image = bpy.data.images.new("Grain", size, size, alpha=False, is_data=True)
    image.pixels.foreach_set(pixels.astype("float32").ravel())
    folder = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "textures")
    os.makedirs(folder, exist_ok=True)
    image.filepath_raw = os.path.join(folder, "grain.png")
    image.file_format = "PNG"
    image.save()
    image.colorspace_settings.name = "Non-Color"
    _grain = image
    return image


def material(name, white, roughness, metallic=0.0, color=None, emission=None, grain=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    rgb = color or (white, white, white)
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1)
        bsdf.inputs["Emission Strength"].default_value = 2
    if grain > 0:
        texture = nodes.new("ShaderNodeTexImage")
        texture.image = grain_image()
        normal = nodes.new("ShaderNodeNormalMap")
        normal.inputs["Strength"].default_value = grain
        links.new(texture.outputs["Color"], normal.inputs["Color"])
        links.new(normal.outputs["Normal"], bsdf.inputs["Normal"])
        mat["grain"] = True
    return mat


M = {}


def make_materials():
    M["plinth"] = material("Plinth", 0.03, 0.6, grain=0.55)
    M["panel"] = material("Panel", 0.012, 0.75, grain=0.4)
    M["well"] = material("Well", 0.006, 0.8)
    M["platter"] = material("Platter", 0.10, 0.38, 1.0)
    M["bright"] = material("BrightMetal", 0.78, 0.26, 1.0)
    M["steel"] = material("Steel", 0.45, 0.35, 1.0)
    M["black_metal"] = material("BlackMetal", 0.035, 0.42, 1.0)
    M["felt"] = material("Felt", 0.010, 1.0)
    M["rubber"] = material("Rubber", 0.028, 0.8, grain=1.0)
    M["button"] = material("Button", 0.075, 0.55, grain=0.7)
    M["ink"] = material("Ink", 0.9, 0.5)
    M["lamp"] = material("Lamp", 0.0, 0.3, color=(0.02, 0.04, 0.12))
    M["led"] = material("Led", 0.0, 0.25, color=(0.16, 0.02, 0.02))
    M["light_cap"] = material("LightCap", 0.5, 0.35)
    M["lens"] = material("Lens", 0.0, 0.08, color=(0.02, 0.025, 0.03))
    M["cartridge"] = material("Cartridge", 0.0, 0.45, color=(0.03, 0.06, 0.16))


# --- Mesh helpers -----------------------------------------------------------------------------------------------
def finish(obj, mat, parent=None, bevel=0.0, smooth=True):
    obj.data.materials.append(M[mat])
    if M[mat].get("grain"):
        # Grain is laid on from above, at real-world scale, whatever the size of the part.
        mesh = obj.data
        layer = mesh.uv_layers.active or mesh.uv_layers.new(name="UVMap")
        for loop in mesh.loops:
            world = obj.matrix_world @ mesh.vertices[loop.vertex_index].co
            layer.data[loop.index].uv = ((world.x + world.z) / GRAIN_TILE, (world.y + world.z) / GRAIN_TILE)
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(40)
    if smooth:
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
        # Keep hard edges crisp where faces meet at more than 40 degrees.
        mod = obj.modifiers.new("Normals", "WEIGHTED_NORMAL")
        mod.keep_sharp = True
    if parent is not None:
        world = obj.matrix_world.copy()
        obj.parent = parent
        obj.matrix_world = world
    return obj


def cylinder(name, mat, at, radius, bottom, top, parent=None, bevel=0.0, vertices=96, radius_top=None):
    centre = Vector((at.x, at.y, (bottom + top) / 2))
    if radius_top is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=top - bottom, location=centre)
    else:
        bpy.ops.mesh.primitive_cone_add(
            vertices=vertices, radius1=radius, radius2=radius_top, depth=top - bottom, location=centre
        )
    obj = bpy.context.object
    obj.name = name
    bpy.context.view_layer.update()
    return finish(obj, mat, parent, bevel)


def box(name, mat, at, size, bottom, top, parent=None, bevel=0.0, yaw=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(at.x, at.y, (bottom + top) / 2), rotation=(0, 0, yaw))
    obj = bpy.context.object
    obj.name = name
    obj.scale = (size[0], size[1], top - bottom)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.context.view_layer.update()
    return finish(obj, mat, parent, bevel, smooth=bevel > 0)


def knurled(name, mat, at, radius, bottom, top, parent=None, teeth=48, depth=0.0006):
    """A cylinder with a ridged grip, like the edge of a knob."""
    verts, faces = [], []
    steps = teeth * 2
    for i in range(steps):
        angle = 2 * math.pi * i / steps
        r = radius if i % 2 == 0 else radius - depth
        verts.append((at.x + r * math.cos(angle), at.y + r * math.sin(angle), bottom))
        verts.append((at.x + r * math.cos(angle), at.y + r * math.sin(angle), top))
    for i in range(steps):
        a, b = 2 * i, 2 * ((i + 1) % steps)
        faces.append((a, b, b + 1, a + 1))
    faces.append(tuple(range(0, 2 * steps, 2))[::-1])
    faces.append(tuple(range(1, 2 * steps, 2)))
    return from_data(name, mat, verts, faces, parent, smooth=False)


def from_data(name, mat, verts, faces, parent=None, smooth=True, bevel=0.0):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.update()
    return finish(obj, mat, parent, bevel, smooth)


def rounded_outline(at, size, radius, steps=6):
    """Corner points of a rounded rectangle, counter-clockwise from above."""
    w, d = size[0] / 2 - radius, size[1] / 2 - radius
    points = []
    for k, (sx, sy) in enumerate(((1, 1), (-1, 1), (-1, -1), (1, -1))):
        for i in range(steps + 1):
            angle = math.radians(90 * k + 90 * i / steps)
            points.append((at.x + sx * w + radius * math.cos(angle), at.y + sy * d + radius * math.sin(angle)))
    return points


def rounded_box(name, mat, at, size, bottom, top, radius, parent=None, bevel=0.0):
    outline = rounded_outline(at, size, radius)
    n = len(outline)
    verts = [(x, y, bottom) for x, y in outline] + [(x, y, top) for x, y in outline]
    faces = [tuple(range(n))[::-1], tuple(range(n, 2 * n))]
    faces += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    return from_data(name, mat, verts, faces, parent, smooth=bevel > 0, bevel=bevel)


def rounded_ring(name, mat, at, outer, inner, bottom, top, radius_outer, radius_inner, parent=None, bevel=0.0):
    """A raised rounded-rectangle lip around an open middle."""
    out, inn = rounded_outline(at, outer, radius_outer), rounded_outline(at, inner, radius_inner)
    n = len(out)
    verts = [(x, y, bottom) for x, y in out] + [(x, y, top) for x, y in out]
    verts += [(x, y, bottom) for x, y in inn] + [(x, y, top) for x, y in inn]
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces.append((n + i, n + j, 3 * n + j, 3 * n + i))  # top
        faces.append((i, j, n + j, n + i))  # outer wall
        faces.append((2 * n + j, 2 * n + i, 3 * n + i, 3 * n + j))  # inner wall
    return from_data(name, mat, verts, faces, parent, smooth=bevel > 0, bevel=bevel)


def tick_ring(name, at, radius, length, count, z, every=5, parent=None, arc=(0, 360)):
    """Printed scale marks around a dial."""
    for i in range(count):
        angle = math.radians(arc[0] + (arc[1] - arc[0]) * i / count)
        long = length * (1.6 if i % every == 0 else 1.0)
        centre = at + Vector((math.cos(angle), math.sin(angle), 0)) * (radius - long / 2)
        box(name, "ink", centre, (0.00035, long), z, z + 0.00006, parent, yaw=angle - math.pi / 2)


def tube(name, mat, points, radius, parent=None, segments=24, samples=10):
    """A round tube through `points` (local to `parent`), smoothed with a Catmull-Rom spline."""
    path = []
    padded = [points[0]] + list(points) + [points[-1]]
    for i in range(1, len(padded) - 2):
        p0, p1, p2, p3 = (Vector(p) for p in padded[i - 1 : i + 3])
        for s in range(samples):
            t = s / samples
            path.append(
                0.5
                * (
                    2 * p1
                    + (-p0 + p2) * t
                    + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                    + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t
                )
            )
    path.append(Vector(points[-1]))

    verts, faces = [], []
    up = Vector((0, 0, 1))
    for i, point in enumerate(path):
        ahead = path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]
        ahead.normalize()
        side = ahead.cross(up).normalized()
        lift = side.cross(ahead).normalized()
        for s in range(segments):
            angle = 2 * math.pi * s / segments
            verts.append(point + radius * (math.cos(angle) * side + math.sin(angle) * lift))
    for i in range(len(path) - 1):
        for s in range(segments):
            a = i * segments + s
            b = i * segments + (s + 1) % segments
            faces.append((a, b, b + segments, a + segments))
    faces.append(tuple(range(segments))[::-1])
    faces.append(tuple(range((len(path) - 1) * segments, len(path) * segments)))
    obj = from_data(name, mat, [tuple(v) for v in verts], faces)
    if parent is not None:
        obj.parent = parent  # points are already local to the parent
    return obj


def empty(name, at, parent=None):
    obj = bpy.data.objects.new(name, None)
    obj.location = at
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.update()
    if parent is not None:
        world = obj.matrix_world.copy()
        obj.parent = parent
        obj.matrix_world = world
    return obj


def label(text, at, size, parent=None, z=0.0, mat="ink", yaw=0.0):
    """Printed lettering: flat text lying on a surface, readable from the front of the deck."""
    curve = bpy.data.curves.new("Text", "FONT")
    curve.body = text
    curve.size = size
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    curve.extrude = 0.00004
    source = bpy.data.objects.new("Text", curve)
    source.location = (at.x, at.y, z + 0.00005)
    source.rotation_euler = (0, 0, yaw)
    bpy.context.collection.objects.link(source)
    bpy.context.view_layer.update()
    mesh = bpy.data.meshes.new_from_object(source.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    obj = bpy.data.objects.new("Label " + text, mesh)
    obj.matrix_world = source.matrix_world
    bpy.context.collection.objects.link(obj)
    bpy.data.objects.remove(source)
    bpy.context.view_layer.update()
    return finish(obj, mat, parent, smooth=False)


def glyph(name, at, pointing_right, parent, size=0.0042, z=0.0):
    """Two small raised triangles: the previous or next symbol."""
    verts, faces = [], []
    for k, offset in enumerate((-size * 0.55, size * 0.55)):
        tip = size / 2 if pointing_right else -size / 2
        base = k * 6
        for height in (z, z + 0.0003):
            verts += [
                (at.x + offset - tip, at.y + size * 0.6, height),
                (at.x + offset + tip, at.y, height),
                (at.x + offset - tip, at.y - size * 0.6, height),
            ]
        order = (5, 4, 3) if pointing_right else (3, 4, 5)  # counter-clockwise from above, so the face points up
        faces.append(tuple(base + i for i in order))
        for i in range(3):
            j = (i + 1) % 3
            faces.append((base + i, base + j, base + 3 + j, base + 3 + i))
    return from_data(name, "ink", verts, faces, parent, smooth=False)


# --- The deck ---------------------------------------------------------------------------------------------------
def build_plinth():
    w, d, h = PLINTH
    box("Plinth", "plinth", table(0, 0), (w, d), -h, 0, bevel=0.004)
    # The round well the platter sits in.
    cylinder("PlatterWell", "well", table(*SPINDLE), PLATTER_RADIUS + 0.005, 0.0, 0.0004, vertices=128)
    # Four feet, mostly hidden from above.
    for sx in (-1, 1):
        for sz in (-1, 1):
            cylinder(
                "Foot", "rubber", table(sx * (w / 2 - 0.045), sz * (d / 2 - 0.045)), 0.034, -h - 0.022, -h, bevel=0.003
            )


def build_platter():
    spin = empty("Spin", table(*SPINDLE))
    at = table(*SPINDLE)
    cylinder("PlatterBody", "platter", at, PLATTER_RADIUS, 0.003, 0.0185, spin, bevel=0.0012, vertices=160)
    # Sloped rim that carries the strobe dots.
    cylinder(
        "PlatterRim", "black_metal", at, PLATTER_RADIUS - 0.0005, 0.0185, 0.0200, spin,
        vertices=160, radius_top=0.1520,
    )
    cylinder("PlatterLip", "bright", at, 0.1520, 0.0196, 0.0204, spin, vertices=160)
    cylinder("Slipmat", "felt", at, 0.1500, 0.0200, PLATTER_TOP, spin, vertices=160)
    cylinder("Spindle", "bright", at, 0.0036, PLATTER_TOP, 0.0320, spin, bevel=0.0012, vertices=32)

    # Four rows of round strobe dots.
    verts, faces = [], []
    rows = [(0.1640, 180, 0.00135), (0.1603, 176, 0.00125), (0.1568, 172, 0.00115), (0.1535, 168, 0.00105)]
    for radius, count, dot in rows:
        for i in range(count):
            angle = 2 * math.pi * i / count
            centre = at + Vector((math.cos(angle), math.sin(angle), 0)) * radius
            base = len(verts)
            for k in range(14):
                a = 2 * math.pi * k / 14
                p = centre + Vector((math.cos(a), math.sin(a), 0)) * dot
                r = (Vector((p.x, p.y, 0)) - Vector((at.x, at.y, 0))).length
                verts.append((p.x, p.y, 0.0189 + (PLATTER_RADIUS - r) / (PLATTER_RADIUS - 0.152) * 0.0014))
            faces.append(tuple(range(base, base + 14)))
    from_data("StrobeDots", "bright", verts, faces, spin, smooth=False)
    return spin


def build_controls():
    # --- Front left: start/stop pad, strobe tower, previous and next ---
    at = table(-0.199, 0.147)
    cylinder("StartSeat", "well", at, 0.0190, 0.0, 0.0004, vertices=128)
    cylinder("StartRing", "black_metal", at, 0.0180, 0.0004, 0.0022, bevel=0.0006, vertices=128)
    cylinder("StartRingLip", "steel", at, 0.0168, 0.0022, 0.0025, vertices=128)
    start = empty("BtnStart", at)
    cylinder("StartPad", "rubber", at, 0.0158, 0.0, 0.0052, start, bevel=0.0014, vertices=128)
    # A raised rim around a flat face for the finger.
    cylinder("StartFace", "rubber", at, 0.0126, 0.0052, 0.00535, start, bevel=0.0001, vertices=128)
    label("START", at + Vector((0, 0.0022, 0)), 0.0028, start, z=0.00537)
    label("STOP", at + Vector((0, -0.0022, 0)), 0.0028, start, z=0.00537)
    box("StartRule", "ink", at, (0.0080, 0.00025), 0.00535, 0.00543, start)

    tower = table(-0.2035, 0.105)
    cylinder("StrobeSeat", "well", tower, 0.0155, 0.0, 0.0004, vertices=96)
    cylinder("StrobeBase", "black_metal", tower, 0.0145, 0.0004, 0.0032, bevel=0.0007)
    knurled("StrobeTower", "black_metal", tower, 0.0118, 0.0032, 0.0200, teeth=44, depth=0.0007)
    cylinder("StrobeCollar", "steel", tower, 0.0120, 0.0188, 0.0196, vertices=96)
    cylinder("StrobeCap", "button", tower, 0.0111, 0.0200, 0.0226, bevel=0.0009)
    cylinder("StrobeCapInset", "well", tower, 0.0070, 0.0226, 0.02265, vertices=64)
    cylinder("StrobeCapCentre", "button", tower, 0.0063, 0.02265, 0.0229, bevel=0.0004, vertices=64)
    box("StrobeHood", "black_metal", tower + Vector((0.0121, 0, 0)), (0.0060, 0.0145), 0.0030, 0.0160, bevel=0.0010)
    lamp = box("StrobeLamp", "lamp", tower + Vector((0.0145, 0, 0)), (0.0022, 0.0105), 0.0045, 0.0140, bevel=0.0006)
    lamp["note"] = "The app swaps this material to light the lamp."
    # The speed-check dots printed beside the lamp.
    for row in range(3):
        for col in range(4 - row):
            cylinder("StrobeMark", "ink", table(-0.1840 + col * 0.0026 + row * 0.0013, 0.1245 + row * 0.0026), 0.00055, 0.0, 0.00008, vertices=12)

    # The two speed buttons of the real deck become previous and next: slim keys in one shared frame.
    rounded_ring("TrackFrame", "black_metal", table(-0.146, 0.160), (0.0530, 0.0118), (0.0506, 0.0094), 0.0, 0.0012, 0.0012, 0.0006, bevel=0.0002)
    box("TrackWell", "well", table(-0.146, 0.160), (0.0506, 0.0094), 0.0, 0.0003)
    for name, x, right in (("BtnPrev", -0.1585, False), ("BtnNext", -0.1335, True)):
        at = table(x, 0.160)
        holder = empty(name, at)
        box(name + "Cap", "button", at, (0.0240, 0.0084), 0.0003, 0.0030, holder, bevel=0.0007)
        glyph(name + "Glyph", at + Vector((-0.0030, 0, 0)), right, holder, size=0.0036, z=0.0030)
        box(name + "Led", "led", at + Vector((0.0078, 0, 0)), (0.0034, 0.0009), 0.0030, 0.0032, holder)

    # Target light, front, right of the platter.
    at = table(0.042, 0.157)
    cylinder("TargetSeat", "well", at, 0.0080, 0.0, 0.0004, vertices=64)
    cylinder("TargetRing", "black_metal", at, 0.0070, 0.0004, 0.0016, bevel=0.0004, vertices=64)
    cylinder("TargetLight", "rubber", at, 0.0052, 0.0, 0.0062, bevel=0.0008, vertices=64)
    cylinder("TargetLens", "lens", at, 0.0028, 0.0062, 0.0064, vertices=32)

    # 45 rpm adapter in its recess, back left.
    at = table(-0.192, -0.142)
    cylinder("AdapterRecess", "well", at, 0.0205, 0.0, 0.0004)
    cylinder("Adapter", "bright", at, 0.0185, 0.0004, 0.0050, bevel=0.0010)
    cylinder("AdapterCone", "steel", at, 0.0115, 0.0050, 0.0075, radius_top=0.0050)
    cylinder("AdapterHole", "well", at, 0.0037, 0.0075, 0.0077, vertices=32)

    # --- Front right: pitch fader in a rounded trough, scale, two round buttons, range keys ---
    px, mid = 0.189, 0.0815
    trough = table(px, mid)
    rounded_ring("PitchLip", "black_metal", trough, (0.0230, 0.1290), (0.0204, 0.1264), 0.0, 0.0011, 0.0036, 0.0024, bevel=0.0003)
    rounded_box("PitchFloor", "panel", trough, (0.0204, 0.1264), 0.0, 0.00025, 0.0024)
    rounded_box("PitchSlot", "well", trough, (0.0026, 0.1130), 0.00025, 0.00032, 0.0012)

    # Scale beside the trough: 21 marks, a minus above, a plus below, a light at the centre mark.
    edge, step = px - 0.0115 - 0.0014, 0.00506
    for i in range(21):
        length = 0.0068 if i % 2 == 0 else 0.0040
        box("PitchTick", "ink", table(edge - length / 2, mid + (i - 10) * step), (length, 0.0003), 0.0, 0.00006)
    for sign, tz in (("-", mid - 10 * step), ("+", mid + 10 * step)):
        at = table(edge - 0.0068 - 0.0021, tz)
        cylinder("PitchSign", "ink", at, 0.0019, 0.0, 0.00006, vertices=32)
        cylinder("PitchSignFill", "plinth", at, 0.0015, 0.0, 0.00009, vertices=32)
        box("PitchSignBar", "ink", at, (0.0018, 0.0003), 0.00009, 0.00013)
        if sign == "+":
            box("PitchSignBar", "ink", at, (0.0003, 0.0018), 0.00009, 0.00013)
    led_x = edge - 0.0068 - 0.0028
    rounded_box("PitchZeroLed", "led", table(led_x, mid), (0.0034, 0.0014), 0.0, 0.0004, 0.0006)

    # Fader cap: a block with a dished top and a centre line.
    profile = [(-0.0060, 0.0006), (0.0060, 0.0006), (0.0060, 0.0090), (0.0048, 0.0098), (0.0032, 0.0090),
               (0.0012, 0.0076), (-0.0012, 0.0076), (-0.0032, 0.0090), (-0.0048, 0.0098), (-0.0060, 0.0090)]
    n = len(profile)
    verts = [(trough.x + side * 0.0090, trough.y + y, z) for side in (-1, 1) for y, z in profile]
    faces = [tuple(range(n)), tuple(range(n, 2 * n))[::-1]]
    faces += [((i + 1) % n, i, n + i, n + (i + 1) % n) for i in range(n)]
    from_data("PitchKnob", "button", verts, faces, smooth=False, bevel=0.0005)
    box("PitchStem", "well", trough, (0.0022, 0.0040), 0.0003, 0.0010)
    box("PitchKnobLine", "ink", trough, (0.0170, 0.0008), 0.0076, 0.00775)

    # A thin printed line from the centre light to the round button beside the scale.
    quartz = table(0.1536, 0.1260)
    box("QuartzLine", "ink", table((led_x - 0.0024 + 0.1536) / 2, mid), (led_x - 0.0024 - 0.1536, 0.00025), 0.0, 0.00006)
    box("QuartzLine", "ink", table(0.1536, (mid + 0.1165) / 2), (0.00025, 0.1165 - mid), 0.0, 0.00006)
    cylinder("QuartzSeat", "well", quartz, 0.0086, 0.0, 0.0004, vertices=64)
    cylinder("QuartzRing", "black_metal", quartz, 0.0080, 0.0004, 0.0016, bevel=0.0004, vertices=64)
    cylinder("QuartzButton", "button", quartz, 0.0062, 0.0, 0.0028, bevel=0.0008, vertices=64)
    label("QUARTZ", table(0.1536, 0.1372), 0.0020)

    reverse = table(px, 0.0015)
    cylinder("ReverseSeat", "well", reverse, 0.0086, 0.0, 0.0004, vertices=64)
    cylinder("ReverseRing", "black_metal", reverse, 0.0080, 0.0004, 0.0016, bevel=0.0004, vertices=64)
    cylinder("ReverseButton", "light_cap", reverse, 0.0062, 0.0, 0.0028, bevel=0.0008, vertices=64)
    label("REVERSE", table(px, 0.0128), 0.0020)

    rounded_ring("RangeFrame", "black_metal", table(0.1886, 0.160), (0.0500, 0.0118), (0.0476, 0.0094), 0.0, 0.0012, 0.0012, 0.0006, bevel=0.0002)
    box("RangeWell", "well", table(0.1886, 0.160), (0.0476, 0.0094), 0.0, 0.0003)
    for bx, text in ((0.1768, "±8"), (0.2004, "±16")):
        at = table(bx, 0.160)
        box("RangeButton", "button", at, (0.0228, 0.0084), 0.0003, 0.0030, bevel=0.0007)
        label(text, at + Vector((-0.0038, 0, 0)), 0.0026, z=0.0030)
        box("RangeLed", "led", at + Vector((0.0070, 0, 0)), (0.0034, 0.0009), 0.0030, 0.0032)
    label("±24%", table(0.1886, 0.1508), 0.0020)
    for side in (-1, 1):
        box("RangeBracket", "ink", table(0.1886 + side * 0.0120, 0.1508), (0.0130, 0.00025), 0.0, 0.00006)
        box("RangeBracket", "ink", table(0.1886 + side * 0.0185, 0.1518), (0.00025, 0.0022), 0.0, 0.00006)

    # Dust-cover hinge sockets at the back.
    for hx in (-0.150, 0.092):
        box("HingeSocket", "well", table(hx, -0.166), (0.030, 0.010), 0.0, 0.0004)


# The arm tube seen from above, in the arm's own frame: (to the right, forward) from the pivot.
# The stylus sits straight ahead at ARM_LENGTH; the tube bows out to the right and the headshell angles back in.
ARM_TUBE = [(0.0, 0.0), (0.0052, 0.033), (0.0100, 0.066), (0.0185, 0.100), (0.0285, 0.128), (0.0335, 0.148),
            (0.0285, 0.1665), (0.0186, 0.1888)]
ARM_REAR = math.atan2(ARM_TUBE[1][0], ARM_TUBE[1][1])  # the counterweight continues the tube's first stretch


def rest_direction():
    to_spindle = Vector((SPINDLE[0] - PIVOT[0], SPINDLE[1] - PIVOT[1])).normalized()
    c, s = math.cos(-REST_SWING), math.sin(-REST_SWING)
    return Vector((to_spindle.x * c - to_spindle.y * s, to_spindle.x * s + to_spindle.y * c))


def build_tonearm_base():
    at = table(*PIVOT)
    cylinder("ArmBoard", "black_metal", at, 0.0600, 0.0, 0.0030, bevel=0.0008, vertices=128)
    knurled("HeightRing", "black_metal", at, 0.0470, 0.0030, 0.0110, teeth=90, depth=0.0005)
    cylinder("HeightRingTop", "button", at, 0.0440, 0.0110, 0.0125, bevel=0.0005, vertices=128)
    cylinder("ArmColumn", "black_metal", at, 0.0150, 0.0125, 0.0260, bevel=0.0008)

    # Anti-skate dial.
    dial = table(PIVOT[0] + 0.030, PIVOT[1] + 0.024)
    knurled("AntiSkate", "black_metal", dial, 0.0100, 0.0125, 0.0230, teeth=32)
    cylinder("AntiSkateCap", "button", dial, 0.0088, 0.0230, 0.0240)
    box("AntiSkateMark", "ink", dial + Vector((0, 0.005, 0)), (0.0008, 0.005), 0.0240, 0.0242)

    # Cue lever.
    lever = table(PIVOT[0] - 0.012, PIVOT[1] + 0.046)
    cylinder("CueBase", "black_metal", lever, 0.0075, 0.0030, 0.0120, bevel=0.0006)
    box("CueLever", "black_metal", lever + Vector((-0.012, 0, 0)), (0.030, 0.0050), 0.0100, 0.0135, bevel=0.0010)
    cylinder("CueTip", "button", lever + Vector((-0.027, 0, 0)), 0.0040, 0.0095, 0.0140, bevel=0.0008, vertices=32)

    # Arm rest: a post with a cradle and a clip, under the tube in its rest position.
    direction = rest_direction()
    arm_yaw = math.atan2(direction.x, direction.y)
    lateral, forward = 0.0142, 0.083
    spot = Matrix.Rotation(arm_yaw, 3, "Z") @ Vector((lateral, -forward, 0))
    post = table(*PIVOT) + spot
    yaw = arm_yaw + math.atan2(0.0085, 0.034)
    cylinder("RestPost", "black_metal", post, 0.0050, 0.0, 0.0400, bevel=0.0005, vertices=32)
    box("RestCradle", "black_metal", post, (0.020, 0.008), 0.0400, 0.0435, bevel=0.0008, yaw=yaw)
    for side in (-1, 1):
        offset = Vector((math.cos(yaw), math.sin(yaw), 0)) * side * 0.0085
        box("RestCheek", "black_metal", post + offset, (0.003, 0.008), 0.0435, 0.0520, bevel=0.0006, yaw=yaw)

    # Printed scales on the height ring and the anti-skate dial.
    tick_ring("HeightTick", at, 0.0432, 0.0016, 30, 0.0125, arc=(-170, -20))
    tick_ring("AntiSkateTick", dial, 0.0084, 0.0016, 20, 0.0240)


def build_tonearm():
    """The moving arm, in the Arm empty's local frame: forward is -y, right is +x, tube axis at z = 0."""
    arm = empty("Arm", table(PIVOT[0], PIVOT[1], ARM_AXIS_HEIGHT))
    origin = arm.location

    def local(right, forward, up=0.0):
        return origin + Vector((right, -forward, up))

    def adopt(obj):
        bpy.context.view_layer.update()
        world = obj.matrix_world.copy()
        obj.parent = arm
        obj.matrix_world = world
        return obj

    def rod(name, mat, base, heading, start, end, radius, bevel=0.0006, radius_end=None):
        """A cylinder lying along `heading` (right, forward), from `start` to `end` metres past `base`."""
        centre = Vector(base) + Vector(heading) * (start + end) / 2
        at = local(centre.x, centre.y)
        obj = cylinder(name, mat, at, radius, 0, end - start, None, bevel=bevel, vertices=48, radius_top=radius_end)
        obj.rotation_euler = (math.radians(90), 0, math.atan2(heading[0], heading[1]))
        obj.location = at
        return adopt(obj)

    rear = (math.sin(ARM_REAR), math.cos(ARM_REAR))
    rear_yaw = ARM_REAR

    # Gimbal: a square frame the tube passes through, on a turning base, with the pivot screw on top.
    cylinder("GimbalBase", "black_metal", local(0, 0), 0.0150, origin.z - 0.0140, origin.z - 0.0085, arm, bevel=0.0008)
    box("GimbalSill", "black_metal", local(0, 0), (0.0460, 0.0140), origin.z - 0.0100, origin.z - 0.0068, arm, bevel=0.0008, yaw=rear_yaw)
    for side in (-1, 1):
        offset = Vector((math.cos(rear_yaw), math.sin(rear_yaw), 0)) * side * 0.0202
        box("GimbalPost", "black_metal", local(0, 0) + offset, (0.0056, 0.0140), origin.z - 0.0068, origin.z + 0.0085, arm, bevel=0.0008, yaw=rear_yaw)
        cylinder("BearingScrew", "steel", local(0, 0) + offset, 0.0017, origin.z + 0.0115, origin.z + 0.0121, arm, vertices=16)
    box("GimbalBar", "black_metal", local(0, 0), (0.0460, 0.0140), origin.z + 0.0085, origin.z + 0.0115, arm, bevel=0.0010, yaw=rear_yaw)
    box("PivotBlock", "black_metal", local(0, 0), (0.0130, 0.0170), origin.z - 0.0055, origin.z + 0.0055, arm, bevel=0.0012, yaw=rear_yaw)
    cylinder("PivotScrew", "steel", local(0, 0), 0.0032, origin.z + 0.0115, origin.z + 0.0128, arm, bevel=0.0004, vertices=32)
    box("PivotScrewSlot", "well", local(0, 0), (0.0046, 0.0007), origin.z + 0.0128, origin.z + 0.0129, arm, yaw=rear_yaw)

    # The tube: a rear stub, a thicker sleeve out of the gimbal, then the long bowed run to the headshell collar.
    stub = (-rear[0] * 0.066, -rear[1] * 0.066)
    points = [(stub[0], -stub[1], 0)] + [(right, -forward, 0) for right, forward in ARM_TUBE]
    tube("ArmTube", "black_metal", points, 0.0039, arm, samples=14)
    rod("ArmSleeve", "black_metal", (0, 0), rear, 0.0085, 0.0300, 0.0056, radius_end=0.0044, bevel=0.0)

    # Counterweight: numbered dial ring at the front, bright body, black grip at the back.
    back = (-rear[0], -rear[1])
    rod("CounterweightDial", "black_metal", (0, 0), back, 0.0280, 0.0360, 0.0136)
    rod("CounterweightMark", "ink", (0, 0), back, 0.0352, 0.0356, 0.01365, bevel=0.0)
    rod("Counterweight", "bright", (0, 0), back, 0.0360, 0.0560, 0.0126)
    rod("CounterweightGrip", "black_metal", (0, 0), back, 0.0560, 0.0660, 0.0126)
    rod("CounterweightEnd", "button", (0, 0), back, 0.0660, 0.0685, 0.0080)

    # Headshell, angled in from the joint to put the stylus on the arm's axis at ARM_LENGTH.
    stylus = Vector((0.0, ARM_LENGTH))
    start = Vector(ARM_TUBE[-1])
    heading = (stylus - start).normalized()
    yaw = math.atan2(heading.x, heading.y)  # rotation about z for a part modelled along -y
    side = Vector((heading.y, -heading.x))  # to the right of the heading

    def on_shell(distance, lateral=0.0, up=0.0):
        p = start + heading * distance + side * lateral
        return local(p.x, p.y, up)

    # Locking collar: black grip rings, a bright ring, then the headshell's neck.
    rod("ShellCollar", "black_metal", start, heading, -0.0030, 0.0070, 0.0056)
    for k in range(4):
        rod("ShellCollarRib", "button", start, heading, 0.0002 + k * 0.0016, 0.0010 + k * 0.0016, 0.0059, bevel=0.0)
    rod("ShellRing", "bright", start, heading, 0.0070, 0.0086, 0.0050, bevel=0.0003)
    rod("ShellNeck", "black_metal", start, heading, 0.0086, 0.0150, 0.0036)

    length = (stylus - start).length + 0.006
    # Angular plate with two slots, like a real universal headshell.
    plate_verts, plate_faces = [], []
    outline = [(-0.0036, 0.0120), (0.0036, 0.0120), (0.0036, 0.0190), (0.0095, 0.0265), (0.0095, length),
               (-0.0095, length), (-0.0095, 0.0265), (-0.0036, 0.0190)]
    for z in (origin.z - 0.0010, origin.z + 0.0012):
        for lateral, distance in outline:
            p = on_shell(distance, lateral)
            plate_verts.append((p.x, p.y, z))
    n = len(outline)
    plate_faces.append(tuple(range(n))[::-1])
    plate_faces.append(tuple(range(n, 2 * n)))
    for i in range(n):
        j = (i + 1) % n
        plate_faces.append((i, j, n + j, n + i))
    from_data("Headshell", "black_metal", plate_verts, plate_faces, arm, smooth=False, bevel=0.0004)
    for lateral in (-0.0048, 0.0048):
        box("ShellSlot", "well", on_shell(length - 0.0125, lateral), (0.0030, 0.0150), origin.z + 0.0012, origin.z + 0.0014, arm, yaw=yaw)
        cylinder("ShellScrew", "bright", on_shell(length - 0.0105, lateral), 0.0019, origin.z + 0.0012, origin.z + 0.0024, arm, vertices=20)

    # Finger lift: a thin bar out to the right, turned up at the end.
    box("FingerLift", "black_metal", on_shell(length - 0.0200, 0.0165), (0.0160, 0.0034), origin.z - 0.0008, origin.z + 0.0008, arm, bevel=0.0006, yaw=yaw)
    box("FingerLiftTip", "black_metal", on_shell(length - 0.0200, 0.0250), (0.0036, 0.0034), origin.z - 0.0008, origin.z + 0.0045, arm, bevel=0.0006, yaw=yaw)

    # Cartridge and stylus under the plate.
    box("CartridgeBody", "black_metal", on_shell(length - 0.016), (0.0165, 0.0200), origin.z - 0.0100, origin.z - 0.0010, arm, bevel=0.0008, yaw=yaw)
    box("StylusGrip", "cartridge", on_shell(length - 0.0045), (0.0150, 0.0080), origin.z - 0.0125, origin.z - 0.0030, arm, bevel=0.0008, yaw=yaw)
    cylinder("Stylus", "bright", local(0, ARM_LENGTH), 0.0004, origin.z - STYLUS_DROP, origin.z - 0.0120, arm, vertices=8)
    return arm


# --- Preview and export -----------------------------------------------------------------------------------------
def render_preview(path, arm):
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.resolution_x = 1400
    scene.render.resolution_y = 1100
    scene.render.filepath = path
    scene.view_settings.view_transform = "Standard"

    world = bpy.data.worlds.new("Preview")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.05, 0.05, 0.05, 1)
    scene.world = world

    camera = bpy.data.objects.new("PreviewCamera", bpy.data.cameras.new("PreviewCamera"))
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 0.60
    camera.location = (0, 0, 2)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera

    for name, location, energy, size in (("Key", (-0.5, 0.5, 1.2), 60, 0.8), ("Fill", (0.6, -0.5, 1.0), 20, 1.2)):
        light = bpy.data.objects.new(name, bpy.data.lights.new(name, "AREA"))
        light.data.energy = energy
        light.data.size = size
        light.location = location
        direction = Vector((0, 0, 0)) - Vector(location)
        light.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        bpy.context.collection.objects.link(light)

    # Pose the arm on its rest for the picture only.
    direction = rest_direction()
    arm.rotation_euler = (0, 0, math.atan2(direction.x, direction.y))
    arm.location.z += 0.010
    bpy.ops.render.render(write_still=True)
    arm.rotation_euler = (0, 0, 0)
    arm.location.z -= 0.010
    for obj in [camera] + [o for o in bpy.data.objects if o.type == "LIGHT"]:
        bpy.data.objects.remove(obj)


def export(path):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.wm.usd_export(
        filepath=path,
        export_materials=True,
        generate_preview_surface=True,
        export_normals=True,
        export_uvmaps=True,
        export_animation=False,
        convert_world_material=False,
        convert_orientation=True,
        export_global_forward_selection="NEGATIVE_Z",
        export_global_up_selection="Y",
        evaluation_mode="RENDER",
        root_prim_path="/Turntable",
    )


def main():
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if not args:
        raise SystemExit("usage: Blender --background --python turntable.py -- <out.usdz> [preview.png]")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    make_materials()
    build_plinth()
    build_platter()
    build_controls()
    build_tonearm_base()
    arm = build_tonearm()

    if len(args) > 1:
        render_preview(args[1], arm)
    export(args[0])


if __name__ == "__main__":
    main()
