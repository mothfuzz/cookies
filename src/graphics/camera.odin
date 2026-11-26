package graphics

import "vendor:wgpu"
import "core:math/linalg"

//align to 256 so we can get 512 bytes and not have to do any math
Camera_Uniforms :: struct #align(256) {
    view, world, projection, viewproj, inv_viewproj: matrix[4,4]f32, //5x64
    frustum_planes: [6][4]f32, //left, right, bottom, top, near, far
    color: [4]f32, //rgb + exposure
    fog_distance: [2]f32,
    layer_mask: Layer_Mask, //vec2<u32>
    reserved: [2]u32,
    cascade_offset, cascade_count: u32,
    cascade_splits: [4]f32,
    //cluster info
    xy_scale: [2]f32, xy_bias: [2]f32, //derived from viewport
    z_scale: f32, z_bias: f32,
    grid_size: [4]u8, header_offset: u32,
}

Camera_Background :: struct {
    color: [3]f32, //srgb
    environment: Texture, //skybox or probe
    image: Texture, //2d image
    filtering: bool, //false for pixels
}

Camera_Raster_Background :: struct {
    environment: wgpu.TextureView,
    image: wgpu.TextureView,
    filtering: bool,
}

Camera_Raster :: struct {
    pass: int,
    viewport: [4]f32,
    near, far: f32,
    background: Camera_Raster_Background,
    fill: bool,
    flip: bool, //swap triangle cull mode back/front
}

Camera :: struct {
    translation: [3]f32,
    rotation: quaternion128,
    viewport: [4]f32, //xywh
    background: Camera_Background,
    exposure: f32, //evs
    fov: f32, //vertical, radians
    near, far: f32,
    fog_onset: f32,
    relative: bool, //auto-resize based on window width/height
    fill: bool,
    mirrored: bool, //flips view x
    layer_mask: Layer_Mask,
    cascades: Directional_Cascades,
}

/* TODO:
when using absolute cameras with w/h != resolution, use upscaling/downscaling & letterboxing/pillarboxing
render to HDR (i.e. floating point) target so you can do post-processing
*/

@(export)
make_camera :: proc(viewport: [4]f32 = {0, 0, 0, 0}, near: f32 = 0.1, far: f32 = 0, fov: f32 = linalg.RAD_PER_DEG*60, relative: bool = false, fill: bool = true, cascades: Directional_Cascades = .Default, layers: Layer_Mask = All_Layers) -> (cam: Camera) {
    cam.viewport = viewport
    cam.near = near
    cam.far = far
    cam.fov = fov
    cam.rotation = 1
    cam.relative = relative
    cam.fill = fill
    cam.cascades = cascades
    cam.layer_mask = layers
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

calculate_camera :: proc(cam: Camera, trans: matrix[4,4]f32 = 1, target_resolution: [2]uint = 0) -> (draw: Camera_Uniforms, raster: Camera_Raster) {
    assert(cam.fov > 0, "Camera must have a non-zero FOV")
    assert(cam.near > 0, "Camera must have a non-zero near plane")
    draw.world = trans * linalg.matrix4_from_trs(cam.translation, cam.rotation, 1)
    draw.view = rigid_inverse(draw.world)
    if cam.mirrored {
        xflip: matrix[4,4]f32
        xflip[0,0] = -1
        xflip[1,1] = 1
        xflip[2,2] = 1
        xflip[3,3] = 1
        draw.view = xflip * draw.view
    }
    raster.viewport = get_viewport_rect(cam, target_resolution)
    width, height := raster.viewport[2], raster.viewport[3]
    if cam.far == 0 {
        draw.projection = linalg.matrix4_infinite_perspective(cam.fov, width/height, cam.near)
        draw.fog_distance = 0
    } else {
        draw.projection = linalg.matrix4_perspective(cam.fov, width/height, cam.near, cam.far)
        draw.fog_distance[1] = cam.far
        if cam.fog_onset == 0 {
            draw.fog_distance[0] = cam.near + 0.75 * (cam.far - cam.near)
        } else {
            draw.fog_distance[0] = cam.fog_onset
        }
    }
    raster.near = cam.near
    raster.far = cam.far
    raster.flip = calculate_frustum(&draw)
    raster.fill = cam.fill
    if cam.background.environment.view != nil {
        raster.background.environment = cam.background.environment.view
    } else {
        raster.background.environment = trans_cubemap.view
    }
    if cam.background.image.view != nil {
        raster.background.image = cam.background.image.view
    } else {
        raster.background.image = trans_tex.view
    }
    raster.background.filtering = cam.background.filtering
    draw.color.rgb = linalg.vector3_srgb_to_linear(cam.background.color)
    draw.color.a = linalg.exp2(cam.exposure)
    draw.cascade_count = num_directional_cascades(cam.cascades)
    draw.layer_mask = cam.layer_mask
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
    x, y, w, h := **cam.viewport
    if cam.relative {
    }
    if cam.relative {
        x *= f32(screen_resolution.x)
        y *= f32(screen_resolution.y)
        w *= f32(screen_resolution.x)
        h *= f32(screen_resolution.y)
    } else {
        if w == 0 {
            w = f32(screen_resolution.x)
        }
        if h == 0 {
            h = f32(screen_resolution.y)
        }
    }
    return {max(x, 0), max(y, 0), w, h}
}

//returns the z coordinate which the camera should be at to have sprites rendered at z=0 be pixel-perfect
@(export)
z_2d :: proc(cam: Camera) -> f32 {
    height := get_viewport_rect(cam)[3]
    return height / (2 * linalg.tan(cam.fov * 0.5))
}

//returns the minimum z-value you can offset sprites so that they will be depth-sorted but not visibly scaled by perspective (within tolerance)
MAX_Z_LAYERS :: 16 //conservative
PERSPECTIVE_SCALE_TOLERANCE :: 0.01 //maximum scale offset at max layer (0.01 should be invisible at most resolutions)
DEPTH_PADDING :: 2.0 //padding to avoid z-fighting
@(export)
z_min_step :: proc(cam: Camera, num_layers: int = MAX_Z_LAYERS) -> f32 {
    d := z_2d(cam)
    depth_precision :: f32(1 << 24) //number of distinct values in depth buffer
    depth_quant: f32 //minimum epsilon given precision & perspective matrix
    if cam.far == 0 {
        //infinite perspective
        depth_quant = (d*d)/(cam.near*depth_precision)
    } else {
        //finite
        depth_quant = (d*d*(cam.far - cam.near))/(cam.near*cam.far*depth_precision)
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
