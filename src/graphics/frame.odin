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

Shadow_Pass :: struct {
    cam: int,
    attachments: Shadow_Attachments,
}

/*
can reduce to one BeginRenderPass if I bind all output attachments:
- attach all three targets (msaa, accum, revealage) plus depth to one pass
- solid pipeline declares all three color targets, with writeMask = .None on accum and revealage
- trans pipeline declares all three, with writeMask = .None on the solid target
- set pipeline, render_pass(solid...), set pipeline, render_pass(trans...)

should work for both main & shadow
*/
Main_Pass :: struct {
    first_cam, cam_count: int,
    //resolve target varies: user-RTT is owned, cubemaps slice the cubemaps texture, screen is swapchain
    resolve: wgpu.TextureView,
    attachments: Main_Attachments,
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

Shadow_Attachments :: struct {
    color, depth: wgpu.TextureView,
}

Main_Attachments :: struct {
    msaa, depth: wgpu.TextureView,
    accum, revealage: wgpu.TextureView,
    oit_composite_bind_group: wgpu.BindGroup,
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

    shadows: [dynamic]Shadow_Pass,
    captures: [dynamic]Capture_Pass,
    screen: Main_Pass,
    
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
    clear(&f.shadows)
    clear(&f.captures)
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
    delete(f.shadows)
    delete(f.captures)
    delete(f.instances)
    delete(f.skeletons)
    delete(f.instance_bins)
    delete(f.batches)
    delete(f.batch_order)
    delete(f.batch_ids)
    delete(f.instance_ids)
    delete(f.draws)
}

//once per frame: batches sorted by key, prefix-summed -> batch.first_instance = slot base
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
        for bin, id in f.instance_bins { //linear, submission order
            if camera.layer_mask & bin.layer_mask == 0 do continue
            if !sphere_in_frustum(camera, bin.center, bin.radius) do continue
            if !bounds_in_frustum(camera, bin.center, bin.axes) do continue
            b := f.batches[bin.batch]
            ids[b.first_instance + counts[bin.batch]] = u32(id)
            counts[bin.batch] += 1
        }
        //compact: one memcpy per batch
        for b, i in f.batch_order {
            n := counts[b]
            f.draws[c*len(f.batches) + i] = {u32(len(f.instance_ids)), n}
            append(&f.instance_ids, ..ids[f.batches[b].first_instance:][:n])
        }
    }
}

//run first...
add_screen_pass :: proc(swapchain: wgpu.TextureView) {
    //f.screen.first_cam = 0
    f.screen.cam_count = len(f.cameras)
    f.screen.resolve = swapchain
    f.screen.attachments = {
        msaa = ren.main_textures.msaa.view,
        depth = ren.main_textures.depth.view,
        accum = ren.main_textures.accum.view,
        revealage = ren.main_textures.revealage.view,
        oit_composite_bind_group = ren.main_textures.oit_composite_bind_group,
    }
}

resolve_capture :: proc(command_encoder: wgpu.CommandEncoder, p: Capture_Pass) {
    if p.copy_info != {} {
        src, dst, ext := **p.copy_info
        wgpu.CommandEncoderCopyTextureToTexture(command_encoder, &src, &dst, &ext)
    }
    if p.mips != nil {
        render_mips(command_encoder, p.mips)
    }
}

/*
PRESENT LOOP:

clear_targets()

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
draw_main_pass :: proc(encoder: wgpu.CommandEncoder, p: Main_Pass) {
    a := p.attachments
    has_trans := f.trans_begin < len(f.batch_order)

    //solid: Solid + Mixed batches
    solid := wgpu.CommandEncoderBeginRenderPass(encoder, &{
        label = "main solid",
        colorAttachmentCount = 1,
        colorAttachments = &wgpu.RenderPassColorAttachment{
            view = a.msaa,
            resolveTarget = nil if has_trans else p.resolve,
            loadOp = .Clear,
            storeOp = .Store,
            depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
            clearValue = {0, 0, 0, 1},
        },
        depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment{
            view = a.depth,
            depthLoadOp = .Clear, depthStoreOp = .Store, depthClearValue = 1,
            stencilLoadOp = .Clear, stencilStoreOp = .Store, //required: format has stencil
        },
    })
    draw_cameras(solid, p, .Opaque, 0, f.solid_end, fill = true)
    wgpu.RenderPassEncoderEnd(solid)
    wgpu.RenderPassEncoderRelease(solid)

    if !has_trans do return

    //trans: Mixed + Trans batches, depth test only
    trans_attachments := []wgpu.RenderPassColorAttachment{
        {view = a.accum,     loadOp = .Clear, storeOp = .Store, depthSlice = wgpu.DEPTH_SLICE_UNDEFINED, clearValue = {0, 0, 0, 0}},
        {view = a.revealage, loadOp = .Clear, storeOp = .Store, depthSlice = wgpu.DEPTH_SLICE_UNDEFINED, clearValue = {1, 0, 0, 0}},
    }
    trans := wgpu.CommandEncoderBeginRenderPass(encoder, &{
        label = "main trans",
        colorAttachmentCount = len(trans_attachments),
        colorAttachments = raw_data(trans_attachments),
        depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment{
            view = a.depth,
            depthLoadOp = .Load, depthStoreOp = .Store,
            stencilLoadOp = .Load, stencilStoreOp = .Store,
        },
    })
    draw_cameras(trans, p, .Blended, f.trans_begin, len(f.batch_order), fill = false)
    wgpu.RenderPassEncoderEnd(trans)
    wgpu.RenderPassEncoderRelease(trans)

    //composite onto msaa, then resolve
    composite := wgpu.CommandEncoderBeginRenderPass(encoder, &{
        label = "main composite",
        colorAttachmentCount = 1,
        colorAttachments = &wgpu.RenderPassColorAttachment{
            view = a.msaa,
            resolveTarget = p.resolve,
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
draw_cameras :: proc(pass: wgpu.RenderPassEncoder, p: Main_Pass, blend: Blend_Key, begin, end: int, fill: bool) {
    n := len(f.batches)
    wgpu.RenderPassEncoderSetVertexBuffer(pass, 7, instance_id_buffer.buffer, 0, instance_id_buffer.capacity)
    bind_instance_data(pass) //group 2: survives fill pipeline switches (see below)

    for c in p.first_cam ..< p.first_cam + p.cam_count {
        r := f.rasters[c]
        vp := r.viewport
        wgpu.RenderPassEncoderSetViewport(pass, vp.x, vp.y, vp.z, vp.w, 0, 1)
        bind_camera_data(pass, u32(c))

        if fill && r.bg_bind_group != nil {
            wgpu.RenderPassEncoderSetPipeline(pass, ren.camera_fill_pipeline)
            wgpu.RenderPassEncoderSetBindGroup(pass, 1, r.bg_bind_group)
            wgpu.RenderPassEncoderDraw(pass, 3, 1, 0, 0)
        }

        //reset per camera: the fill replaced group 1, and the pipeline changed
        prev_pipeline: wgpu.RenderPipeline
        prev_mesh, prev_material := ~Mesh_Hash(0), ~Material_Hash(0)

        for i in begin ..< end {
            d := f.draws[c*n + i]
            if d.instance_count == 0 do continue
            b := &f.batches[f.batch_order[i]]

            prim := b.key.primitive
            if r.flip {
                #partial switch prim {
                case .Triangles_Back:  prim = .Triangles_Front
                case .Triangles_Front: prim = .Triangles_Back
                }
            }
            pipeline := pipelines[.Main][blend][prim]
            if pipeline == nil do continue //feature not supported in this stage/blend

            if pipeline != prev_pipeline {
                wgpu.RenderPassEncoderSetPipeline(pass, pipeline)
                prev_pipeline = pipeline
            }
            if b.key.mesh != prev_mesh {
                bind_mesh(pass, b.mesh)
                prev_mesh = b.key.mesh
            }
            if b.key.material != prev_material {
                bind_material(pass, b.material.bind_group)
                prev_material = b.key.material
            }

            if b.mesh.indices != nil {
                wgpu.RenderPassEncoderDrawIndexed(pass, b.mesh.size, d.instance_count, 0, 0, d.first_instance)
            } else {
                wgpu.RenderPassEncoderDraw(pass, b.mesh.size, d.instance_count, 0, d.first_instance)
            }
        }
    }
}
