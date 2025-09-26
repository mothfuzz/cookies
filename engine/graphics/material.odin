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
    //material uniforms
    wgpu.BindGroupLayoutEntry{
        binding = 2,
        visibility = {.Fragment},
        buffer = {type=.Uniform},
    },
}
material_layout: wgpu.BindGroupLayout

MaterialUniforms :: struct {
    albedo_tint: [4]f32,
}

Material :: struct {
    bind_group: wgpu.BindGroup,
    uniform_buffer: wgpu.Buffer,
    sampler: wgpu.Sampler,
    albedo: Texture,
    using uniforms: MaterialUniforms,
}

rebuild_material :: proc(mat: ^Material) {
    if mat.uniform_buffer != nil {
        wgpu.BufferRelease(mat.uniform_buffer)
    }
    mat.uniform_buffer = wgpu.DeviceCreateBufferWithDataTyped(ren.device, &{usage={.Uniform, .CopyDst}}, mat.uniforms)

    bindings := []wgpu.BindGroupEntry{
        {binding = 0, sampler = mat.sampler},
        {binding = 1, textureView = mat.albedo.view},
        {binding = 2, buffer = mat.uniform_buffer, size = size_of(MaterialUniforms)},
    }
    mat.bind_group = wgpu.DeviceCreateBindGroup(ren.device, &{
        layout = material_layout,
        entryCount = len(bindings),
        entries = raw_data(bindings),
    })
}

make_material :: proc(albedo: Texture, albedo_tint: [4]f32 = 1, filtering: bool = true, tiling: [2]bool = false) -> (mat: Material) {
    mat.sampler = wgpu.DeviceCreateSampler(ren.device, &{
        minFilter = .Linear if filtering else .Nearest,
        magFilter = .Linear if filtering else .Nearest,
        mipmapFilter = .Linear if filtering else .Nearest,
        maxAnisotropy = 16 if filtering else 1,
        addressModeU = .Repeat if tiling.x else .ClampToEdge,
        addressModeV = .Repeat if tiling.y else .ClampToEdge,
    })
    mat.albedo = albedo
    mat.albedo_tint = albedo_tint
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
