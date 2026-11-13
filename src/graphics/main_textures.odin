package graphics

import "vendor:wgpu"

//container for owned Main_Pass-related textures
//used by screen, probes, and RTT

Main_Textures :: struct {
    msaa, depth: Texture,
    accum, revealage: Texture,
    oit_composite_bind_group: wgpu.BindGroup,
}

@(private)
make_main_textures :: proc(size: [2]uint) -> (a: Main_Textures) {
    a.msaa = make_render_texture(size, with_srgb(ren.config.format), true)
    a.depth = make_render_texture(size, .Depth24PlusStencil8, true)
    a.accum = make_render_texture(size, .RGBA16Float, true)
    a.revealage = make_render_texture(size, .R8Unorm, true)

    oit_composite_bindings := []wgpu.BindGroupEntry{
        {binding = 0, textureView = a.accum.view},
        {binding = 1, textureView = a.revealage.view},
    }
    a.oit_composite_bind_group = wgpu.DeviceCreateBindGroup(ren.device, &{
        layout = ren.oit_composite_bind_group_layout,
        entryCount = len(oit_composite_bindings),
        entries = raw_data(oit_composite_bindings),
    })
}

@(private)
delete_main_textures :: proc(a: Main_Textures) {
    delete_texture(a.msaa)
    delete_texture(a.depth)
    delete_texture(a.accum)
    delete_texture(a.revealage)
    wgpu.BindGroupRelease(a.oit_composite_bind_group)
}
