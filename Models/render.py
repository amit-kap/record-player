"""High-resolution beauty renders of the turntable from several angles.

Run through scripts/render-model.sh:
    Blender --background --python Models/render.py -- <output folder> [width height samples]

Uses the same builders as the exported model, plus a record that exists only for these pictures
(in the app the record is built in code).
"""

import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import turntable as tt  # noqa: E402

PLAY_SWING = math.radians(26)


def add_record(spin):
    at = tt.table(*tt.SPINDLE)

    vinyl = bpy.data.materials.new("Vinyl")
    vinyl.use_nodes = True
    nodes, links = vinyl.node_tree.nodes, vinyl.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.004, 0.004, 0.004, 1)
    bsdf.inputs["Roughness"].default_value = 0.22
    bsdf.inputs["Anisotropic"].default_value = 0.85
    # Grooves: fine concentric ridges around the spindle, as a bump.
    coords = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Location"].default_value = (-at.x, -at.y, 0)
    wave = nodes.new("ShaderNodeTexWave")
    wave.wave_type = "RINGS"
    wave.rings_direction = "Z"
    wave.inputs["Scale"].default_value = 900
    wave.inputs["Distortion"].default_value = 0.4
    wave.inputs["Detail"].default_value = 2
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.35
    bump.inputs["Distance"].default_value = 0.00005
    links.new(coords.outputs["Object"], mapping.inputs["Vector"])
    links.new(mapping.outputs["Vector"], wave.inputs["Vector"])
    links.new(wave.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    # Radial tangent, so the highlight stretches into the streaks vinyl is known for.
    tangent = nodes.new("ShaderNodeTangent")
    tangent.direction_type = "RADIAL"
    tangent.axis = "Z"
    links.new(tangent.outputs["Tangent"], bsdf.inputs["Tangent"])
    tt.M["vinyl"] = vinyl
    tt.M["label"] = tt.material("Label", 0.0, 0.6, color=(0.80, 0.77, 0.70))
    tt.M["label_ring"] = tt.material("LabelRing", 0.02, 0.5)

    record = tt.cylinder("Record", "vinyl", at, 0.150, tt.PLATTER_TOP, tt.PLATTER_TOP + 0.002, spin, bevel=0.0006, vertices=200)
    # Object coordinates must be centred on the spindle for the rings and the radial tangent.
    bpy.context.view_layer.objects.active = record
    record.select_set(True)
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY")
    record.select_set(False)
    mapping.inputs["Location"].default_value = (0, 0, 0)

    top = tt.PLATTER_TOP + 0.002
    tt.cylinder("RunOut", "label_ring", at, 0.058, top, top + 0.00005, spin, vertices=128)
    tt.cylinder("Label", "label", at, 0.050, top, top + 0.0002, spin, vertices=128)
    tt.cylinder("LabelRing", "label_ring", at, 0.044, top + 0.0002, top + 0.00022, spin, vertices=128)
    tt.cylinder("LabelInner", "label", at, 0.0435, top + 0.00022, top + 0.00024, spin, vertices=128)


def pose_arm(arm):
    to_spindle = Vector((tt.SPINDLE[0] - tt.PIVOT[0], tt.SPINDLE[1] - tt.PIVOT[1])).normalized()
    c, s = math.cos(-PLAY_SWING), math.sin(-PLAY_SWING)
    direction = Vector((to_spindle.x * c - to_spindle.y * s, to_spindle.x * s + to_spindle.y * c))
    arm.rotation_euler = (0, 0, math.atan2(direction.x, direction.y))
    arm.location.z = tt.ARM_AXIS_HEIGHT + 0.002  # needle on the record


def light_lamp():
    lamp = tt.M["lamp"]
    bsdf = lamp.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.25, 0.45, 1, 1)
    bsdf.inputs["Emission Color"].default_value = (0.25, 0.45, 1, 1)
    bsdf.inputs["Emission Strength"].default_value = 60
    glow = bpy.data.objects.new("StrobeGlow", bpy.data.lights.new("StrobeGlow", "POINT"))
    glow.data.color = (0.3, 0.5, 1)
    glow.data.energy = 0.25
    glow.data.shadow_soft_size = 0.004
    glow.location = tt.table(-0.1855, 0.105, 0.010)
    bpy.context.collection.objects.link(glow)


def studio():
    scene = bpy.context.scene
    world = bpy.data.worlds.new("Studio")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.006, 0.006, 0.007, 1)
    scene.world = world

    floor_mat = tt.material("Floor", 0.012, 0.5)
    tt.M["floor"] = floor_mat
    tt.box("Floor", "floor", tt.table(0, 0), (8, 8), -tt.PLINTH[2] - 0.024, -tt.PLINTH[2] - 0.022)

    def area(name, location, target, energy, size, color=(1, 1, 1)):
        light = bpy.data.objects.new(name, bpy.data.lights.new(name, "AREA"))
        light.data.energy = energy
        light.data.shape = "RECTANGLE"
        light.data.size, light.data.size_y = size
        light.data.color = color
        light.location = location
        light.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()
        bpy.context.collection.objects.link(light)

    # A long soft box behind and left, a cool rim from the right, a faint fill from the front.
    area("Key", (-0.55, 0.75, 0.70), (0, 0, 0), 55, (1.3, 0.35))
    area("Rim", (0.85, 0.25, 0.45), (0.05, 0, 0), 22, (0.25, 0.9), color=(0.82, 0.90, 1.0))
    area("Fill", (0.1, -0.95, 0.55), (0, 0, 0), 9, (1.2, 0.5))


def shot(name, location, target, lens, folder, dof=None):
    scene = bpy.context.scene
    data = bpy.data.cameras.new(name)
    data.lens = lens
    data.sensor_width = 36
    data.clip_start = 0.01
    if dof:
        data.dof.use_dof = True
        data.dof.focus_distance = (Vector(location) - Vector(target)).length
        data.dof.aperture_fstop = dof
    camera = bpy.data.objects.new(name, data)
    camera.location = location
    camera.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    scene.render.filepath = os.path.join(folder, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("rendered", scene.render.filepath)


def main():
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if not args:
        raise SystemExit("usage: Blender --background --python render.py -- <folder> [width height samples]")
    folder = args[0]
    width, height, samples = (int(v) for v in (args[1:4] + ["2880", "1800", "96"][len(args[1:4]) :]))
    only = args[4].split(",") if len(args) > 4 else None

    bpy.ops.wm.read_factory_settings(use_empty=True)
    tt.make_materials()
    tt.build_plinth()
    spin = tt.build_platter()
    tt.build_controls()
    tt.build_tonearm_base()
    arm = tt.build_tonearm()
    add_record(spin)
    pose_arm(arm)
    light_lamp()
    studio()

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for device in prefs.devices:
            device.use = True
        scene.cycles.device = "GPU"
    except Exception as error:  # falls back to the CPU
        print("GPU unavailable:", error)
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = -1.5  # a dark deck in a dark room, like the app

    centre = (0.0, 0.0, 0.0)
    shots = [
        # name, camera position (x, y away from viewer, z up), target, lens mm, f-stop
        ("01-top", (0.0, 0.0, 1.9), centre, 110, None),
        ("02-front-three-quarter", (-0.62, -0.78, 0.52), (0.0, 0.0, -0.01), 70, None),
        ("03-low-front", (0.10, -0.95, 0.20), (0.0, 0.0, 0.0), 75, 8),
        ("04-tonearm", (0.50, -0.34, 0.26), (0.13, -0.02, 0.03), 85, 5.6),
        ("11-tonearm-top", (0.170, 0.0, 0.75), (0.170, 0.001, 0.0), 105, None),
        ("05-headshell", (0.06, -0.40, 0.11), (0.03, -0.085, 0.03), 100, 4),
        ("06-strobe", (-0.42, -0.30, 0.10), (-0.20, -0.125, 0.012), 100, 4),
        ("07-front-left", (-0.330, -0.385, 0.200), (-0.180, -0.140, 0.0), 85, 8),
        ("08-front-right", (0.330, -0.400, 0.220), (0.186, -0.105, 0.0), 85, 8),
        ("09-front-left-top", (-0.180, -0.136, 0.60), (-0.180, -0.135, 0.0), 120, None),
        ("10-front-right-top", (0.180, -0.081, 0.60), (0.180, -0.080, 0.0), 78, None),
    ]
    os.makedirs(folder, exist_ok=True)
    for name, location, target, lens, dof in shots:
        if only and name[:2] not in only:
            continue
        shot(name, location, target, lens, folder, dof)


main()
