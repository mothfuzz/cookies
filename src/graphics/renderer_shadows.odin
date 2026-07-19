package graphics

import "vendor:wgpu"

Shadow_Renderer :: struct {
    //shadow map data
    shadow_layout: wgpu.PipelineLayout,
    shadow_pipeline: wgpu.RenderPipeline,
    shadow_depth_sampler: wgpu.Sampler,
    shadow_color_sampler: wgpu.Sampler,
    spot_light_shadow_depth: Texture,
    spot_light_shadow_color: Texture,
}

init_shadows :: proc() {
    bind_group_layouts := []wgpu.BindGroupLayout{camera_layout, material_layout, skeletons_layout}
    ren.shadow_layout = wgpu.DeviceCreatePipelineLayout(ren.device, &{
        bindGroupLayoutCount = len(bind_group_layouts),
        bindGroupLayouts = raw_data(bind_group_layouts),
    })

    ren.shadow_pipeline = wgpu.DeviceCreateRenderPipeline(ren.device, &{
        label = "shadows",
        layout = ren.shadow_layout,
        vertex = {
            module = ren.shader,
            entryPoint = "vs_main",
            bufferCount = len(vertex_buffer_layouts),
            buffers = raw_data(vertex_buffer_layouts),
        },
        fragment = &{
            module = ren.shader,
            entryPoint = "shadow_main",
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
        },
        primitive = {
            topology = .TriangleList,
            cullMode = .None,
            frontFace = .CCW,
        },
        depthStencil = &{
            format = .Depth32Float,
            depthWriteEnabled = .True,
            depthCompare = .Less,
            //these don't seem to do anything
            //depthBias = 10000,
            //depthBiasSlopeScale = 2.0,
            //depthBiasClamp = 0.01,
        },
        multisample = {
            count = 1,
            mask = 0xffffffff,
        },
    })

    size: [2]uint = {SPOT_LIGHT_SHADOW_MAP_RES, SPOT_LIGHT_SHADOW_MAP_RES}
    ren.spot_light_shadow_depth = make_render_texture_array(size, .Depth32Float, 1)
    ren.spot_light_shadow_color = make_render_texture_array(size, .RGBA8Unorm, 1)
    ren.shadow_depth_sampler = wgpu.DeviceCreateSampler(ren.device, &{
        minFilter = .Linear,
        magFilter = .Linear,
        mipmapFilter = .Nearest,
        addressModeU = .ClampToEdge,
        addressModeV = .ClampToEdge,
        addressModeW = .ClampToEdge,
        compare = .LessEqual,
        maxAnisotropy = 1,
    })
    ren.shadow_color_sampler = wgpu.DeviceCreateSampler(ren.device, &{
        minFilter = .Nearest,
        magFilter = .Nearest,
        mipmapFilter = .Nearest,
        addressModeU = .ClampToEdge,
        addressModeV = .ClampToEdge,
        addressModeW = .ClampToEdge,
        maxAnisotropy = 1,
    })
}

delete_shadows :: proc() {
    wgpu.RenderPipelineRelease(ren.shadow_pipeline)
    wgpu.PipelineLayoutRelease(ren.shadow_layout)
    wgpu.SamplerRelease(ren.shadow_depth_sampler)
    wgpu.SamplerRelease(ren.shadow_color_sampler)
    delete_texture(ren.spot_light_shadow_depth)
    delete_texture(ren.spot_light_shadow_color)
}
