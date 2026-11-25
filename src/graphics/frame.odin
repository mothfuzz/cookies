package graphics

import "core:slice"
import "core:math"
import "core:math/linalg"
import "vendor:wgpu"

Alpha_Set :: struct {
    zero, one: bool, //at least one value is 0/1
    lo, hi: f32, //low and high for inbetweens
}

@(private)
alpha_product :: proc(a, b: Alpha_Set) -> (r: Alpha_Set) {
    r.zero = a.zero || b.zero
    r.one = a.one && b.one
    r.lo, r.hi = 1, 0 //empty
    a_partial := a.lo <= a.hi
    b_partial := b.lo <= b.hi
    if a_partial && b.one {
        r.lo = min(r.lo, a.lo)
        r.hi = max(r.hi, a.hi)
    }
    if b_partial && a.one {
        r.lo = min(r.lo, b.lo)
        r.hi = max(r.hi, b.hi)
    }
    if a_partial && b_partial {
        r.lo = min(r.lo, a.lo * b.lo)
        r.hi = max(r.hi, a.hi * b.hi)
    }
    return
}

Alpha_Class :: enum u8 {
    Solid,
    Mixed, //needs to be in the center for contiguous ranges in a pass.
    Trans,
}

@(private)
alpha_class :: proc(a: Alpha_Set, mul, add: f32) -> (alpha: Alpha_Class, ok: bool) {
    solid, trans: bool
    test :: proc(lo, hi: f32) -> (solid, trans: bool) {
        return hi >= 1, lo < 1 && hi > 0
    }
    if a.zero {
        a, b := test(add, add) //mul * 0 == 0
        solid |= a
        trans |= b
    }
    if a.one {
        a, b := test(mul + add, mul + add)
        solid |= a
        trans |= b
    }
    if a.lo <= a.hi {
        x := a.lo * mul + add
        y := a.hi * mul + add
        a, b := test(min(x, y), max(x, y))
        solid |= a
        trans |= b
    }
    switch {
    case solid && trans: return .Mixed, true
    case solid: return .Solid, true
    case trans: return .Trans, true
    }
    return
}

//provides map index + sort order
Batch_Key :: struct {
    alpha: Alpha_Class,
    primitive: Primitive_Key,
    mesh: Mesh_Hash,
    material: Material_Hash,
}

Batch :: struct {
    id: u32, //unsorted
    key: Batch_Key, //so we can get pass/pipeline state
    mesh: Mesh,
    material: Material,
    //for counting sort
    first_instance: u32,
    instance_count: u32,
}

@(private)
batch_key_less :: proc(a, b: Batch_Key) -> bool {
    if a.alpha != b.alpha do return a.alpha < b.alpha //preserve continuity between Solid, Mixed, Trans
    if a.primitive != b.primitive do return a.primitive < b.primitive //fewest pipeline switches
    if a.mesh != b.mesh do return a.mesh < b.mesh //mesh-outer since mesh is more bindings
    return a.material < b.material
}

Light_List :: struct($T: typeid) {
    entries: [dynamic]T,
    num_shadowed: int,
}

push_light :: proc(l: ^Light_List($T), light: T, render_shadows: bool) {
    append(&l.entries, light)
    if render_shadows {
        last := len(l.entries) - 1
        //swap
        l.entries[l.num_shadowed], l.entries[last] = l.entries[last], l.entries[l.num_shadowed]
        l.num_shadowed += 1
    }
}
clear_lights :: proc(l: ^Light_List($T)) {
    clear(&l.entries)
    l.num_shadowed = 0
}
delete_lights :: proc(l: Light_List($T)) {
    delete(l.entries)
}

Cluster_Uniforms :: struct #packed {
        offset: u32,
        probe_count: u32,
        point_count: u32,
        spot_count: u32,
}

/*
can reduce to one BeginRenderPass if I bind all output attachments:
- attach all three targets (msaa, accum, revealage) plus depth to one pass
- solid pipeline declares all three color targets, with writeMask = .None on accum and revealage
- trans pipeline declares all three, with writeMask = .None on the solid target
- set pipeline, render_pass(solid...), set pipeline, render_pass(trans...)

should work for both main & shadow
*/

Pass :: struct {
    first_cam, cam_count: int,
    kind: Pass_Kind,
    source: Pass_Source,
    stage: Pass_Stage,
}

Pass_Kind :: enum {
    Shadow,
    Capture,
    Screen,
}

Pass_Source :: union {
    Probe_Source,
    Shadow_Source,
    Screen_Source,
}

Probe_Source :: struct {
    slot, face: int,
}
Shadow_Source :: struct {
    layer: int,
}
Screen_Source :: struct{/*it's the swapchain...*/}

Pass_Stage :: union #no_nil {
    Shadow_Pass,
    Capture_Pass,
    Screen_Pass,
}

Shadow_Pass :: struct {
    attachments: Shadow_Attachments,
}

Shadow_Attachments :: struct {
    color, depth: wgpu.TextureView,
}

Main_Pass :: struct {
    //resolve target varies: user-RTT is owned, cubemaps slice the cubemaps texture, screen is swapchain
    resolve: wgpu.TextureView,
    attachments: Main_Attachments,
}

Main_Attachments :: struct {
    msaa, depth: wgpu.TextureView,
    accum, revealage: wgpu.TextureView,
    oit_composite_bind_group: wgpu.BindGroup,
}

Capture_Pass :: struct {
    using main: Main_Pass,
    copy_info: Copy_Info,
    mips: []Mip_Draw, //can be nil
}

Copy_Info :: struct {
    src, dst: wgpu.TexelCopyTextureInfo,
    size: wgpu.Extent3D,
}

Screen_Pass :: struct {
    using main: Main_Pass,
}

//4 u32s vs 5 u32s chicanery
Draw_Indirect :: struct {
    count: u32, //vertex or index
    instance_count: u32,
    first: u32, //vertex or index
    base_vertex: u32, //read as first_instance in drawindirect
    first_instance: u32, //0 either way
}

Frame :: struct {
    //lights
    point_lights: Light_List(Point_Light_Uniforms),
    directional_lights: Light_List(Directional_Light_Uniforms),
    spot_lights: Light_List(Spot_Light_Uniforms),

    spot_shadow_transforms: [dynamic]matrix[4,4]f32,
    cascade_shadow_transforms: [dynamic]matrix[4,4]f32,

    reflection_probes: [dynamic]Reflection_Probe_Uniforms,
    
    scene_extents: [2][3]f32,

    cluster_headers: [dynamic]Cluster_Uniforms,
    cluster_items: [dynamic]u32,

    //cameras
    cameras: [dynamic]Camera_Uniforms, //buffer
    rasters: [dynamic]Camera_Raster,

    passes: [dynamic]Pass,
    pass_order: [dynamic]int,
    pass_counts: [Pass_Kind]int,
    pass_ranges: [Pass_Kind][2]int,
    cam_order: [dynamic]int,
    pass_ids: map[Render_Target_Hash]int,
    last_target: Render_Target_Hash,
    last_target_id: int,
    
    //action!
    instances: [dynamic]Instance_Uniforms, //buffer
    skeletons: [dynamic]matrix[4,4]f32, //buffer
    instance_bins: [dynamic]Instance_Bin_Uniforms, //buffer (later)
    batches: [dynamic]Batch,
    batch_order: [dynamic]u32,
    batch_ids: map[Batch_Key]u32,
    last_key: Batch_Key,
    last_batch_id: u32,
    solid_end, trans_begin: int,

    instance_ids: [dynamic]u32, //vertex buffer
    instance_offsets: [dynamic]u64,
    draws: [dynamic]Draw_Indirect, //buffer (later)
}

//static frame so commands can be called context-free
f: Frame

clear_frame :: proc() {
    clear_lights(&f.point_lights)
    clear_lights(&f.directional_lights)
    clear_lights(&f.spot_lights)
    clear(&f.spot_shadow_transforms)
    clear(&f.cascade_shadow_transforms)
    clear(&f.reflection_probes)
    clear(&f.cluster_headers)
    clear(&f.cluster_items)
    clear(&f.cameras)
    clear(&f.rasters)
    clear(&f.passes)
    clear(&f.pass_order)
    clear(&f.cam_order)
    clear(&f.pass_ids)
    f.last_target = 0
    f.last_target_id = 0
    for k in Pass_Kind {
        f.pass_counts[k] = 0
    }
    clear(&f.instances)
    clear(&f.skeletons)
    clear(&f.instance_bins)
    clear(&f.batches)
    clear(&f.batch_order)
    clear(&f.batch_ids)
    clear(&f.instance_ids)
    clear(&f.instance_offsets)
    clear(&f.draws)
    f.last_key = {}
    f.last_batch_id = 0
    f.solid_end, f.trans_begin = 0, 0
    f.scene_extents[0] = math.INF_F32
    f.scene_extents[1] = math.NEG_INF_F32
}

delete_frame :: proc() {
    delete_lights(f.point_lights)
    delete_lights(f.directional_lights)
    delete_lights(f.spot_lights)
    delete(f.spot_shadow_transforms)
    delete(f.cascade_shadow_transforms)
    delete(f.reflection_probes)
    delete(f.cluster_headers)
    delete(f.cluster_items)
    delete(f.cameras)
    delete(f.rasters)
    delete(f.passes)
    delete(f.pass_order)
    delete(f.cam_order)
    delete(f.pass_ids)
    delete(f.instances)
    delete(f.skeletons)
    delete(f.instance_bins)
    delete(f.batches)
    delete(f.batch_order)
    delete(f.batch_ids)
    delete(f.instance_ids)
    delete(f.instance_offsets)
    delete(f.draws)
}

sort_batches :: proc() {
    //sort batches
    resize(&f.batch_order, len(f.batches))
    for &o, i in f.batch_order do o = u32(i)
    slice.sort_by(f.batch_order[:], proc(a, b: u32) -> bool {
        return batch_key_less(f.batches[a].key, f.batches[b].key)
    })

    //find solid/trans split
    f.solid_end = len(f.batch_order)
    f.trans_begin = len(f.batch_order)
    for b, i in f.batch_order {
        batch := f.batches[b]
        if batch.key.alpha != .Solid && f.trans_begin == len(f.batch_order) {
            f.trans_begin = i
        }
        if batch.key.alpha == .Trans {
            f.solid_end = i
            //trans strictly follows solid/mixed, so can end here
            break
        }
    }

    //prefix sum using first_instance
    running_total: u32
    for b in f.batch_order {
        batch := &f.batches[b]
        batch.first_instance = running_total
        running_total += batch.instance_count
    }

}

draws_buffer := Growable_Buffer{usage={.Storage, .Indirect, .CopyDst}}
cull_instances_cpu :: proc() {
    ids := make([]u32, len(f.instance_bins), context.temp_allocator)
    counts  := make([]u32, len(f.batches), context.temp_allocator) //indexed by dense batch id

    resize(&f.draws, len(f.cameras) * len(f.batches))
    resize(&f.instance_offsets, len(f.draws))

    for camera, c in f.cameras {
        slice.zero(counts)
        for bin, id in f.instance_bins {
            if camera.layer_mask & bin.layer_mask == 0 do continue
            if !sphere_in_frustum(camera, bin.center, bin.radius) do continue
            if !bounds_in_frustum(camera, bin.center, bin.axes) do continue
            ids[f.batches[bin.batch].first_instance + counts[bin.batch]] = u32(id)
            counts[bin.batch] += 1
        }
        //compact per batch
        for b in f.batch_order {
            n := counts[b]
            batch := f.batches[b]
            draw_index := c * len(f.batches) + int(b)
            draw := Draw_Indirect{instance_count=n, count=batch.mesh.size} //first_instance not universally supported
            f.draws[draw_index] = draw
            f.instance_offsets[draw_index] = u64(len(f.instance_ids)) * size_of(u32)
            append(&f.instance_ids, ..ids[batch.first_instance:][:n])
        }
    }
    write_buffer(&draws_buffer, f.draws[:])
    write_instance_ids()
}

Cull_Counts_Uniforms :: struct {
    num_bins: u32,
    num_batches: u32,
}

cull_pipeline: wgpu.ComputePipeline
cull_shader: wgpu.ShaderModule
cull_pipeline_layout: wgpu.PipelineLayout

delete_culling :: proc() {
    if cull_pipeline != nil {
        wgpu.ComputePipelineRelease(cull_pipeline)
    }
    if cull_shader != nil {
        wgpu.ShaderModuleRelease(cull_shader)
    }
    if cull_pipeline_layout != nil {
        wgpu.PipelineLayoutRelease(cull_pipeline_layout)
    }
    delete_cull_bindings()
}

cull_instances_gpu :: proc(command_encoder: wgpu.CommandEncoder) {
    rebind := cull_bind_group == nil

    if cull_layout == nil {
        cull_layout = wgpu.DeviceCreateBindGroupLayout(ren.device, &{
            entries = raw_data(cull_layout_entries),
            entryCount = len(cull_layout_entries),
        })
    }
    if cull_pipeline_layout == nil {
        cull_pipeline_layout = wgpu.DeviceCreatePipelineLayout(ren.device, &{
            bindGroupLayoutCount = 1,
            bindGroupLayouts = &cull_layout,
        })
    }
    if cull_shader == nil {
        cull_shader = wgpu.DeviceCreateShaderModule(ren.device, &{
            nextInChain = &wgpu.ShaderSourceWGSL{
                sType = .ShaderSourceWGSL,
                code = #load("cull_instances.wgsl"),
            }
        })
    }
    if cull_pipeline == nil {
        cull_pipeline = wgpu.DeviceCreateComputePipeline(ren.device, &{
            layout = cull_pipeline_layout,
            compute = {
                module = cull_shader,
                entryPoint = "cull_instances",
            }
        })
    }

    resize(&f.draws, len(f.cameras) * len(f.batches))
    resize(&f.instance_offsets, len(f.draws))

    for camera, c in f.cameras {
        for b in f.batch_order {
            batch := f.batches[b]
            draw_index := c * len(f.batches) + int(b)
            draw := Draw_Indirect{instance_count=0, count=batch.mesh.size}
            f.draws[draw_index] = draw
            f.instance_offsets[draw_index] = u64(c * len(f.instance_bins) + int(batch.first_instance)) * size_of(u32)
        } 
    }

    batch_offsets := make([]u32, len(f.batches), context.temp_allocator)
    for b, i in f.batches {
        batch_offsets[i] = b.first_instance
    }

    write_cull_buffers(batch_offsets)

    compute_pass := wgpu.CommandEncoderBeginComputePass(command_encoder, nil)
    wgpu.ComputePassEncoderSetPipeline(compute_pass, cull_pipeline)
    wgpu.ComputePassEncoderSetBindGroup(compute_pass, 0, cull_bind_group)
    num_instances := len(f.instance_bins)
    num_cameras := len(f.cameras)
    workgroup_size :: 64
    x := u32(math.ceil(f32(num_instances) / f32(workgroup_size)))
    y := u32(num_cameras)
    z := u32(1)
    wgpu.ComputePassEncoderDispatchWorkgroups(compute_pass, x, y, z)
    wgpu.ComputePassEncoderEnd(compute_pass)
}

@(private)
push_pass :: proc(kind: Pass_Kind, stage: Pass_Stage, source: Pass_Source = nil) -> (id: int) {
    id = len(f.passes)
    append(&f.passes, Pass{kind = kind, stage = stage, source = source})
    f.pass_counts[kind] += 1
    return
}

@(private)
push_camera :: proc(pass: int, camera: Camera_Uniforms, raster: Camera_Raster) {
    raster := raster
    raster.pass = pass
    camera := camera
    // TODO: size these dynamically using viewport + a tile size (small for Screen, large for Capture)
    switch f.passes[pass].kind {
    case .Shadow: camera.grid_size.xyz = {0, 0, 0}
    case .Capture: camera.grid_size.xyz = {4, 4, 8}
    case .Screen: camera.grid_size.xyz = {16, 9, 24}
    }
    //1
    camera.header_offset = u32(len(f.cluster_headers))
    grid_size := u32(camera.grid_size.x) * u32(camera.grid_size.y) * u32(camera.grid_size.z)
    resize(&f.cluster_headers, camera.header_offset + grid_size)
    //can scale/bias also be calculated here?
    append(&f.cameras, camera)
    append(&f.rasters, raster)
    f.passes[pass].cam_count += 1
}

//shadow_pass

@(private)
user_pass :: proc(rt: Render_Target) -> int {
    if rt.hash == f.last_target do return f.last_target_id
    id, ok := f.pass_ids[rt.hash]
    if !ok {
        pass: Capture_Pass
        pass.attachments = {
            msaa = rt.main.msaa.view,
            depth = rt.main.depth.view,
            accum = rt.main.accum.view,
            revealage = rt.main.revealage.view,
            oit_composite_bind_group = rt.main.oit_composite_bind_group,
        }
        pass.resolve = rt.msaa_resolve.view
        pass.copy_info.src = {
            texture = rt.msaa_resolve.image,
            aspect = .All,
        }
        pass.copy_info.dst = {
            texture = rt.output.image,
            aspect = .All,
        }
        pass.copy_info.size = {u32(rt.output.width), u32(rt.output.height), 1}
        pass.mips = rt.mipmapper
        id = push_pass(.Capture, pass)
        f.pass_ids[rt.hash] = id
    }
    f.last_target = rt.hash
    f.last_target_id = id
    return id
}

@(private)
probe_pass :: proc(slot, face: int) -> int {
    //actual pass will be filled out from source during resolve
    return push_pass(.Capture, Capture_Pass{}, Probe_Source{slot, face})
}

@(private)
screen_pass :: proc() -> int {
    id, ok := f.pass_ids[0]
    if !ok {
        pass: Screen_Pass
        pass.attachments = {
            msaa = ren.main_textures.msaa.view,
            depth = ren.main_textures.depth.view,
            accum = ren.main_textures.accum.view,
            revealage = ren.main_textures.revealage.view,
            oit_composite_bind_group = ren.main_textures.oit_composite_bind_group,
        }
        id = push_pass(.Screen, pass, Screen_Source{})
        f.pass_ids[0] = id
    }
    return id
}

sort_passes :: proc() {
    resize(&f.pass_order, len(f.passes))
    pass_cursor: [Pass_Kind]int
    start := 0
    for k in Pass_Kind {
        f.pass_ranges[k] = {start, start + f.pass_counts[k]}
        pass_cursor[k] = start
        start += f.pass_counts[k]
    }
    for p, i in f.passes {
        f.pass_order[pass_cursor[p.kind]] = i
        pass_cursor[p.kind] += 1
    }
    //slice.sort_by(f.pass_order[:], proc(a, b: u32) -> bool {
        //return f.passes[a].kind < f.passes[b].kind
    //})

    //prefix_sum
    running_total := 0
    for p, i in f.pass_order {
        pass := &f.passes[p]
        pass.first_cam = running_total
        running_total += pass.cam_count
    }

    cam_cursor := make([]int, len(f.passes), context.temp_allocator)
    resize(&f.cam_order, len(f.cameras))
    for cam, i in f.rasters {
        p := &f.passes[cam.pass]
        f.cam_order[p.first_cam + cam_cursor[cam.pass]] = i
        cam_cursor[cam.pass] += 1
    }
}

pass_range :: proc(k: Pass_Kind) -> []int {
    range := f.pass_ranges[k]
    return f.pass_order[range[0]:range[1]]
}

resolve_passes :: proc(swapchain: wgpu.TextureView) {
    for &pass in f.passes {
        switch src in pass.source {
            case nil: //user-RTT, already resolved upon submission
            case Probe_Source:
            //get resolve from slot+face
            stage := &pass.stage.(Capture_Pass)
            stage.attachments = {
                msaa = probe_capture.main.msaa.view,
                depth = probe_capture.main.depth.view,
                accum = probe_capture.main.accum.view,
                revealage = probe_capture.main.revealage.view,
                oit_composite_bind_group = probe_capture.main.oit_composite_bind_group,
            }
            stage.resolve = probe_capture.msaa_resolve.view
            stage.copy_info.src = {
                texture = probe_capture.msaa_resolve.image,
                aspect = .All,
            }
            stage.copy_info.dst = {
                texture = cubemaps.texture,
                mipLevel = 0,
                origin = {0, 0, u32(src.slot * 6 + src.face)},
                aspect = .All,
            }
            stage.copy_info.size = {REFLECTION_CUBEMAP_RES, REFLECTION_CUBEMAP_RES, 1}
            stage.mips = cubemaps_mipmappers[src.slot][src.face]
            case Shadow_Source:
            //get resolve from layer
            case Screen_Source:
            stage := &pass.stage.(Screen_Pass)
            stage.resolve = swapchain
        }
    }
}

@(private)
//bounds of c/d covered by a sphere
//d - r must be >0
tangent_bounds :: proc(c, d, r: f32) -> (lo, hi: f32) {
    l := math.sqrt(c*c + d*d - r*r)
    lo = (c*l - r*d) / (d*l + r*c)
    hi = (c*l + r*d) / (d*l - r*c)
    return
}

@(private)
sphere_clusters :: proc(camera: Camera_Uniforms, near, far: f32, center: [3]f32, radius: f32) -> [2][3]u8 {
    pos := (camera.view * [4]f32{**center, 1}).xyz
    d := -pos.z
    //z: project z exactly
    min_pos_z := max(d - radius, near) //might be negative if sphere intersects near
    max_pos_z := d + radius //always positive if sphere survived culling
    z_min := int(math.floor(math.log2(min_pos_z) * camera.z_scale + camera.z_bias))
    z_max := int(math.floor(math.log2(max_pos_z) * camera.z_scale + camera.z_bias))
    z_min = clamp(z_min, 0, int(camera.grid_size.z-1))
    z_max = clamp(z_max, 0, int(camera.grid_size.z-1))
    //xy: projected to screen space
    x_min, x_max, y_min, y_max: int
    if d - radius < near {
        x_min = 0
        y_min = 0
        x_max = int(camera.grid_size.x-1)
        y_max = int(camera.grid_size.y-1)
    } else {
        p00 := camera.projection[0, 0]
        p02 := camera.projection[0, 2]
        p11 := camera.projection[1, 1]
        p12 := camera.projection[1, 2]
        xl, xh := tangent_bounds(pos.x, d, radius)
        yl, yh := tangent_bounds(pos.y, d, radius)
        xl_ndc := xl*p00 - p02
        xh_ndc := xh*p00 - p02
        yl_ndc := yl*p11 - p12
        yh_ndc := yh*p11 - p12
        x_min = int(math.floor(((xl_ndc+1)/2) * f32(camera.grid_size.x)))
        x_max = int(math.floor(((xh_ndc+1)/2) * f32(camera.grid_size.x)))
        //high NDC y is a low cluster tile
        y_min = int(math.floor(((1-yh_ndc)/2) * f32(camera.grid_size.y)))
        y_max = int(math.floor(((1-yl_ndc)/2) * f32(camera.grid_size.y)))
    }
    x_min = clamp(x_min, 0, int(camera.grid_size.x-1))
    y_min = clamp(y_min, 0, int(camera.grid_size.y-1))
    x_max = clamp(x_max, 0, int(camera.grid_size.x-1))
    y_max = clamp(y_max, 0, int(camera.grid_size.y-1))
    return {
        {u8(x_min), u8(y_min), u8(z_min)},
        {u8(x_max), u8(y_max), u8(z_max)},
    }
}

//bins lights *and* reflection probes.
bin_lights :: proc() {

    //sort probes by volume, lowest volume = highest influence
    slice.sort_by(f.reflection_probes[:], proc(a, b: Reflection_Probe_Uniforms) -> bool {
        vol_a := a.half_extents.x * a.half_extents.y * a.half_extents.z
        vol_b := b.half_extents.x * b.half_extents.y * b.half_extents.z
        return vol_a < vol_b
    })
    
    //assign clusters
    for cam in 0..<len(f.cameras) {
        camera := &f.cameras[cam]
        raster := &f.rasters[cam]
        if camera.grid_size == 0 do continue

        //near/far from scene_extents
        scene_center := (f.scene_extents[0] + f.scene_extents[1])/2
        scene_half := (f.scene_extents[1] - f.scene_extents[0])/2
        fwd := linalg.normalize(-camera.world[2].xyz)
        cam_pos := camera.world[3].xyz
        far := linalg.dot(scene_center - cam_pos, fwd) + linalg.dot(linalg.abs(fwd), scene_half)
        far = max(far, raster.near+1e-6) //clamp to near plane
        if raster.far != 0 do far = min(far, raster.far) //camera far or scene far, whichever is smaller
        near := raster.near
        //screen-space xy-scaling
        camera.xy_scale = ([2]f32)(camera.grid_size.xy)/raster.viewport.zw
        camera.xy_bias = -raster.viewport.xy * camera.xy_scale
        //logarithmic z-scaling
        camera.z_scale = f32(camera.grid_size.z) / math.log2(far/near)
        camera.z_bias = -math.log2(near) * camera.z_scale

        //tile = floor(frag_coord.xy * xy_scale + xy_bias)
        //slice = floor(log(view_z) * z_scale + z_bias)
        //very nice
        
        header_count := u32(camera.grid_size.x) * u32(camera.grid_size.y) * u32(camera.grid_size.z)
        headers := f.cluster_headers[camera.header_offset:][:header_count]

        item_sizes := make([]u32, len(headers), context.temp_allocator)

        EMPTY_RANGE :: [2][3]u8{{1, 0, 0}, {0, 0, 0}} //so that range loops run 0 times with <=
        cluster_index :: #force_inline proc(g: [4]u8, x, y, z: u8) -> u32 {
            return (u32(x) * u32(g.y) * u32(g.z)) + (u32(y) * u32(g.z)) + u32(z)
        }

        probe_ranges := make([][2][3]u8, len(f.reflection_probes), context.temp_allocator)
        for &probe, i in f.reflection_probes {
            probe_ranges[i] = EMPTY_RANGE
            //use loose sphere test for MVP
            radius := linalg.length(probe.half_extents) + probe.edge_blend
            if !sphere_in_frustum(camera^, probe.position, radius) do continue
            r := sphere_clusters(camera^, near, far, probe.position, radius)
            probe_ranges[i] = r
            for x in r[0].x..=r[1].x do for y in r[0].y..=r[1].y do for z in r[0].z..=r[1].z {
                item_sizes[cluster_index(camera.grid_size, x, y, z)] += 1
            }
        }
        point_light_ranges := make([][2][3]u8, len(f.point_lights.entries), context.temp_allocator)
        for &pl, i in f.point_lights.entries {
            point_light_ranges[i] = EMPTY_RANGE
            if !sphere_in_frustum(camera^, pl.position, pl.range) do continue
            r := sphere_clusters(camera^, near, far, pl.position, pl.range)
            point_light_ranges[i] = r
            for x in r[0].x..=r[1].x do for y in r[0].y..=r[1].y do for z in r[0].z..=r[1].z {
                item_sizes[cluster_index(camera.grid_size, x, y, z)] += 1
            }
        }
        spot_light_ranges := make([][2][3]u8, len(f.spot_lights.entries), context.temp_allocator)
        for &sl, i in f.spot_lights.entries {
            spot_light_ranges[i] = EMPTY_RANGE
            if !sphere_in_frustum(camera^, sl.position, sl.range) do continue
            r := sphere_clusters(camera^, near, far, sl.position, sl.range)
            spot_light_ranges[i] = r
            for x in r[0].x..=r[1].x do for y in r[0].y..=r[1].y do for z in r[0].z..=r[1].z {
                item_sizes[cluster_index(camera.grid_size, x, y, z)] += 1
            }
        }

        //since headers & items are stored in the same buffer, we need to offset by the number of u32s in a header, times the number of headers already there.
        running := u32(len(f.cluster_items))
        header_words := u32(len(f.cluster_headers))*(size_of(Cluster_Uniforms)/size_of(u32))
        //prefix sum + offset
        for i in 0..<header_count {
            size := item_sizes[i]
            item_sizes[i] = running
            headers[i].offset = running + header_words
            running += size
        }
        resize(&f.cluster_items, running)

        //must be in shader read order (that is, add probes prior to points & spots)
        for r, i in probe_ranges {
            for x in r[0].x..=r[1].x do for y in r[0].y..=r[1].y do for z in r[0].z..=r[1].z {
                c := cluster_index(camera.grid_size, x, y, z)
                //optional narrowphase goes here later (box/froxel)
                f.cluster_items[item_sizes[c]] = u32(i)
                item_sizes[c] += 1
                headers[c].probe_count += 1
            }
        }
        for r, i in point_light_ranges {
            for x in r[0].x..=r[1].x do for y in r[0].y..=r[1].y do for z in r[0].z..=r[1].z {
                c := cluster_index(camera.grid_size, x, y, z)
                //optional narrowphase goes here later (sphere/froxel)
                f.cluster_items[item_sizes[c]] = u32(i)
                item_sizes[c] += 1
                headers[c].point_count += 1
            }
        }
        for r, i in spot_light_ranges {
            for x in r[0].x..=r[1].x do for y in r[0].y..=r[1].y do for z in r[0].z..=r[1].z {
                c := cluster_index(camera.grid_size, x, y, z)
                //optional narrowphase goes here later (cone/froxel)
                f.cluster_items[item_sizes[c]] = u32(i)
                item_sizes[c] += 1
                headers[c].spot_count += 1
            }
        }
    }
}

resolve_capture :: proc(command_encoder: wgpu.CommandEncoder, pass: Capture_Pass) {
    if pass.copy_info != {} {
        src, dst, ext := **pass.copy_info
        wgpu.CommandEncoderCopyTextureToTexture(command_encoder, &src, &dst, &ext)
    }
    if pass.mips != nil {
        render_mips(command_encoder, pass.mips)
    }
}

import "core:log"
draw_main_pass :: proc(command_encoder: wgpu.CommandEncoder, pass: Main_Pass, first_cam, cam_count: int) {
    a := pass.attachments
    has_trans := f.trans_begin < len(f.batch_order)

    //solid batches (and mixed)
    solid := wgpu.CommandEncoderBeginRenderPass(command_encoder, &{
        label = "main solid",
        colorAttachmentCount = 1,
        colorAttachments = &wgpu.RenderPassColorAttachment{
            view = a.msaa,
            resolveTarget = nil if has_trans else pass.resolve,
            loadOp = .Clear,
            storeOp = .Store,
            depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
            clearValue = {0, 0, 0, 1},
        },
        depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment{
            view = a.depth,
            depthLoadOp = .Clear,
            depthStoreOp = .Store,
            depthClearValue = 1,
            stencilLoadOp = .Clear,
            stencilStoreOp = .Store,
        },
    })
    draw_cameras(solid, .Main, .Opaque, first_cam, cam_count, 0, f.solid_end)
    wgpu.RenderPassEncoderEnd(solid)
    wgpu.RenderPassEncoderRelease(solid)

    if !has_trans do return

    //trans batches (and mixed), depth test only
    trans_attachments := []wgpu.RenderPassColorAttachment{
        //accum
        {
            view = a.accum,
            loadOp = .Clear,
            storeOp = .Store,
            depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
            clearValue = {0, 0, 0, 0}
        },
        //revealage
        {
            view = a.revealage,
            loadOp = .Clear,
            storeOp = .Store,
            depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
            clearValue = {1, 0, 0, 0}
        },
    }
    trans := wgpu.CommandEncoderBeginRenderPass(command_encoder, &{
        label = "main trans",
        colorAttachmentCount = len(trans_attachments),
        colorAttachments = raw_data(trans_attachments),
        depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment{
            view = a.depth,
            depthLoadOp = .Load,
            depthStoreOp = .Store,
            stencilLoadOp = .Load,
            stencilStoreOp = .Store,
        },
    })
    draw_cameras(trans, .Main, .Blended, first_cam, cam_count, f.trans_begin, len(f.batch_order))
    wgpu.RenderPassEncoderEnd(trans)
    wgpu.RenderPassEncoderRelease(trans)

    //composite pass
    composite := wgpu.CommandEncoderBeginRenderPass(command_encoder, &{
        label = "main composite",
        colorAttachmentCount = 1,
        colorAttachments = &wgpu.RenderPassColorAttachment{
            view = a.msaa,
            resolveTarget = pass.resolve,
            loadOp = .Load,
            storeOp = .Store,
            depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
        },
    })
    wgpu.RenderPassEncoderSetPipeline(composite, ren.oit_composite_pipeline)
    wgpu.RenderPassEncoderSetBindGroup(composite, 0, a.oit_composite_bind_group)
    wgpu.RenderPassEncoderDraw(composite, 3, 1, 0, 0)
    wgpu.RenderPassEncoderEnd(composite)
    wgpu.RenderPassEncoderRelease(composite)
}

@(private)
draw_cameras :: proc(render_pass: wgpu.RenderPassEncoder, stage: Stage_Key, blend: Blend_Key, first_cam, cam_count, begin, end: int) {
    n := len(f.batches)
    //instance data survives fill pipeline switches, so can be bound once
    bind_instance_data(render_pass)
    bind_light_data(render_pass)

    for c in first_cam ..< first_cam + cam_count {
        cam := f.cam_order[c]
        raster := f.rasters[cam]
        wgpu.RenderPassEncoderSetViewport(render_pass, **raster.viewport, 0, 1)
        bind_camera_data(render_pass, u32(cam))

        //execute fill once for main/solid before other cameras
        if stage == .Main && blend == .Opaque && raster.bg_bind_group != nil {
            wgpu.RenderPassEncoderSetPipeline(render_pass, ren.camera_fill_pipeline)
            wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, raster.bg_bind_group)
            wgpu.RenderPassEncoderDraw(render_pass, 3, 1, 0, 0)
        }

        prev_pipeline: wgpu.RenderPipeline
        prev_mesh, prev_material := ~Mesh_Hash(0), ~Material_Hash(0)

        for i in begin..<end {
            b := f.batch_order[i]
            draw_index := cam*n + int(b)
            offset := f.instance_offsets[draw_index]
            
            //if draw.instance_count == 0 do continue
            batch := &f.batches[b]

            //select pipeline by stage/blend/primitive
            primitive := batch.key.primitive
            if raster.flip {
                #partial switch primitive {
                    case .Triangles_CCW: primitive = .Triangles_CW
                    case .Triangles_CW: primitive = .Triangles_CCW
                    case .Triangles_CCW_Double_Sided: primitive = .Triangles_CW_Double_Sided
                    case .Triangles_CW_Double_Sided: primitive = .Triangles_CCW_Double_Sided
                }
            }
            pipeline := pipelines[stage][blend][primitive]
            //skip if feature not supported for this combo
            if pipeline == nil do continue 

            //minimize state changes by caching
            if pipeline != prev_pipeline {
                wgpu.RenderPassEncoderSetPipeline(render_pass, pipeline)
                prev_pipeline = pipeline
            }
            if batch.key.mesh != prev_mesh {
                bind_mesh(render_pass, batch.mesh)
                prev_mesh = batch.key.mesh
            }
            if batch.key.material != prev_material {
                bind_material(render_pass, batch.material.bind_group)
                prev_material = batch.key.material
            }

            //draw!
            //draw := f.draws[draw_index]
            bind_instance_ids(render_pass, offset)
            indirect_offset := u64(draw_index * size_of(Draw_Indirect))
            if batch.mesh.indices != nil {
                //wgpu.RenderPassEncoderDrawIndexed(render_pass, batch.mesh.size, draw.instance_count, 0, 0, 0)
                wgpu.RenderPassEncoderDrawIndexedIndirect(render_pass, draws_buffer.buffer, indirect_offset)
            } else {
                //wgpu.RenderPassEncoderDraw(render_pass, batch.mesh.size, draw.instance_count, 0, 0)
                wgpu.RenderPassEncoderDrawIndirect(render_pass, draws_buffer.buffer, indirect_offset)
            }
        }
    }
}
