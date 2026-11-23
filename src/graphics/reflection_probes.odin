package graphics

import "vendor:wgpu"
import "core:math"

REFLECTION_CUBEMAP_RES :: 512
reflection_mip_count := mip_count(REFLECTION_CUBEMAP_RES)

probe_capture: Render_Target //executed 6 times per cubemap, resolving to cubemap faces.

Capture_State :: struct {
    current_face: uint,
    one_shot: bool,
}

capture_states: [dynamic]Capture_State

cubemaps_capture: Texture
cubemaps: Growable_Texture_Array
cubemaps_sampler: wgpu.Sampler
cubemaps_len: int
cubemaps_mipmappers: [dynamic][6][]Mip_Draw
cubemaps_free: [dynamic]int

Projection_Type :: enum {
    Default,
    Infinite,
    Box_Projected,
}

Reflection_Probe :: struct {
    cubemap_slot: int,
    position: [3]f32,
    size: [3]f32, //0 = infinite
    faces_per_frame: int, //0 = one shot
    camera: Camera, //so that probes can have individual bg/exposure/layer_mask
}

Reflection_Probe_Uniforms :: struct #align(16) {
      position: [4]f32, //w = 0/1 inf/box perspective
      mini: [3]f32, slot: u32,
      maxi: [3]f32, //padding
}

make_probe_capture :: proc() {
    probe_capture = make_render_target(REFLECTION_CUBEMAP_RES, mipmapping=false)
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
    cubemaps = {
        size = REFLECTION_CUBEMAP_RES,
        format = with_srgb(ren.config.format),
        usage = {.RenderAttachment, .CopySrc, .CopyDst},
        mip_count = u32(reflection_mip_count),
        cubemap = true,
        preserve = true,
    }
}

delete_probe_capture :: proc() {
    delete_render_target(probe_capture)
    delete_texture_array(cubemaps)
    wgpu.SamplerRelease(cubemaps_sampler)
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
            mip_group[face] = make_mipmapper(cubemaps.texture, cubemaps_sampler, u32(i*6+face))
        }
        append(&cubemaps_mipmappers, mip_group)
    }
}

make_reflection_probe :: proc(position: [3]f32, size: [3]f32 = 0, faces_per_frame: int = 6, projection_type: Projection_Type = .Default, layers: Layer_Mask = All_Layers) -> (probe: Reflection_Probe) {
    probe.position = position
    probe.size = size
    projection_type := projection_type
    if projection_type == .Default {
        if size == 0 {
            projection_type = .Infinite
        } else {
            projection_type = .Box_Projected
        }
    }
    probe.camera = make_camera({0, 0, REFLECTION_CUBEMAP_RES, REFLECTION_CUBEMAP_RES}, 0.1, 0, math.PI/2, true, layers)
    probe.faces_per_frame = faces_per_frame
    if slot, ok := pop_safe(&cubemaps_free); ok {
        probe.cubemap_slot = slot
        capture_states[slot] = {}
    } else {
        probe.cubemap_slot = cubemaps_len
        cubemaps_len += 1
        append(&capture_states, Capture_State{})
    }
    return
}

delete_reflection_probe :: proc(probe: Reflection_Probe) {
    append(&cubemaps_free, probe.cubemap_slot)
}

reset_reflection_probe :: proc(probe: Reflection_Probe) {
    capture_states[probe.cubemap_slot].one_shot = false
}

@(private)
schedule_faces :: proc(probe: Reflection_Probe) -> (faces: bit_set[0..<6]) {
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
realloc_cubemaps :: proc(command_encoder: wgpu.CommandEncoder) -> bool {
    return grow_texture_array(&cubemaps, cubemaps_len, command_encoder)
}
