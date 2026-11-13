package graphics

import "vendor:wgpu"
import "core:math"

/* TODO:

have global environment fallback to avoid doing any nearest-search
what will be used in order of priority:
set_global_environment_probe(probe)
set_skybox(skybox)
set_Background_color(...)

for mips:
base texture (6x or just 1 scratch) is multisampled, but *resolve* is the actual cubemap faces.
mipmaps are already allocated when creating the texture, so resolution will be correct in all the downscaling subpasses.

*/

ENVIRONMENT_CUBEMAP_RES :: 512
environment_mip_count := mip_count(ENVIRONMENT_CUBEMAP_RES)

probe_capture: Main_Textures //executed 6 times per cubemap, resolving to cubemap faces.

Capture_State :: struct {
    current_face: uint,
    one_shot: bool,
}

capture_states: [dynamic]Capture_State

cubemaps_capture: Texture //probe_capture resolved into here
cubemaps_capture_layers: [dynamic]wgpu.TextureView
cubemaps: Texture //capture copied into here
cubemaps_sampler: wgpu.Sampler
cubemaps_boxes: [dynamic]Environment_Probe_Box_Uniforms
cubemaps_buffer: wgpu.Buffer
cubemaps_mipmappers: [dynamic][6][]Mip_Draw
cubemaps_free: [dynamic]int

Projection_Type :: enum {
    Default,
    Infinite,
    Box_Projected,
}

Environment_Probe :: struct {
    cubemap_slot: int,
    position: [3]f32,
    extents: [2][3]f32,
    faces_per_frame: int,
    camera: Camera, //so that probes can have individual bg/exposure/layer_mask
}

Environment_Probe_Box_Uniforms :: struct {
    center: [4]f32, //0 = infinite, 1 = box projected
    mini: [4]f32,
    maxi: [4]f32,
}

Environment_Probe_Draw :: distinct Render_Target_Draw

make_probe_capture :: proc() {
    probe_capture = make_main_textures(ENVIRONMENT_CUBEMAP_RES)
    cubemaps_sampler = wgpu.DeviceCreateSampler(ren.device, &{
        minFilter = .Linear,
        magFilter = .Linear,
        mipmapFilter = .Linear,
        addressModeU = .ClampToEdge,
        addressModeV = .ClampToEdge,
        addressModeW = .ClampToEdge,
        maxAnisotropy = 1,
        lodMinClamp = 0,
        lodMaxClamp = 32,
    })
    append(&cubemaps_free, 0)
    append(&cubemaps_boxes, Environment_Probe_Box_Uniforms{})
    realloc_cubemaps()
}

delete_probe_capture :: proc() {
    delete_main_textures(probe_capture)
    delete_texture(cubemaps_capture)
    delete_texture(cubemaps)
    wgpu.SamplerRelease(cubemaps_sampler)
    delete(cubemaps_boxes)
    wgpu.BufferRelease(cubemaps_buffer)
    delete(cubemaps_free)
    delete(capture_states)
    for mip_group in cubemaps_mipmappers {
        for mip in mip_group {
            delete_mipmapper(mip)
        }
    }
    delete(cubemaps_mipmappers)
}

make_cubemaps_mipmappers :: proc(new_size: int) {
    for mip_group in cubemaps_mipmappers {
        for mip in mip_group {
            delete_mipmapper(mip)
        }
    }
    clear(&cubemaps_mipmappers)
    for i in 0..<new_size {
        mip_group: [6][]Mip_Draw
        for mip, face in mip_group {
            mip_group[face] = make_mipmapper(cubemaps.image, cubemaps_sampler, u32(i*6+face))
        }
        append(&cubemaps_mipmappers, mip_group)
    }
}

realloc_cubemaps_views  :: proc() {
    for view in cubemaps_capture_layers {
        wgpu.TextureViewRelease(view)
    }
    size := wgpu.TextureGetDepthOrArrayLayers(cubemaps_capture.image)
    resize(&cubemaps_capture_layers, size)
    for i in 0..<len(cubemaps_capture_layers) {
        cubemaps_capture_layers[i] = wgpu.TextureCreateView(cubemaps_capture.image, &{
            dimension = ._2D,
            mipLevelCount = 1,
            arrayLayerCount = 1,
            baseArrayLayer = u32(i),
        })
    }
}

realloc_cubemaps :: proc(command_encoder: wgpu.CommandEncoder = nil) -> (rebind: bool) {
    format := with_srgb(ren.config.format)
    if cubemaps.image == nil {
        cubemaps_capture = make_render_texture_array(ENVIRONMENT_CUBEMAP_RES, format, 1, true, copy_src=true)
        realloc_cubemaps_views()

        cubemaps = make_render_texture_array(ENVIRONMENT_CUBEMAP_RES, format, 1, true, mip_count=environment_mip_count)
        append(&capture_states, Capture_State{})
        make_cubemaps_mipmappers(1)

        cubemaps_buffer = wgpu.DeviceCreateBuffer(ren.device, &{usage={.Storage, .CopyDst}, size=u64(size_of(Environment_Probe_Box_Uniforms))})

        rebind = true
    } else {
        new_size := len(cubemaps_boxes)
        current_size := wgpu.TextureGetDepthOrArrayLayers(cubemaps.image)/6
        if u32(new_size) > current_size {
            delete_texture(cubemaps_capture)
            cubemaps_capture = make_render_texture_array(ENVIRONMENT_CUBEMAP_RES, format, uint(new_size), true, copy_src=true)
            realloc_cubemaps_views()

            new_cubemaps := make_render_texture_array(ENVIRONMENT_CUBEMAP_RES, format, uint(new_size), true, mip_count=environment_mip_count)
            extents := wgpu.Extent3D{
                width = ENVIRONMENT_CUBEMAP_RES,
                height = ENVIRONMENT_CUBEMAP_RES,
                depthOrArrayLayers = current_size * 6,
            }
            wgpu.CommandEncoderCopyTextureToTexture(command_encoder, &{texture=cubemaps.image}, &{texture=new_cubemaps.image}, &extents)

            delete_texture(cubemaps)
            cubemaps = new_cubemaps
            make_cubemaps_mipmappers(new_size)

            wgpu.BufferRelease(cubemaps_buffer)
            cubemaps_buffer = wgpu.DeviceCreateBuffer(ren.device, &{usage={.Storage, .CopyDst}, size=u64(size_of(Environment_Probe_Box_Uniforms)*new_size)})

            rebind = true
        }
    }
    wgpu.QueueWriteBuffer(ren.queue, cubemaps_buffer, 0, raw_data(cubemaps_boxes[:]), size_of(Environment_Probe_Box_Uniforms)*len(cubemaps_boxes))
    return
}

/*
copy_cubemaps :: proc(command_encoder: wgpu.CommandEncoder) {
    extents := wgpu.Extent3D{
        width = ENVIRONMENT_CUBEMAP_RES,
        height = ENVIRONMENT_CUBEMAP_RES,
        depthOrArrayLayers = wgpu.TextureGetDepthOrArrayLayers(cubemaps.image),
    }
    wgpu.CommandEncoderCopyTextureToTexture(command_encoder, &{texture=cubemaps_capture.image}, &{texture=cubemaps.image}, &extents)
}
*/

make_environment_probe :: proc(position: [3]f32, size: [3]f32 = 0, faces_per_frame: int = 6, projection_type: Projection_Type = .Default, layers: Layer_Mask = All_Layers) -> (probe: Environment_Probe) {
    probe.position = position
    projection_type := projection_type
    if size == 0 {
        if projection_type == .Default {
            projection_type = .Infinite
        }
        probe.extents = {-math.INF_F32, math.INF_F32}
        probe.camera = make_camera({0, 0, ENVIRONMENT_CUBEMAP_RES, ENVIRONMENT_CUBEMAP_RES}, 0.1, 0, math.PI/2, true, .One, layers)
    } else {
        if projection_type == .Default {
            projection_type = .Box_Projected
        }
        probe.extents = {{-size.x/2, -size.y/2, -size.z/2}, {size.x/2, size.y/2, size.z/2}}
        far := max(size.x, max(size.y, size.z))
        probe.camera = make_camera({0, 0, ENVIRONMENT_CUBEMAP_RES, ENVIRONMENT_CUBEMAP_RES}, 0.1, far, math.PI/2, true, .One, layers)
    }
    probe.faces_per_frame = faces_per_frame
    probe_box := Environment_Probe_Box_Uniforms{
        center = {**position, projection_type == .Infinite?0:1},
        mini = vecpos(probe.extents[0]),
        maxi = vecpos(probe.extents[1]),
    }
    if slot, ok := pop_safe(&cubemaps_free); ok {
        probe.cubemap_slot = slot
        cubemaps_boxes[slot] = probe_box
    } else {
        probe.cubemap_slot = len(cubemaps_boxes)
        append(&cubemaps_boxes, probe_box)
    }
    if probe.cubemap_slot >= len(capture_states) {
        resize(&capture_states, probe.cubemap_slot + 1)
    }
    capture_states[probe.cubemap_slot] = {}
    return
}

delete_environment_probe :: proc(probe: Environment_Probe) {
    append(&cubemaps_free, probe.cubemap_slot)
}

@(private)
schedule_faces :: proc(probe: Environment_Probe) -> (faces: bit_set[0..<6]) {
    capture_state := &capture_states[probe.cubemap_slot]
    n := probe.faces_per_frame
    if n == 0 {
        if capture_state.one_shot do return
        //render all 6 at once
        capture_state.one_shot = true
        n = 6
    }
    for _ in 0..<min(n, 6) {
        faces += {int(capture_state.current_face)}
        capture_state.current_face = (capture_state.current_face + 1) % 6
    }
    return
}

@(private)
probe_face_cam :: proc(probe: Environment_Probe, face: int) -> Camera_Draw {
    cam := probe.camera
    directions := cubemap_directions()
    look_at(&cam, probe.position, probe.position + directions[face][0], directions[face][1])
    return calculate_camera(cam, 1, ENVIRONMENT_CUBEMAP_RES)
}

@(private)
probe_pass :: proc(probe: Environment_Probe, face: int) -> (pass: Capture_Pass) {
    layer := u32(probe.cubemap_slot * 6 + face)
    pass.attachments = {
        msaa = probe_capture.msaa.view,
        depth = probe_capture.depth.view,
        accum = probe_capture.accum.view,
        revealage = probe_capture.revealage.view,
        oit_composite_bind_group = probe_capture.oit_composite_bind_group,
    }
    pass.resolve = cubemaps_capture_layers[layer]
    pass.copy_info.src = {
        texture = cubemaps_capture.image,
        aspect = .All,
        origin = {0, 0, layer},
    }
    pass.copy_info.dst = {
        texture = cubemaps.image,
        aspect = .All,
        origin = {0, 0, layer},
    }
    pass.copy_info.size = {ENVIRONMENT_CUBEMAP_RES, ENVIRONMENT_CUBEMAP_RES, 1}
    pass.mips = cubemaps_mipmappers[probe.cubemap_slot][face]
    return
}
