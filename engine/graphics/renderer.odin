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
    msaa_tex: wgpu.Texture, //used for AA resolve on surface
    msaa_view: wgpu.TextureView,
    depth_buffer: Texture,
    accum: Texture,
    revealage: Texture,
    config: wgpu.SurfaceConfiguration,
    queue: wgpu.Queue,
    shader: wgpu.ShaderModule,
    composite_shader: wgpu.ShaderModule,
    layout: wgpu.PipelineLayout,
    solid_pipeline: wgpu.RenderPipeline,
    trans_pipeline: wgpu.RenderPipeline,
    composite_layout: wgpu.PipelineLayout,
    composite_pipeline: wgpu.RenderPipeline,
    composite_bind_group_layout: wgpu.BindGroupLayout,
    composite_bind_group: wgpu.BindGroup,
    composite_sampler: wgpu.Sampler,
    ready: bool,
}
ren: Renderer

Screen_Uniforms :: struct {
    size: [4]f32, //width, height, near, far
    color: [4]f32, //rgb + fog start
}
screen_uniforms: Screen_Uniforms = {
    size={0, 0, 0.1, 0},
}
screen_uniforms_buffer: wgpu.Buffer
uniform_bind_group: wgpu.BindGroup

set_background_color :: proc(color: [3]f32) {
    screen_uniforms.color.rgb = linalg.vector4_srgb_to_linear([4]f32{color.r, color.g, color.b, 1.0}).rgb
}
get_background_color :: proc() -> [3]f32 {
    c := screen_uniforms.color.rgb
    return linalg.vector4_linear_to_srgb([4]f32{c.r, c.g, c.b, 1.0}).rgb
}

set_render_distance :: proc(far: f32) {
    screen_uniforms.size[3] = far
}

get_screen_size :: proc() -> [2]f32 {
    return screen_uniforms.size.xy
}

set_fog_distance :: proc(fog_start: f32) {
    screen_uniforms.color[3] = fog_start
}

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
configure_surface :: proc(size: [2]uint = 0) {
    if size != 0 {
        screen_uniforms.size.xy = {f32(size.x), f32(size.y)}
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
    //prefer mailbox to unlink FPS from refresh rate
    presentMode := wgpu.PresentMode.Fifo
    for i in 0..<caps.presentModeCount {
        if caps.presentModes[i] == .Mailbox {
            presentMode = .Mailbox
            fmt.println("Upgrading to fast vsync.")
            break
        }
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
        width = u32(screen_uniforms.size.x),
        height = u32(screen_uniforms.size.y),
        presentMode = presentMode,
        alphaMode = .Opaque,
    }
    wgpu.SurfaceConfigure(ren.surface, &ren.config)
}

configure_render_targets :: proc() {
    fmt.println("creating render targets:", ren.config.width, "x", ren.config.height)
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

    if ren.depth_buffer.image != nil {
        delete_texture(ren.depth_buffer)
    }
    ren.depth_buffer = make_render_target({uint(ren.config.width), uint(ren.config.height)}, .Depth24PlusStencil8, .Depth24PlusStencil8)

    if ren.accum.image != nil {
        delete_texture(ren.accum)
    }
    ren.accum = make_render_target({uint(ren.config.width), uint(ren.config.height)}, .RGBA16Float, .RGBA16Float)
    if ren.revealage.image != nil {
        delete_texture(ren.revealage)
    }
    ren.revealage = make_render_target({uint(ren.config.width), uint(ren.config.height)}, .R8Unorm, .R8Unorm)

    //only re-bind when those textures actually change.
    if ren.composite_bind_group != nil {
        wgpu.BindGroupRelease(ren.composite_bind_group)
    }
    composite_bindings := []wgpu.BindGroupEntry{
        {binding = 0, sampler=ren.composite_sampler},
        {binding = 1, textureView=ren.accum.resolve_view},
        {binding = 2, textureView=ren.revealage.resolve_view},
    }
    ren.composite_bind_group = wgpu.DeviceCreateBindGroup(ren.device, &{
        layout = ren.composite_bind_group_layout,
        entryCount = len(composite_bindings),
        entries = raw_data(composite_bindings),
    })

    fmt.println("MSAA WIDTH:", wgpu.TextureGetWidth(ren.msaa_tex))
    fmt.println("MSAA HEIGHT:", wgpu.TextureGetHeight(ren.msaa_tex))
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
        fmt.println("THERE WAS AN ERROR!!!!")
        panic(message)
    }
    ren.device = device

    //print limits
    limits, _ := wgpu.DeviceGetLimits(ren.device)
    fmt.println("max uniform buffers:", limits.maxUniformBuffersPerShaderStage)
    fmt.println("max uniform buffer size:", limits.maxUniformBufferBindingSize, "bytes")
    fmt.println("max storage buffers:", limits.maxStorageBuffersPerShaderStage)
    fmt.println("max storage buffer size:", limits.maxStorageBufferBindingSize, "bytes")
    fmt.println("max vertex buffers:", limits.maxVertexBuffers)
    fmt.println("max vertex buffer size:", limits.maxBufferSize, "bytes")
    fmt.println("max vertex attributes:", limits.maxVertexAttributes)

    configure_surface()

    ren.queue = wgpu.DeviceGetQueue(ren.device)

    ren.shader = wgpu.DeviceCreateShaderModule(ren.device, &{
        nextInChain = &wgpu.ShaderSourceWGSL{
            sType = .ShaderSourceWGSL,
            code = #load("renderer.wgsl"),
        },
    })

    ren.composite_shader = wgpu.DeviceCreateShaderModule(ren.device, &{
        nextInChain = &wgpu.ShaderSourceWGSL{
            sType = .ShaderSourceWGSL,
            code = #load("composite.wgsl"),
        },
    })

    //bind group layouts
    uniform_layout_entries := []wgpu.BindGroupLayoutEntry{
        //screen_uniforms
        wgpu.BindGroupLayoutEntry{
            binding = 0,
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
        //binding for: base_color, normal, pbr, and environment (for now)
    })
    lights_layout = wgpu.DeviceCreateBindGroupLayout(ren.device, &{
        entryCount = len(lights_layout_entries),
        entries = raw_data(lights_layout_entries),
    })

    bind_group_layouts := []wgpu.BindGroupLayout{uniform_layout, camera_layout, material_layout, lights_layout}
    ren.layout = wgpu.DeviceCreatePipelineLayout(ren.device, &{
        bindGroupLayoutCount = len(bind_group_layouts),
        bindGroupLayouts = raw_data(bind_group_layouts),
    })

    //create uniform buffers/bind group up front
    screen_uniforms_buffer = wgpu.DeviceCreateBuffer(device, &{usage={.Uniform, .CopyDst}, size=size_of(Screen_Uniforms)})
    bindings := []wgpu.BindGroupEntry{
        {binding = 0, buffer = screen_uniforms_buffer, size = size_of(Screen_Uniforms)},
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
        instance_data_attribute,
    }

    fmt.println("creating solid pipeline...")
    ren.solid_pipeline = wgpu.DeviceCreateRenderPipeline(ren.device, &{
        label = "solid",
        layout = ren.layout,
        vertex = {
            module = ren.shader,
            entryPoint = "vs_main",
            bufferCount = len(vertex_buffer_layouts),
            buffers = raw_data(vertex_buffer_layouts),
        },
        fragment = &{
            module = ren.shader,
            entryPoint = "solid_main",
            targetCount = 1,
            targets = &wgpu.ColorTargetState{
                format = with_srgb(ren.config.format),
                writeMask = wgpu.ColorWriteMaskFlags_All,
            },
        },
        primitive = {
            topology = .TriangleList,
            cullMode = .None,
            frontFace = .CCW,
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

    fmt.println("creating trans pipeline...")
    trans_targets := []wgpu.ColorTargetState{
        //accum
        {
            format = .RGBA16Float,
            writeMask = wgpu.ColorWriteMaskFlags_All,
            blend = &{
                color = wgpu.BlendComponent{
                    operation = .Add,
                    srcFactor = .One,
                    dstFactor = .One,
                },
                alpha = wgpu.BlendComponent{
                    operation = .Add,
                    srcFactor = .One,
                    dstFactor = .One,
                },
            },
        },
        //revealage
        {
            format = .R8Unorm,
            writeMask = wgpu.ColorWriteMaskFlags_All,
            blend = &{
                color = wgpu.BlendComponent{
                    operation = .Add,
                    srcFactor = .Zero,
                    dstFactor = .OneMinusSrc,
                },
                alpha = wgpu.BlendComponent{
                    operation = .Add,
                    srcFactor = .Zero,
                    dstFactor = .OneMinusSrc,
                },
            },
        },
    }
    ren.trans_pipeline = wgpu.DeviceCreateRenderPipeline(ren.device, &{
        label = "trans",
        layout = ren.layout,
        vertex = {
            module = ren.shader,
            entryPoint = "vs_main",
            bufferCount = len(vertex_buffer_layouts),
            buffers = raw_data(vertex_buffer_layouts),
        },
        fragment = &{
            module = ren.shader,
            entryPoint = "trans_main",
            targetCount = len(trans_targets),
            targets = raw_data(trans_targets),
        },
        primitive = {
            topology = .TriangleList,
            cullMode = .None,
            frontFace = .CCW,
        },
        depthStencil = &{
            format = .Depth24PlusStencil8,
            depthWriteEnabled = .False, //false for transparent materials
            depthCompare = .LessEqual,
        },
        multisample = {
            count = 4,
            mask = 0xffffffff,
        },
    })

    fmt.println("creating compositor...")
    composite_layout_entries := []wgpu.BindGroupLayoutEntry{
        wgpu.BindGroupLayoutEntry{
            binding = 0,
            visibility = {.Fragment},
            sampler = {type = .Filtering},
        },
        //accum
        wgpu.BindGroupLayoutEntry{
            binding = 1,
            visibility = {.Fragment},
            texture = {sampleType = .Float, viewDimension = ._2D},
        },
        //revealage
        wgpu.BindGroupLayoutEntry{
            binding = 2,
            visibility = {.Fragment},
            texture = {sampleType = .Float, viewDimension = ._2D},
        },
    }
    ren.composite_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(ren.device, &{
        entryCount = len(composite_layout_entries),
        entries = raw_data(composite_layout_entries),
    })
    ren.composite_layout = wgpu.DeviceCreatePipelineLayout(ren.device, &{
        bindGroupLayoutCount = 1,
        bindGroupLayouts = &ren.composite_bind_group_layout,
    })
    ren.composite_pipeline = wgpu.DeviceCreateRenderPipeline(ren.device, &{
        label = "composite",
        layout = ren.composite_layout,
        vertex = {
            module = ren.composite_shader,
            entryPoint = "vs_main",
            bufferCount = 0,
        },
        fragment = &{
            module = ren.composite_shader,
            entryPoint = "fs_main",
            targetCount = 1,
            targets = &wgpu.ColorTargetState{
                format = with_srgb(ren.config.format), //same as surface, since this outputs to screen.
                writeMask = wgpu.ColorWriteMaskFlags_All,
                blend = &{
                    color = wgpu.BlendComponent{
                        operation = .Add,
                        srcFactor = .OneMinusSrcAlpha,
                        dstFactor = .SrcAlpha,
                    },
                    alpha = wgpu.BlendComponent{
                        operation = .Add,
                        srcFactor = .OneMinusSrcAlpha,
                        dstFactor = .SrcAlpha,
                    },
                },
            },
        },
        primitive = {
            topology = .TriangleList,
            cullMode = .None,
            frontFace = .CCW,
        },
        depthStencil = nil,
        multisample = {
            count = 4,
            mask = 0xffffffff,
        },
    })
    ren.composite_sampler = wgpu.DeviceCreateSampler(ren.device, &{
        minFilter=.Linear,
        magFilter=.Linear,
        mipmapFilter=.Linear, //don't use mips for fullscreen, dog
        maxAnisotropy=1,
        addressModeU=.ClampToEdge,
        addressModeV=.ClampToEdge,
    })

    fmt.println("setting up render targets...")
    configure_render_targets()


    init_defaults()
    init_ui()

    ren.ready = true
    fmt.println("renderer SAYS it's ready.")
    fmt.println(status)
    fmt.println(ren.device)
}

ctx: runtime.Context
init :: proc(surface_proc: proc(wgpu.Instance)->wgpu.Surface, size: [2]uint) {
    screen_uniforms.size.xy = {f32(size.x), f32(size.y)}
    ren.instance = wgpu.CreateInstance(nil)
    if ren.instance == nil {
        panic("WebGPU not supported.")
    }
    ren.surface = surface_proc(ren.instance)
    ctx = context
    wgpu.InstanceRequestAdapter(ren.instance, &{compatibleSurface = ren.surface}, {callback=request_adapter, userdata1=&ctx})
}

quit :: proc() {
    delete_batches()
    delete_ui_batches()
    delete_lights()
    delete(cameras)
    delete_defaults()
    wgpu.RenderPipelineRelease(ren.solid_pipeline)
    wgpu.RenderPipelineRelease(ren.trans_pipeline)
    wgpu.PipelineLayoutRelease(ren.layout)
    wgpu.RenderPipelineRelease(ren.composite_pipeline)
    wgpu.PipelineLayoutRelease(ren.composite_layout)
    wgpu.BindGroupLayoutRelease(ren.composite_bind_group_layout)
    wgpu.BindGroupRelease(ren.composite_bind_group)
    wgpu.SamplerRelease(ren.composite_sampler)
    wgpu.ShaderModuleRelease(ren.shader)
    wgpu.TextureViewRelease(ren.msaa_view)
    wgpu.TextureRelease(ren.msaa_tex)
    delete_texture(ren.depth_buffer)
    delete_texture(ren.accum)
    delete_texture(ren.revealage)
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

//renders all meshes to a specific view with a specific pipeline
render_meshes :: proc(render_pass: wgpu.RenderPassEncoder, pipeline: wgpu.RenderPipeline, cam: ^Camera, all_meshes: []MeshRenderItem, all_indices: []int, t: f64) {
    wgpu.RenderPassEncoderSetPipeline(render_pass, pipeline)
    wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, uniform_bind_group)
    bind_camera(render_pass, 1, cam, t) //view produced here
    bind_lights(render_pass, 3, cam)

    reset_modelviews(all_meshes[:])
    indices := frustum_culling(cam, all_meshes[:], all_indices[:])
    defer delete(indices)

    current_mesh: Mesh
    current_material: Material
    instances := make([dynamic]InstanceData, 0)
    flush := false
    defer delete(instances)
    for i in 0..<len(indices) {
        //batch em up
        instance := &all_meshes[indices[i]]
        if instance.mesh != current_mesh {
            current_mesh = instance.mesh
            bind_mesh(render_pass, current_mesh)
        }
        if instance.material != current_material {
            current_material = instance.material
            bind_material(render_pass, 2, current_material)
        }
        calculate_modelview(instance, cam)
        append(&instances, InstanceData{modelview=instance.modelview, dynamic_material=instance.dynamic_material})

        //if next mesh is different, or there is no next mesh, draw the current batch
        switch {
        case i+1 < len(indices):
            instance := &all_meshes[indices[i+1]]
            if instance.mesh != current_mesh || instance.material != current_material {
                flush = true
            }
        case i+1 == len(indices):
            flush = true
        }

        if flush {
            draw_mesh_instances(render_pass, current_mesh, instances[:])
            clear(&instances)
            flush = false
        }
    }

}

append_render_list :: proc(all_meshes: ^[dynamic]MeshRenderItem, all_indices: ^[dynamic]int, batches: ^map[Mesh]map[Material][dynamic]MeshDraw) {
    for mesh, &batch in batches {
        for material, &instances in batch {
            for instance, i in instances {
                append(all_meshes, MeshRenderItem{mesh=mesh, material=material, draw=instance})
                append(all_indices, len(all_indices))
            }
        }
    }

}

render :: proc(t: f64) {
    if !ren.ready {
        return
    }

    //t is the interpolation factor.
    //prepare the screen surface
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

    //gather all meshes into a list
    all_meshes := make([dynamic]MeshRenderItem)
    defer delete(all_meshes)
    all_indices := make([dynamic]int)
    defer delete(all_indices)

    //solid AND opaque for lights
    append_render_list(&all_meshes, &all_indices, &solid_batches)
    append_render_list(&all_meshes, &all_indices, &solid_batches)

    //TODO: render both solid & trans meshes for each light with a shadow map...
    clear(&all_meshes)
    clear(&all_indices)

    //first do simple clear-color pass
    clear_pass := wgpu.CommandEncoderBeginRenderPass(command_encoder, &{
        label = "clear",
        colorAttachmentCount = 1,
        colorAttachments = &wgpu.RenderPassColorAttachment{
            view = ren.msaa_view,
            resolveTarget = screen,
            loadOp = .Clear,
            storeOp = .Store,
            depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
            clearValue = [4]f64{f64(screen_uniforms.color.r),
                                f64(screen_uniforms.color.g),
                                f64(screen_uniforms.color.b), 1.0},
        },
        depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment{
            view = ren.depth_buffer.view,
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

    //then execute an opaque pass for each camera
    append_render_list(&all_meshes, &all_indices, &solid_batches)
    for cam in cameras {
        screen_uniforms_temp := screen_uniforms
        cam_width, cam_height := get_viewport_size(cam)
        screen_uniforms_temp.size.x = cam_width
        screen_uniforms_temp.size.y = cam_height
        if screen_uniforms_temp.color.rgb == 0 {
            screen_uniforms_temp.color.rgb = 1
        }
        wgpu.QueueWriteBuffer(ren.queue, screen_uniforms_buffer, 0, &screen_uniforms_temp, size_of(Screen_Uniforms))

        render_pass := wgpu.CommandEncoderBeginRenderPass(command_encoder, &{
            label = "solid",
            colorAttachmentCount = 1,
            colorAttachments = &wgpu.RenderPassColorAttachment{
                view = ren.msaa_view,
                resolveTarget = screen,
                loadOp = .Load,
                storeOp = .Store,
                depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
            },
            depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment{
                view = ren.depth_buffer.view,
                depthLoadOp = .Load,
                depthStoreOp = .Store,
                stencilLoadOp = .Load,
                stencilStoreOp = .Store,
            },
        })

        render_meshes(render_pass, ren.solid_pipeline, cam, all_meshes[:], all_indices[:], t)

        wgpu.RenderPassEncoderEnd(render_pass)
        wgpu.RenderPassEncoderRelease(render_pass)
    }
    clear(&all_meshes)
    clear(&all_indices)

    //then execute a clear pass for the transparent objects...
    trans_clear_attachments := []wgpu.RenderPassColorAttachment{
        //accum
        {
            view = ren.accum.view,
            resolveTarget = ren.accum.resolve_view,
            loadOp = .Clear,
            storeOp = .Store,
            depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
            clearValue = {0, 0, 0, 0},
        },
        //revealage
        {
            view = ren.revealage.view,
            resolveTarget = ren.revealage.resolve_view,
            loadOp = .Clear,
            storeOp = .Store,
            depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
            clearValue = {1, 0, 0, 0},
        },
    }
    trans_clear_pass := wgpu.CommandEncoderBeginRenderPass(command_encoder, &{
        label = "trans_clear",
        colorAttachmentCount = len(trans_clear_attachments),
        colorAttachments = raw_data(trans_clear_attachments),
        depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment{
            view = ren.depth_buffer.view,
            depthLoadOp = .Load,
            depthStoreOp = .Store,
            stencilLoadOp = .Load,
            stencilStoreOp = .Store,
        },
    })
    wgpu.RenderPassEncoderEnd(trans_clear_pass)
    wgpu.RenderPassEncoderRelease(trans_clear_pass)

    //then execute a transparent pass for each camera
    append_render_list(&all_meshes, &all_indices, &trans_batches)
    for cam in cameras {
        screen_uniforms_temp := screen_uniforms
        cam_width, cam_height := get_viewport_size(cam)
        screen_uniforms_temp.size.x = cam_width
        screen_uniforms_temp.size.y = cam_height
        if screen_uniforms_temp.color.rgb == 0 {
            screen_uniforms_temp.color.rgb = 1
        }
        wgpu.QueueWriteBuffer(ren.queue, screen_uniforms_buffer, 0, &screen_uniforms_temp, size_of(Screen_Uniforms))

        trans_color_attachments := []wgpu.RenderPassColorAttachment{
            //accum
            {
                view = ren.accum.view,
                resolveTarget = ren.accum.resolve_view,
                loadOp = .Load,
                storeOp = .Store,
                depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
            },
            //revealage
            {
                view = ren.revealage.view,
                resolveTarget = ren.revealage.resolve_view,
                loadOp = .Load,
                storeOp = .Store,
                depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
            },
        }
        render_pass := wgpu.CommandEncoderBeginRenderPass(command_encoder, &{
            label = "trans",
            colorAttachmentCount = len(trans_color_attachments),
            colorAttachments = raw_data(trans_color_attachments),
            depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment{
                view = ren.depth_buffer.view,
                depthLoadOp = .Load,
                depthStoreOp = .Store, //remember to disable depth-store for transparent.
                stencilLoadOp = .Load,
                stencilStoreOp = .Store,
            },
        })

        render_meshes(render_pass, ren.trans_pipeline, cam, all_meshes[:], all_indices[:], t)

        wgpu.RenderPassEncoderEnd(render_pass)
        wgpu.RenderPassEncoderRelease(render_pass)
    }
    clear(&all_meshes)
    clear(&all_indices)

    //finally render composite pass...
    composite_pass := wgpu.CommandEncoderBeginRenderPass(command_encoder, &{
        label = "composite",
        colorAttachmentCount = 1,
        colorAttachments = &wgpu.RenderPassColorAttachment{
            view = ren.msaa_view,
            resolveTarget = screen,
            loadOp = .Load,
            storeOp = .Store,
            depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
        },
    })
    wgpu.RenderPassEncoderSetPipeline(composite_pass, ren.composite_pipeline)
    wgpu.RenderPassEncoderSetBindGroup(composite_pass, 0, ren.composite_bind_group)
    //should be default
    //wgpu.RenderPassEncoderSetViewport(composite_pass, 0, 0, f32(ren.config.width), f32(ren.config.height), 0, 1)
    //wgpu.RenderPassEncoderSetScissorRect(composite_pass, 0, 0, ren.config.width, ren.config.height)
    wgpu.RenderPassEncoderDraw(composite_pass, 3, 1, 0, 0)
    wgpu.RenderPassEncoderEnd(composite_pass)
    wgpu.RenderPassEncoderRelease(composite_pass)

    //cleanup the lights & meshes
    clear_lights()
    clear_batches()

    //render the UI on top
    render_ui(screen, command_encoder)

    //then blast it
    command_buffer := wgpu.CommandEncoderFinish(command_encoder)
    defer wgpu.CommandBufferRelease(command_buffer)

    wgpu.QueueSubmit(ren.queue, {command_buffer})
    wgpu.SurfacePresent(ren.surface)
}
