package graphics

import "core:fmt"
import "base:runtime"
import "vendor:wgpu"
import "../window"

Renderer :: struct {
    ctx: runtime.Context,
    instance: wgpu.Instance,
    adapter: wgpu.Adapter,
    device: wgpu.Device,
    surface: wgpu.Surface,
    msaa_tex: wgpu.Texture,
    msaa_view: wgpu.TextureView,
    config: wgpu.SurfaceConfiguration,
    queue: wgpu.Queue,
    shader: wgpu.ShaderModule,
    layout: wgpu.PipelineLayout,
    pipeline: wgpu.RenderPipeline,
    ready: bool
}
ren: Renderer

resize_surface :: proc() {
    fmt.println("resizing...")
    size := window.get_size()
    ren.config = wgpu.SurfaceConfiguration {
        device = ren.device,
        usage = {.RenderAttachment},
        format = .BGRA8Unorm,
        width = u32(size.x),
        height = u32(size.y),
        presentMode = .Fifo,
        alphaMode = .Opaque,
    }
    wgpu.SurfaceConfigure(ren.surface, &ren.config)
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
        format = ren.config.format,
        usage = {.RenderAttachment},
    })
    ren.msaa_view = wgpu.TextureCreateView(ren.msaa_tex, nil)
}

request_adapter :: proc "c" (status: wgpu.RequestAdapterStatus, adapter: wgpu.Adapter, message: string, userdata1, userdata2: rawptr) {
    context = (^runtime.Context)(userdata1)^
    if status != .Success || adapter == nil {
        panic(message)
    }
    ren.adapter = adapter
    wgpu.AdapterRequestDevice(ren.adapter, nil, {callback = request_device, userdata1=userdata1})
}

request_device :: proc "c" (status: wgpu.RequestDeviceStatus, device: wgpu.Device, message: string, userdata1, userdata2: rawptr) {
    context = (^runtime.Context)(userdata1)^
    if status != .Success || device == nil {
        panic(message)
    }
    ren.device = device

    resize_surface()

    ren.queue = wgpu.DeviceGetQueue(ren.device)

    ren.shader = wgpu.DeviceCreateShaderModule(ren.device, &{
        nextInChain = &wgpu.ShaderSourceWGSL{
            sType = .ShaderSourceWGSL,
            code = #load("renderer.wgsl"),
        },
    })
    ren.layout = wgpu.DeviceCreatePipelineLayout(ren.device, &{})
    ren.pipeline = wgpu.DeviceCreateRenderPipeline(ren.device, &{
        layout = ren.layout,
        vertex = {
            module = ren.shader,
            entryPoint = "vs_main",
        },
        fragment = &{
            module = ren.shader,
            entryPoint = "fs_main",
            targetCount= 1,
            targets = &wgpu.ColorTargetState{
                format = ren.config.format, //same as surface, since this outputs to screen.
                writeMask = wgpu.ColorWriteMaskFlags_All,
            },
        },
        primitive = {
            topology = .TriangleList,
        },
        multisample = {
            count = 4,
            mask = 0xffffffff,
        },
    })
    ren.ready = true
}

@(init)
window_hooks :: proc() {
    append(&window.init_hooks, init)
    append(&window.quit_hooks, quit)
    append(&window.resize_hooks, resize_surface)
    append(&window.draw_hooks, render)
}

ctx: runtime.Context
init :: proc() {
    ren.instance = wgpu.CreateInstance(nil)
    if ren.instance == nil {
        panic("WebGPU not supported.")
    }
    ren.surface = window.get_wgpu_surface(ren.instance)
    ctx = context
    wgpu.InstanceRequestAdapter(ren.instance, &{compatibleSurface = ren.surface}, {callback=request_adapter, userdata1=&ctx})
}

quit :: proc() {
    wgpu.RenderPipelineRelease(ren.pipeline)
    wgpu.PipelineLayoutRelease(ren.layout)
    wgpu.ShaderModuleRelease(ren.shader)
    wgpu.TextureViewRelease(ren.msaa_view)
    wgpu.TextureRelease(ren.msaa_tex)
    wgpu.QueueRelease(ren.queue)
    wgpu.DeviceRelease(ren.device)
    wgpu.AdapterRelease(ren.adapter)
    wgpu.SurfaceRelease(ren.surface)
    wgpu.InstanceRelease(ren.instance)
}

render :: proc(t: f64) {
    if !ren.ready {
        return
    }
    //t is the interpolation factor.
    surface_tex := wgpu.SurfaceGetCurrentTexture(ren.surface)
    switch surface_tex.status {
    case .SuccessOptimal, .SuccessSuboptimal:
        //yay...!
    case .Timeout, .Outdated, .Lost:
        if surface_tex.texture != nil {
            wgpu.TextureRelease(surface_tex.texture)
        }
        resize_surface()
        return
    case .OutOfMemory, .DeviceLost, .Error:
        fmt.eprintln(surface_tex.status)
        panic("Surface texture lost.")
    }
    defer wgpu.TextureRelease(surface_tex.texture)
    screen := wgpu.TextureCreateView(surface_tex.texture, nil)
    defer wgpu.TextureViewRelease(screen)
    command_encoder := wgpu.DeviceCreateCommandEncoder(ren.device, nil)
    defer wgpu.CommandEncoderRelease(command_encoder)

    //draw loop
    render_pass := wgpu.CommandEncoderBeginRenderPass(command_encoder, &{
        colorAttachmentCount = 1,
        colorAttachments = &wgpu.RenderPassColorAttachment{
            view = ren.msaa_view,
            resolveTarget = screen,
            loadOp = .Clear,
            storeOp = .Store,
            depthSlice = wgpu.DEPTH_SLICE_UNDEFINED, //the hell?
            clearValue = {0.4, 0.6, 0.9, 1.0},
        },
    })

    wgpu.RenderPassEncoderSetPipeline(render_pass, ren.pipeline)
    wgpu.RenderPassEncoderDraw(render_pass, 3, 1, 0, 0) //draw 3 vertices, 1 instance.

    wgpu.RenderPassEncoderEnd(render_pass)
    wgpu.RenderPassEncoderRelease(render_pass)

    command_buffer := wgpu.CommandEncoderFinish(command_encoder, nil)
    defer wgpu.CommandBufferRelease(command_buffer)

    wgpu.QueueSubmit(ren.queue, {command_buffer})
    wgpu.SurfacePresent(ren.surface)
}
