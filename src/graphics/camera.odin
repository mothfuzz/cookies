package graphics

import "vendor:wgpu"
import "core:math/linalg"

// TODO: move to camera_fill_bindings.odin
camera_bg_layout_entries :: []wgpu.BindGroupLayoutEntry{
    {
        binding = 0,
        visibility = {.Fragment},
        sampler = {type = .Filtering},
    },
    {
        binding = 1,
        visibility = {.Fragment},
        texture = {sampleType = .Float, viewDimension = .Cube},
    },
    {
        binding = 2,
        visibility = {.Fragment},
        texture = {sampleType = .Float, viewDimension = ._2D},
    },
}
camera_bg_layout: wgpu.BindGroupLayout
bg_sampler: wgpu.Sampler

//align to 256 so we can get 512 bytes and not have to do any math
//need all the previously CPU-only data on the GPU struct now if we want to do GPU culling
Camera_Uniforms :: struct #align(256) {
    view, world, projection, viewproj, inv_viewproj: matrix[4,4]f32, //5x64
    frustum_planes: [6][4]f32, //left, right, bottom, top, near, far
    color: [4]f32, //rgb + exposure
    fog_distance: [2]f32,
    layer_mask: Layer_Mask, //vec2<u32>
    mirrored: b32, reserved: u32,
    cascade_offset, cascade_count: u32,
    cascade_splits: [4]f32,
    //cluster info
    xy_scale: [2]f32, xy_bias: [2]f32, //derived from viewport
    z_scale: f32, z_bias: f32,
    grid_size: [4]u8, header_offset: u32,
}

Camera_Raster :: struct {
    pass: int,
    viewport: [4]f32,
    near, far: f32,
    bg_bind_group: wgpu.BindGroup, //nil = no fill
    flip: bool, //swap triangle cull mode back/front
}

Camera :: struct {
    buffer: wgpu.Buffer,
    bg_bind_group: wgpu.BindGroup,
    bg_image: wgpu.TextureView,
    bg_skybox: wgpu.TextureView,
    translation: [3]f32,
    rotation: quaternion128,
    viewport: [4]f32, //xywh
    color: [4]f32, //background rgb+exposure
    range: [4]f32, //fov, near, far, fog onset
    relative: bool, //auto-resize based on window width/height
    fill: bool,
    cubemap: bool, //flips view x
    layer_mask: Layer_Mask,
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

@(export)
set_draw_distance :: proc(cam: ^Camera, distance: f32) {
    set_far_clip(cam, distance)
}

@(export)
set_layer_mask :: proc(cam: ^Camera, layer_mask: Layer_Mask) {
    cam.layer_mask = layer_mask
}

@(export)
set_background_image :: proc(cam: ^Camera, tex: Texture) {
    cam.bg_image = tex.view
    rebind_bg(cam)
}

@(export)
set_skybox :: proc(cam: ^Camera, tex: Texture) {
    cam.bg_skybox = tex.view
    rebind_bg(cam)
}

@(private)
rebind_bg :: proc(cam: ^Camera) {
    if cam.bg_bind_group != nil {
        wgpu.BindGroupRelease(cam.bg_bind_group)
    }
    entries := []wgpu.BindGroupEntry{
        {binding = 0, sampler = bg_sampler},
        {binding = 1, textureView = cam.bg_skybox},
        {binding = 2, textureView = cam.bg_image},
    }
    cam.bg_bind_group = wgpu.DeviceCreateBindGroup(ren.device, &{
        layout = camera_bg_layout,
        entries = raw_data(entries),
        entryCount = len(entries),
    }) 
}

/* TODO:
when using absolute cameras with w/h != resolution, use upscaling/downscaling & letterboxing/pillarboxing
render to HDR (i.e. floating point) target so you can do post-processing
*/

@(export)
make_camera :: proc(viewport: [4]f32 = {0, 0, 0, 0}, near: f32 = 0, far: f32 = 0, fov: f32 = 0, fill: bool = true, layers: Layer_Mask = All_Layers) -> (cam: Camera) {
    cam.viewport = viewport
    fog_onset := f32(0)
    if far != 0 {
        fog_onset = (far - near) / 2
    }
    cam.range = {fov, near, far, fog_onset}
    cam.rotation = 1
    cam.fill = fill
    cam.color.a = 1.0
    cam.layer_mask = layers
    if bg_sampler == nil {
        bg_sampler = wgpu.DeviceCreateSampler(ren.device, &{minFilter = .Linear, magFilter = .Linear, mipmapFilter=.Nearest, maxAnisotropy=1})
    }
    cam.bg_skybox = trans_cubemap.view
    cam.bg_image = trans_tex.view
    rebind_bg(&cam)
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
    cam.rotation = linalg.quaternion_from_forward_and_up(center - eye, up)
}

rigid_inverse :: proc(trans: matrix[4,4]f32) -> (inv: matrix[4,4]f32) {
    translation := trans[3].xyz
    rotation := cast(matrix[3,3]f32)(trans)
    inv_r := linalg.transpose(rotation) //can use transpose instead of inverse as it's orthonormal
    inv_t := -(inv_r * translation)
    inv[0] = {expand_values(inv_r[0]), 0}
    inv[1] = {expand_values(inv_r[1]), 0}
    inv[2] = {expand_values(inv_r[2]), 0}
    inv[3] = {expand_values(inv_t), 1}
    return
}

calculate_frustum :: proc(cam: ^Camera_Uniforms) -> (flipped: bool) {
    cam.viewproj = cam.projection * cam.view
    cam.inv_viewproj = linalg.inverse(cam.viewproj)
    //calculate frustum planes... Gribb-Hartmann
    rows := linalg.transpose(cam.viewproj)
    cam.frustum_planes[0] = rows[3] + rows[0]
    cam.frustum_planes[1] = rows[3] - rows[0]
    cam.frustum_planes[2] = rows[3] + rows[1]
    cam.frustum_planes[3] = rows[3] - rows[1]
    cam.frustum_planes[4] = rows[2]
    cam.frustum_planes[5] = rows[3] - rows[2]
    //normalize planes
    for &p in cam.frustum_planes {
        l := linalg.length(p.xyz)
        if l < 1e-6 {
            //don't divide by zero, always pass this plane
            p = {0, 0, 0, 1}
        } else {
            p = p/l
        }
    }
    flipped = linalg.determinant(cast(matrix[4,4]f32)cam.view) < 0
    return
}

FOV :: 60.0
calculate_camera :: proc(cam: Camera, trans: matrix[4,4]f32 = 1, target_resolution: [2]uint = 0) -> (draw: Camera_Uniforms, raster: Camera_Raster) {
    draw.world = trans * linalg.matrix4_from_trs(cam.translation, cam.rotation, 1)
    draw.view = rigid_inverse(draw.world)
    if cam.cubemap {
        xflip: matrix[4,4]f32
        xflip[0,0] = -1
        xflip[1,1] = 1
        xflip[2,2] = 1
        xflip[3,3] = 1
        draw.view = xflip * draw.view
        draw.mirrored = true
    }
    fov := cam.range[0]
    if fov == 0 {
        fov = linalg.to_radians(f32(FOV))
    } 
    raster.viewport = get_viewport_rect(cam, target_resolution)
    width, height := raster.viewport[2], raster.viewport[3]
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
    raster.near = near
    raster.far = far
    raster.flip = calculate_frustum(&draw)
    fog_onset := cam.range[3] if cam.range[3] != 0 else (far - near)/2.0
    draw.color = cam.color
    //draw.cascade_count = num_directional_cascades(cam.directional_cascades)
    draw.layer_mask = cam.layer_mask
    draw.fog_distance = {fog_onset, far}
    if cam.fill {
        raster.bg_bind_group = cam.bg_bind_group
    }
    return
}

@(export)
set_viewport :: proc(cam: ^Camera, viewport: [4]f32) {
    cam.viewport = viewport
}

get_viewport_rect :: proc(cam: Camera, target_resolution: [2]uint = 0) -> [4]f32 {
    screen_resolution := screen_resolution
    if target_resolution != 0 {
        screen_resolution = target_resolution
    }
    x, y := cam.viewport.x, cam.viewport.y
    width, height := get_viewport_size(cam, screen_resolution)
    if cam.relative {
        x *= f32(screen_resolution.x)
        y *= f32(screen_resolution.y)
    }
    return {max(x, 0), max(y, 0), width, height}
}
get_viewport_size :: proc(cam: Camera, target_resolution: [2]uint = 0) -> (width, height: f32) {
    screen_resolution := screen_resolution
    if target_resolution != 0 {
        screen_resolution = target_resolution
    }
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
@(export)
z_2d :: proc(cam: Camera) -> f32 {
    width, height := get_viewport_size(cam)
    fov := cam.range[0]
    if fov == 0 {
        fov = linalg.to_radians(f32(FOV))
    }
    return height / (2 * linalg.tan(fov * 0.5))
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

sphere_in_frustum :: proc(cam: Camera_Uniforms, bounding_center: [3]f32, bounding_radius: f32) -> bool {
    for p in cam.frustum_planes {
        if linalg.dot(p.xyz, bounding_center) + p.w < -bounding_radius {
            return false
        }
    }
    return true 
}

bounds_in_frustum :: proc(cam: Camera_Uniforms, bounding_center: [3]f32, bounding_axes: [3][3]f32) -> bool {
    for p in cam.frustum_planes {
        n := p.xyz
        //project OBB axes onto plane's normal, then it becomes roughly the same as sphere check
        r := abs(linalg.dot(n, bounding_axes[0])) +
            abs(linalg.dot(n, bounding_axes[1])) +
            abs(linalg.dot(n, bounding_axes[2]))
        if linalg.dot(n, bounding_center) + p.w < -r {
            return false
        }
    }
    return true
}
