package graphics

import "vendor:wgpu"
import "core:math/linalg"
import "core:fmt"

Camera_Uniforms :: struct {
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
    using uniforms: Camera_Uniforms,
    near, far, fov: f32, //custom overrides
}

Screen_Uniforms :: struct {
    size: [4]f32, //width, height, near, far
    color: [4]f32, //rgb + fog start
}
screen_uniforms: Screen_Uniforms = {
    size={0, 0, 0.1, 0},
}
screen_uniforms_buffer: wgpu.Buffer

@(export)
set_background_color :: proc(color: [3]f32) {
    screen_uniforms.color.rgb = linalg.vector4_srgb_to_linear([4]f32{color.r, color.g, color.b, 1.0}).rgb
}

@(export)
set_render_distance :: proc(far: f32) {
    screen_uniforms.size[3] = far
}

@(export)
set_fog_distance :: proc(fog_start: f32) {
    screen_uniforms.color[3] = fog_start
}

camera_buffer: wgpu.Buffer
camera_layout_entries := []wgpu.BindGroupLayoutEntry{
    //screen bindings
    wgpu.BindGroupLayoutEntry{
        binding = 0,
        visibility = {.Vertex, .Fragment},
        buffer = {type=.Uniform},
    },
    //actual camera data
    wgpu.BindGroupLayoutEntry{
        binding = 1,
        visibility = {.Vertex, .Fragment},
        buffer = {type=.Uniform},
    },
}
camera_layout: wgpu.BindGroupLayout

@(export)
make_camera :: proc(viewport: [4]f32 = {0, 0, 0, 0}, near: f32 = 0, far: f32 = -1, fov: f32 = 0) -> (cam: Camera) {
    cam.buffer = wgpu.DeviceCreateBuffer(ren.device, &{usage={.Uniform, .CopyDst}, size=size_of(Camera_Uniforms)})
    bindings := []wgpu.BindGroupEntry{
        {binding = 0, buffer = screen_uniforms_buffer, size = size_of(Screen_Uniforms)},
        {binding = 1, buffer = cam.buffer, size = size_of(Camera_Uniforms)},
    }
    cam.bind_group = wgpu.DeviceCreateBindGroup(ren.device, &{
        layout = camera_layout,
        entryCount = len(bindings),
        entries = raw_data(bindings),
    })
    cam.viewport = viewport
    cam.near = near
    cam.far = far
    cam.fov = fov
    calculate_projection(&cam)
    return
}

calculate_camera :: proc(cam: ^Camera, a: f64 = 1.0, up: [3]f32 = {0, 1, 0}) {
    a := f32(a)
    eye := linalg.lerp(cam.eye_prev, cam.eye_next, [3]f32{a, a, a})
    center := linalg.lerp(cam.center_prev, cam.center_next, [3]f32{a, a, a})
    cam.eye = {eye.x, eye.y, eye.z, 1.0}
    cam.center = {center.x, center.y, center.z, 1.0}
    cam.view = linalg.matrix4_look_at(cam.eye.xyz, cam.center.xyz, up)
    if cam.viewport[2] == 0 || cam.viewport[3] == 0 {
        calculate_projection(cam)
    }
}

//this is a bit redundant to be called multiple times, but oh well
bind_camera :: proc(render_pass: wgpu.RenderPassEncoder, slot: u32, cam: Camera) {
    cam := cam
    //load camera uniforms
    wgpu.QueueWriteBuffer(ren.queue, cam.buffer, 0, &cam.uniforms, size_of(Camera_Uniforms))
    x := cam.viewport.x
    y := cam.viewport.y
    w, h := get_viewport_size(cam)
    x = max(x, 0)
    y = max(y, 0)
    if cam.viewport[2] == 0 && cam.viewport[3] == 0 {
        w = min(w, screen_uniforms.size.x)
        h = min(h, screen_uniforms.size.y)
    }
    wgpu.RenderPassEncoderSetViewport(render_pass, x, y, w, h, 0, 1)
    wgpu.RenderPassEncoderSetScissorRect(render_pass, u32(x), u32(y), u32(w), u32(h))
    
    //load screen uniforms
    screen_uniforms_temp := screen_uniforms
    cam_width, cam_height := get_viewport_size(cam)
    screen_uniforms_temp.size.x = cam_width
    screen_uniforms_temp.size.y = cam_height
    if screen_uniforms_temp.color.rgb == 0 {
        screen_uniforms_temp.color.rgb = 1
    }
    if cam.near != 0 {
        screen_uniforms_temp.size[2] = cam.near
    }
    if cam.far != -1 {
        screen_uniforms_temp.size[3] = cam.far
    }
    wgpu.QueueWriteBuffer(ren.queue, screen_uniforms_buffer, 0, &screen_uniforms_temp, size_of(Screen_Uniforms))

    //bind both
    wgpu.RenderPassEncoderSetBindGroup(render_pass, slot, cam.bind_group)
}

@(export)
delete_camera :: proc(cam: Camera) {
    wgpu.BufferRelease(cam.buffer)
    wgpu.BindGroupRelease(cam.bind_group)
}

//look_at is instant, look_to is interpolated.
@(export)
look_at :: proc(cam: ^Camera, eye: [3]f32, center: [3]f32) {
    cam.eye_prev = eye
    cam.center_prev = center
    cam.eye_next = eye
    cam.center_next = center
}
@(export)
look_to :: proc(cam: ^Camera, eye: [3]f32, center: [3]f32) {
    cam.eye_prev = cam.eye_next
    cam.center_prev = cam.center_next
    cam.eye_next = eye
    cam.center_next = center
}

@(export)
set_viewport :: proc(cam: ^Camera, viewport: [4]f32) {
    cam.viewport = viewport
    calculate_projection(cam)
}

get_viewport_size :: proc(cam: Camera) -> (width, height: f32) {
    width = cam.viewport[2]
    height = cam.viewport[3]
    if width == 0 {
        width = screen_uniforms.size.x
    }
    if height == 0 {
        height = screen_uniforms.size.y
    }
    return
}

FOV :: 60.0
calculate_projection :: proc(cam: ^Camera) {
    width, height := get_viewport_size(cam^)
    near, far, fov: f32
    if cam.near == 0 {
        near = screen_uniforms.size[2]
    } else {
        near = cam.near
    }
    if cam.far == -1 {
        far = screen_uniforms.size[3]
    } else {
        far = cam.far
    }
    if cam.fov == 0 {
        fov = f32(linalg.to_radians(FOV))
    } else {
        fov = cam.fov
    }
    if far == 0 {
        cam.projection = linalg.matrix4_infinite_perspective(fov, width/height, near)
    } else {
        cam.projection = linalg.matrix4_perspective(fov, width/height, near, far)
    }
}

//returns the z coordinate which the camera should be at to have sprites rendered at z=0 be pixel-perfect
//(assumes FOV = default of 60 degrees)
@(export)
z_2d :: proc(cam: Camera) -> f32 {
    width, height := get_viewport_size(cam)
    return linalg.sqrt(linalg.pow(height, 2) - linalg.pow(height/2.0, 2))
}

bounds_in_frustum :: proc(cam: Camera, bounding_box: [8][4]f32) -> bool {
    //need to check if all planes are passing (i.e. at least one point is inside)
    passing: [6]bool = false
    //OBB check for meshes
    for point in bounding_box {
        test_point := cam.projection * cam.view * point
        if test_point.x >= -test_point.w {
            passing[0] = true
        }
        if test_point.x <= test_point.w {
            passing[1] = true
        }
        if test_point.y >= -test_point.w {
            passing[2] = true
        }
        if test_point.y <= test_point.w {
            passing[3] = true
        }
        if test_point.z >= -test_point.w {
            passing[4] = true
        }
        if test_point.z <= test_point.w {
            passing[5] = true
        }
    }
    //if inside_this_plane[n] == false, then all points were outside that plane.
    return passing[0] && passing[1] && passing[2] && passing[3] && passing[4] && passing[5]
}
