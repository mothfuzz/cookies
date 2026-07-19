package graphics

import "vendor:wgpu"
import "base:runtime"

Render_Target_Hash :: distinct uintptr

Render_Target :: struct {
    output: Texture,
    msaa: Texture,
    depth: Texture,
    accum: Texture,
    accum_resolve: Texture,
    revealage: Texture,
    revealage_resolve: Texture,
    //
    hash: Render_Target_Hash,
}

Render_Target_Draw :: struct {
    output: wgpu.TextureView,
    msaa: wgpu.TextureView,
    depth: wgpu.TextureView,
    accum: wgpu.TextureView,
    accum_resolve: wgpu.TextureView,
    revealage: wgpu.TextureView,
    revealage_resolve: wgpu.TextureView,
    cameras: [dynamic]int,
}

make_render_target :: proc(size: [2]uint) -> (target: Render_Target) {
    target.output = make_render_texture(size, with_srgb(ren.config.format)) //don't juggle formats, use same format as screen
    target.msaa = make_render_texture(size, with_srgb(ren.config.format), true)
    target.depth = make_render_texture(size, .Depth24PlusStencil8, true)
    target.accum = make_render_texture(size, .RGBA16Float, true)
    target.accum_resolve = make_render_texture(size, .RGBA16Float)
    target.revealage = make_render_texture(size, .R8Unorm, true)
    target.revealage_resolve = make_render_texture(size, .R8Unorm)
    target.hash = Render_Target_Hash(runtime.default_hasher(&target, 0, size_of(Render_Target)))
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
}
