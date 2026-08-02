package graphics

import "vendor:wgpu"
import "core:math"

Mip_Draw :: struct {
    bind_group: wgpu.BindGroup,
    input_view: wgpu.TextureView,
    output_view: wgpu.TextureView,
}

mip_count_tex :: proc "contextless" (tex: wgpu.Texture) -> int {
    width := uint(wgpu.TextureGetWidth(tex))
    height := uint(wgpu.TextureGetHeight(tex))
    return mip_count_res({width, height})
}

mip_count_res :: proc "contextless" (res: [2]uint) -> int {
    return int(math.floor(math.log2(f32(max(res.x, res.y))))) + 1
}

mip_count :: proc{mip_count_tex, mip_count_res}

mipmapper_layout_entries := []wgpu.BindGroupLayoutEntry{
    wgpu.BindGroupLayoutEntry{
        binding = 0,
        visibility = {.Fragment},
        sampler = {type = .Filtering},
    },
    wgpu.BindGroupLayoutEntry{
        binding = 1,
        visibility = {.Fragment},
        texture = {sampleType = .Float, viewDimension = ._2D},
    },
}
mipmapper_bind_group_layout: wgpu.BindGroupLayout
mipmapper_layout: wgpu.PipelineLayout
mipmapper_pipeline: wgpu.RenderPipeline
mipmapper_shader: wgpu.ShaderModule
make_mipmapping :: proc() {
    mipmapper_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(ren.device, &{
        entryCount = len(mipmapper_layout_entries),
        entries = raw_data(mipmapper_layout_entries)
    })
    mipmapper_layout = wgpu.DeviceCreatePipelineLayout(ren.device, &{
        bindGroupLayoutCount = 1,
        bindGroupLayouts = &mipmapper_bind_group_layout,
    })

    mipmapper_shader = wgpu.DeviceCreateShaderModule(ren.device, &{
        nextInChain = &wgpu.ShaderSourceWGSL{
            sType = .ShaderSourceWGSL,
            code = #load("fullscreen_pass.wgsl"),
        },
    })
    mipmapper_pipeline = wgpu.DeviceCreateRenderPipeline(ren.device, &{
        label = "mipmap gen",
        layout = mipmapper_layout,
        vertex = {
            module = mipmapper_shader,
            entryPoint = "vs_main",
            bufferCount = 0,
        },
        fragment = &{
            module = mipmapper_shader,
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
            count = 1,
            mask = 0xffffffff,
        },
    })
}
delete_mipmapping :: proc() {
    wgpu.BindGroupLayoutRelease(mipmapper_bind_group_layout)
    wgpu.PipelineLayoutRelease(mipmapper_layout)
    wgpu.RenderPipelineRelease(mipmapper_pipeline)
    wgpu.ShaderModuleRelease(mipmapper_shader)
}

make_mipmapper :: proc(tex: wgpu.Texture, smp: wgpu.Sampler, layer: u32 = 0) -> (mipmapper: []Mip_Draw) {
    mipmapper = make([]Mip_Draw, mip_count(tex)-1)
    for &mip, i in mipmapper {
        mip.input_view = wgpu.TextureCreateView(tex, &{
            dimension = ._2D,
            arrayLayerCount = 1,
            baseArrayLayer = layer,
            mipLevelCount = 1,
            baseMipLevel = u32(i),
        })
        mip.output_view = wgpu.TextureCreateView(tex, &{
            dimension = ._2D,
            arrayLayerCount = 1,
            baseArrayLayer = layer,
            mipLevelCount = 1,
            baseMipLevel = u32(i+1),
        })
        mipmapper_bindings := []wgpu.BindGroupEntry{
            {binding = 0, sampler=smp},
            {binding = 1, textureView=mip.input_view}
        }
        mip.bind_group = wgpu.DeviceCreateBindGroup(ren.device, &{
            layout = mipmapper_bind_group_layout,
            entryCount = len(mipmapper_bindings),
            entries = raw_data(mipmapper_bindings),
        })
    }
    return
}

delete_mipmapper :: proc(mipmapper: []Mip_Draw) {
    for mip in mipmapper {
        wgpu.BindGroupRelease(mip.bind_group)
        wgpu.TextureViewRelease(mip.input_view)
        wgpu.TextureViewRelease(mip.output_view)
    }
    delete(mipmapper)
}


render_mips :: proc(command_encoder: wgpu.CommandEncoder, mipmapper: []Mip_Draw) {
    for mip, i in mipmapper {
        render_pass := wgpu.CommandEncoderBeginRenderPass(command_encoder, &{
            label = "mipmap gen",
            colorAttachmentCount = 1,
            colorAttachments = &wgpu.RenderPassColorAttachment{
                view = mip.output_view,
                loadOp = .Clear,
                storeOp = .Store,
                depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
            },
        })

        wgpu.RenderPassEncoderSetPipeline(render_pass, mipmapper_pipeline)
        wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, mip.bind_group)
        wgpu.RenderPassEncoderDraw(render_pass, 3, 1, 0, 0)
        
        wgpu.RenderPassEncoderEnd(render_pass)
        wgpu.RenderPassEncoderRelease(render_pass)
    } 
}
