package graphics

import "vendor:wgpu"

//THE! pipeline table

//needs a way to key a table of pipelines by 'feature'
//i.e. shadow targets skip lines/point
//any feature we add that doesn't support trans passes skips trans
//etc etc

//skipping doesn't require a manual check on a bit_set, it should check for nil entries in the pipelines table
//and not emit any draw ranges for that pipeline

Stage_Key :: enum u8 {
    Shadow,
    Main,
}

Blend_Key :: enum u8 {
    Opaque,
    Blended,
}

alpha_blends :: [Alpha_Class]bit_set[Blend_Key]{
        .Solid = {.Opaque},
        .Mixed = {.Opaque, .Blended},
        .Trans = {.Blended},
}

Primitive_Key :: enum u8 {
    Triangles_CCW,
    Triangles_CW,
    Triangles_CCW_Double_Sided,
    Triangles_CW_Double_Sided,
    Lines,
    Points,
}
primitive_state := [Primitive_Key]struct{wgpu.PrimitiveTopology, wgpu.FrontFace, wgpu.CullMode} {
        .Triangles_CCW = {.TriangleList, .CCW, .Back},
        .Triangles_CW = {.TriangleList, .CW, .Back},
        .Triangles_CCW_Double_Sided = {.TriangleList, .CCW, .None},
        .Triangles_CW_Double_Sided = {.TriangleList, .CW, .None},
        .Lines = {.LineList, .Undefined, .None},
        .Points = {.PointList, .Undefined, .None},
}

topology_constant := #partial [wgpu.PrimitiveTopology]f64 {
        .TriangleList = 0,
        .LineList = 1,
        .PointList = 2,
}

pipelines: [Stage_Key][Blend_Key][Primitive_Key]wgpu.RenderPipeline

create_main_pipeline :: proc(topology: wgpu.PrimitiveTopology, front_face: wgpu.FrontFace, cull_mode: wgpu.CullMode) -> (solid, trans: wgpu.RenderPipeline) {
    constants := []wgpu.ConstantEntry{
        {key = "TOPOLOGY", value = topology_constant[topology]}
    }
    solid = wgpu.DeviceCreateRenderPipeline(ren.device, &{
        label = "solid main",
        layout = ren.main_layout,
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
            topology = topology,
            cullMode = cull_mode,
            frontFace = front_face,
        },
        depthStencil = &{
            format = .Depth24PlusStencil8,
            depthWriteEnabled = .True,
            depthCompare = .LessEqual,
        },
        multisample = {
            count = 4,
            mask = 0xffffffff,
            //alphaToCoverageEnabled = true,
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
        label = "trans main",
        layout = ren.main_layout,
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
            topology = topology,
            cullMode = cull_mode,
            frontFace = front_face,
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

create_shadow_pipeline :: proc(topology: wgpu.PrimitiveTopology, front_face: wgpu.FrontFace, cull_mode: wgpu.CullMode) -> (solid, trans: wgpu.RenderPipeline) {
    constants := []wgpu.ConstantEntry{
        {key = "TOPOLOGY", value = topology_constant[topology]}
    }
    solid = wgpu.DeviceCreateRenderPipeline(ren.device, &{
        label = "solid shadows",
        layout = ren.shadow_layout,
        vertex = {
            module = ren.shader,
            entryPoint = "vs_main",
            bufferCount = len(vertex_buffer_layouts),
            buffers = raw_data(vertex_buffer_layouts),
        },
        fragment = &{
            module = ren.shader,
            entryPoint = "solid_shadow",
            targetCount = 1,
            targets = &wgpu.ColorTargetState{
                format = .RGBA8Unorm,
                writeMask = wgpu.ColorWriteMaskFlags_All,
                blend = &{
                    color = {
                        operation = .Add,
                        srcFactor = .Zero,
                        dstFactor = .Src,
                    },
                    alpha = {
                        operation = .Add,
                        srcFactor = .One,
                        dstFactor = .Zero,
                    }
                }
            },
            constantCount = len(constants),
            constants = raw_data(constants),
        },
        primitive = {
            topology = topology,
            cullMode = cull_mode,
            frontFace = front_face,
        },
        depthStencil = &{
            format = .Depth32Float,
            depthWriteEnabled = .True,
            depthCompare = .GreaterEqual,
        },
        multisample = {
            count = 1,
            mask = 0xffffffff,
        },
    })

    trans = wgpu.DeviceCreateRenderPipeline(ren.device, &{
        label = "trans shadows",
        layout = ren.shadow_layout,
        vertex = {
            module = ren.shader,
            entryPoint = "vs_main",
            bufferCount = len(vertex_buffer_layouts),
            buffers = raw_data(vertex_buffer_layouts),
        },
        fragment = &{
            module = ren.shader,
            entryPoint = "trans_shadow",
            targetCount = 1,
            targets = &wgpu.ColorTargetState{
                format = .RGBA8Unorm,
                writeMask = wgpu.ColorWriteMaskFlags_All,
                blend = &{
                    color = {
                        operation = .Add,
                        srcFactor = .Zero,
                        dstFactor = .Src,
                    },
                    alpha = {
                        operation = .Add,
                        srcFactor = .One,
                        dstFactor = .Zero,
                    },
                },
            },
            constantCount = len(constants),
            constants = raw_data(constants),
        },
        primitive = {
            topology = topology,
            cullMode = cull_mode,
            frontFace = front_face,
        },
        depthStencil = &{
            format = .Depth32Float,
            depthWriteEnabled = .False, //false for transparent materials
            depthCompare = .Greater,
        },
        multisample = {
            count = 1,
            mask = 0xffffffff,
        },
    })
    return
}

create_pipeline_table :: proc() {
    for key in Primitive_Key {
        solid, trans := create_main_pipeline(**primitive_state[key])
        pipelines[.Main][.Opaque][key] = solid
        pipelines[.Main][.Blended][key] = trans
    }
    for key in Primitive_Key {
        if key == .Lines || key == .Points do continue //shadow maps skip lines and points
        solid, trans := create_shadow_pipeline(**primitive_state[key])
        pipelines[.Shadow][.Opaque][key] = solid
        pipelines[.Shadow][.Blended][key] = trans
    }
}

destroy_pipeline_table :: proc() {
    for bp, stage in pipelines {
        for pp, blend in bp {
            for pipeline, primitive in pp {
                if pipeline == nil do continue
                wgpu.RenderPipelineRelease(pipeline)
            }
        }
    }
}
