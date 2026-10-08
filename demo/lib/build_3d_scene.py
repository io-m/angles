import bpy
import math
from pathlib import Path

ROOT = Path("/Users/josipmiljak/projects/angles")
STORE = ROOT / "store"

bpy.ops.wm.read_factory_settings(use_empty=True)

scene = bpy.context.scene
scene.render.engine = 'CYCLES'
cprefs = bpy.context.preferences.addons['cycles'].preferences
cprefs.compute_device_type = 'METAL'
cprefs.get_devices()
scene.cycles.device = 'GPU'
scene.cycles.samples = 128
scene.cycles.use_adaptive_sampling = True
scene.cycles.adaptive_threshold = 0.015
scene.cycles.use_denoising = True

# AgX color management
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - High Contrast'

# World: Deep luxury studio darkroom
world = bpy.data.worlds.new('AtmosphereWorld')
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes['Background']
bg.inputs['Color'].default_value = (0.005, 0.004, 0.0035, 1.0)
bg.inputs['Strength'].default_value = 0.35

# Ground: Dark tactile slate with fine micro-grain
bpy.ops.mesh.primitive_plane_add(size=80, location=(0, 0, 0))
ground = bpy.context.active_object
ground.name = "GroundTable"

g_mat = bpy.data.materials.new(name="DarkSlatePaper")
g_mat.use_nodes = True
nodes = g_mat.node_tree.nodes
links = g_mat.node_tree.links
bsdf = nodes["Principled BSDF"]

tex_coord = nodes.new(type="ShaderNodeTexCoord")
mapping = nodes.new(type="ShaderNodeMapping")
mapping.inputs['Scale'].default_value = (45, 45, 45)
links.new(tex_coord.outputs['Object'], mapping.inputs['Vector'])

noise = nodes.new(type="ShaderNodeTexNoise")
noise.inputs['Scale'].default_value = 22.0
noise.inputs['Detail'].default_value = 8.0
noise.inputs['Roughness'].default_value = 0.72
links.new(mapping.outputs['Vector'], noise.inputs['Vector'])

bump = nodes.new(type="ShaderNodeBump")
bump.inputs['Strength'].default_value = 0.02
bump.inputs['Distance'].default_value = 0.08
links.new(noise.outputs['Fac'], bump.inputs['Height'])
links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])

bsdf.inputs['Base Color'].default_value = (0.012, 0.010, 0.009, 1.0)
bsdf.inputs['Roughness'].default_value = 0.38
bsdf.inputs['Specular IOR Level'].default_value = 0.45
ground.data.materials.append(g_mat)

# Four Style colors: Stoic blue, Optimistic amber, Humorous green, Tough Love coral
STYLE_COLORS = [
    ("Stoic", (0.20, 0.45, 1.0), (115/255, 166/255, 255/255)),
    ("Optimistic", (1.0, 0.45, 0.06), (255/255, 158/255, 56/255)),
    ("Humorous", (0.10, 0.80, 0.20), (89/255, 209/255, 115/255)),
    ("ToughLove", (1.0, 0.18, 0.12), (255/255, 107/255, 97/255)),
]

def make_sculptural_monolith(name, location, rotation, dimensions):
    import bmesh
    mesh = bpy.data.meshes.new(name + "_Mesh")
    bm = bmesh.new()

    w, d, h = dimensions
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= w
        v.co.y *= d
        v.co.z = (v.co.z + 0.5) * h  # base sits on z=0
        if v.co.z > h * 0.45:
            v.co.x *= 0.82
            v.co.y *= 0.82

    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = rotation

    bev = obj.modifiers.new(name="Bevel", type='BEVEL')
    bev.width = 0.04
    bev.segments = 4
    bev.profile = 0.7

    for poly in obj.data.polygons:
        poly.use_smooth = True

    return obj

def make_crystal_glass_material(name, tint_rgb, emit_rgb):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    m_nodes = mat.node_tree.nodes
    m_bsdf = m_nodes["Principled BSDF"]

    # Pristine optical glass with high internal reflection
    m_bsdf.inputs['Base Color'].default_value = (1.0, 1.0, 1.0, 1.0)
    m_bsdf.inputs['Roughness'].default_value = 0.012
    m_bsdf.inputs['IOR'].default_value = 1.54
    m_bsdf.inputs['Transmission Weight'].default_value = 1.0

    # Optical coat and subtle dichroic thin film
    m_bsdf.inputs['Coat Weight'].default_value = 1.0
    m_bsdf.inputs['Coat Roughness'].default_value = 0.008
    m_bsdf.inputs['Thin Film Thickness'].default_value = 360.0
    m_bsdf.inputs['Thin Film IOR'].default_value = 1.38

    # Delicate volume absorption giving deep, jewel-like body color
    vol = m_nodes.new(type="ShaderNodeVolumeAbsorption")
    vol.inputs['Color'].default_value = (*tint_rgb, 1.0)
    vol.inputs['Density'].default_value = 0.85
    mat.node_tree.links.new(vol.outputs['Volume'], m_nodes["Material Output"].inputs['Volume'])

    # Subtle internal emission at the bottom for radiant internal glow without blowout
    tex_coord = m_nodes.new(type="ShaderNodeTexCoord")
    sep_xyz = m_nodes.new(type="ShaderNodeSeparateXYZ")
    mat.node_tree.links.new(tex_coord.outputs['Object'], sep_xyz.inputs['Vector'])

    map_range = m_nodes.new(type="ShaderNodeMapRange")
    map_range.inputs['From Min'].default_value = 0.0
    map_range.inputs['From Max'].default_value = 1.0
    map_range.inputs['To Min'].default_value = 1.2
    map_range.inputs['To Max'].default_value = 0.0
    mat.node_tree.links.new(sep_xyz.outputs['Z'], map_range.inputs['Value'])

    m_bsdf.inputs['Emission Color'].default_value = (*emit_rgb, 1.0)
    mat.node_tree.links.new(map_range.outputs['Result'], m_bsdf.inputs['Emission Strength'])

    return mat

prisms = []
spacing = 1.76
start_x = -2.64

for i, (style_name, emit_color, tint_color) in enumerate(STYLE_COLORS):
    px = start_x + i * spacing
    py = (i - 1.5) ** 2 * 0.06
    pz = 0.0

    rot_z = math.radians(16 - i * 11)
    rot_x = math.radians(2)
    rot_y = math.radians(-2 if i < 2 else 2)

    height = 1.95
    p_obj = make_sculptural_monolith(
        f"Prism_{style_name}",
        (px, py, pz),
        (rot_x, rot_y, rot_z),
        (0.85, 0.85, height)
    )
    p_mat = make_crystal_glass_material(f"Glass_{style_name}", tint_color, emit_color)
    p_obj.data.materials.append(p_mat)
    prisms.append(p_obj)

    # Soft caustic pool on floor in front of each prism
    fwd_data = bpy.data.lights.new(name=f"FwdCaustic_{style_name}", type='SPOT')
    fwd_data.energy = 220.0
    fwd_data.color = emit_color
    fwd_data.spot_size = math.radians(65)
    fwd_data.spot_blend = 0.95
    fwd_data.shadow_soft_size = 0.45
    fwd_obj = bpy.data.objects.new(name=f"FwdCausticObj_{style_name}", object_data=fwd_data)
    fwd_obj.visible_camera = False
    fwd_obj.visible_transmission = False
    bpy.context.collection.objects.link(fwd_obj)
    fwd_obj.location = (px, py + 1.2, 0.7)
    fwd_obj.rotation_euler = (math.radians(-60), 0, 0)

# Studio Key Lighting
# 1. Warm Golden Amber Main Key (Overhead right)
key_data = bpy.data.lights.new(name="MainKey", type='AREA')
key_data.energy = 1100.0
key_data.color = (1.0, 0.84, 0.60)
key_data.size = 6.5
key_data.size_y = 5.0
key_obj = bpy.data.objects.new(name="MainKey", object_data=key_data)
key_obj.visible_camera = False
bpy.context.collection.objects.link(key_obj)
key_obj.location = (5.5, -6.5, 7.0)
key_obj.rotation_euler = (math.radians(52), math.radians(12), math.radians(35))

# 2. Cool Precision Rim Light (Back left, sharp glass specular lines)
rim_data = bpy.data.lights.new(name="EdgeRim", type='AREA')
rim_data.energy = 550.0
rim_data.color = (0.75, 0.88, 1.0)
rim_data.size = 8.5
rim_data.size_y = 2.0
rim_obj = bpy.data.objects.new(name="EdgeRim", object_data=rim_data)
rim_obj.visible_camera = False
bpy.context.collection.objects.link(rim_obj)
rim_obj.location = (-7.5, 4.5, 4.8)
rim_obj.rotation_euler = (math.radians(-42), math.radians(-25), math.radians(-130))

# 3. Soft Ambient Fill
fill_data = bpy.data.lights.new(name="AmbientFill", type='AREA')
fill_data.energy = 160.0
fill_data.color = (1.0, 0.94, 0.88)
fill_data.size = 14.0
fill_obj = bpy.data.objects.new(name="AmbientFill", object_data=fill_data)
fill_obj.visible_camera = False
bpy.context.collection.objects.link(fill_obj)
fill_obj.location = (0.0, -3.0, 8.5)

# ----------------- Cameras -----------------

# Camera 1: Header (21:9 - 3840×1646)
cam_header_data = bpy.data.cameras.new("CamHeader")
cam_header_data.lens = 36.0
cam_header_data.dof.use_dof = True
cam_header_data.dof.focus_object = prisms[1]
cam_header_data.dof.aperture_fstop = 4.5
cam_header_obj = bpy.data.objects.new("CamHeader", cam_header_data)
bpy.context.collection.objects.link(cam_header_obj)
# Pulled back for clean dynamic island headroom and grounded floor reflection
cam_header_obj.location = (0.0, -10.8, 4.9)
cam_header_obj.rotation_euler = (math.radians(67), 0, 0)

# Camera 2: Search (3:2 - 3840×2560)
cam_search_data = bpy.data.cameras.new("CamSearch")
cam_search_data.lens = 42.0
cam_search_data.dof.use_dof = True
cam_search_data.dof.focus_object = prisms[1]
cam_search_data.dof.aperture_fstop = 4.0
cam_search_obj = bpy.data.objects.new("CamSearch", cam_search_data)
bpy.context.collection.objects.link(cam_search_obj)
# Balanced vertical framing: monoliths centered with top headroom and bottom caustic reflection
cam_search_obj.location = (0.0, -8.6, 4.3)
cam_search_obj.rotation_euler = (math.radians(68), 0, 0)

# Save blend file
blend_path = str(STORE / "creative_scene.blend")
bpy.ops.wm.save_as_mainfile(filepath=blend_path)

def render_pass(camera_obj, width, height, out_path, samples=128):
    scene.camera = camera_obj
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.cycles.samples = samples
    scene.render.filepath = str(out_path)
    print(f"Rendering {out_path} at {width}x{height} ({samples} samples)...")
    bpy.ops.render.render(write_still=True)
    print(f"Finished {out_path}")

STORE.mkdir(parents=True, exist_ok=True)
header_out = STORE / "header-21x9.png"
search_out = STORE / "search-3x2.png"

render_pass(cam_header_obj, 3840, 1646, header_out, samples=128)
render_pass(cam_search_obj, 3840, 2560, search_out, samples=128)
