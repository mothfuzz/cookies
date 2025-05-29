package graphics

import "core:fmt"
import "core:math/linalg"
import "base:runtime"
import "vendor:wgpu"

Renderer :: struct {
    ctx: runtime.Context,
    instance: wgpu.Instance,
    adapter: wgpu.Adapter,
    device: wgpu.Device,
    surface: wgpu.Surface,
    msaa_tex: wgpu.Texture,
    msaa_view: wgpu.TextureView,
    depth_tex: wgpu.Texture,
    depth_view: wgpu.TextureView,
    config: wgpu.SurfaceConfiguration,
    queue: wgpu.Queue,
    shader: wgpu.ShaderModule,
    layout: wgpu.PipelineLayout,
    pipeline: wgpu.RenderPipeline,
    cameras: []Camera,
    ready: bool,
}
ren: Renderer

/*
TODO: move camera stuff into its own file.
TODO: draw_sprite function that modifies the model matrix to scale it by wgpu.TextureGetWidth & wgpu.TextureGetHeight (potentially move this stuff into its own file too)
TODO: also add texture clipping while you're at it
*/
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

tex_format: wgpu.TextureFormat
view_format: wgpu.TextureFormat
screen_size: [2]u32
configure_surface :: proc(size: [2]uint = 0) {
    if size != 0 {
        screen_size = {u32(size.x), u32(size.y)}
        for cam in cameras {
            calculate_projection(cam)
        }
    }

    fmt.println("reconfiguring draw surface...")
    caps, status := wgpu.SurfaceGetCapabilities(ren.surface, ren.adapter)
    if status == .Error {
        panic("Unable to get surface capabilities!")
    }
    if caps.formatCount == 0 {
        panic("No available surface formats!")
    }
    //fmt.println(caps)
    tex_format = without_srgb(caps.formats[0])
    view_format = with_srgb(caps.formats[0])
    ren.config = wgpu.SurfaceConfiguration {
        device = ren.device,
        usage = {.RenderAttachment},
        format = tex_format,
        viewFormatCount = 1,
        viewFormats = &view_format,
        width = screen_size.x,
        height = screen_size.y,
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
        format = with_srgb(ren.config.format), //same as surface view
        usage = {.RenderAttachment},
    })
    ren.msaa_view = wgpu.TextureCreateView(ren.msaa_tex, nil)

    ren.depth_tex = wgpu.DeviceCreateTexture(ren.device, &{
        size = {ren.config.width, ren.config.height, 1},
        mipLevelCount = 1,
        sampleCount = 4,
        dimension = ._2D,
        format = .Depth24PlusStencil8,
        usage = {.RenderAttachment},
    })
    ren.depth_view = wgpu.TextureCreateView(ren.depth_tex, nil)
}

request_adapter :: proc "c" (status: wgpu.RequestAdapterStatus, adapter: wgpu.Adapter, message: string, userdata1, userdata2: rawptr) {
    context = (^runtime.Context)(userdata1)^
    if status != .Success || adapter == nil {
        panic(message)
    }
    ren.adapter = adapter
    wgpu.AdapterRequestDevice(ren.adapter, nil, {callback = request_device, userdata1=userdata1})
}

screen_size_buffer: wgpu.Buffer
screen_color_blend_buffer: wgpu.Buffer
uniform_bind_group: wgpu.BindGroup

request_device :: proc "c" (status: wgpu.RequestDeviceStatus, device: wgpu.Device, message: string, userdata1, userdata2: rawptr) {
    context = (^runtime.Context)(userdata1)^
    if status != .Success || device == nil {
        panic(message)
    }
    ren.device = device

    configure_surface()

    ren.queue = wgpu.DeviceGetQueue(ren.device)

    ren.shader = wgpu.DeviceCreateShaderModule(ren.device, &{
        nextInChain = &wgpu.ShaderSourceWGSL{
            sType = .ShaderSourceWGSL,
            code = #load("renderer.wgsl"),
        },
    })

    //bind group layouts
    uniform_layout_entries := []wgpu.BindGroupLayoutEntry{
        //screen_size
        wgpu.BindGroupLayoutEntry{
            binding = 0,
            visibility = {.Vertex, .Fragment},
            buffer = {type=.Uniform},
        },
        //screen_color_blend
        wgpu.BindGroupLayoutEntry{
            binding = 1,
            visibility = {.Vertex, .Fragment},
            buffer = {type=.Uniform},
        },
    }
    uniform_layout := wgpu.DeviceCreateBindGroupLayout(ren.device, &{
        entryCount = len(uniform_layout_entries),
        entries = raw_data(uniform_layout_entries),
    })
    camera_layout = wgpu.DeviceCreateBindGroupLayout(ren.device, &{
        entryCount = len(camera_layout_entries),
        entries = raw_data(camera_layout_entries),
    })
    material_layout = wgpu.DeviceCreateBindGroupLayout(ren.device, &{
        entryCount = len(material_layout_entries),
        entries = raw_data(material_layout_entries),
        //one entry for each texture in the material
        //binding for: albedo, normal, pbr, and environment (for now)
    })

    bind_group_layouts := []wgpu.BindGroupLayout{uniform_layout, camera_layout, material_layout}
    ren.layout = wgpu.DeviceCreatePipelineLayout(ren.device, &{
        bindGroupLayoutCount = len(bind_group_layouts),
        bindGroupLayouts = raw_data(bind_group_layouts),
    })

    //create uniform buffers/bind group up front
    screen_size_buffer = wgpu.DeviceCreateBuffer(device, &{usage={.Uniform, .CopyDst}, size=size_of([2]f32)})
    screen_color_blend_buffer = wgpu.DeviceCreateBuffer(device, &{usage={.Uniform, .CopyDst}, size=size_of(f32)})
    bindings := []wgpu.BindGroupEntry{
        {binding = 0, buffer = screen_size_buffer, size = size_of([2]f32)},
        {binding = 1, buffer = screen_color_blend_buffer, size = size_of(f32)},
    }
    uniform_bind_group = wgpu.DeviceCreateBindGroup(device, &{
        layout = uniform_layout,
        entryCount = len(bindings),
        entries = raw_data(bindings),
    })

    //vertex data
    vertex_buffers := []wgpu.VertexBufferLayout{
        position_attribute,
        texcoord_attribute,
        color_attribute,
        model_attribute,
    }
    ren.pipeline = wgpu.DeviceCreateRenderPipeline(ren.device, &{
        layout = ren.layout,
        vertex = {
            module = ren.shader,
            entryPoint = "vs_main",
            bufferCount = len(vertex_buffers),
            buffers = raw_data(vertex_buffers),
        },
        fragment = &{
            module = ren.shader,
            entryPoint = "fs_main",
            targetCount = 1,
            targets = &wgpu.ColorTargetState{
                format = with_srgb(ren.config.format), //same as surface, since this outputs to screen.
                writeMask = wgpu.ColorWriteMaskFlags_All,
            },
        },
        primitive = {
            topology = .TriangleList,
            cullMode = .None,
            frontFace = .CW,
        },
        depthStencil = &{
            format = .Depth24PlusStencil8,
            depthWriteEnabled = .True,
            depthCompare = .LessEqual,
        },
        multisample = {
            count = 4,
            mask = 0xffffffff,
        },
    })
    ren.ready = true
}

ctx: runtime.Context
init :: proc(surface_proc: proc(wgpu.Instance)->wgpu.Surface, size: [2]uint) {
    screen_size = {u32(size.x), u32(size.y)}
    ren.instance = wgpu.CreateInstance(nil)
    if ren.instance == nil {
        panic("WebGPU not supported.")
    }
    ren.surface = surface_proc(ren.instance)
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

cameras: []^Camera
set_camera :: proc(cam: ^Camera) {
    delete(cameras)
    cameras = make([]^Camera, 1)
    cameras[0] = cam
}
set_cameras :: proc(cams: []^Camera) {
    delete(cameras)
    cameras = make([]^Camera, len(cams))
    copy(cameras, cams)
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
        configure_surface()
        return
    case .OutOfMemory, .DeviceLost, .Error:
        fmt.eprintln(surface_tex.status)
        panic("Surface texture lost! Unable to draw to screen.")
    }
    defer wgpu.TextureRelease(surface_tex.texture)
    screen := wgpu.TextureCreateView(surface_tex.texture, &{format=with_srgb(ren.config.format), mipLevelCount=1, arrayLayerCount=1})
    defer wgpu.TextureViewRelease(screen)
    command_encoder := wgpu.DeviceCreateCommandEncoder(ren.device, nil)
    defer wgpu.CommandEncoderRelease(command_encoder)

    screen_size := [2]f32{f32(screen_size.x), f32(screen_size.y)}
    blend_factor := f32(0.0)
    wgpu.QueueWriteBuffer(ren.queue, screen_size_buffer, 0, raw_data(&screen_size), size_of([2]f32))
    wgpu.QueueWriteBuffer(ren.queue, screen_color_blend_buffer, 0, &blend_factor, size_of(f32))

    clear_pass := wgpu.CommandEncoderBeginRenderPass(command_encoder, &{
        colorAttachmentCount = 1,
        colorAttachments = &wgpu.RenderPassColorAttachment{
            view = ren.msaa_view,
            resolveTarget = screen,
            loadOp = .Clear,
            storeOp = .Store,
            depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
            clearValue = linalg.vector4_srgb_to_linear([4]f64{0.4, 0.6, 0.9, 1.0}),
        },
        depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment{
            view = ren.depth_view,
            depthLoadOp = .Clear,
            depthStoreOp = .Store,
            depthClearValue = 1.0,
            stencilLoadOp = .Clear,
            stencilStoreOp = .Store,
            stencilClearValue = 1.0,
        },
    })
    wgpu.RenderPassEncoderEnd(clear_pass)
    wgpu.RenderPassEncoderRelease(clear_pass)


    //draw loop
    for cam in cameras {
        render_pass := wgpu.CommandEncoderBeginRenderPass(command_encoder, &{
            colorAttachmentCount = 1,
            colorAttachments = &wgpu.RenderPassColorAttachment{
                view = ren.msaa_view,
                resolveTarget = screen,
                loadOp = .Load,
                storeOp = .Store,
                depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
            },
            depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment{
                view = ren.depth_view,
                depthLoadOp = .Load,
                depthStoreOp = .Store,
                stencilLoadOp = .Load,
                stencilStoreOp = .Store,
            },
        })

        wgpu.RenderPassEncoderSetPipeline(render_pass, ren.pipeline)
        wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, uniform_bind_group)
        bind_camera(render_pass, 1, cam)

        for mesh, &batch in batches {
            //fmt.println("unique materials in this batch:", len(batch))
            bind_mesh(render_pass, mesh)
            for material, &instances in batch {
                //fmt.println("number of instances:", len(instances.models))
                bind_material(render_pass, 2, material)
                draw_batch(render_pass, mesh, material)
            }
        }

        wgpu.RenderPassEncoderEnd(render_pass)
        wgpu.RenderPassEncoderRelease(render_pass)

    }

    clear_batches()

    command_buffer := wgpu.CommandEncoderFinish(command_encoder, nil)
    defer wgpu.CommandBufferRelease(command_buffer)

    wgpu.QueueSubmit(ren.queue, {command_buffer})
    wgpu.SurfacePresent(ren.surface)
}
