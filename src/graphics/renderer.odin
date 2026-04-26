package graphics

import "core:fmt"
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
    skeletons_layout = wgpu.DeviceCreateBindGroupLayout(ren.device, &{
        entryCount = len(skeletons_layout_entries),
        entries = raw_data(skeletons_layout_entries),
    })

    bind_group_layouts := []wgpu.BindGroupLayout{camera_layout, material_layout, lights_layout, skeletons_layout}
    ren.layout = wgpu.DeviceCreatePipelineLayout(ren.device, &{
        bindGroupLayoutCount = len(bind_group_layouts),
        bindGroupLayouts = raw_data(bind_group_layouts),
    })

    //create uniform buffers/bind group up front
    screen_uniforms_buffer = wgpu.DeviceCreateBuffer(device, &{usage={.Uniform, .CopyDst}, size=size_of(Screen_Uniforms)})

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
    fmt.println("GPU device address:", ren.device)
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
    delete_ui_batches()
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

//now for the good part!

Frame :: struct {
    lights: [dynamic]Light_Draw,
    cameras: [dynamic]Camera,
    action: map[Material_Hash]map[Mesh_Hash][dynamic]Mesh_Draw,
    //resources
    meshes: map[Mesh_Hash]Mesh,
    materials: map[Material_Hash]Material,
}

delete_frame :: proc(frame: Frame) {
    delete(frame.lights)
    delete(frame.cameras)
    for material, meshes in frame.action {
        for mesh, instances in meshes {
            for instance in instances {
                if instance.bones != nil {
                    delete(instance.bones)
                }
            }
            delete(instances)
        }
        delete(meshes)
    }
    delete(frame.action)
    delete(frame.meshes)
    delete(frame.materials)
}

draw_point_light :: proc(frame: ^Frame, light: Point_Light, trans: matrix[4,4]f32 = 1) {
    append(&frame.lights, Light_Draw{light, trans})
}
draw_directional_light :: proc(frame: ^Frame, light: Directional_Light, trans: matrix[4,4]f32 = 1) {
    append(&frame.lights, Light_Draw{light, trans})
}
draw_spot_light :: proc(frame: ^Frame, light: Spot_Light, trans: matrix[4,4]f32 = 1) {
    append(&frame.lights, Light_Draw{light, trans})
}
draw_light :: proc{draw_point_light, draw_directional_light, draw_spot_light}

draw_camera :: proc(frame: ^Frame, camera: ^Camera, a: f64 = 1.0) {
    calculate_camera(camera, a)
    append(&frame.cameras, camera^)
}

draw_mesh :: proc(f: ^Frame, mesh: Mesh, material: Material, trans: matrix[4,4]f32 = 1,
                  clip_rect: [4]f32 = 0,
                  base_color_tint: [4]f32 = 1,
                  ambient_tint: f32 = 1, roughness_tint: f32 = 1, metallic_tint: f32 = 1,
                  emissive_tint: [3]f32 = 1,
                  sprite: bool = false, billboard: bool = false,
                  bones: []matrix[4,4]f32 = nil) {
    //make sure resources are set
    if !(mesh.hash in f.meshes) {
        f.meshes[mesh.hash] = mesh
    }
    if !(material.hash in f.materials) {
        f.materials[material.hash] = material
    }

    //get the batch
    if f.action == nil {
        f.action = make(map[Material_Hash]map[Mesh_Hash][dynamic]Mesh_Draw)
    }
    if !(material.hash in f.action) {
        f.action[material.hash] = make(map[Mesh_Hash][dynamic]Mesh_Draw)
    }
    meshes := &f.action[material.hash]
    if !(mesh.hash in meshes) {
        meshes[mesh.hash] = make([dynamic]Mesh_Draw)
    }
    instances := &meshes[mesh.hash]

    pbr_tint := [4]f32{ambient_tint, roughness_tint, metallic_tint, 1}
    emissive_tint := [4]f32{emissive_tint.r, emissive_tint.g, emissive_tint.b, 1}
    dynamic_material := Dynamic_Material{clip_rect, base_color_tint, pbr_tint, emissive_tint}

    draw := Mesh_Draw{{trans, dynamic_material}, sprite, billboard, bones, {}}
    calculate_mesh_local(&draw, mesh, material)

    append(instances, draw)
}

draw_sprite :: proc(frame: ^Frame, material: Material, model: matrix[4, 4]f32 = 1,
                    clip_rect: [4]f32 = 0,
                    base_color_tint: [4]f32 = 1,
                    ambient_tint: f32 = 1, roughness_tint: f32 = 1, metallic_tint: f32 = 1,
                    emissive_tint: [3]f32 = 1,
                    billboard: bool = true) {
    draw_mesh(frame, quad_mesh, material, model, clip_rect,
              base_color_tint, ambient_tint, roughness_tint, metallic_tint, emissive_tint, true, billboard)
}

Mesh_Batch :: struct {
    mesh: Mesh,
    material: Material,
    instances: []Mesh_Draw,
}
flatten_action :: proc(f: Frame) -> []Mesh_Batch {
    batches := make([dynamic]Mesh_Batch)
    for material_hash, meshes in f.action {
        for mesh_hash, instances in meshes {
            mesh := f.meshes[mesh_hash]
            material := f.materials[material_hash]
            append(&batches, Mesh_Batch{mesh, material, instances[:]})
        }
    }
    return batches[:]
}
clear_action :: proc(f: ^Frame) {
    for material, &meshes in f.action {
        for mesh, &instances in meshes {
            for instance in instances {
                if instance.bones != nil {
                    delete(instance.bones)
                }
            }
            clear(&instances)
        }
    }
}

Draw_Call :: struct {
    mesh: Mesh,
    material: Material,
    instances: []Instance,
    skeletons: []matrix[4,4]f32,
}

//embarassingly parallel.
compute_draw_calls :: proc(batches: []Mesh_Batch, camera: Camera) -> []Draw_Call {
    draws := make([dynamic]Draw_Call)
    for batch, i in batches {
        trans := batch.mesh.is_trans || batch.material.base_color.is_trans
        solid := batch.mesh.is_solid || batch.material.base_color.is_solid
        instances := make([dynamic]Instance)
        skeletons := make([dynamic]matrix[4,4]f32)
        for instance in batch.instances {
            instance_is_trans := instance.base_color_tint.a > 0 && instance.base_color_tint.a < 1
            instance_is_solid := instance.base_color_tint.a == 1
            if !trans && !solid && !instance_is_trans && !instance_is_solid {
                //don't render a totally invisible mesh
                continue;
            }
            instance := instance
            //check it against frustum before doing world calculations
            //if it passes, compute billboards/modelview/etc.
            if bounds_in_frustum(camera, instance.bounding_box) {
                calculate_mesh_world(&instance, camera)
                append(&instances, instance)
                if instance.bones == nil {
                    append(&skeletons, 1)
                } else {
                    append(&skeletons, ..instance.bones)
                }
            }
        }
        if len(instances) == 0 {
            delete(instances)
        } else {
            append(&draws, Draw_Call{batch.mesh, batch.material, instances[:], skeletons[:]})
        }
    }
    return draws[:]
}
delete_draw_calls :: proc(draws: []Draw_Call) {
    for d in draws {
        delete(d.instances)
        delete(d.skeletons)
    }
    delete(draws)
}

execute_draw_calls :: proc(render_pass: wgpu.RenderPassEncoder, draws: []Draw_Call) {
    //lights and cameras are already bound at this point.
    prev_material: Material_Hash
    prev_mesh: Mesh_Hash
    for draw in draws {
        if prev_material == 0 || draw.material.hash != prev_material {
            bind_material(render_pass, 1, draw.material)
        }
        if prev_mesh == 0 || draw.mesh.hash != prev_mesh {
            bind_mesh(render_pass, draw.mesh)
        }
        bind_skeletons(render_pass, 3, draw.skeletons, u32(len(draw.instances)))
        draw_mesh_instances(render_pass, draw.mesh, draw.instances)
    }
}

render_frame :: proc(frame: Frame) {

    //context.allocator = context.temp_allocator
    //defer free_all(context.temp_allocator)

    defer delete_frame(frame)

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


    //begin with a simple full-screen clear pass
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

    //next get started going through the current frame's render batches...

    batches := flatten_action(frame)
    defer delete(batches)

    //go through lights & render shadow maps...
    //shadow_mapping_pass := wgpu.CommandEncoderBeginRenderPass(...)
    //wgpu.RenderPassEncoderSetPipeline(shadow_mapping_pass, shadow_mapping_pipeline)
    /*for light in frame.point_lights {
        if !light.has_shadows {
            continue
        }
        light_camera := Camera{} //might be multiple if point light / cascaded

        //set render target...
        
        draws := compute_draw_calls(batches, light_camera)
        defer delete_draw_calls(draws)
        execute_draw_calls(draws)
    }*/

    lights := calculate_lights(frame.lights[:])
    defer delete_lights(lights)

    for camera in frame.cameras {

        //gather all draw calls...
        all_draws := compute_draw_calls(batches, camera)
        defer delete_draw_calls(all_draws)

        lights := calculate_lights_uniforms(lights, camera)
        defer delete_lights_uniforms(lights)

        //perform solid pass
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
        wgpu.RenderPassEncoderSetPipeline(render_pass, ren.solid_pipeline)
        bind_camera(render_pass, 0, camera)
        bind_lights(render_pass, 2, lights)
        solid_draws := make([dynamic]Draw_Call)
        defer delete_draw_calls(solid_draws[:])
        for draw in all_draws {
            skeleton_size := 0
            if draw.skeletons != nil {
                skeleton_size = len(draw.skeletons)/len(draw.instances)
            }
            instances := make([dynamic]Instance)
            skeletons := make([dynamic]matrix[4,4]f32)
            for instance, i in draw.instances {
                if (draw.mesh.is_solid || draw.material.base_color.is_solid) &&
                    instance.base_color_tint.a == 1 {
                    append(&instances, instance)
                    if draw.skeletons != nil {
                        base := i*skeleton_size
                        append(&skeletons, ..draw.skeletons[base:base+skeleton_size])
                    }
                }
            }
            if len(instances) == 0 {
                delete(instances)
                delete(skeletons)
            } else {
                append(&solid_draws, Draw_Call{draw.mesh, draw.material, instances[:], skeletons[:]})
            }
        }
        execute_draw_calls(render_pass, solid_draws[:])
        wgpu.RenderPassEncoderEnd(render_pass)
        wgpu.RenderPassEncoderRelease(render_pass)

        //then perform trans pass
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
        render_pass = wgpu.CommandEncoderBeginRenderPass(command_encoder, &{
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
        wgpu.RenderPassEncoderSetPipeline(render_pass, ren.trans_pipeline)
        bind_camera(render_pass, 0, camera)
        bind_lights(render_pass, 2, lights)
        trans_draws := make([dynamic]Draw_Call)
        defer delete_draw_calls(trans_draws[:])
        for draw in all_draws {
            skeleton_size := 0
            if draw.skeletons != nil {
                skeleton_size = len(draw.skeletons)/len(draw.instances)
            }
            instances := make([dynamic]Instance)
            skeletons := make([dynamic]matrix[4,4]f32)
            for instance, i in draw.instances {
                if draw.mesh.is_trans || draw.material.base_color.is_trans ||
                    (instance.base_color_tint.a > 0 && instance.base_color_tint.a < 1) {
                    append(&instances, instance)
                    if draw.skeletons != nil {
                        base := i*skeleton_size
                        append(&skeletons, ..draw.skeletons[base:base+skeleton_size])
                    }
                }
            }
            if len(instances) == 0 {
                delete(instances)
                delete(skeletons)
            } else {
                append(&trans_draws, Draw_Call{draw.mesh, draw.material, instances[:], skeletons[:]})
            }
        }
        execute_draw_calls(render_pass, trans_draws[:])
        wgpu.RenderPassEncoderEnd(render_pass)
        wgpu.RenderPassEncoderRelease(render_pass)
    }

    //finally, execute the composite pass
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

    //render the UI on top of everything else
    render_ui(screen, command_encoder)

    //then blast it!!!
    command_buffer := wgpu.CommandEncoderFinish(command_encoder)
    defer wgpu.CommandBufferRelease(command_buffer)

    wgpu.QueueSubmit(ren.queue, {command_buffer})
    wgpu.SurfacePresent(ren.surface)

    //cleanup...
    //clear(&frame.cameras)
    //clear(&frame.lights)
    //clear_action(frame)
}
