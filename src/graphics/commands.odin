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
draw_environment_probe :: proc(probe: Environment_Probe, trans: transform.Transform = nil) {
    /* TODO:
    don't keep environment_probe_boxes around.
    have a list in Frame, like lights.
    transform probes via trans before append
    upload the list to the GPU post-submission
    do clustered.
    do probe assignment in the fragment shader via clustering, not on the CPU.
    this makes probes work with lighting as part of the same general feature set
    do clustered!
    */
    f.max_cubemap_slot = max(f.max_cubemap_slot, probe.cubemap_slot)
    dirs := cubemap_directions()
    for face in schedule_faces(probe) {
        cam := probe.camera
        look_at(&cam, probe.position, probe.position + dirs[face][0], dirs[face][1])
        //push_camera(probe_pass(probe.cubemap_slot, face), calculate_camera(cam, 1, ENVIRONMENT_CUBEMAP_RES))
    }
    //append(&f.environment_probes, probe) //meshes need all drawn cubemaps, not just ones with capture this frame
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
        key.primitive = .Triangles_Back
        if double_sided {
            key.primitive = .Triangles_None
        } else if linalg.determinant(cast(matrix[3,3]f32)(inst.model)) < 0 {
            key.primitive = .Triangles_Front
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
    bin := Instance_Bin_Uniforms{bounds, layers, id}

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
