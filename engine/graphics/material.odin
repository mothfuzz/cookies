package graphics

import "vendor:wgpu"


//INIT
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
//DRAW
//then create the actual bindings... here.

Material :: struct {
    bind_group: wgpu.BindGroup,
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

make_material :: proc(albedo: Texture) -> (mat: Material) {
    mat.sampler = wgpu.DeviceCreateSampler(ren.device, &{
        minFilter = .Linear,
        magFilter = .Linear,
        mipmapFilter = .Linear,
        maxAnisotropy = 16,
    })
    mat.albedo = albedo
    rebuild_material(&mat)
    return
}

delete_material :: proc(mat: Material) {
    wgpu.SamplerRelease(mat.sampler)
    wgpu.BindGroupRelease(mat.bind_group)
}

bind_material :: proc(render_pass: wgpu.RenderPassEncoder, mat: Material) {
    wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, mat.bind_group)
}
