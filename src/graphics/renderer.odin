package graphics

import "core:log"
import "base:runtime"

import "vendor:wgpu"
import "core:math"
import "core:math/linalg"
import "core:slice"

//whoa we did it we imported another cookies package in a cookies package
import "cookies:transform"

Renderer :: struct {
    ctx: runtime.Context,
    instance: wgpu.Instance,
    adapter: wgpu.Adapter,
    device: wgpu.Device,
    surface: wgpu.Surface,
    main_textures: Main_Textures,
    config: wgpu.SurfaceConfiguration,
    queue: wgpu.Queue,
    shader: wgpu.ShaderModule,
    oit_composite_shader: wgpu.ShaderModule,
    camera_fill_shader: wgpu.ShaderModule,
    layout: wgpu.PipelineLayout,
    oit_composite_layout: wgpu.PipelineLayout,
    oit_composite_pipeline: wgpu.RenderPipeline,
    oit_composite_bind_group_layout: wgpu.BindGroupLayout,
    camera_fill_layout: wgpu.PipelineLayout,
    camera_fill_pipeline: wgpu.RenderPipeline,
    ready: bool,
}
ren: Renderer

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

create_pipeline :: proc(cull_mode: Cull_Mode, topology: Mesh_Topology) -> (solid, trans: wgpu.RenderPipeline) {
    constants := []wgpu.ConstantEntry{
        {key = "TOPOLOGY", value = topology_constant[topology]}
    }
    solid = wgpu.DeviceCreateRenderPipeline(ren.device, &{
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
            constantCount = len(constants),
            constants = raw_data(constants),
        },
        primitive = {
            topology = wgpu_topology[topology],
            cullMode = wgpu_cull_mode[cull_mode],
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
    trans = wgpu.DeviceCreateRenderPipeline(ren.device, &{
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
            constantCount = len(constants),
            constants = raw_data(constants),
        },
        primitive = {
            topology = wgpu_topology[topology],
            cullMode = wgpu_cull_mode[cull_mode],
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
    return
}

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

    ren.oit_composite_shader = wgpu.DeviceCreateShaderModule(ren.device, &{
        nextInChain = &wgpu.ShaderSourceWGSL{
            sType = .ShaderSourceWGSL,
            code = #load("oit_composite.wgsl"),
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
    camera_bg_layout = wgpu.DeviceCreateBindGroupLayout(ren.device, &{
        entryCount = len(camera_bg_layout_entries),
        entries = raw_data(camera_bg_layout_entries),
    })
    material_layout = wgpu.DeviceCreateBindGroupLayout(ren.device, &{
        entryCount = len(material_layout_entries),
        entries = raw_data(material_layout_entries),
    })
    instances_layout = wgpu.DeviceCreateBindGroupLayout(ren.device, &{
        entryCount = len(instances_layout_entries),
        entries = raw_data(instances_layout_entries),
    })
    lights_layout = wgpu.DeviceCreateBindGroupLayout(ren.device, &{
        entryCount = len(lights_layout_entries),
        entries = raw_data(lights_layout_entries),
    })

    bind_group_layouts := []wgpu.BindGroupLayout{camera_layout, material_layout, instances_layout, lights_layout}
    ren.layout = wgpu.DeviceCreatePipelineLayout(ren.device, &{
        bindGroupLayoutCount = len(bind_group_layouts),
        bindGroupLayouts = raw_data(bind_group_layouts),
    })

    log.debug("creating pipelines table...")
    create_pipeline_table()


    log.debug("creating compositor...")
    oit_composite_layout_entries := []wgpu.BindGroupLayoutEntry{
        //accum
        wgpu.BindGroupLayoutEntry{
            binding = 0,
            visibility = {.Fragment},
            texture = {sampleType = .UnfilterableFloat, viewDimension = ._2D, multisampled = true},
        },
        //revealage
        wgpu.BindGroupLayoutEntry{
            binding = 1,
            visibility = {.Fragment},
            texture = {sampleType = .UnfilterableFloat, viewDimension = ._2D, multisampled = true},
        },
    }
    ren.oit_composite_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(ren.device, &{
        entryCount = len(oit_composite_layout_entries),
        entries = raw_data(oit_composite_layout_entries),
    })
    ren.oit_composite_layout = wgpu.DeviceCreatePipelineLayout(ren.device, &{
        bindGroupLayoutCount = 1,
        bindGroupLayouts = &ren.oit_composite_bind_group_layout,
    })
    ren.oit_composite_pipeline = wgpu.DeviceCreateRenderPipeline(ren.device, &{
        label = "OIT composite",
        layout = ren.oit_composite_layout,
        vertex = {
            module = ren.oit_composite_shader,
            entryPoint = "vs_main",
            bufferCount = 0,
        },
        fragment = &{
            module = ren.oit_composite_shader,
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

    log.debug("creating camera fill pipeline...")
    camera_fill_layouts := []wgpu.BindGroupLayout{camera_layout, camera_bg_layout}
    ren.camera_fill_layout = wgpu.DeviceCreatePipelineLayout(ren.device, &{
        bindGroupLayoutCount = len(camera_fill_layouts),
        bindGroupLayouts = raw_data(camera_fill_layouts),
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
        depthStencil = &{
            format = .Depth24PlusStencil8,
            depthWriteEnabled = .True,
            depthCompare = .Always,
        },
        multisample = {
            count = 4,
            mask = 0xffffffff,
        },
    })

    log.debug("setting up screen textures...")
    configure_screen_textures()

    init_defaults()
    init_ui()

    make_mipmapping()

    make_probe_capture()

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
    when ODIN_OS != .JS {
        wgpu.SetLogLevel(.Warn)
        wgpu.SetLogCallback(proc "c" (level: wgpu.LogLevel, message: wgpu.StringView, userdata: rawptr) {
            context = ctx
            log.warn(message)
        }, nil)
    }
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
    delete_probe_capture()
    destroy_pipeline_table()
    wgpu.PipelineLayoutRelease(ren.layout)
    wgpu.RenderPipelineRelease(ren.oit_composite_pipeline)
    wgpu.PipelineLayoutRelease(ren.oit_composite_layout)
    wgpu.BindGroupLayoutRelease(ren.oit_composite_bind_group_layout)
    wgpu.RenderPipelineRelease(ren.camera_fill_pipeline)
    wgpu.PipelineLayoutRelease(ren.camera_fill_layout)
    wgpu.ShaderModuleRelease(ren.shader)
    wgpu.ShaderModuleRelease(ren.oit_composite_shader)
    wgpu.ShaderModuleRelease(ren.camera_fill_shader)
    delete_main_textures(ren.main_textures)
    delete_mipmapping()
    delete_cull_bindings()
    delete_renderer_bindings()

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

    sort_batches()
    sort_passes()
    resolve_passes(screen)
    bin_lights()
    write_instance_buffers()
    write_camera_buffer()
    write_light_buffers(command_encoder)
    //cull_instances_cpu()
    cull_instances_gpu(command_encoder)

    for p in pass_range(.Shadow) {
        //pass := f.passes[p]
        //draw_shadow_pass(command_encoder, pass.stage.(Shadow_Pass), pass.first_cam, pass.cam_count)
        //or just pass.first_cam
    }
    CAPTURE_BOUNCE :: 1
    for _ in 0..<CAPTURE_BOUNCE {
        for p in pass_range(.Capture) {
            pass := f.passes[p]
            stage := pass.stage.(Capture_Pass)
            draw_main_pass(command_encoder, stage, pass.first_cam, pass.cam_count)
            resolve_capture(command_encoder, stage)
        }
    }
    for p in pass_range(.Screen) {
        pass := f.passes[p]
        draw_main_pass(command_encoder, pass.stage.(Screen_Pass), pass.first_cam, pass.cam_count)
    }

    //render the UI on top of everything else
    render_ui(screen, command_encoder)
}
