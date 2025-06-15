package graphics

import "core:fmt"
import "vendor:wgpu"

//set up graphics pipeline & renderpass
//(renders to screen.)

ui_shader: wgpu.ShaderModule
ui_pipeline: wgpu.RenderPipeline
ui_bind_group_layout: wgpu.BindGroupLayout
ui_sampler: wgpu.Sampler


ui_layout_entries := []wgpu.BindGroupLayoutEntry{
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
ui_attributes := []wgpu.VertexAttribute{
    {format = .Float32x4, offset = 0 * size_of([4]f32), shaderLocation = 0},
    {format = .Float32x4, offset = 1 * size_of([4]f32), shaderLocation = 1},
    {format = .Float32x4, offset = 2 * size_of([4]f32), shaderLocation = 2},
}

init_ui :: proc() {

    //load shader & create pipeline...

    ui_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(ren.device, &{
        entryCount = len(ui_layout_entries),
        entries = raw_data(ui_layout_entries),
    })

    ui_layout := wgpu.DeviceCreatePipelineLayout(ren.device, &{
        bindGroupLayoutCount = 1,
        bindGroupLayouts = &ui_bind_group_layout,
    })

    ui_shader = wgpu.DeviceCreateShaderModule(ren.device, &{
        nextInChain = &wgpu.ShaderSourceWGSL{
            sType = .ShaderSourceWGSL,
            code = #load("ui.wgsl"),
        },
    })
    ui_pipeline = wgpu.DeviceCreateRenderPipeline(ren.device, &{
        layout = ui_layout,
        label = "ui_pipeline",
        vertex = {
            module = ui_shader,
            entryPoint = "vs_main",
            bufferCount = 1,
            buffers = &wgpu.VertexBufferLayout{
                stepMode = .Instance,
                arrayStride = size_of(UiInstanceData),
                attributeCount = len(ui_attributes),
                attributes = raw_data(ui_attributes),
            },
        },
        fragment = &{
            module = ui_shader,
            entryPoint = "fs_main",
            targetCount = 1,
            targets = &wgpu.ColorTargetState{
                format = with_srgb(ren.config.format),
                writeMask = wgpu.ColorWriteMaskFlags_All,
                blend = &{
                    color = wgpu.BlendComponent{.Add, .SrcAlpha, .OneMinusSrcAlpha},
                    alpha = wgpu.BlendComponent{.Add, .SrcAlpha, .OneMinusSrcAlpha},
                }
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

    ui_sampler = wgpu.DeviceCreateSampler(ren.device, &{
        minFilter = .Nearest,
        magFilter = .Nearest,
        mipmapFilter = .Nearest,
        maxAnisotropy = 1,
    })
}

UiBatch :: struct {
    bind_group: wgpu.BindGroup,
    instances: [dynamic]UiInstanceData,
}

//buffer data
UiInstanceData :: struct {
    fill_rect: [4]f32,
    color: [4]f32,
    clip_rect: [4]f32,
}
ui_batches: map[Texture]UiBatch

//base function for all UI drawing.
//assumes fill_rect is normalized screen space xywh -1:+1 & clip_rect is texcoord space xywh 0:1...
draw_ui :: proc(fill_rect: [4]f32, color: [4]f32, texture: Texture, clip_rect: [4]f32) {
    if !(texture in ui_batches) {
        bindings := []wgpu.BindGroupEntry{
            {binding = 0, sampler = ui_sampler},
            {binding = 1, textureView = texture.view},
        }
        ui_batches[texture] = UiBatch{
            bind_group = wgpu.DeviceCreateBindGroup(ren.device, &{
                layout = ui_bind_group_layout,
                entryCount = len(bindings),
                entries = raw_data(bindings),
            }),
            instances = make([dynamic]UiInstanceData),
        }
    }
    batch := &ui_batches[texture]
    append(&batch.instances, UiInstanceData{fill_rect, color, clip_rect})
}

render_ui :: proc(screen: wgpu.TextureView, command_encoder: wgpu.CommandEncoder) {
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

    wgpu.RenderPassEncoderSetPipeline(render_pass, ui_pipeline)
    wgpu.RenderPassEncoderSetViewport(render_pass, 0, 0, f32(screen_size.x), f32(screen_size.y), 0, 1)
    wgpu.RenderPassEncoderSetScissorRect(render_pass, 0, 0, screen_size.x, screen_size.y)

    //fmt.println("rendering ui batch...")
    for tex, &batch in ui_batches {
        //fmt.println("ui batch size...", len(batch.instances))
        wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, batch.bind_group)
        instance_buffer := wgpu.DeviceCreateBufferWithDataSlice(ren.device, &{usage={.Vertex, .CopyDst}}, batch.instances[:])
        wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 0, instance_buffer, 0, wgpu.BufferGetSize(instance_buffer))
        wgpu.BufferRelease(instance_buffer)
        wgpu.RenderPassEncoderDraw(render_pass, 6, u32(len(batch.instances)), 0, 0)
        clear(&batch.instances)
    }

    wgpu.RenderPassEncoderEnd(render_pass)
    wgpu.RenderPassEncoderRelease(render_pass)
}
