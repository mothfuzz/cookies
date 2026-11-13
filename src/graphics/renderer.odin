package graphics

import "core:log"
import "base:runtime"

import "vendor:wgpu"
import "core:math"
import "core:math/linalg"
import "core:slice"

Renderer :: struct {
    ctx: runtime.Context,
    instance: wgpu.Instance,
    adapter: wgpu.Adapter,
    device: wgpu.Device,
    surface: wgpu.Surface,
    msaa_tex: wgpu.Texture, //used for AA resolve on surface
    msaa_view: wgpu.TextureView,
    main_textures: Main_Textures,
    config: wgpu.SurfaceConfiguration,
    queue: wgpu.Queue,
    shader: wgpu.ShaderModule,
    oit_composite_shader: wgpu.ShaderModule,
    camera_fill_shader: wgpu.ShaderModule,
    layout: wgpu.PipelineLayout,
    solid_pipelines: [Cull_Mode]wgpu.RenderPipeline,
    trans_pipelines: [Cull_Mode]wgpu.RenderPipeline,
    solid_lines_pipeline: wgpu.RenderPipeline,
    trans_lines_pipeline: wgpu.RenderPipeline,
    solid_points_pipeline: wgpu.RenderPipeline,
    trans_points_pipeline: wgpu.RenderPipeline,
    oit_composite_layout: wgpu.PipelineLayout,
    oit_composite_pipeline: wgpu.RenderPipeline,
    oit_composite_bind_group_layout: wgpu.BindGroupLayout,
    camera_fill_layout: wgpu.PipelineLayout,
    camera_fill_pipeline: wgpu.RenderPipeline,
    using shadows: Shadow_Renderer,
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

vertex_buffer_layouts := []wgpu.VertexBufferLayout{
    //mesh
    position_attribute,
    normal_attribute,
    tangent_attribute,
    texcoord_attribute,
    color_attribute,
    bones_attribute,
    weights_attribute,
    //instance
    instance_attribute,
}

// TODO: move this and create_shadow_pipeline into pipelines.odin
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

    log.debug("creating main pipelines...")
    for cull_mode in Cull_Mode {
        solid, trans := create_pipeline(cull_mode, .Triangles)
        ren.solid_pipelines[cull_mode] = solid
        ren.trans_pipelines[cull_mode] = trans
    }
    lines_solid, lines_trans := create_pipeline(.None, .Lines)
    ren.solid_lines_pipeline = lines_solid
    ren.trans_lines_pipeline = lines_trans
    points_solid, points_trans := create_pipeline(.None, .Points)
    ren.solid_points_pipeline = points_solid
    ren.trans_points_pipeline = points_trans


    log.debug("creating compositor...")
    oit_composite_layout_entries := []wgpu.BindGroupLayoutEntry{
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
    ren.oit_composite_sampler = wgpu.DeviceCreateSampler(ren.device, &{
        minFilter=.Linear,
        magFilter=.Linear,
        mipmapFilter=.Linear, //don't use mips for fullscreen, dog
        maxAnisotropy=1,
        addressModeU=.ClampToEdge,
        addressModeV=.ClampToEdge,
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
        depthStencil = nil,
        multisample = {
            count = 4,
            mask = 0xffffffff,
        },
    })

    log.debug("creating shadow renderer...")
    init_shadows()

    log.debug("setting up screen textures...")
    configure_screen_textures()

    init_defaults()
    init_ui()

    realloc_skeletons_buffer(0) //need minimum size for valid bindings

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
    delete_lights_buffer()
    delete_skeletons_buffer()
    delete_probe_capture()
    delete_instance_buffer()
    for cull_mode in Cull_Mode {
        wgpu.RenderPipelineRelease(ren.solid_pipelines[cull_mode])
        wgpu.RenderPipelineRelease(ren.trans_pipelines[cull_mode])
    }
    wgpu.RenderPipelineRelease(ren.solid_lines_pipeline)
    wgpu.RenderPipelineRelease(ren.trans_lines_pipeline)
    wgpu.RenderPipelineRelease(ren.solid_points_pipeline)
    wgpu.RenderPipelineRelease(ren.trans_points_pipeline)
    wgpu.PipelineLayoutRelease(ren.layout)
    wgpu.RenderPipelineRelease(ren.oit_composite_pipeline)
    wgpu.PipelineLayoutRelease(ren.oit_composite_layout)
    wgpu.BindGroupLayoutRelease(ren.oit_composite_bind_group_layout)
    wgpu.RenderPipelineRelease(ren.camera_fill_pipeline)
    wgpu.PipelineLayoutRelease(ren.camera_fill_layout)
    wgpu.BindGroupLayoutRelease(camera_layout)
    wgpu.BindGroupLayoutRelease(material_layout)
    wgpu.BindGroupLayoutRelease(skeletons_layout)
    wgpu.BindGroupLayoutRelease(lights_layout)
    wgpu.ShaderModuleRelease(ren.shader)
    wgpu.ShaderModuleRelease(ren.oit_composite_shader)
    wgpu.ShaderModuleRelease(ren.camera_fill_shader)
    wgpu.TextureViewRelease(ren.msaa_view)
    wgpu.TextureRelease(ren.msaa_tex)
    delete_main_textures(ren.main_textures)
    delete_shadows()
    delete_mipmapping()

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

//actual GPU-side representations

Render_Frame :: struct {
    using inst: Instance_Data,
    using lite: Light_Data,
    using pass: Pass_Data,
    using draw: Draw_Data,
}

assign_cubemaps :: proc(f: ^Render_Frame, probes: []Environment_Probe) {
    for c, i in f.culls {
        inst := &f.instances[i]
        inst.probe_a = -1
        inst.probe_b = -1
        for probe in probes {
            mini := probe.position + probe.extents[0]
            maxi := probe.position + probe.extents[1]
            if c.center.x > mini.x &&
                c.center.x < maxi.x &&
                c.center.y > mini.y &&
                c.center.y < maxi.y &&
                c.center.z > mini.z &&
                c.center.z < maxi.z {
                    inst.probe_a = i32(probe.cubemap_slot)
                }
        }
    }
}

@(private)
Draw_Call :: struct {
    mesh: Mesh,
    material: Material,
    cull_mode: Cull_Mode,
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
compute_pass_staging :: proc(batches: []Mesh_Batch, cam: Camera_View, solid, trans: ^Pass_Staging, skip_points_lines: bool = false) {
    cam_flip := linalg.determinant(cast(matrix[3,3]f32)(cam.view)) < 0
    remap := [Cull_Mode]Cull_Mode{
            .Back_CCW = cam_flip ? .Front_CCW : .Back_CCW,
            .Front_CCW = cam_flip ? .Back_CCW : .Front_CCW,
            .None = .None,
    }
    for mode in Cull_Mode {
        for batch in batches {
            if batch.mesh.topology != .Triangles && skip_points_lines do continue
            solid_start, trans_start: u32
            if solid != nil {
                solid_start = u32(len(solid.instances))
            }
            if trans != nil {
                trans_start = u32(len(trans.instances))
            }

            for instance in batch.instances[mode] {
                if (cam.layer_mask & instance.layer_mask) == 0 do continue
                instance := instance
                is_solid, is_trans := instance_filter(batch.mesh, batch.material, instance)
                if !is_solid && !is_trans do continue
                if !sphere_in_frustum(cam, instance.bounding_center, instance.bounding_radius) do continue
                if !bounds_in_frustum(cam, instance.bounding_center, instance.bounding_axes) do continue
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
                    cull_mode = remap[mode],
                    first_instance = solid_start,
                    instance_count = solid_count,
                })
            }
            if trans_count > 0 {
                append(&trans.draw_calls, Draw_Call{
                    mesh = batch.mesh, material = batch.material,
                    cull_mode = remap[mode],
                    first_instance = trans_start,
                    instance_count = trans_count,
                })
            }
        }
    }
}

//write from staging into real pass data
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

//write from pass into instance buffer
//trying to do this all at once overwhelmed temp_alloc :C
@(private)
write_pass_instances :: proc(pass: Pass) {
    if len(pass.instances) == 0 do return
    size := u64(len(pass.instances)) * size_of(Instance)
    wgpu.QueueWriteBuffer(ren.queue, instance_buffer, pass.buffer_offset, raw_data(pass.instances), uint(size))
}

@(private)
compute_passes :: proc(batches: []Mesh_Batch, cameras: []Camera_Draw, shadow_cameras: []Shadow_Camera_Draw) -> (passes: Passes) {
    solid_shadows_staging := make([]Pass_Staging, len(shadow_cameras))
    defer delete(solid_shadows_staging)
    trans_shadows_staging := make([]Pass_Staging, len(shadow_cameras))
    defer delete(trans_shadows_staging)
    solid_main_staging := make([]Pass_Staging, len(cameras))
    defer delete(solid_main_staging)
    trans_main_staging := make([]Pass_Staging, len(cameras))
    defer delete(trans_main_staging)

    passes.solid_main = make([]Pass, len(cameras))
    passes.trans_main = make([]Pass, len(cameras))
    passes.solid_shadows = make([]Pass, len(shadow_cameras))
    passes.trans_shadows = make([]Pass, len(shadow_cameras))

    for cam, i in cameras {
        compute_pass_staging(batches, cam, &solid_main_staging[i], &trans_main_staging[i])
    }
    for cam, i in shadow_cameras {
        compute_pass_staging(batches, cam, &solid_shadows_staging[i], &trans_shadows_staging[i], true)
    }

    //actually pack the staging passes to the real passes
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

    //the big buffer...
    //[solid shadow cam 0][trans shadow cam 0][solid main cam 0][trans main cam 0][etc.]

    realloc_instance_buffer(running_offset)

    //write the vertex buffer...
    for &pass in passes.solid_shadows {
        write_pass_instances(pass)
    }
    for &pass in passes.trans_shadows {
        write_pass_instances(pass)
    }
    for &pass in passes.solid_main {
        write_pass_instances(pass)
    }
    for &pass in passes.trans_main {
        write_pass_instances(pass)
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

Pipelines :: struct {
    main: [Cull_Mode]wgpu.RenderPipeline,
    lines: wgpu.RenderPipeline,
    points: wgpu.RenderPipeline,
}

@(private)
execute_draw_calls :: proc(render_pass: wgpu.RenderPassEncoder, draws: []Draw_Call, pipelines: Pipelines) {
    //lights and cameras are already bound at this point.
    prev_material: Material_Hash
    prev_mesh: Mesh_Hash
    pipeline_set: bool = false
    prev_topology: Mesh_Topology
    prev_cull_mode: Cull_Mode
    bind_instances(render_pass)
    for draw in draws {
        if prev_material == 0 || draw.material.hash != prev_material {
            bind_material(render_pass, 1, draw.material)
            prev_material = draw.material.hash
        }
        if prev_mesh == 0 || draw.mesh.hash != prev_mesh {
            bind_mesh(render_pass, draw.mesh)
            prev_mesh = draw.mesh.hash
        }
        topology := draw.mesh.topology
        if pipeline_set == false || draw.cull_mode != prev_cull_mode || topology != prev_topology {
            switch topology {
            case .Triangles: wgpu.RenderPassEncoderSetPipeline(render_pass, pipelines.main[draw.cull_mode])
            case .Lines: wgpu.RenderPassEncoderSetPipeline(render_pass, pipelines.lines)
            case .Points: wgpu.RenderPassEncoderSetPipeline(render_pass, pipelines.points)
            }
            prev_cull_mode = draw.cull_mode
            prev_topology = draw.mesh.topology
            pipeline_set = true
        }
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
            resolveTarget = target.render_view,
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
            resolveTarget = target.render_view,
            loadOp = .Load,
            storeOp = .Store,
            depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
        },
    })
    wgpu.RenderPassEncoderSetPipeline(camera_fill_pass, ren.camera_fill_pipeline)
    for i in target.cameras {
        camera := cameras[i]
        if !camera.fill do continue
        bind_camera(camera_fill_pass, 0, camera)
        bind_camera_bg(camera_fill_pass, 1, camera)
        //wgpu.RenderPassEncoderSetBindGroup(camera_fill_pass, 0, camera.bind_group)
        //x, y, w, h := expand_values(camera.viewport)
        //wgpu.RenderPassEncoderSetViewport(camera_fill_pass, x, y, w, h, 0, 1)
        //wgpu.RenderPassEncoderSetScissorRect(camera_fill_pass, u32(x), u32(y), u32(w), u32(h))
        wgpu.RenderPassEncoderDraw(camera_fill_pass, 3, 1, 0, 0)
    }
    wgpu.RenderPassEncoderEnd(camera_fill_pass)
    wgpu.RenderPassEncoderRelease(camera_fill_pass)

    pipelines: Pipelines

    for i in target.cameras {

        camera := cameras[i]

        //perform solid pass
        if draw_solid {
            render_pass := wgpu.CommandEncoderBeginRenderPass(command_encoder, &{
                label = "solid",
                colorAttachmentCount = 1,
                colorAttachments = &wgpu.RenderPassColorAttachment{
                    view = target.msaa,
                    resolveTarget = target.render_view,
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
            bind_camera(render_pass, 0, camera)
            bind_skeletons(render_pass, 2)
            bind_lights(render_pass, 3, u32(i))
            pipelines.main = ren.solid_pipelines
            pipelines.lines = ren.solid_lines_pipeline
            pipelines.points = ren.solid_points_pipeline
            execute_draw_calls(render_pass, solid_passes[i].draw_calls[:], pipelines)
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
            bind_camera(render_pass, 0, camera)
            bind_skeletons(render_pass, 2)
            bind_lights(render_pass, 3, u32(i))
            pipelines.main = ren.trans_pipelines
            pipelines.lines = ren.trans_lines_pipeline
            pipelines.points = ren.trans_points_pipeline
            execute_draw_calls(render_pass, trans_passes[i].draw_calls[:], pipelines)
            wgpu.RenderPassEncoderEnd(render_pass)
            wgpu.RenderPassEncoderRelease(render_pass)
        }
    }

    //finally, execute the OIT composite pass for the output
    if draw_trans {
        oit_composite_pass := wgpu.CommandEncoderBeginRenderPass(command_encoder, &{
            label = "OIT composite",
            colorAttachmentCount = 1,
            colorAttachments = &wgpu.RenderPassColorAttachment{
                view = target.msaa,
                resolveTarget = target.render_view,
                loadOp = .Load,
                storeOp = .Store,
                depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
            },
        })
        wgpu.RenderPassEncoderSetPipeline(oit_composite_pass, ren.oit_composite_pipeline)
        wgpu.RenderPassEncoderSetBindGroup(oit_composite_pass, 0, target.oit_composite_bind_group)
        wgpu.RenderPassEncoderDraw(oit_composite_pass, 3, 1, 0, 0)
        wgpu.RenderPassEncoderEnd(oit_composite_pass)
        wgpu.RenderPassEncoderRelease(oit_composite_pass)
    }
    
}

frame_arena: runtime.Arena

@(export)
render_frame :: proc() {
    if !ren.ready do return

    //so we can retain the data-flow procedural style while not reallocating every frame
    context.allocator = runtime.arena_allocator(&frame_arena)
    defer free_all(context.allocator)

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

    // TODO: move the above clear passes into render_target_passes, clear on first, load on second et al

    //firstly, get this frame's data
    f: Render_Frame
    defer clear_render_frame(&f)
    batch_instances(&f, frame.action[:], frame.batches[:])

    //allocate cubemaps
    rebind := realloc_cubemaps(command_encoder)
    assign_cubemaps(&f, frame.environment_probes[:])

    //upload instances after cubemaps are assigned
    write_instance_buffers(f.instances[:], f.skeletons[:])

    //add all main passes (probes, user-RTT, screen), schedule captures
    add_capture_passes(&f, frame.environment_probes[:])
    add_user_passes(&f, frame.render_targets[:])
    add_screen_pass(&f, screen, frame.cameras[:])

    //then gather up all lights, cascades by main views
    lights := calculate_lights(frame.lights[:], f.views[:], frame.scene_extents, rebind)
    add_shadow_views(&f, lights.shadow_cameras[:])

    //batch all the cameras into one...
    write_camera_buffer(f.views[:]) // TODO: rework this proc to use the new Views

    //make sure to upload + offset lights per-camera.
    shadow_offsets := shadow_offsets(lights, len(f.captures)+1)
    write_light_buffers(lights, main_views, shadow_offsets) // TODO: same as cameras, rework

    //cull & write draw indices (move to compute shader)
    cull_views(&f)

    //now on to actual drawing!

    //first render shadow maps
    for p in f.shadows {
        render_shadow_pass(command_encoder, f, p)
    }
    //then render all captures, with bounces
    for _ in 0..<CAPTURE_BOUNCES {
        for p in f.captures {
            render_main_pass(command_encoder, f, p)
        }
        //copy/mip
        for p in f.captures {
            resolve_capture(command_encoder, p)
        }
    }
    //finally render to the screen...
    render_main_pass(command_encoder, f, f.screen)

    //everything below is stale

    //get number of draw calls, in case we need to skip a pass
    draw_solid: bool = false
    for pass in passes.solid_main {
        if len(pass.draw_calls) > 0 {
            draw_solid = true
            break
        }
    }
    draw_trans: bool = false
    for pass in passes.trans_main {
        if len(pass.draw_calls) > 0 {
            draw_trans = true
            break
        }
    }

    //first render environment probes
    for target in frame.environment_probe_captures {
        target := Render_Target_Draw(target)
        clear_render_target(command_encoder, target)
        render_main_pass(command_encoder, frame.cameras[:], passes.solid_main, passes.trans_main, target, draw_solid, draw_trans)
    }
    copy_cubemaps(command_encoder)
    for target in frame.environment_probe_captures {
        render_mips(command_encoder, target.mipmapper)
    }

    //then render to custom render targets
    for hash, target in frame.render_targets {
        clear_render_target(command_encoder, target)
        render_main_pass(command_encoder, frame.cameras[:], passes.solid_main, passes.trans_main, target, draw_solid, draw_trans)
        render_mips(command_encoder, target.mipmapper)
    }

    //then finally render to screen (already cleared above)...
    set_screen_target(&frame, screen)
    render_main_pass(command_encoder, frame.cameras[:], passes.solid_main, passes.trans_main, frame.screen_target, draw_solid, draw_trans)

    //render the UI on top of everything else
    render_ui(screen, command_encoder)
}
