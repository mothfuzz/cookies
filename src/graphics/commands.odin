package graphics

//whoa we did it we imported another cookies package in a cookies package
import "cookies:transform"

import "core:math"
import "core:math/linalg"

Frame :: struct {
    //draw commands
    lights: [dynamic]Light_Draw,
    cameras: [dynamic]Camera_Draw,
    action: [dynamic]Mesh_Draw,
    batch_ids: map[Batch_Key]u32,
    batches: [dynamic]Batch,
    render_targets: [dynamic]Render_Target_Draw,
    environment_probes: [dynamic]Environment_Probe, //even if not captured, still need to be sampled.
    
    //running extents
    scene_extents: [2][3]f32,
}
//static frame so commands can be called context-free
frame: Frame

@(private)
delete_frame :: proc() {
    delete(frame.lights)
    delete(frame.cameras)
    delete(frame.action)
    delete(frame.batch_ids)
    delete(frame.batches)
    delete(frame.render_targets)
    delete(frame.environment_probes)
}

@(private)
clear_frame :: proc() {
    clear(&frame.lights)
    clear(&frame.cameras)
    clear(&frame.action)
    clear(&frame.batch_ids)
    clear(&frame.batches)
    clear(&frame.render_targets)
    clear(&frame.environment_probes)
    frame.scene_extents[0] = math.INF_F32
    frame.scene_extents[1] = math.NEG_INF_F32
}

@(export)
draw_point_light :: proc(light: Point_Light, trans: transform.Transform = nil, layers: Layer_Mask = All_Layers) {
    append(&frame.lights, Light_Draw{light, transform.world(trans), layers})
}
@(export)
draw_directional_light :: proc(light: Directional_Light, trans: transform.Transform = nil, layers: Layer_Mask = All_Layers) {
    append(&frame.lights, Light_Draw{light, transform.world(trans), layers})
}
@(export)
draw_spot_light :: proc(light: Spot_Light, trans: transform.Transform = nil, layers: Layer_Mask = All_Layers) {
    append(&frame.lights, Light_Draw{light, transform.world(trans), layers})
}
draw_light :: proc{draw_point_light, draw_directional_light, draw_spot_light}

@(export)
draw_camera :: proc(camera: Camera, trans: transform.Transform = nil, layers: Layer_Mask = All_Layers) {
    camera := camera
    if layers != All_Layers {
        camera.layer_mask = layers
    }
    append(&frame.cameras, calculate_camera(camera, transform.world(trans))) //compute once, don't defer
}

// TODO: iterate entries of this when building targets/views in stage_views
Capture_Draw :: union {
    Render_Target_Draw,
    Environment_Probe,
}

@(export)
draw_render_target :: proc(camera: Camera, target: Render_Target, trans: transform.Transform = nil, layers: Layer_Mask = All_Layers) {
    target := target
    camera := calculate_camera(camera, transform.world(trans), &target)
    if layers != All_Layers {
        camera.layer_mask = layers
    }
    append(&frame.render_targets, Render_Target_Draw{target, camera})
}

@(export)
draw_environment_probe :: proc(probe: Environment_Probe, layers: Layer_Mask = All_Layers) {
    //frame.max_cubemap_slot = max(frame.max_cubemap_slot, probe.cubemap_slot)

    probe := probe
    if layers != All_Layers {
        probe.camera.layer_mask = layers
    }

    append(&frame.environment_probes, probe) //meshes need all drawn cubemaps, not just ones with capture this frame
}

@(private)
draw_mesh_internal :: proc(mesh: Mesh, material: Material, trans: matrix[4,4]f32,
                           material_params: Material_Params,
                           sprite, billboard, double_sided, unlit: bool,
                           bones: []matrix[4,4]f32, layers: Layer_Mask) {

    //mesh/material-local computations
    tex_size := [2]f32{material.base_color_tex.width, material.base_color_tex.height}
    uv := normalize_clip_rect(material_params.clip_rect, tex_size)
    model := sprite ? scale_sprite(trans, uv, tex_size, billboard) : trans
    bounds := mesh_bounds(model, mesh.bounding_box, billboard)
    alpha_set := alpha_product(mesh.alpha, material.base_color_tex.alpha)
    alpha, visible := alpha_class(alpha_set, material_params.base_color_mul.a, material_params.base_color_add.a)
    if !visible do return

    //prepare instance
    inst := Instance_Uniforms{}
    inst.model = model
    inst.clip_rect = uv
    inst.base_color_mul = material_params.base_color_mul
    inst.base_color_add = material_params.base_color_add
    inst.pbr_mul = material_params.pbr_mul
    inst.pbr_add = material_params.pbr_add
    inst.emissive_mul = material_params.emissive_mul
    inst.emissive_add = material_params.emissive_add
    if unlit do inst.flags += {.Unlit}
    if billboard do inst.flags += {.Billboard}
    if bones == nil do inst.skeleton_offset = -1

    //gather culling data & expand scene bounds
    cull := Mesh_Cull{bounds, layers}

    mini := &frame.scene_extents[0]
    maxi := &frame.scene_extents[1]
    //Arvo's method - convert transformed bounding axes to AABB using absolute values
    e: [3]f32
    for a in cull.axes {
        e += [3]f32{abs(a.x), abs(a.y), abs(a.z)}
    }
    extents := [2][3]f32{cull.center - e, cull.center + e}
    mini.x = min(extents[0].x, mini.x)
    mini.y = min(extents[0].y, mini.y)
    mini.z = min(extents[0].z, mini.z)
    maxi.x = max(extents[1].x, maxi.x)
    maxi.y = max(extents[1].y, maxi.y)
    maxi.z = max(extents[1].z, maxi.z)

    //construct the batch key
    key: Batch_Key
    key.mesh = mesh.hash
    key.material = material.hash
    key.alpha = alpha
    switch mesh.topology {
    case .Triangles:
        key.primitive = .Triangles_Back
        if double_sided {
            key.primitive = .Triangles_None
        } else if linalg.determinant(cast(matrix[3,3]f32)(inst.model)) < 0 {
            key.primitive = .Triangles_Front
        }
    case .Lines: key.primitive = .Lines
    case .Points: key.primitive = .Points
    }

    id, ok := frame.batch_ids[key]
    if !ok {
        id = u32(len(frame.batches))
        frame.batch_ids[key] = id
        append(&frame.batches, Batch{id, key, mesh, material})
    }
    frame.batches[id].instance_count += 1
    
    //finally push to draw list
    append(&frame.action, Mesh_Draw{key, inst, cull, bones})
}

@(export)
draw_mesh :: proc(mesh: Mesh, material: Material, trans: transform.Transform = nil,
                  material_params: Material_Params = Default_Material_Params,
                  sprite: bool = false, billboard: bool = false, double_sided: bool = false, unlit: bool = false,
                  bones: []matrix[4,4]f32 = nil, layers: Layer_Mask = All_Layers) {
    trans := transform.world(trans)
    draw_mesh_internal(mesh, material, trans, material_params, sprite, billboard, double_sided, unlit, bones, layers)
}

//sprites are just special kinds of meshes
@(export)
draw_sprite :: proc(material: Material, trans: transform.Transform = nil,
                    material_params: Material_Params = Default_Material_Params,
                    billboard: bool = true, double_sided: bool = false, unlit: bool = false, layers: Layer_Mask = All_Layers) {
    draw_mesh(quad_mesh, material, trans, material_params, true, billboard, double_sided, unlit, nil, layers)
}

@(export)
draw_line :: proc(a, b: [3]f32, color: [4]f32 = 1, trans: transform.Transform = nil, layers: Layer_Mask = All_Layers) {
    local: matrix[4,4]f32
    ab := b - a
    p1, p2: [3]f32
    if ab == 0 {
        p1, p2 = {1, 0, 0}, {0, 1, 0}
    } else {
        if abs(ab.x) > abs(ab.z) {
            p1 = {-ab.y, ab.x, 0}
        } else {
            p1 = {0, -ab.z, ab.y}
        }
        p2 = linalg.cross(ab, p1)
    }
    local[0].xyz = p1
    local[1].xyz = p2
    local[2].xyz = ab
    local[3].xyz = a
    local[3].w = 1

    draw_mesh(line_mesh, white_material, transform.world(trans) * local, base_color_tint=color, unlit=true, layers=layers)
}

@(export)
draw_point :: proc(p: [3]f32, color: [4]f32 = 1, trans: transform.Transform = nil, layers: Layer_Mask = All_Layers) {
    local: matrix[4,4]f32 = 1
    local[3].xyz = p

    draw_mesh(point_mesh, white_material, transform.world(trans) * local, base_color_tint=color, unlit=true, layers=layers)
}
