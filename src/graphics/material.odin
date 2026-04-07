package graphics

import "vendor:wgpu"


material_layout_entries := []wgpu.BindGroupLayoutEntry{
    wgpu.BindGroupLayoutEntry{
        binding = 0,
        visibility = {.Fragment},
        sampler = {type = .Filtering},
    },
    //base_color
    wgpu.BindGroupLayoutEntry{
        binding = 1,
        visibility = {.Fragment},
        texture = {sampleType = .Float, viewDimension = ._2D},
    },
    //normal
    wgpu.BindGroupLayoutEntry{
        binding = 2,
        visibility = {.Fragment},
        texture = {sampleType = .Float, viewDimension = ._2D},
    },
    //pbr
    wgpu.BindGroupLayoutEntry{
        binding = 3,
        visibility = {.Fragment},
        texture = {sampleType = .Float, viewDimension = ._2D},
    },
    //emissive
    wgpu.BindGroupLayoutEntry{
        binding = 4,
        visibility = {.Fragment},
        texture = {sampleType = .Float, viewDimension = ._2D},
    },
}
material_layout: wgpu.BindGroupLayout

DynamicMaterial :: struct {
    clip_rect: [4]f32,
    tint: [4]f32, //base_color_tint
}

Material :: struct {
    bind_group: wgpu.BindGroup,
    sampler: wgpu.Sampler,
    base_color: Texture,
    normal: Texture,
    pbr: Texture,
    emissive: Texture,
}

rebuild_material :: proc(mat: ^Material) {
    bindings := []wgpu.BindGroupEntry{
        {binding = 0, sampler = mat.sampler},
        {binding = 1, textureView = mat.base_color.view},
        {binding = 2, textureView = mat.normal.view},
        {binding = 3, textureView = mat.pbr.view},
        {binding = 4, textureView = mat.emissive.view},
    }
    mat.bind_group = wgpu.DeviceCreateBindGroup(ren.device, &{
        layout = material_layout,
        entryCount = len(bindings),
        entries = raw_data(bindings),
    })
}

make_material :: proc(base_color: Texture=white_tex, normal: Texture=normal_tex, pbr: Texture=white_tex, emissive: Texture=black_tex, filtering: bool = true, tiling: [2]bool = false) -> (mat: Material) {
    mat.sampler = wgpu.DeviceCreateSampler(ren.device, &{
        minFilter = .Linear if filtering else .Nearest,
        magFilter = .Linear if filtering else .Nearest,
        mipmapFilter = .Linear if filtering else .Nearest,
        maxAnisotropy = 16 if filtering else 1,
        addressModeU = .Repeat if tiling.x else .ClampToEdge,
        addressModeV = .Repeat if tiling.y else .ClampToEdge,
    })
    mat.base_color = base_color
    mat.normal = normal
    mat.pbr = pbr
    mat.emissive = emissive
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
