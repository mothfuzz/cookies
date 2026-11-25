package graphics

import "cookies:transform"
import "core:math/linalg"

@(export)
draw_camera :: proc(camera: Camera, trans: transform.Transform = nil) {
    push_camera(screen_pass(), calculate_camera(camera, transform.world(trans)))
}

@(export)
draw_render_target :: proc(camera: Camera, target: Render_Target, trans: transform.Transform = nil) {
    push_camera(user_pass(target), calculate_camera(camera, transform.world(trans), {uint(target.output.width), uint(target.output.height)}))
}

@(export)
draw_reflection_probe :: proc(probe: Reflection_Probe, trans: transform.Transform = nil) {
    uniforms: Reflection_Probe_Uniforms
    uniforms.slot = u32(probe.cubemap_slot)
    uniforms.flags = 0 if probe.projection_type == .Infinite else 1
    uniforms.edge_blend = probe.edge_blend
    uniforms.capture_offset = probe.capture_offset
    
    trans := transform.world(trans)
    uniforms.position = (trans * [4]f32{**probe.position, 1}).xyz
    uniforms.half_extents = probe.size / 2 //half-extents
    //orientation gives incorrect parallax for box-projection, so just use scale...
    /*local: matrix[3,3]f32
    local[0] = linalg.abs(trans[0].xyz)
    local[1] = linalg.abs(trans[1].xyz)
    local[2] = linalg.abs(trans[2].xyz)
    half_extents = local * half_extents*/
    scale: [3]f32
    scale.x = linalg.length(trans[0].xyz)
    scale.y = linalg.length(trans[1].xyz)
    scale.z = linalg.length(trans[2].xyz)
    uniforms.half_extents = scale * uniforms.half_extents
    append(&f.reflection_probes, uniforms)

    cam := probe.camera
    far := linalg.length(probe.size) //max distance to corner * 2
    set_draw_distance(&cam, far)
    set_fog_onset(&cam, far/2) //fog starts roughly at face edge
    dirs := cubemap_directions()
    for face in schedule_faces(probe) {
        capture_position := uniforms.position + probe.capture_offset
        look_at(&cam, capture_position, capture_position + dirs[face].forward, dirs[face].up)
        push_camera(probe_pass(probe.cubemap_slot, face), calculate_camera(cam, 1, REFLECTION_CUBEMAP_RES))
    }
}


@(private)
draw_mesh_internal :: proc(mesh: Mesh, material: Material, trans: matrix[4,4]f32,
                           material_params: Material_Params,
                           pixel_scale, billboard, double_sided, unlit: bool,
                           bones: []matrix[4,4]f32, layers: Layer_Mask) {

    //mesh/material-local computations
    tex_size := [2]f32{material.base_color_tex.width, material.base_color_tex.height}
    uv := normalize_clip_rect(material_params.clip_rect, tex_size)
    model := pixel_scale ? scale_to_pixels(trans, uv, tex_size, billboard) : trans
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
    inst.probe_a = -1
    inst.probe_b = -1
    if unlit do inst.flags += {.Unlit}
    if billboard do inst.flags += {.Billboard}
    if bones == nil {
        inst.skeleton_offset = -1
    } else {
        inst.skeleton_offset = i32(len(f.skeletons))
    }


    //construct the batch key
    key: Batch_Key
    key.mesh = mesh.hash
    key.material = material.hash
    key.alpha = alpha
    switch mesh.topology {
    case .Triangles:
        if linalg.determinant(cast(matrix[3,3]f32)(inst.model)) >= 0 {
            if double_sided {
                key.primitive = .Triangles_CCW_Double_Sided
            } else {
                key.primitive = .Triangles_CCW
            }
        } else {
            if double_sided {
                key.primitive = .Triangles_CW_Double_Sided
            } else {
                key.primitive = .Triangles_CW
            }
        }
    case .Lines: key.primitive = .Lines
    case .Points: key.primitive = .Points
    }
    
    id: u32
    ok: bool
    if key == f.last_key {
        id = f.last_batch_id
    } else {
        id, ok = f.batch_ids[key]
        if !ok {
            id = u32(len(f.batches))
            append(&f.batches, Batch{id, key, mesh, material, 0, 0})
            f.batch_ids[key] = id
        }
    }   
    f.last_key, f.last_batch_id = key, id

    f.batches[id].instance_count += 1

    //gather binning data & expand scene bounds
    bin := Instance_Bin_Uniforms{bounds, id, layers}

    mini := &f.scene_extents[0]
    maxi := &f.scene_extents[1]
    //Arvo's method - convert transformed bounding axes to AABB using absolute values
    e: [3]f32
    for a in bin.axes {
        e += [3]f32{abs(a.x), abs(a.y), abs(a.z)}
    }
    extents := [2][3]f32{bin.center - e, bin.center + e}
    mini.x = min(extents[0].x, mini.x)
    mini.y = min(extents[0].y, mini.y)
    mini.z = min(extents[0].z, mini.z)
    maxi.x = max(extents[1].x, maxi.x)
    maxi.y = max(extents[1].y, maxi.y)
    maxi.z = max(extents[1].z, maxi.z)

    //append
    append(&f.instances, inst)
    append(&f.skeletons, ..bones)
    append(&f.instance_bins, bin)
}

@(export)
draw_mesh :: proc(mesh: Mesh, material: Material, trans: transform.Transform = nil,
                  material_params: Material_Params = Default_Material_Params,
                  pixel_scale: bool = false, billboard: bool = false, double_sided: bool = false, unlit: bool = false,
                  bones: []matrix[4,4]f32 = nil, layers: Layer_Mask = All_Layers) {
    trans := transform.world(trans)
    draw_mesh_internal(mesh, material, trans, material_params, pixel_scale, billboard, double_sided, unlit, bones, layers)
}

//sprites are just special kinds of meshes
@(export)
draw_sprite :: proc(material: Material, trans: transform.Transform = nil,
                    material_params: Material_Params = Default_Material_Params,
                    unlit: bool = false, layers: Layer_Mask = All_Layers) {
    draw_mesh(quad_mesh, material, trans, material_params, true, true, false, unlit, nil, layers)
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

    mat_params := Default_Material_Params
    mat_params.base_color_mul = color

    draw_mesh(line_mesh, white_material, transform.world(trans) * local, mat_params, unlit=true, layers=layers)
}

@(export)
draw_point :: proc(p: [3]f32, color: [4]f32 = 1, trans: transform.Transform = nil, layers: Layer_Mask = All_Layers) {
    local: matrix[4,4]f32 = 1
    local[3].xyz = p

    mat_params := Default_Material_Params
    mat_params.base_color_mul = color

    draw_mesh(point_mesh, white_material, transform.world(trans) * local, mat_params, unlit=true, layers=layers)
}

@(export)
draw_point_light :: proc(pl: Point_Light, trans: transform.Transform = nil, layers: Layer_Mask = All_Layers) {
    plu: Point_Light_Uniforms
    plu.color = pl.color
    plu.layer_mask = layers
    trans := transform.world(trans)
    max_scale := linalg.sqrt(max(linalg.length2(trans[0].xyz), linalg.length2(trans[1].xyz), linalg.length2(trans[2].xyz)))
    plu.position = (trans * [4]f32{**pl.position, 1}).xyz
    plu.range = pl.range * max_scale
    push_light(&f.point_lights, plu, pl.render_shadows)
}

@(export)
draw_directional_light :: proc(dl: Directional_Light, trans: transform.Transform = nil, layers: Layer_Mask = All_Layers) {
    dlu: Directional_Light_Uniforms
    dlu.color = dl.color
    dlu.layer_mask = layers
    trans := transform.world(trans)
    dlu.direction = trans * [4]f32{**dl.direction, 0}
    push_light(&f.directional_lights, dlu, dl.render_shadows)
}

@(export)
draw_spot_light :: proc(sl: Spot_Light, trans: transform.Transform = nil, layers: Layer_Mask = All_Layers) {
    slu: Spot_Light_Uniforms
    slu.color = sl.color
    slu.layer_mask = layers
    trans := transform.world(trans)
    max_scale := linalg.sqrt(max(linalg.length2(trans[0].xyz), linalg.length2(trans[1].xyz), linalg.length2(trans[2].xyz)))
    slu.position = (trans * [4]f32{**sl.position, 1}).xyz
    slu.direction = (trans * [4]f32{**sl.direction, 0}).xyz
    slu.range = sl.range * max_scale
    slu.inner_angle = linalg.cos(sl.inner_angle)
    slu.outer_angle = linalg.cos(sl.outer_angle)
    push_light(&f.spot_lights, slu, sl.render_shadows)
}


draw_light :: proc{draw_point_light, draw_directional_light, draw_spot_light}
