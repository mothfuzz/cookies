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

probe_capture: Render_Target //executed 6 times per cubemap, resolving to cubemap faces.

Capture_State :: struct {
    current_face: uint,
    one_shot: bool,
}

capture_states: [dynamic]Capture_State

cubemaps_capture: Texture
cubemaps: Texture
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
    probe_capture = make_render_target(ENVIRONMENT_CUBEMAP_RES, mipmapping=false)
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
    delete_render_target(probe_capture)
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

realloc_cubemaps :: proc(command_encoder: wgpu.CommandEncoder = nil, new_size: int = 0) -> (rebind: bool) {
    format := with_srgb(ren.config.format)
    if cubemaps.image == nil {
        cubemaps_capture = make_render_texture_array(ENVIRONMENT_CUBEMAP_RES, format, 1, true, copy_src=true)

        cubemaps = make_render_texture_array(ENVIRONMENT_CUBEMAP_RES, format, 1, true, mip_count=environment_mip_count)
        append(&capture_states, Capture_State{})
        make_cubemaps_mipmappers(1)

        cubemaps_buffer = wgpu.DeviceCreateBuffer(ren.device, &{usage={.Storage, .CopyDst}, size=u64(size_of(Environment_Probe_Box_Uniforms))})
    } else {
        current_size := wgpu.TextureGetDepthOrArrayLayers(cubemaps.image)/6
        if u32(new_size) > current_size {
            new_cubemaps_capture := make_render_texture_array(ENVIRONMENT_CUBEMAP_RES, format, uint(new_size), true, copy_src=true)
            new_cubemaps := make_render_texture_array(ENVIRONMENT_CUBEMAP_RES, format, uint(new_size), true, mip_count=environment_mip_count)
            extents := wgpu.Extent3D{
                width = ENVIRONMENT_CUBEMAP_RES,
                height = ENVIRONMENT_CUBEMAP_RES,
                depthOrArrayLayers = current_size * 6,
            }
            wgpu.CommandEncoderCopyTextureToTexture(command_encoder, &{texture=cubemaps_capture.image}, &{texture=new_cubemaps_capture.image}, &extents)
            wgpu.CommandEncoderCopyTextureToTexture(command_encoder, &{texture=cubemaps.image}, &{texture=new_cubemaps.image}, &extents)
            for len(capture_states) < new_size {
                append(&capture_states, Capture_State{})
            }
            rebind = true
            delete_texture(cubemaps_capture)
            cubemaps_capture = new_cubemaps_capture
            delete_texture(cubemaps)
            cubemaps = new_cubemaps
            make_cubemaps_mipmappers(new_size)

            wgpu.BufferRelease(cubemaps_buffer)
            cubemaps_buffer = wgpu.DeviceCreateBuffer(ren.device, &{usage={.Storage, .CopyDst}, size=u64(size_of(Environment_Probe_Box_Uniforms)*new_size)})
        }
    }
    wgpu.QueueWriteBuffer(ren.queue, cubemaps_buffer, 0, raw_data(cubemaps_boxes[:]), size_of(Environment_Probe_Box_Uniforms)*len(cubemaps_boxes))
    return
}

copy_cubemaps :: proc(command_encoder: wgpu.CommandEncoder) {
    extents := wgpu.Extent3D{
        width = ENVIRONMENT_CUBEMAP_RES,
        height = ENVIRONMENT_CUBEMAP_RES,
        depthOrArrayLayers = wgpu.TextureGetDepthOrArrayLayers(cubemaps.image),
    }
    wgpu.CommandEncoderCopyTextureToTexture(command_encoder, &{texture=cubemaps_capture.image}, &{texture=cubemaps.image}, &extents)
}

make_environment_probe :: proc(position: [3]f32, size: [3]f32 = 0, faces_per_frame: int = 6, projection_type: Projection_Type = .Default, layers: Layer_Mask = All_Layers) -> (probe: Environment_Probe) {
    probe.position = position
    projection_type := projection_type
    if size == 0 {
        if projection_type == .Default {
            projection_type = .Infinite
        }
        probe.extents = {-math.INF_F32, math.INF_F32}
        probe.camera = make_camera({0, 0, ENVIRONMENT_CUBEMAP_RES, ENVIRONMENT_CUBEMAP_RES}, 0.1, 0, math.PI/2, true, layers)
    } else {
        if projection_type == .Default {
            projection_type = .Box_Projected
        }
        probe.extents = {{-size.x/2, -size.y/2, -size.z/2}, {size.x/2, size.y/2, size.z/2}}
        far := max(size.x, max(size.y, size.z))
        probe.camera = make_camera({0, 0, ENVIRONMENT_CUBEMAP_RES, ENVIRONMENT_CUBEMAP_RES}, 0.1, far, math.PI/2, true, layers)
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
        probe.cubemap_slot = int(wgpu.TextureGetDepthOrArrayLayers(cubemaps.image))/6
        append(&cubemaps_boxes, probe_box)
    }
    return
}

delete_environment_probe :: proc(probe: Environment_Probe) {
    append(&cubemaps_free, probe.cubemap_slot)
}
