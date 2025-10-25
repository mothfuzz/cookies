package graphics

import "vendor:wgpu"


material_layout_entries := []wgpu.BindGroupLayoutEntry{
    wgpu.BindGroupLayoutEntry{
        binding = 0,
        visibility = {.Fragment},
        sampler = {type = .Filtering},
    },
    //albedo
    wgpu.BindGroupLayoutEntry{
        binding = 1,
        visibility = {.Fragment},
        texture = {sampleType = .Float, viewDimension = ._2D},
    },
}
material_layout: wgpu.BindGroupLayout

DynamicMaterial :: struct {
    clip_rect: [4]f32,
    albedo_tint: [4]f32,
}

Material :: struct {
    bind_group: wgpu.BindGroup,
    uniform_buffer: wgpu.Buffer,
    sampler: wgpu.Sampler,
    albedo: Texture,
}

rebuild_material :: proc(mat: ^Material) {
    bindings := []wgpu.BindGroupEntry{
        {binding = 0, sampler = mat.sampler},
        {binding = 1, textureView = mat.albedo.view},
    }
    mat.bind_group = wgpu.DeviceCreateBindGroup(ren.device, &{
        layout = material_layout,
        entryCount = len(bindings),
        entries = raw_data(bindings),
    })
}

make_material :: proc(albedo: Texture, filtering: bool = true, tiling: [2]bool = false) -> (mat: Material) {
    mat.sampler = wgpu.DeviceCreateSampler(ren.device, &{
        minFilter = .Linear if filtering else .Nearest,
        magFilter = .Linear if filtering else .Nearest,
        mipmapFilter = .Linear if filtering else .Nearest,
        maxAnisotropy = 16 if filtering else 1,
        addressModeU = .Repeat if tiling.x else .ClampToEdge,
        addressModeV = .Repeat if tiling.y else .ClampToEdge,
    })
    mat.albedo = albedo
    rebuild_material(&mat)
    return
}

bind_material :: proc(render_pass: wgpu.RenderPassEncoder, slot: u32, mat: Material) {
    wgpu.RenderPassEncoderSetBindGroup(render_pass, slot, mat.bind_group)
}

delete_material :: proc(mat: Material) {
    wgpu.SamplerRelease(mat.sampler)
    wgpu.BindGroupRelease(mat.bind_group)
}
