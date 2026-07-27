package graphics

import "vendor:wgpu"
import "core:math/linalg"

Shadow_Renderer :: struct {
    //shadow map data
    shadow_layout: wgpu.PipelineLayout,
    solid_shadow_pipeline: wgpu.RenderPipeline,
    trans_shadow_pipeline: wgpu.RenderPipeline,
    shadow_depth_sampler: wgpu.Sampler,
    shadow_color_sampler: wgpu.Sampler,
    point_light_shadow_depth: Texture,
    point_light_shadow_color: Texture,
    spot_light_shadow_depth: Texture,
    spot_light_shadow_color: Texture,
}

init_shadows :: proc() {
    bind_group_layouts := []wgpu.BindGroupLayout{camera_layout, material_layout, skeletons_layout}
    ren.shadow_layout = wgpu.DeviceCreatePipelineLayout(ren.device, &{
        bindGroupLayoutCount = len(bind_group_layouts),
        bindGroupLayouts = raw_data(bind_group_layouts),
    })

    ren.solid_shadow_pipeline = wgpu.DeviceCreateRenderPipeline(ren.device, &{
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
            entryPoint = "solid_shadow_main",
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
            depthCompare = .Greater,
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
    ren.trans_shadow_pipeline = wgpu.DeviceCreateRenderPipeline(ren.device, &{
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
            entryPoint = "trans_shadow_main",
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
            depthWriteEnabled = .False,
            depthCompare = .Greater,
        },
        multisample = {
            count = 1,
            mask = 0xffffffff,
        },
    })

    size: [2]uint = {POINT_LIGHT_SHADOW_MAP_RES, POINT_LIGHT_SHADOW_MAP_RES}
    ren.point_light_shadow_depth = make_render_texture_array(size, .Depth32Float, 1, true)
    ren.point_light_shadow_color = make_render_texture_array(size, .RGBA8Unorm, 1, true)

    size = {SPOT_LIGHT_SHADOW_MAP_RES, SPOT_LIGHT_SHADOW_MAP_RES}
    ren.spot_light_shadow_depth = make_render_texture_array(size, .Depth32Float, 1)
    ren.spot_light_shadow_color = make_render_texture_array(size, .RGBA8Unorm, 1)


    ren.shadow_depth_sampler = wgpu.DeviceCreateSampler(ren.device, &{
        minFilter = .Linear,
        magFilter = .Linear,
        mipmapFilter = .Nearest,
        addressModeU = .ClampToEdge,
        addressModeV = .ClampToEdge,
        addressModeW = .ClampToEdge,
        compare = .GreaterEqual,
        maxAnisotropy = 1,
    })
    ren.shadow_color_sampler = wgpu.DeviceCreateSampler(ren.device, &{
        minFilter = .Linear,
        magFilter = .Linear,
        mipmapFilter = .Nearest,
        addressModeU = .ClampToEdge,
        addressModeV = .ClampToEdge,
        addressModeW = .ClampToEdge,
        maxAnisotropy = 1,
    })
}

delete_shadows :: proc() {
    wgpu.RenderPipelineRelease(ren.solid_shadow_pipeline)
    wgpu.RenderPipelineRelease(ren.trans_shadow_pipeline)
    wgpu.PipelineLayoutRelease(ren.shadow_layout)
    wgpu.SamplerRelease(ren.shadow_depth_sampler)
    wgpu.SamplerRelease(ren.shadow_color_sampler)
    delete_texture(ren.point_light_shadow_depth)
    delete_texture(ren.point_light_shadow_color)
    delete_texture(ren.spot_light_shadow_depth)
    delete_texture(ren.spot_light_shadow_color)
}


POINT_LIGHT_SHADOW_MAP_RES :: 1024

DIRECTIONAL_LIGHT_SHADOW_MAP_RES :: 1024
DIRECTIONAL_CASCADES :: 3

SPOT_LIGHT_SHADOW_MAP_RES :: 1024

Shadow_Target :: enum {
    Point,
    Directional,
    Spot,
}
Shadow_Camera_Draw :: struct {
    using camera_view: Camera_View,
    layer: uint,
    target: Shadow_Target,
}

calculate_shadow_camera_perspective :: proc(position, direction, up: [3]f32, fov, near, far: f32) -> (cam: Shadow_Camera_Draw) {
    cam.view = linalg.matrix4_look_at(position, position+direction, up)
    t1 := 1/(linalg.tan(fov/2))
    t2 := near/(far - near) //reverse-z for greater depth precision
    cam.projection[0, 0] = t1
    cam.projection[1, 1] = t1
    cam.projection[2, 2] = t2
    cam.projection[3, 2] = -1
    cam.projection[2, 3] = far * t2
    cam.viewproj = cam.projection * cam.view
    return
}
calculate_shadow_camera_ortho :: proc(center: [3]f32, left, right, top, bottom, near, far: f32) -> (cam: Shadow_Camera_Draw) {
    // TODO
    return
}

bind_shadow_camera :: proc(render_pass: wgpu.RenderPassEncoder, slot: u32, cam: Shadow_Camera_Draw) {
    bind_camera_uniforms(render_pass, slot, cam.buffer_index)
}

render_shadow_maps :: proc(command_encoder: wgpu.CommandEncoder, passes: Passes, shadow_cameras: []Shadow_Camera_Draw) {
    for shadow_cam, i in shadow_cameras {
        //render to a specific spot in the texture array
        view_descriptor := wgpu.TextureViewDescriptor{
            dimension = ._2D,
            mipLevelCount = 1,
            arrayLayerCount = 1,
            baseArrayLayer=u32(shadow_cam.layer),
        }
        shadow_depth: wgpu.Texture
        shadow_color: wgpu.Texture
        switch shadow_cam.target {
        case .Point:
            shadow_depth = ren.point_light_shadow_depth.image
            shadow_color = ren.point_light_shadow_color.image
        case .Directional:
            //shadow_depth = ren.directional_light_shadow_depth.image
            //shadow_color = ren.directional_light_shadow_color.image
        case .Spot:
            shadow_depth = ren.spot_light_shadow_depth.image
            shadow_color = ren.spot_light_shadow_color.image
        }
        shadow_color_view := wgpu.TextureCreateView(shadow_color, &view_descriptor)
        defer wgpu.TextureViewRelease(shadow_color_view)
        shadow_depth_view := wgpu.TextureCreateView(shadow_depth, &view_descriptor)
        defer wgpu.TextureViewRelease(shadow_depth_view)

        solid_shadow_pass := wgpu.CommandEncoderBeginRenderPass(command_encoder, &{
            label = "solid shadows",
            colorAttachmentCount = 1,
            colorAttachments = &wgpu.RenderPassColorAttachment{
                view = shadow_color_view,
                loadOp = .Clear,
                storeOp = .Store,
                depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
                clearValue = [4]f64{1, 1, 1, 1},
            },
            depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment{
                view = shadow_depth_view,
                depthLoadOp = .Clear,
                depthStoreOp = .Store,
                depthClearValue = 0.0,
            },
        })
        wgpu.RenderPassEncoderSetPipeline(solid_shadow_pass, ren.solid_shadow_pipeline)

        bind_shadow_camera(solid_shadow_pass, 0, shadow_cam)
        execute_draw_calls(solid_shadow_pass, passes.solid_shadows[i].draw_calls[:])

        wgpu.RenderPassEncoderEnd(solid_shadow_pass)
        wgpu.RenderPassEncoderRelease(solid_shadow_pass)

        trans_shadow_pass := wgpu.CommandEncoderBeginRenderPass(command_encoder, &{
            label = "trans shadows",
            colorAttachmentCount = 1,
            colorAttachments = &wgpu.RenderPassColorAttachment{
                view = shadow_color_view,
                loadOp = .Load,
                storeOp = .Store,
                depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
            },
            depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment{
                view = shadow_depth_view,
                depthLoadOp = .Load,
                depthStoreOp = .Store,
            },
        })
        wgpu.RenderPassEncoderSetPipeline(trans_shadow_pass, ren.trans_shadow_pipeline)

        bind_shadow_camera(trans_shadow_pass, 0, shadow_cam)
        execute_draw_calls(trans_shadow_pass, passes.trans_shadows[i].draw_calls[:])

        wgpu.RenderPassEncoderEnd(trans_shadow_pass)
        wgpu.RenderPassEncoderRelease(trans_shadow_pass)
    }
}

