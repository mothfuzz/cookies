package graphics

import "vendor:wgpu"
import "core:math/linalg"
import "core:fmt"

CameraUniforms :: struct {
    eye: [4]f32,
    center: [4]f32,
    view: matrix[4,4]f32,
    projection: matrix[4,4]f32,
}
Camera :: struct {
    bind_group: wgpu.BindGroup,
    buffer: wgpu.Buffer,
    eye_prev: [3]f32,
    eye_next: [3]f32,
    center_prev: [3]f32,
    center_next: [3]f32,
    viewport: [4]f32,
    using uniforms: CameraUniforms,
}
camera_buffer: wgpu.Buffer
camera_layout_entries := []wgpu.BindGroupLayoutEntry{
    wgpu.BindGroupLayoutEntry{
        binding = 0,
        visibility = {.Vertex, .Fragment},
        buffer = {type=.Uniform},
    },
}
camera_layout: wgpu.BindGroupLayout

make_camera :: proc(viewport: [4]f32 = {0, 0, 0, 0}) -> (cam: Camera) {
    cam.buffer = wgpu.DeviceCreateBuffer(ren.device, &{usage={.Uniform, .CopyDst}, size=size_of(CameraUniforms)})
    bindings := []wgpu.BindGroupEntry{
        {binding = 0, buffer = cam.buffer, size = size_of(CameraUniforms)},
    }
    cam.bind_group = wgpu.DeviceCreateBindGroup(ren.device, &{
        layout = camera_layout,
        entryCount = len(bindings),
        entries = raw_data(bindings),
    })
    cam.viewport = viewport
    calculate_projection(&cam)
    return
}

bind_camera :: proc(render_pass: wgpu.RenderPassEncoder, slot: u32, cam: ^Camera, t: f64 = 1.0) {
    t := f32(t)
    eye := linalg.lerp(cam.eye_prev, cam.eye_next, [3]f32{t, t, t})
    center := linalg.lerp(cam.center_prev, cam.center_next, [3]f32{t, t, t})
    cam.eye = {eye.x, eye.y, eye.z, 1.0}
    cam.center = {center.x, center.y, center.z, 1.0}
    cam.view = linalg.matrix4_look_at(cam.eye.xyz, cam.center.xyz, [3]f32{0, 1, 0})
    wgpu.QueueWriteBuffer(ren.queue, cam.buffer, 0, &cam.uniforms, size_of(CameraUniforms))
    wgpu.RenderPassEncoderSetBindGroup(render_pass, slot, cam.bind_group)
    x := cam.viewport.x
    y := cam.viewport.y
    w, h := get_viewport_size(cam)
    wgpu.RenderPassEncoderSetViewport(render_pass, x, y, w, h, 0, 1)
    wgpu.RenderPassEncoderSetScissorRect(render_pass, u32(x), u32(y), u32(w), u32(h))
}

delete_camera :: proc(cam: Camera) {
    wgpu.BufferRelease(cam.buffer)
    wgpu.BindGroupRelease(cam.bind_group)
}

//look_at is instant, look_to is interpolated.
look_at :: proc(cam: ^Camera, eye: [3]f32, center: [3]f32) {
    cam.eye_prev = eye
    cam.center_prev = center
    cam.eye_next = eye
    cam.center_next = center
}
look_to :: proc(cam: ^Camera, eye: [3]f32, center: [3]f32) {
    cam.eye_prev = cam.eye_next
    cam.center_prev = cam.center_next
    cam.eye_next = eye
    cam.center_next = center
}

get_viewport_size :: proc(cam: ^Camera) -> (width, height: f32) {
    width = cam.viewport[2]
    height = cam.viewport[3]
    if width == 0 {
        width = f32(screen_size.x)
    }
    if height == 0 {
        height = f32(screen_size.y)
    }
    return
}

FOV :: 60.0
calculate_projection :: proc(cam: ^Camera) {
    width, height := get_viewport_size(cam)
    fov := f32(linalg.to_radians(FOV))
    cam.projection = linalg.matrix4_perspective(fov, width/height, 0.1, 2048.0)
}

z_2d :: proc(cam: ^Camera) -> f32 {
    width, height := get_viewport_size(cam)
    return linalg.sqrt(linalg.pow(height, 2) - linalg.pow(height/2.0, 2))
}
