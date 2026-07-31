package graphics

import "vendor:wgpu"

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

ENVIRONMENT_CUBEMAP_RES :: 1024

probe_capture: Render_Target //executed 6 times per cubemap, resolving to cubemap faces.

Capture_State :: struct {
    current_face: uint,
    one_shot: bool,
}

capture_states: [dynamic]Capture_State

cubemaps_capture: Texture
cubemaps: Texture
cubemaps_sampler: wgpu.Sampler
cubemaps_free: [dynamic]int

Environment_Probe :: struct {
    cubemap_slot: int,
    position: [3]f32,
    extents: [2][3]f32,
    faces_per_frame: int,
    camera: Camera //so that probes can have individual bg/exposure/layer_mask
}

Environment_Probe_Draw :: distinct Render_Target_Draw

make_probe_capture :: proc() {
    probe_capture = make_render_target(ENVIRONMENT_CUBEMAP_RES)
    realloc_cubemaps()
    cubemaps_sampler = wgpu.DeviceCreateSampler(ren.device, &{
        minFilter = .Linear,
        magFilter = .Linear,
        mipmapFilter = .Nearest, //.Linear when we implement mipmapping
        addressModeU = .ClampToEdge,
        addressModeV = .ClampToEdge,
        addressModeW = .ClampToEdge,
        maxAnisotropy = 1,
    })
    append(&cubemaps_free, 0)
}

delete_probe_capture :: proc() {
    delete_render_target(probe_capture)
    delete_texture(cubemaps_capture)
    delete_texture(cubemaps)
    wgpu.SamplerRelease(cubemaps_sampler)
    delete(cubemaps_free)
}

import "core:fmt"
realloc_cubemaps :: proc(command_encoder: wgpu.CommandEncoder = nil, new_size: int = 0) -> (rebind: bool) {
    format := with_srgb(ren.config.format)
    if cubemaps.image == nil {
        cubemaps_capture = make_render_texture_array(ENVIRONMENT_CUBEMAP_RES, format, 1, true, copy_src=true)
        cubemaps = make_render_texture_array(ENVIRONMENT_CUBEMAP_RES, format, 1, true)
        append(&capture_states, Capture_State{})
    } else {
        current_size := wgpu.TextureGetDepthOrArrayLayers(cubemaps.image)/6
        if u32(new_size) > current_size {
            new_cubemaps_capture := make_render_texture_array(ENVIRONMENT_CUBEMAP_RES, format, uint(new_size), true, copy_src=true)
            new_cubemaps := make_render_texture_array(ENVIRONMENT_CUBEMAP_RES, format, uint(new_size), true)
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
        }
    }
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

import "core:math"
make_environment_probe :: proc(position, size: [3]f32, faces_per_frame: int = 6, layers: Layer_Mask = All_Layers) -> (probe: Environment_Probe) {
    probe.position = position
    probe.extents = {{-size.x/2, -size.y/2, -size.z/2}, {size.x/2, size.y/2, size.z/2}}
    probe.faces_per_frame = faces_per_frame
    probe.camera = make_camera({0, 0, ENVIRONMENT_CUBEMAP_RES, ENVIRONMENT_CUBEMAP_RES}, 0.1, 0, math.PI/2, true, layers)
    if slot, ok := pop_safe(&cubemaps_free); ok {
        probe.cubemap_slot = slot
    } else {
        probe.cubemap_slot = int(wgpu.TextureGetDepthOrArrayLayers(cubemaps.image))/6
    }
    return
}

delete_environment_probe :: proc(probe: Environment_Probe) {
    append(&cubemaps_free, probe.cubemap_slot)
}
