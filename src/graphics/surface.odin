package graphics

import "vendor:wgpu"
import "core:log"

with_srgb :: proc(format: wgpu.TextureFormat) -> wgpu.TextureFormat {
    //don't care about BC1, BC2, BC3, BC7, ETC2, or ASTC
    #partial switch format {
    case .RGBA8Unorm:
        return .RGBA8UnormSrgb
    case .BGRA8Unorm:
        return .BGRA8UnormSrgb
    case:
        return format
    }
}
without_srgb :: proc(format: wgpu.TextureFormat) -> wgpu.TextureFormat {
    //don't care about BC1, BC2, BC3, BC7, ETC2, or ASTC
    #partial switch format {
    case .RGBA8UnormSrgb:
        return .RGBA8Unorm
    case .BGRA8UnormSrgb:
        return .BGRA8Unorm
    case:
        return format
    }
}

screen_resolution: [2]uint
logical_resolution: [2]uint
window_resized :: proc(size: [2]uint) {
    configure_surface(size)
    configure_screen_textures()
}

tex_format: wgpu.TextureFormat
view_format: wgpu.TextureFormat
@(private)
configure_surface :: proc(size: [2]uint = 0, resolution: [2]uint = 0) {
    if size != 0 {
        screen_resolution = size
    }
    logical_resolution = resolution
    if screen_resolution.x == 0 || screen_resolution.y == 0 {
        return
    }
    log.debug("reconfiguring draw surface...")
    caps, status := wgpu.SurfaceGetCapabilities(ren.surface, ren.adapter)
    if status == .Error {
        log.panic("Unable to get surface capabilities!")
    }
    defer wgpu.SurfaceCapabilitiesFreeMembers(caps)
    if caps.formatCount == 0 {
        log.panic("No available surface formats!")
    }
    //prefer mailbox to unlink FPS from refresh rate
    presentMode := wgpu.PresentMode.Fifo
    for i in 0..<caps.presentModeCount {
        if caps.presentModes[i] == .Mailbox {
            presentMode = .Mailbox
            log.debug("Upgrading to fast vsync.")
            break
        }
    }
    tex_format = without_srgb(caps.formats[0])
    view_format = with_srgb(caps.formats[0])
    ren.config = wgpu.SurfaceConfiguration {
        device = ren.device,
        usage = {.RenderAttachment},
        format = tex_format,
        viewFormatCount = 1,
        viewFormats = &view_format,
        width = u32(screen_resolution.x),
        height = u32(screen_resolution.y),
        presentMode = presentMode,
        alphaMode = .Opaque,
    }
    wgpu.SurfaceConfigure(ren.surface, &ren.config)
}

@(private)
configure_screen_textures :: proc() {
    log.debug("creating screen textures:", ren.config.width, "x", ren.config.height)
    if ren.msaa_view != nil {
        wgpu.TextureViewRelease(ren.msaa_view)
    }
    if ren.msaa_tex != nil {
        wgpu.TextureRelease(ren.msaa_tex)
    }
    ren.msaa_tex = wgpu.DeviceCreateTexture(ren.device, &{
        size = {ren.config.width, ren.config.height, 1},
        mipLevelCount = 1,
        sampleCount = 4,
        dimension = ._2D,
        format = with_srgb(ren.config.format), //same as surface view
        usage = {.RenderAttachment},
    })
    ren.msaa_view = wgpu.TextureCreateView(ren.msaa_tex)

    if ren.main_textures.oit_composite_bind_group != nil {
        delete_main_textures(ren.main_textures)
    }
    ren.main_textures := make_main_textures({uint(ren.config.width), uint(ren.config.height)})
}
