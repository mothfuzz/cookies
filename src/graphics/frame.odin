package graphics

import "core:slice"
import "core:math"
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


Draw_Indirect :: struct {
    first_instance: u32,
    instance_count: u32,
}

Frame :: struct {
    //lights
    /*point_lights_unshadowed: [dynamic]Point_Light_Uniforms,
    point_lights_shadowed: [dynamic]Point_Light_Uniforms,
    spot_lights_unshadowed: [dynamic]Spot_Light_Uniforms,
    spot_lights_shadowed: [dynamic]Spot_Light_Uniforms,
    directional_lights_unshadowed: [dynamic]Directional_Light_Uniforms,
    directional_lights_shadowed: [dynamic]Directional_Light_Uniforms,

    spot_shadow_transforms: [dynamic]matrix[4,4]f32,
    cascade_shadow_transforms: [dynamic]matrix[4,4]f32,*/
    
    scene_extents: [2][3]f32,

    //cameras
    cameras: [dynamic]Camera_Uniforms, //buffer
    rasters: [dynamic]Camera_Raster,

    //need grouping info ala Batch-but-for-cameras
    //order doesn't necessarily matter, as long as we can identify the 'batch'

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
    draws: [dynamic]Draw_Indirect, //buffer (later)
}

//static frame so commands can be called context-free
f: Frame

clear_frame :: proc() {
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
    clear(&f.draws)
    f.last_key = {}
    f.last_batch_id = 0
    f.solid_end, f.trans_begin = 0, 0
    f.scene_extents[0] = math.INF_F32
    f.scene_extents[1] = math.NEG_INF_F32
}

delete_frame :: proc() {
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

cull_instances :: proc() {
    ids := make([]u32, len(f.instance_bins), context.temp_allocator)
    counts  := make([]u32, len(f.batches), context.temp_allocator) //indexed by dense batch id

    resize(&f.draws, len(f.cameras)*len(f.batches))

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
        for b, i in f.batch_order {
            n := counts[b]
            f.draws[c*len(f.batches) + i] = {u32(len(f.instance_ids)), n}
            append(&f.instance_ids, ..ids[f.batches[b].first_instance:][:n])
        }
    }
}

@(private)
push_pass :: proc(kind: Pass_Kind, stage: Pass_Stage) -> (id: int) {
    id = len(f.passes)
    append(&f.passes, Pass{kind = kind, stage = stage})
    f.pass_counts[kind] += 1
    return
}

@(private)
push_camera :: proc(pass: int, camera: Camera_Uniforms, raster: Camera_Raster) {
    raster := raster
    raster.pass = pass
    append(&f.cameras, camera)
    append(&f.rasters, raster)
    f.passes[pass].cam_count += 1
}

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
    }
    f.last_target = rt.hash
    f.last_target_id = id
    return id
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
        id = push_pass(.Screen, pass)
    }
    return id
}

//probe_pass
//shadow_pass

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
            case Shadow_Source:
            //get resolve from layer
            case Screen_Source:
            stage := &pass.stage.(Screen_Pass)
            stage.resolve = swapchain
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

/*
PRESENT LOOP:

for p in f.shadows {
    draw_shadow_pass(p)
}
for _ in 0..<CAPTURE_BOUNCES {
    for p in f.captures {
        draw_main_pass(p)
        resolve_capture(p)
    }
}
draw_main_pass(f.screen)
*/

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
    bind_instance_ids(render_pass)

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
            draw := f.draws[cam*n + i]
            if draw.instance_count == 0 do continue
            batch := &f.batches[f.batch_order[i]]

            //select pipeline by stage/blend/primitive
            primitive := batch.key.primitive
            if raster.flip {
                #partial switch primitive {
                    case .Triangles_Back: primitive = .Triangles_Front
                    case .Triangles_Front: primitive = .Triangles_Back
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
            if batch.mesh.indices != nil {
                wgpu.RenderPassEncoderDrawIndexed(render_pass, batch.mesh.size, draw.instance_count, 0, 0, draw.first_instance)
            } else {
                wgpu.RenderPassEncoderDraw(render_pass, batch.mesh.size, draw.instance_count, 0, draw.first_instance)
            }
        }
    }
}
