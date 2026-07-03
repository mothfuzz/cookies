package graphics

import "vendor:wgpu"
import "core:math/linalg"

camera_layout_entries :: []wgpu.BindGroupLayoutEntry{
    wgpu.BindGroupLayoutEntry{
        binding = 0,
        visibility = {.Vertex, .Fragment},
        buffer = {type=.Uniform}
    },
}
camera_layout: wgpu.BindGroupLayout

Camera_Uniforms :: struct {
    view: matrix[4,4]f32,
    projection: matrix[4,4]f32,
    color: [4]f32,
    fog_distance: [2]f32,
}

//everythang needed to render (to) a camera...
Camera_Draw :: struct {
    //buffer: wgpu.Buffer,
    bind_group: wgpu.BindGroup,
    viewport: [4]f32,
    fill: bool,
    using uniforms: Camera_Uniforms,
}

Camera :: struct {
    buffer: wgpu.Buffer,
    bind_group: wgpu.BindGroup,
    translation: [3]f32,
    rotation: quaternion128,
    viewport: [4]f32, //xywh
    color: [4]f32, //background rgb+exposure
    range: [4]f32, //fov, near, far, fog onset
    relative: bool, //auto-resize based on window width/height
    fill: bool,
}

@(export)
set_background_color :: proc(cam: ^Camera, color: [3]f32) {
    cam.color.rgb = linalg.vector4_srgb_to_linear([4]f32{color.r, color.g, color.b, 1.0}).rgb
}

@(export)
set_exposure :: proc(cam: ^Camera, exp: f32) {
    cam.color.a = exp
}

@(export)
set_exposure_ev :: proc(cam: ^Camera, exp: f32) {
    cam.color.a = linalg.exp2(exp)
}

@(export)
set_fov_degrees :: proc(cam: ^Camera, fov: f32) {
    cam.range[0] = linalg.to_radians(fov)
}

@(export)
set_fov :: proc(cam: ^Camera, fov: f32) {
    cam.range[0] = fov
}

@(export)
set_near_clip :: proc(cam: ^Camera, near: f32) {
    cam.range[1] = near
}

@(export)
set_far_clip :: proc(cam: ^Camera, far: f32) {
    cam.range[2] = far
}

@(export)
set_fog_onset :: proc(cam: ^Camera, fog_onset: f32) {
    cam.range[3] = fog_onset
}

/* TODO:
when using absolute cameras with w/h != resolution, use upscaling/downscaling & letterboxing/pillarboxing
render to HDR (i.e. floating point) target so you can do post-processing
*/

@(export)
make_camera :: proc(viewport: [4]f32 = {0, 0, 0, 0}, near: f32 = 0, far: f32 = 0, fov: f32 = 0, fill: bool = true) -> (cam: Camera) {
    cam.buffer = wgpu.DeviceCreateBuffer(ren.device, &{usage={.Uniform, .CopyDst}, size=size_of(Camera_Uniforms)})
    bindings := []wgpu.BindGroupEntry{
        {binding = 0, buffer = cam.buffer, size = size_of(Camera_Uniforms)},
    }
    cam.bind_group = wgpu.DeviceCreateBindGroup(ren.device, &{
        layout = camera_layout,
        entryCount = len(bindings),
        entries = raw_data(bindings),
    })
    cam.viewport = viewport
    cam.range = {fov, near, far, (far - near) / 2}
    cam.rotation = 1
    cam.fill = fill
    cam.color.a = 1.0
    return
}

@(export)
make_camera_relative :: proc(viewport: [4]f32, near: f32 = 0, far: f32 = 0, fov: f32 = 0, fill: bool = true) -> (cam: Camera) {
    cam = make_camera(viewport, near, far, fov, fill)
    cam.relative = true
    return
}

look_at :: proc(cam: ^Camera, eye, center: [3]f32, up: [3]f32 = {0, 1, 0}) {
    cam.translation = eye
    eye := eye
    //dunno why it requires an inverse... handedness issues or z-flip maybe?
    cam.rotation = linalg.quaternion_inverse(linalg.quaternion_look_at(eye, center, up))
}

inverse_view :: proc(trans: matrix[4,4]f32) -> (inv_view: matrix[4,4]f32) {
    translation := trans[3].xyz
    rotation := cast(matrix[3,3]f32)(trans)
    inv_r := linalg.transpose(rotation) //can use transpose instead of inverse as it's orthonormal
    inv_t := -(inv_r * translation)
    inv_view[0] = {expand_values(inv_r[0]), 0}
    inv_view[1] = {expand_values(inv_r[1]), 0}
    inv_view[2] = {expand_values(inv_r[2]), 0}
    inv_view[3] = {expand_values(inv_t), 1}
    return
}

FOV :: 60.0
calculate_camera :: proc(cam: Camera, trans: matrix[4,4]f32 = 1) -> (draw: Camera_Draw) {
    draw.bind_group = cam.bind_group
    draw.view = inverse_view(trans * linalg.matrix4_from_trs(cam.translation, cam.rotation, 1))
    fov := cam.range[0]
    if fov == 0 {
        fov = linalg.to_radians(f32(FOV))
    } 
    draw.viewport = get_viewport_rect(cam)
    width, height := draw.viewport[2], draw.viewport[3]
    near := cam.range[1]
    far := cam.range[2]
    if near == 0 {
        near = 0.01
    }
    if far == 0 {
        draw.projection = linalg.matrix4_infinite_perspective(fov, width/height, near)
    } else {
        draw.projection = linalg.matrix4_perspective(fov, width/height, near, far)
    }
    fog_onset := cam.range[3] if cam.range[3] != 0 else (far - near)/2.0
    draw.color = cam.color
    draw.fill = cam.fill
    draw.fog_distance = {fog_onset, far}
    wgpu.QueueWriteBuffer(ren.queue, cam.buffer, 0, &draw.uniforms, size_of(Camera_Uniforms))
    return
}

bind_camera :: proc(render_pass: wgpu.RenderPassEncoder, slot: u32, cam: Camera_Draw) {
    x, y, w, h := expand_values(cam.viewport)
    wgpu.RenderPassEncoderSetViewport(render_pass, x, y, w, h, 0, 1)
    wgpu.RenderPassEncoderSetScissorRect(render_pass, u32(x), u32(y), u32(w), u32(h))
    wgpu.RenderPassEncoderSetBindGroup(render_pass, slot, cam.bind_group)
}

@(export)
delete_camera :: proc(cam: Camera) {
    wgpu.BufferRelease(cam.buffer)
    wgpu.BindGroupRelease(cam.bind_group)
}

@(export)
set_viewport :: proc(cam: ^Camera, viewport: [4]f32) {
    cam.viewport = viewport
}

get_viewport_rect :: proc(cam: Camera) -> [4]f32 {
    x, y := cam.viewport.x, cam.viewport.y
    width, height := get_viewport_size(cam)
    if cam.relative {
        x *= f32(screen_resolution.x)
        y *= f32(screen_resolution.y)
    }
    return {max(x, 0), max(y, 0), width, height}
}
get_viewport_size :: proc(cam: Camera) -> (width, height: f32) {
    width = cam.viewport[2]
    height = cam.viewport[3]
    if cam.relative {
        width = f32(screen_resolution.x) * width
        height = f32(screen_resolution.y) * height
    } else {
        if width == 0 {
            width = f32(screen_resolution.x)
        }
        if height == 0 {
            height = f32(screen_resolution.y)
        }
    }
    return
}

//returns the z coordinate which the camera should be at to have sprites rendered at z=0 be pixel-perfect
//(assumes FOV = default of 60 degrees)
@(export)
z_2d :: proc(cam: Camera) -> f32 {
    width, height := get_viewport_size(cam)
    return linalg.sqrt(linalg.pow(height, 2) - linalg.pow(height/2.0, 2))
}

//returns the minimum z-value you can offset sprites so that they will be depth-sorted but not visibly scaled by perspective (within tolerance)
MAX_Z_LAYERS :: 16 //conservative
PERSPECTIVE_SCALE_TOLERANCE :: 0.01 //maximum scale offset at max layer (0.01 should be invisible at most resolutions)
DEPTH_PADDING :: 2.0 //padding to avoid z-fighting
@(export)
z_min_step :: proc(cam: Camera, num_layers: int = MAX_Z_LAYERS) -> f32 {
    d := z_2d(cam)
    near := 0.01 if cam.range[1] == 0 else cam.range[1]
    far := 1024 if cam.range[2] == 0 else cam.range[2]

    depth_precision :: f32(1 << 24) //number of distinct values in depth buffer
    depth_quant: f32 //minimum epsilon given precision & perspective matrix
    if far == 0 {
        //infinite perspective
        depth_quant = (d*d)/(near*depth_precision)
    } else {
        //finite
        depth_quant = (d*d*(far - near))/(near*far*depth_precision)
    }
    depth_epsilon := depth_quant * DEPTH_PADDING
    scale_epsilon := (d * PERSPECTIVE_SCALE_TOLERANCE) / f32(num_layers)
    //depth buffer usually gives us lots of values to work with
    //for reasonable layer counts, depth quantum should win
    //for low depth precision or extremely high layer counts, scale epsilon would win (and likely result in z-fighting)
    return min(scale_epsilon, max(depth_epsilon, 1e-4))
}

@(export)
z_layer :: proc(cam: Camera, layer: int, num_layers: int = MAX_Z_LAYERS) -> f32 {
    return f32(layer) * z_min_step(cam, num_layers) 
}

bounds_in_frustum :: proc(cam: Camera_Uniforms, bounding_box: [8][4]f32) -> bool {
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
