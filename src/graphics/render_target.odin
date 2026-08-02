package graphics

import "vendor:wgpu"
import "base:runtime"
import "core:math"

//user render targets

Render_Target_Hash :: distinct uintptr

Render_Target :: struct {
    output: Texture,
    msaa: Texture,
    depth: Texture,
    accum: Texture,
    accum_resolve: Texture,
    revealage: Texture,
    revealage_resolve: Texture,
    sampler: wgpu.Sampler,
    oit_composite_bind_group: wgpu.BindGroup,
    mipmapper: []Mip_Draw,
    //
    hash: Render_Target_Hash,
}


Render_Target_Draw :: struct {
    render_view: wgpu.TextureView,
    output: wgpu.TextureView,
    msaa: wgpu.TextureView,
    depth: wgpu.TextureView,
    accum: wgpu.TextureView,
    accum_resolve: wgpu.TextureView,
    revealage: wgpu.TextureView,
    revealage_resolve: wgpu.TextureView,
    sampler: wgpu.Sampler,
    oit_composite_bind_group: wgpu.BindGroup,
    mipmapper: []Mip_Draw,
    cameras: [dynamic]int,
}


make_render_target :: proc(size: [2]uint, filtering: bool = true, mipmapping: bool = true) -> (target: Render_Target) {
    target.output = make_render_texture(size, with_srgb(ren.config.format), false, mipmapping?mip_count(size):1) //don't juggle formats, use same format as screen
    target.msaa = make_render_texture(size, with_srgb(ren.config.format), true)
    target.depth = make_render_texture(size, .Depth24PlusStencil8, true)
    target.accum = make_render_texture(size, .RGBA16Float, true)
    target.accum_resolve = make_render_texture(size, .RGBA16Float)
    target.revealage = make_render_texture(size, .R8Unorm, true)
    target.revealage_resolve = make_render_texture(size, .R8Unorm)

    target.sampler = wgpu.DeviceCreateSampler(ren.device, &{
        minFilter = .Linear if filtering else .Nearest,
        magFilter = .Linear if filtering else .Nearest,
        mipmapFilter = .Linear,
        maxAnisotropy = 16 if filtering else 1,
        addressModeU = .ClampToEdge,
        addressModeV = .ClampToEdge,
        lodMinClamp = 0,
        lodMaxClamp = 32,
    })

    //make hash before making bind groups
    target.hash = Render_Target_Hash(runtime.default_hasher(&target, 0, size_of(Render_Target)))

    oit_composite_bindings := []wgpu.BindGroupEntry{
        {binding = 0, sampler=target.sampler},
        {binding = 1, textureView=target.accum_resolve.view},
        {binding = 2, textureView=target.revealage_resolve.view},
    }
    target.oit_composite_bind_group = wgpu.DeviceCreateBindGroup(ren.device, &{
        layout = ren.oit_composite_bind_group_layout,
        entryCount = len(oit_composite_bindings),
        entries = raw_data(oit_composite_bindings),
    })

    if mipmapping do target.mipmapper = make_mipmapper(target.output.image, target.sampler)
    return
}

delete_render_target :: proc(target: Render_Target) {
    delete_texture(target.output)
    delete_texture(target.msaa)
    delete_texture(target.depth)
    delete_texture(target.accum)
    delete_texture(target.accum_resolve)
    delete_texture(target.revealage)
    delete_texture(target.revealage_resolve)
    wgpu.SamplerRelease(target.sampler)
    wgpu.BindGroupRelease(target.oit_composite_bind_group)
    if target.mipmapper != nil {
        delete_mipmapper(target.mipmapper)
    }
}
