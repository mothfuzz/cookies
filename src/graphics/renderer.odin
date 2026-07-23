package graphics

import "core:log"
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
    accum_resolve: Texture,
    revealage: Texture,
    revealage_resolve: Texture,
    config: wgpu.SurfaceConfiguration,
    queue: wgpu.Queue,
    shader: wgpu.ShaderModule,
    composite_shader: wgpu.ShaderModule,
    camera_fill_shader: wgpu.ShaderModule,
    layout: wgpu.PipelineLayout,
    solid_pipeline: wgpu.RenderPipeline,
    trans_pipeline: wgpu.RenderPipeline,
    composite_layout: wgpu.PipelineLayout,
    composite_pipeline: wgpu.RenderPipeline,
    composite_bind_group_layout: wgpu.BindGroupLayout,
    composite_bind_group: wgpu.BindGroup,
    composite_sampler: wgpu.Sampler,
    camera_fill_layout: wgpu.PipelineLayout,
    camera_fill_pipeline: wgpu.RenderPipeline,
    using shadows: Shadow_Renderer,
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

screen_resolution: [2]uint

tex_format: wgpu.TextureFormat
view_format: wgpu.TextureFormat
configure_surface :: proc(size: [2]uint = 0) {
    if size != 0 {
        screen_resolution = size
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

configure_render_targets :: proc() {
    log.debug("creating render targets:", ren.config.width, "x", ren.config.height)
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
    ren.depth_buffer = make_render_texture({uint(ren.config.width), uint(ren.config.height)}, .Depth24PlusStencil8, true)

    if ren.accum.image != nil {
        delete_texture(ren.accum)
    }
    ren.accum = make_render_texture({uint(ren.config.width), uint(ren.config.height)}, .RGBA16Float, true)
    ren.accum_resolve = make_render_texture({uint(ren.config.width), uint(ren.config.height)}, .RGBA16Float)
    if ren.revealage.image != nil {
        delete_texture(ren.revealage)
    }
    ren.revealage = make_render_texture({uint(ren.config.width), uint(ren.config.height)}, .R8Unorm, true)
    ren.revealage_resolve = make_render_texture({uint(ren.config.width), uint(ren.config.height)}, .R8Unorm)

    //only re-bind when those textures actually change.
    if ren.composite_bind_group != nil {
        wgpu.BindGroupRelease(ren.composite_bind_group)
    }
    composite_bindings := []wgpu.BindGroupEntry{
        {binding = 0, sampler=ren.composite_sampler},
        {binding = 1, textureView=ren.accum_resolve.view},
        {binding = 2, textureView=ren.revealage_resolve.view},
    }
    ren.composite_bind_group = wgpu.DeviceCreateBindGroup(ren.device, &{
        layout = ren.composite_bind_group_layout,
        entryCount = len(composite_bindings),
        entries = raw_data(composite_bindings),
    })
}

@(private)
request_adapter :: proc "c" (status: wgpu.RequestAdapterStatus, adapter: wgpu.Adapter, message: string, userdata1, userdata2: rawptr) {
    context = (^runtime.Context)(userdata1)^
    if status != .Success || adapter == nil {
        log.panic(message)
    }
    ren.adapter = adapter
    wgpu.AdapterRequestDevice(ren.adapter, nil, {callback = request_device, userdata1=userdata1})
}

uniform_alignment: int
storage_alignment: int

@(private)
request_device :: proc "c" (status: wgpu.RequestDeviceStatus, device: wgpu.Device, message: string, userdata1, userdata2: rawptr) {
    context = (^runtime.Context)(userdata1)^
    if status != .Success || device == nil {
        log.panic(message)
    }
    ren.device = device

    //print limits
    limits, _ := wgpu.DeviceGetLimits(ren.device)
    log.debug("max uniform buffers:", limits.maxUniformBuffersPerShaderStage)
    log.debug("max uniform buffer size:", limits.maxUniformBufferBindingSize, "bytes")
    uniform_alignment = int(limits.minUniformBufferOffsetAlignment)
    log.debug("min uniform buffer offset alignment:", uniform_alignment, "bytes")
    log.debug("max storage buffers:", limits.maxStorageBuffersPerShaderStage)
    log.debug("max storage buffer size:", limits.maxStorageBufferBindingSize, "bytes")
    storage_alignment = int(limits.minStorageBufferOffsetAlignment)
    log.debug("min storage buffer offset alignment:", storage_alignment, "bytes")
    log.debug("max vertex buffers:", limits.maxVertexBuffers)
    log.debug("max vertex buffer size:", limits.maxBufferSize, "bytes")
    log.debug("max vertex attributes:", limits.maxVertexAttributes)

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

    ren.camera_fill_shader = wgpu.DeviceCreateShaderModule(ren.device, &{
        nextInChain = &wgpu.ShaderSourceWGSL{
            sType = .ShaderSourceWGSL,
            code = #load("camera_fill.wgsl"),
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
    skeletons_layout = wgpu.DeviceCreateBindGroupLayout(ren.device, &{
        entryCount = len(skeletons_layout_entries),
        entries = raw_data(skeletons_layout_entries),
    })
    lights_layout = wgpu.DeviceCreateBindGroupLayout(ren.device, &{
        entryCount = len(lights_layout_entries),
        entries = raw_data(lights_layout_entries),
    })

    bind_group_layouts := []wgpu.BindGroupLayout{camera_layout, material_layout, skeletons_layout, lights_layout}
    ren.layout = wgpu.DeviceCreatePipelineLayout(ren.device, &{
        bindGroupLayoutCount = len(bind_group_layouts),
        bindGroupLayouts = raw_data(bind_group_layouts),
    })

    //vertex data
    vertex_buffers := []wgpu.VertexBufferLayout{
        position_attribute,
        texcoord_attribute,
        color_attribute,
        instance_data_attribute,
    }

    log.debug("creating solid pipeline...")
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
            cullMode = .Back,
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

    log.debug("creating trans pipeline...")
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
            cullMode = .Back,
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

    log.debug("creating compositor...")
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
                        //srcFactor = .OneMinusSrcAlpha,
                        //dstFactor = .SrcAlpha,
                        srcFactor = .One,
                        dstFactor = .OneMinusSrcAlpha,
                    },
                    alpha = wgpu.BlendComponent{
                        operation = .Add,
                        //srcFactor = .OneMinusSrcAlpha,
                        //dstFactor = .SrcAlpha,
                        srcFactor = .One,
                        dstFactor = .OneMinusSrcAlpha,
                    },
                },
            },
        },
        primitive = {
            topology = .TriangleList,
            cullMode = .Back,
            frontFace = .CW,
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

    log.debug("creating camera fill pipeline...")
    camera_fill_layout_entries := []wgpu.BindGroupLayoutEntry{
        wgpu.BindGroupLayoutEntry{
            binding = 0,
            visibility = {.Fragment},
            buffer = {type = .Uniform}
        }
    }
    ren.camera_fill_layout = wgpu.DeviceCreatePipelineLayout(ren.device, &{
        bindGroupLayoutCount = 1,
        bindGroupLayouts = &camera_layout,
    })
    ren.camera_fill_pipeline = wgpu.DeviceCreateRenderPipeline(ren.device, &{
        label = "camera_fill",
        layout = ren.camera_fill_layout,
        vertex = {
            module = ren.camera_fill_shader,
            entryPoint = "vs_main",
            bufferCount = 0,
        },
        fragment = &{
            module = ren.camera_fill_shader,
            entryPoint = "fs_main",
            targetCount = 1,
            targets = &wgpu.ColorTargetState{
                format = with_srgb(ren.config.format),
                writeMask = wgpu.ColorWriteMaskFlags_All,
            },
        },
        primitive = {
            topology = .TriangleList,
            cullMode = .Back,
            frontFace = .CW,
        },
        depthStencil = nil,
        multisample = {
            count = 4,
            mask = 0xffffffff,
        },
    })

    log.debug("creating shadow renderer...")
    init_shadows()

    log.debug("setting up render targets...")
    configure_render_targets()

    init_defaults()
    init_ui()

    realloc_skeletons_buffer(0) //need minimum size for valid bindings

    ren.ready = true
    log.debug("renderer SAYS it's ready.")
    log.debug(status)
    log.debug("GPU device address:", ren.device)

}

ctx: runtime.Context
init :: proc(surface_proc: proc(wgpu.Instance)->wgpu.Surface, size: [2]uint) {
    screen_resolution = size
    ren.instance = wgpu.CreateInstance(nil)
    if ren.instance == nil {
        log.panic("WebGPU not supported.")
    }
    ren.surface = surface_proc(ren.instance)
    ctx = context
    wgpu.InstanceRequestAdapter(ren.instance, &{compatibleSurface = ren.surface}, {callback=request_adapter, userdata1=&ctx})
}

when ODIN_OS != .JS {
    wait_idle :: proc() {
        if !ren.ready do return
        for !wgpu.DevicePoll(ren.device, true) {}
    }
} else {
    wait_idle :: proc() {}
}


quit :: proc() {
    if !ren.ready do return

    delete_frame()
    delete_ui()
    delete_defaults()
    delete_lights_buffer()
    delete_skeletons_buffer()
    delete_instance_buffer()
    wgpu.RenderPipelineRelease(ren.solid_pipeline)
    wgpu.RenderPipelineRelease(ren.trans_pipeline)
    wgpu.PipelineLayoutRelease(ren.layout)
    wgpu.RenderPipelineRelease(ren.composite_pipeline)
    wgpu.PipelineLayoutRelease(ren.composite_layout)
    wgpu.BindGroupLayoutRelease(ren.composite_bind_group_layout)
    wgpu.BindGroupRelease(ren.composite_bind_group)
    wgpu.SamplerRelease(ren.composite_sampler)
    wgpu.RenderPipelineRelease(ren.camera_fill_pipeline)
    wgpu.PipelineLayoutRelease(ren.camera_fill_layout)
    wgpu.BindGroupLayoutRelease(camera_layout)
    wgpu.BindGroupLayoutRelease(material_layout)
    wgpu.BindGroupLayoutRelease(skeletons_layout)
    wgpu.BindGroupLayoutRelease(lights_layout)
    wgpu.ShaderModuleRelease(ren.shader)
    wgpu.ShaderModuleRelease(ren.composite_shader)
    wgpu.ShaderModuleRelease(ren.camera_fill_shader)
    wgpu.TextureViewRelease(ren.msaa_view)
    wgpu.TextureRelease(ren.msaa_tex)
    delete_texture(ren.depth_buffer)
    delete_texture(ren.accum)
    delete_texture(ren.revealage)
    delete_shadows()

    //safely clean up resources prior to releasing
    wgpu.SurfaceUnconfigure(ren.surface)

    wgpu.SurfaceRelease(ren.surface)
    wgpu.QueueRelease(ren.queue)
    wgpu.DeviceRelease(ren.device)
    wgpu.AdapterRelease(ren.adapter)
    wgpu.InstanceRelease(ren.instance)
    ren.ready = false //necessary if we want to re-boot it
}

//now for the good part!

Frame :: struct {
    lights: [dynamic]Light_Draw,
    cameras: [dynamic]Camera_Draw,
    action: map[Material_Hash]map[Mesh_Hash][dynamic]Mesh_Draw,
    //resources
    meshes: map[Mesh_Hash]Mesh,
    materials: map[Material_Hash]Material,
    render_targets: map[Render_Target_Hash]Render_Target_Draw,
    screen_target: Render_Target_Draw,
}

@(private)
delete_frame :: proc() {
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
    for _, render_target in frame.render_targets {
        delete(render_target.cameras)
    }
    delete(frame.render_targets)
    delete(frame.screen_target.cameras)
}

@(private)
clear_frame :: proc() {
    clear(&frame.lights)
    clear(&frame.cameras)
    clear_action(&frame)
    clear(&frame.meshes)
    clear(&frame.materials)
    for _, render_target in frame.render_targets {
        delete(render_target.cameras)
    }
    clear(&frame.render_targets)
    clear(&frame.screen_target.cameras)
}

//static frame so commands can be called context-free
frame: Frame

@(export)
draw_point_light :: proc(light: Point_Light, trans: matrix[4,4]f32 = 1, layers: Layer_Mask = All_Layers) {
    append(&frame.lights, Light_Draw{light, trans, layers})
}
@(export)
draw_directional_light :: proc(light: Directional_Light, trans: matrix[4,4]f32 = 1, layers: Layer_Mask = All_Layers) {
    append(&frame.lights, Light_Draw{light, trans, layers})
}
@(export)
draw_spot_light :: proc(light: Spot_Light, trans: matrix[4,4]f32 = 1, layers: Layer_Mask = All_Layers) {
    append(&frame.lights, Light_Draw{light, trans, layers})
}
draw_light :: proc{draw_point_light, draw_directional_light, draw_spot_light}

@(export)
draw_camera :: proc(camera: Camera, trans: matrix[4,4]f32 = 1, layers: Layer_Mask = All_Layers) {
    camera := camera
    if layers != All_Layers {
        camera.layer_mask = layers
    }
    append(&frame.screen_target.cameras, len(frame.cameras))
    append(&frame.cameras, calculate_camera(camera, trans)) //compute once, don't defer
}

@(export)
draw_render_target :: proc(camera: Camera, target: Render_Target, trans: matrix[4,4]f32 = 1, layers: Layer_Mask = All_Layers) {
    target := target
    camera := calculate_camera(camera, trans, &target)
    if layers != All_Layers {
        camera.layer_mask = layers
    }
    if !(target.hash in frame.render_targets) {
        frame.render_targets[target.hash] = {
            target.output.view,
            target.msaa.view,
            target.depth.view,
            target.accum.view,
            target.accum_resolve.view,
            target.revealage.view,
            target.revealage_resolve.view,
            target.composite_bind_group,
            make([dynamic]int),
        }
    }
    render_target := &frame.render_targets[target.hash]
    append(&render_target.cameras, len(frame.cameras))
    append(&frame.cameras, camera)
}


@(export)
draw_mesh :: proc(mesh: Mesh, material: Material, transform: matrix[4,4]f32 = 1,
                  clip_rect: [4]f32 = 0,
                  base_color_tint: [4]f32 = 1,
                  ambient_tint: f32 = 1, roughness_tint: f32 = 1, metallic_tint: f32 = 1,
                  emissive_tint: [3]f32 = 1,
                  sprite: bool = false, billboard: bool = false,
                  bones: []matrix[4,4]f32 = nil, layers: Layer_Mask = All_Layers) {
    //make sure resources are set
    if !(mesh.hash in frame.meshes) {
        frame.meshes[mesh.hash] = mesh
    }
    if !(material.hash in frame.materials) {
        frame.materials[material.hash] = material
    }

    //get the batch
    if frame.action == nil {
        frame.action = make(map[Material_Hash]map[Mesh_Hash][dynamic]Mesh_Draw)
    }
    if !(material.hash in frame.action) {
        frame.action[material.hash] = make(map[Mesh_Hash][dynamic]Mesh_Draw)
    }
    meshes := &frame.action[material.hash]
    if !(mesh.hash in meshes) {
        meshes[mesh.hash] = make([dynamic]Mesh_Draw)
    }
    instances := &meshes[mesh.hash]

    pbr_tint := [4]f32{ambient_tint, roughness_tint, metallic_tint, 1}
    emissive_tint := [4]f32{emissive_tint.r, emissive_tint.g, emissive_tint.b, 1}
    dynamic_material := Dynamic_Material{clip_rect, base_color_tint, pbr_tint, emissive_tint}

    bones := bones
    if bones != nil {
        //hate this but we gotta
        owned_bones := make([]matrix[4,4]f32, len(bones))
        copy(owned_bones, bones)
        bones = owned_bones
    }
    draw := Mesh_Draw{{transform, dynamic_material, 0}, sprite, billboard, bones, {}, layers}
    calculate_mesh_local(&draw, mesh, material)

    append(instances, draw)
}

//sprites are just special kinds of meshes
@(export)
draw_sprite :: proc(material: Material, transform: matrix[4, 4]f32 = 1,
                    clip_rect: [4]f32 = 0,
                    base_color_tint: [4]f32 = 1,
                    ambient_tint: f32 = 1, roughness_tint: f32 = 1, metallic_tint: f32 = 1,
                    emissive_tint: [3]f32 = 1,
                    billboard: bool = true, layers: Layer_Mask = All_Layers) {
    draw_mesh(quad_mesh, material, transform, clip_rect,
              base_color_tint, ambient_tint, roughness_tint, metallic_tint, emissive_tint,
              true, billboard, nil, layers)
}

@(private)
Mesh_Batch :: struct {
    mesh: Mesh,
    material: Material,
    instances: []Mesh_Draw,
}
@(private)
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
@(private)
clear_action :: proc(f: ^Frame) {
    if f.action == nil do return
    for _, &meshes in f.action {
        for _, &instances in meshes {
            for instance in instances {
                if instance.bones != nil {
                    delete(instance.bones)
                }
            }
            clear(&instances)
        }
    }
}

write_skeletons :: proc(batches: []Mesh_Batch) {
    //all the skeletons at once.
    running_offset := 0
    for &batch in batches {
        for &draw in batch.instances {
            if draw.bones == nil do continue
            draw.skeleton_offset[0] = u32(running_offset)
            running_offset += len(draw.bones)
        }
    }
    realloc_skeletons_buffer(running_offset)
    for batch in batches {
        for draw in batch.instances {
            if draw.bones == nil do continue
            offset := draw.skeleton_offset[0] * size_of(matrix[4,4]f32)
            size := len(draw.bones) * size_of(matrix[4,4]f32)
            wgpu.QueueWriteBuffer(ren.queue, skeletons_buffer, u64(offset), raw_data(draw.bones), uint(size))
        }
    }
}

@(private)
Draw_Call :: struct {
    mesh: Mesh,
    material: Material,
    //offset insto pass's staging buffer
    first_instance: u32,
    instance_count: u32,
    //offset into mesh's instance_buffer
    instance_buffer_offset: u64,
}


@(private)
instance_filter :: proc(mesh: Mesh, material: Material, instance: Instance) -> (is_solid, is_trans: bool) {
    is_solid = (mesh.is_solid || material.base_color_tex.is_solid) && instance.base_color_tint.a == 1
    is_trans = mesh.is_trans || material.base_color_tex.is_trans || (instance.base_color_tint.a > 0 && instance.base_color_tint.a < 1)
    return
}

Pass :: struct {
    buffer_offset: u64,
    instances: []Instance,
    draw_calls: []Draw_Call,
}

//passes slice into instance buffer per-camera
Passes :: struct {
    solid_shadows: []Pass,
    trans_shadows: []Pass,
    solid_main: []Pass,
    trans_main: []Pass,
}

//need separate staging so that each pass 'knows' what slice of instances it has.
Pass_Staging :: struct {
    instances: [dynamic]Instance,
    draw_calls: [dynamic]Draw_Call,
}

@(private)
compute_pass :: proc(batches: []Mesh_Batch, cam: Camera_Draw, solid, trans: ^Pass_Staging) {
    for batch in batches {
        solid_start, trans_start: u32
        if solid != nil {
            solid_start = u32(len(solid.instances))
        }
        if trans != nil {
            trans_start = u32(len(trans.instances))
        }

        for instance in batch.instances {
            if (cam.layer_mask & instance.layer_mask) == 0 do continue
            instance := instance
            is_solid, is_trans := instance_filter(batch.mesh, batch.material, instance)
            if !is_solid && !is_trans do continue
            if !bounds_in_frustum(cam, instance.bounding_box) do continue
            calculate_mesh_world(&instance, cam)
            if is_solid && solid != nil {
                append(&solid.instances, instance)
            }
            if is_trans && trans != nil {
                append(&trans.instances, instance)
            }
        }

        solid_count, trans_count: u32
        if solid != nil {
            solid_count = u32(len(solid.instances)) - solid_start
        }
        if trans != nil {
            trans_count = u32(len(trans.instances)) - trans_start
        }

        if solid_count > 0 {
            append(&solid.draw_calls, Draw_Call{
                mesh = batch.mesh, material = batch.material,
                first_instance = solid_start,
                instance_count = solid_count,
            })
        }
        if trans_count > 0 {
            append(&trans.draw_calls, Draw_Call{
                mesh = batch.mesh, material = batch.material,
                first_instance = trans_start,
                instance_count = trans_count,
            })
        }
    }
}

@(private)
write_pass :: proc(pass: ^Pass, staging: ^Pass_Staging, running_offset: ^u64) {
    pass.buffer_offset = running_offset^
    pass.instances = staging.instances[:]
    pass.draw_calls = staging.draw_calls[:]
    for &draw in pass.draw_calls {
        draw.instance_buffer_offset = running_offset^ + u64(draw.first_instance) * size_of(Instance)
    }
    running_offset^ += u64(len(pass.instances)) * size_of(Instance)
}

//trying to do this all at once overwhelmed temp_alloc :C
@(private)
write_pass_instances :: proc(pass: ^Pass) {
    if len(pass.instances) == 0 do return
    size := u64(len(pass.instances)) * size_of(Instance)
    wgpu.QueueWriteBuffer(ren.queue, instance_buffer, pass.buffer_offset, raw_data(pass.instances), uint(size))
}

@(private)
compute_passes :: proc(batches: []Mesh_Batch, lights: Lights, cameras: []Camera_Draw) -> (passes: Passes) {
    //the big buffer...
    //[solid shadow cam 0][trans shadow cam 0][solid main cam 0][trans main cam 0][etc.]

    solid_shadows_staging := make([]Pass_Staging, len(lights.shadow_cameras))
    trans_shadows_staging := make([]Pass_Staging, len(lights.shadow_cameras))
    solid_main_staging := make([]Pass_Staging, len(cameras))
    trans_main_staging := make([]Pass_Staging, len(cameras))
    defer delete(solid_shadows_staging)
    defer delete(trans_shadows_staging)
    defer delete(solid_main_staging)
    defer delete(trans_main_staging)

    //this should ACTUALLY be a single list of Camera_Draw for all shadows. The pass should be 'take a camera, draw a shadow map'
    //no matter how many cameras (1 per spot light, 6 per point light, num_cascades*num_main_cameras per directional light)
    passes.solid_shadows = make([]Pass, len(lights.shadow_cameras))
    passes.trans_shadows = make([]Pass, len(lights.shadow_cameras))
    passes.solid_main = make([]Pass, len(cameras))
    passes.trans_main = make([]Pass, len(cameras))

    //first generate staging buffers
    for cam, i in lights.shadow_cameras {
        compute_pass(batches, cam, &solid_shadows_staging[i], &trans_shadows_staging[i])
    }
    for cam, i in cameras {
        compute_pass(batches, cam, &solid_main_staging[i], &trans_main_staging[i])
    }

    //then actually pack the staging passes to the real passes
    running_offset: u64
    for &pass, i in passes.solid_shadows {
        write_pass(&pass, &solid_shadows_staging[i], &running_offset)
    }
    for &pass, i in passes.trans_shadows {
        write_pass(&pass, &trans_shadows_staging[i], &running_offset)
    }
    for &pass, i in passes.solid_main {
        write_pass(&pass, &solid_main_staging[i], &running_offset)
    }
    for &pass, i in passes.trans_main {
        write_pass(&pass, &trans_main_staging[i], &running_offset)
    }

    realloc_instance_buffer(running_offset)

    //write the vertex buffer...
    for &pass in passes.solid_shadows {
        write_pass_instances(&pass)
    }
    for &pass in passes.trans_shadows {
        write_pass_instances(&pass)
    }
    for &pass in passes.solid_main {
        write_pass_instances(&pass)
    }
    for &pass in passes.trans_main {
        write_pass_instances(&pass)
    }

    return
}

@(private)
delete_pass :: proc(pass: ^Pass) {
    delete(pass.instances)
    delete(pass.draw_calls)
}

@(private)
delete_passes :: proc(passes: Passes) {
    for &pass in passes.solid_shadows {
        delete_pass(&pass)
    }
    for &pass in passes.trans_shadows {
        delete_pass(&pass)
    }
    for &pass in passes.solid_main {
        delete_pass(&pass)
    }
    for &pass in passes.trans_main {
        delete_pass(&pass)
    }
    delete(passes.solid_shadows)
    delete(passes.trans_shadows)
    delete(passes.solid_main)
    delete(passes.trans_main)
}

@(private)
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
        bind_skeletons(render_pass, 2)
        draw_mesh_instances(render_pass, draw.mesh, draw.instance_count, draw.instance_buffer_offset)
    }
}

@(private)
clear_render_target :: proc(command_encoder: wgpu.CommandEncoder, target: Render_Target_Draw) {
    clear_pass := wgpu.CommandEncoderBeginRenderPass(command_encoder, &{
        label = "render_target_clear",
        colorAttachmentCount = 1,
        colorAttachments = &wgpu.RenderPassColorAttachment{
            view = target.msaa,
            resolveTarget = target.output,
            loadOp = .Clear,
            storeOp = .Store,
            depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
            clearValue = {0, 0, 0, 1},
        },
        depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment{
            view = target.depth,
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

    trans_clear_attachments := []wgpu.RenderPassColorAttachment{
        {
            view = target.accum,
            resolveTarget = target.accum_resolve,
            loadOp = .Clear,
            storeOp = .Store,
            depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
            clearValue = {0, 0, 0, 0},
        },
        {
            view = target.revealage,
            resolveTarget = target.revealage_resolve,
            loadOp = .Clear,
            storeOp = .Store,
            depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
            clearValue = {1, 0, 0, 0},
        },
    }
    trans_clear_pass := wgpu.CommandEncoderBeginRenderPass(command_encoder, &{
        label = "render_target_trans_clear",
        colorAttachmentCount = len(trans_clear_attachments),
        colorAttachments = raw_data(trans_clear_attachments),
        depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment{
            view = target.depth,
            depthLoadOp = .Load,
            depthStoreOp = .Store,
            stencilLoadOp = .Load,
            stencilStoreOp = .Store,
        },
    })
    wgpu.RenderPassEncoderEnd(trans_clear_pass)
    wgpu.RenderPassEncoderRelease(trans_clear_pass)
}

render_main_pass :: proc(command_encoder: wgpu.CommandEncoder, cameras: []Camera_Draw, solid_passes, trans_passes: []Pass, target: Render_Target_Draw, draw_solid, draw_trans: bool) {
    //start with a fill pass for each camera marked 'fill'
    //(this is in a separate loop because cameras may have overlapping viewports)
    camera_fill_pass := wgpu.CommandEncoderBeginRenderPass(command_encoder, &{
        label = "camera_fill",
        colorAttachmentCount = 1,
        colorAttachments = &wgpu.RenderPassColorAttachment{
            view = target.msaa,
            resolveTarget = target.output,
            loadOp = .Load,
            storeOp = .Store,
            depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
        },
    })
    wgpu.RenderPassEncoderSetPipeline(camera_fill_pass, ren.camera_fill_pipeline)
    for i in target.cameras {
        camera := cameras[i]
        if !camera.fill do continue
        wgpu.RenderPassEncoderSetBindGroup(camera_fill_pass, 0, camera.bind_group)
        x, y, w, h := expand_values(camera.viewport)
        wgpu.RenderPassEncoderSetViewport(camera_fill_pass, x, y, w, h, 0, 1)
        wgpu.RenderPassEncoderSetScissorRect(camera_fill_pass, u32(x), u32(y), u32(w), u32(h))
        wgpu.RenderPassEncoderDraw(camera_fill_pass, 3, 1, 0, 0)
    }
    wgpu.RenderPassEncoderEnd(camera_fill_pass)
    wgpu.RenderPassEncoderRelease(camera_fill_pass)

    for i in target.cameras {

        camera := cameras[i]

        //perform solid pass
        if draw_solid {
            render_pass := wgpu.CommandEncoderBeginRenderPass(command_encoder, &{
                label = "solid",
                colorAttachmentCount = 1,
                colorAttachments = &wgpu.RenderPassColorAttachment{
                    view = target.msaa,
                    resolveTarget = target.output,
                    loadOp = .Load,
                    storeOp = .Store,
                    depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
                },
                depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment{
                    view = target.depth,
                    depthLoadOp = .Load,
                    depthStoreOp = .Store,
                    stencilLoadOp = .Load,
                    stencilStoreOp = .Store,
                },
            })
            wgpu.RenderPassEncoderSetPipeline(render_pass, ren.solid_pipeline)
            bind_camera(render_pass, 0, camera)
            bind_lights(render_pass, 3, u32(i))
            execute_draw_calls(render_pass, solid_passes[i].draw_calls[:])
            wgpu.RenderPassEncoderEnd(render_pass)
            wgpu.RenderPassEncoderRelease(render_pass)
        }

        //then perform trans pass
        if draw_trans {
            trans_color_attachments := []wgpu.RenderPassColorAttachment{
                //accum
                {
                    view = target.accum,
                    resolveTarget = target.accum_resolve,
                    loadOp = .Load,
                    storeOp = .Store,
                    depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
                },
                //revealage
                {
                    view = target.revealage,
                    resolveTarget = target.revealage_resolve,
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
                    view = target.depth,
                    depthLoadOp = .Load,
                    depthStoreOp = .Store, //remember to disable depth-store for transparent.
                    stencilLoadOp = .Load,
                    stencilStoreOp = .Store,
                },
            })
            wgpu.RenderPassEncoderSetPipeline(render_pass, ren.trans_pipeline)
            bind_camera(render_pass, 0, camera)
            bind_lights(render_pass, 3, u32(i))
            execute_draw_calls(render_pass, trans_passes[i].draw_calls[:])
            wgpu.RenderPassEncoderEnd(render_pass)
            wgpu.RenderPassEncoderRelease(render_pass)
        }
    }

    //finally, execute the composite pass for the output
    if draw_trans {
        composite_pass := wgpu.CommandEncoderBeginRenderPass(command_encoder, &{
            label = "composite",
            colorAttachmentCount = 1,
            colorAttachments = &wgpu.RenderPassColorAttachment{
                view = target.msaa,
                resolveTarget = target.output,
                loadOp = .Load,
                storeOp = .Store,
                depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
            },
        })
        wgpu.RenderPassEncoderSetPipeline(composite_pass, ren.composite_pipeline)
        wgpu.RenderPassEncoderSetBindGroup(composite_pass, 0, target.composite_bind_group)
        wgpu.RenderPassEncoderDraw(composite_pass, 3, 1, 0, 0)
        wgpu.RenderPassEncoderEnd(composite_pass)
        wgpu.RenderPassEncoderRelease(composite_pass)
    }
    
}

@(export)
render_frame :: proc() {
    if !ren.ready do return

    /*allocator := context.allocator
    context.allocator = context.temp_allocator
    defer {
        context.allocator = allocator
        clear_frame()
    }*/
    defer clear_frame()

    
    //prepare the screen surface
    surface_tex := wgpu.SurfaceGetCurrentTexture(ren.surface)
    switch surface_tex.status {
    case .SuccessOptimal, .SuccessSuboptimal:
        //yay...!
    case .Occluded, .Timeout:
        //no drawable this frame, skip it...
        return
    case .Outdated, .Lost:
        if surface_tex.texture != nil {
            wgpu.TextureRelease(surface_tex.texture)
        }
        configure_surface()
        return
    case .Error:
        log.panic("Surface texture lost! Unable to draw to screen.", surface_tex.status)
    }
    if surface_tex.texture == nil do return
    defer wgpu.TextureRelease(surface_tex.texture)
    screen := wgpu.TextureCreateView(surface_tex.texture, &{format=with_srgb(ren.config.format), mipLevelCount=1, arrayLayerCount=1})
    defer wgpu.TextureViewRelease(screen)
    command_encoder := wgpu.DeviceCreateCommandEncoder(ren.device, nil)
    defer wgpu.CommandEncoderRelease(command_encoder)

    //blast it all off at the end of the proc
    defer {
        command_buffer := wgpu.CommandEncoderFinish(command_encoder)
        defer wgpu.CommandBufferRelease(command_buffer)

        wgpu.QueueSubmit(ren.queue, {command_buffer})
        wgpu.SurfacePresent(ren.surface)
    }

    //first things first, begin with a simple clear pass
    clear_pass := wgpu.CommandEncoderBeginRenderPass(command_encoder, &{
        label = "clear",
        colorAttachmentCount = 1,
        colorAttachments = &wgpu.RenderPassColorAttachment{
            view = ren.msaa_view,
            resolveTarget = screen,
            loadOp = .Clear,
            storeOp = .Store,
            depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
            clearValue = {0, 0, 0, 1},
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

    //then execute a clear pass for the main transparent targets as well...
    trans_clear_attachments := []wgpu.RenderPassColorAttachment{
        //accum
        {
            view = ren.accum.view,
            resolveTarget = ren.accum_resolve.view,
            loadOp = .Clear,
            storeOp = .Store,
            depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
            clearValue = {0, 0, 0, 0},
        },
        //revealage
        {
            view = ren.revealage.view,
            resolveTarget = ren.revealage_resolve.view,
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

    //if no cameras we can return early and skip everything
    if len(frame.cameras) == 0 do return

    //master record of mesh draws this frame
    batches := flatten_action(frame)
    defer delete(batches)

    //gather up them bones
    write_skeletons(batches)

    //then gather up all lights
    lights := calculate_lights(frame.lights[:], frame.cameras[:])
    defer delete_lights(lights)

    //compute all instance data for all passes
    passes := compute_passes(batches, lights, frame.cameras[:])
    defer delete_passes(passes)

    //go through lights & render shadow maps...
    shadow_offsets := shadow_offsets(lights, frame.cameras[:])
    for &spot_light, i in lights.spot_lights {
        if spot_light.render_shadows {
            //render to a specific spot in the texture array
            view_descriptor := wgpu.TextureViewDescriptor{
                dimension = ._2D,
                mipLevelCount = 1,
                arrayLayerCount = 1,
                baseArrayLayer=u32(spot_light.shadow_index),
            }
            shadow_color := wgpu.TextureCreateView(ren.spot_light_shadow_color.image, &view_descriptor)
            defer wgpu.TextureViewRelease(shadow_color)
            shadow_depth := wgpu.TextureCreateView(ren.spot_light_shadow_depth.image, &view_descriptor)
            defer wgpu.TextureViewRelease(shadow_depth)

            shadow_index := shadow_offsets.s + spot_light.shadow_index
            camera := lights.shadow_cameras[shadow_index]
            
            solid_shadow_pass := wgpu.CommandEncoderBeginRenderPass(command_encoder, &{
                label = "spot light solid shadows",
                colorAttachmentCount = 1,
                colorAttachments = &wgpu.RenderPassColorAttachment{
                    view = shadow_color,
                    loadOp = .Clear,
                    storeOp = .Store,
                    depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
                    clearValue = [4]f64{1, 1, 1, 1},
                },
                depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment{
                    view = shadow_depth,
                    depthLoadOp = .Clear,
                    depthStoreOp = .Store,
                    depthClearValue = 1.0,
                },
            })
            wgpu.RenderPassEncoderSetPipeline(solid_shadow_pass, ren.solid_shadow_pipeline)

            bind_camera(solid_shadow_pass, 0, camera)
            execute_draw_calls(solid_shadow_pass, passes.solid_shadows[shadow_index].draw_calls[:])

            wgpu.RenderPassEncoderEnd(solid_shadow_pass)
            wgpu.RenderPassEncoderRelease(solid_shadow_pass)

            trans_shadow_pass := wgpu.CommandEncoderBeginRenderPass(command_encoder, &{
                label = "spot light trans shadows",
                colorAttachmentCount = 1,
                colorAttachments = &wgpu.RenderPassColorAttachment{
                    view = shadow_color,
                    loadOp = .Load,
                    storeOp = .Store,
                    depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
                },
                depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment{
                    view = shadow_depth,
                    depthLoadOp = .Load,
                    depthStoreOp = .Store,
                },
            })
            wgpu.RenderPassEncoderSetPipeline(trans_shadow_pass, ren.trans_shadow_pipeline)

            bind_camera(trans_shadow_pass, 0, camera)
            execute_draw_calls(trans_shadow_pass, passes.trans_shadows[shadow_index].draw_calls[:])

            wgpu.RenderPassEncoderEnd(trans_shadow_pass)
            wgpu.RenderPassEncoderRelease(trans_shadow_pass)
        }
    }

    //make sure to upload + offset lights per-camera.
    write_light_buffers(lights, frame.cameras[:], shadow_offsets)

    //now actually render the main passes
    frame.screen_target.output = screen
    frame.screen_target.msaa = ren.msaa_view
    frame.screen_target.depth = ren.depth_buffer.view
    frame.screen_target.accum = ren.accum.view
    frame.screen_target.accum_resolve = ren.accum_resolve.view
    frame.screen_target.revealage = ren.revealage.view
    frame.screen_target.revealage_resolve = ren.revealage_resolve.view
    frame.screen_target.composite_bind_group = ren.composite_bind_group

    //get number of draw calls, in case we need to skip a pass
    draw_solid: bool = false
    for pass in passes.solid_main {
        if len(pass.draw_calls) > 0 {
            draw_solid = true
            break
        }
    }
    draw_trans: bool = false
    for pass in passes.solid_main {
        if len(pass.draw_calls) > 0 {
            draw_trans = true
            break
        }
    }

    //render to custom render targets first
    for hash, target in frame.render_targets {
        clear_render_target(command_encoder, target)
        render_main_pass(command_encoder, frame.cameras[:], passes.solid_main, passes.trans_main, target, draw_solid, draw_trans)
    }

    //then finally render to screen (already cleared above)...
    render_main_pass(command_encoder, frame.cameras[:], passes.solid_main, passes.trans_main, frame.screen_target, draw_solid, draw_trans)

    //render the UI on top of everything else
    render_ui(screen, command_encoder)
}
