package graphics

import "vendor:wgpu"
import "base:runtime"

//user render targets

Render_Target_Hash :: distinct uintptr

Render_Target :: struct {
    output: Texture,
    msaa_resolve: Texture, //copies into output
    using main: Main_Textures,
    sampler: wgpu.Sampler,
    mipmapper: []Mip_Draw,
    //
    hash: Render_Target_Hash,
}


Render_Target_Draw :: struct {
    target: Render_Target,
    camera: Camera_Draw,
}


make_render_target :: proc(size: [2]uint, filtering: bool = true, mipmapping: bool = true) -> (target: Render_Target) {

    target.output = make_render_texture(size, with_srgb(ren.config.format), false, copy_dst = true, mip_count=mipmapping?mip_count(size):1) //don't juggle formats, use same format as screen
    target.msaa_resolve = make_render_texture(size, with_srgb(ren.config.format), false, copy_src = true)

    //hash only on output/resolve
    target.hash = Render_Target_Hash(runtime.default_hasher(&target, 0, size_of(Render_Target)))

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

    target.main = make_main_textures(size)

    if mipmapping do target.mipmapper = make_mipmapper(target.output.image, target.sampler)
    return
}

delete_render_target :: proc(target: Render_Target) {
    delete_texture(target.output)
    delete_texture(target.msaa_resolve)
    delete_main_textures(target.main)
    wgpu.SamplerRelease(target.sampler)
    if target.mipmapper != nil {
        delete_mipmapper(target.mipmapper)
    }
}

user_pass :: proc(rt: Render_Target_Draw) -> (pass: Capture_Pass) {
    pass.attachments = {
        msaa = rt.main.msaa.view,
        depth = rt.main.depth.view,
        accum = rt.main.accum.view,
        revealage = rt.main.revealage.view,
        oit_composite_bind_group = rt.main.oit_composite_bind_group,
    }
    pass.resolve = rt.msaa_resolve.view
    pass.copy_info.src = {
        texture = rt.msaa_resolve.image,
        aspect = .All,
    }
    pass.copy_info.dst = {
        texture = rt.output.image,
        aspect = .All,
    }
    pass.copy_info.size = {rt.output.width, rt.output.height, 1}
    pass.mips = rt.mipmapper
    return
}
