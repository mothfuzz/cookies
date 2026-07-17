package graphics

import "vendor:wgpu"
import "core:math/linalg"

// TODO: shadow mapping
/*
high level:
- keep track of previous light state (position, color, direction, radius, angles, etc.)
- perform frustum culling as well as check if any point in BB <= radius
- if light state has changed or list of rendered objects has changed (dunno), re-render shadow map
- for point lights:
- instance scene 6 times (frustum/distance culling for each, so they won't be the exact same necessarily), set up 6 render targets, render them in one shader to a cubemap
- for directional lights:
- render scene N times (again, frustum culling for each) for each cascade (2 right now but, you know)
- for spot lights:
- do frustum culling, also check if BB <= outer_angle, render scene once (easy!)

- for each light in the shader:
- discard transparent (a<0.1 or something) pixels
- multiplicative blending (src = Zero, dst = SrcColor) to render colors
- opaques just get 1 ig

- then bind your textures in a big fat array and do shadow mapping
- for point lights / spot lights determine if pixel is within radius/angle at all
- for directional lights use the pixel's depth to slot it into one of the cascades depending on values (cascade ranges themselves calculated based on minimum/maximum object depth)

- use Normal Offset Bias to prevent shadow acne / peter panning at the same time.
*/

Point_Light :: struct {
    position: [3]f32,
    radius: f32,
    color: [4]f32,
    render_shadows: bool,
    shadow_cameras: [6]Camera,
    shadow_index: int,
}
Point_Light_Uniforms :: struct #packed {
    position: [4]f32, //view space xyz + radius
    color: [4]f32, //rgb+intensity
    view_to_shadow: matrix[4,4]f32, //just inverse view (maybe not per-light?)
    shadow_index: [4]i32,
}
Directional_Light :: struct {
    direction: [3]f32,
    color: [4]f32,
    render_shadows: bool,
    shadow_camera: Camera,
    shadow_index: int,
}
Directional_Light_Uniforms :: struct #packed {
    direction: [4]f32,
    color: [4]f32,
    view_to_shadow_near: matrix[4,4]f32,
    view_to_shadow_far: matrix[4,4]f32,
    shadow_index: [4]i32,
}
Spot_Light :: struct {
    position: [3]f32,
    direction: [3]f32,
    inner_angle: f32,
    outer_angle: f32,
    color: [4]f32,
    render_shadows: bool,
    shadow_camera: Camera,
    shadow_index: int,
}
Spot_Light_Uniforms :: struct #packed {
    position: [4]f32, //xyz + inner angle
    direction: [4]f32, //xyz + outer angle
    color: [4]f32,
    view_to_shadow: matrix[4,4]f32,
    shadow_index: [4]i32,
}

lights_layout_entries := []wgpu.BindGroupLayoutEntry{
    //point lights
    wgpu.BindGroupLayoutEntry{
        binding = 0,
        visibility = {.Fragment},
        buffer = {type=.ReadOnlyStorage, hasDynamicOffset = true},
    },
    //directional lights
    wgpu.BindGroupLayoutEntry{
        binding = 1,
        visibility = {.Fragment},
        buffer = {type=.ReadOnlyStorage, hasDynamicOffset = true},
    },
    //spot lights
    wgpu.BindGroupLayoutEntry{
        binding = 2,
        visibility = {.Fragment},
        buffer = {type=.ReadOnlyStorage, hasDynamicOffset = true},
    },
    //light count
    wgpu.BindGroupLayoutEntry{
        binding = 3,
        visibility = {.Fragment},
        buffer = {type=.Uniform},
    },
    //shadow depth sampler (must be Comparison for textureSampleCompare in WGSL)
    wgpu.BindGroupLayoutEntry{
        binding = 4,
        visibility = {.Fragment},
        sampler = {type = .Comparison}
    },
    //shadow color sampler
    wgpu.BindGroupLayoutEntry{
        binding = 5,
        visibility = {.Fragment},
        sampler = {type = .NonFiltering}
    },
    //spot light depth shadows
    wgpu.BindGroupLayoutEntry{
        binding = 6,
        visibility = {.Fragment},
        texture = {sampleType = .Depth, viewDimension = ._2DArray, multisampled=false},
    },
    //spot light color shadows
    wgpu.BindGroupLayoutEntry{
        binding = 7,
        visibility = {.Fragment},
        texture = {sampleType = .Float, viewDimension = ._2DArray, multisampled=false},
    },
}
lights_layout: wgpu.BindGroupLayout

Light_Count :: struct {
    point: u32,
    directional: u32,
    spot: u32,
    total: u32,
}
light_count_buffer: wgpu.Buffer
light_count_buffer_init: bool


POINT_LIGHT_SHADOW_MAP_RES :: 1024

make_point_light :: proc(position: [3]f32, radius: f32, color: [4]f32 = 1, render_shadows: bool = true) -> (pl: Point_Light) {
    pl.position = position
    pl.radius = radius
    pl.color = color
    pl.render_shadows = render_shadows
    if render_shadows {
        //make texture from RTT
        //need to add that proc
        //make_texture_2D_render_target(width, height)
        //render_to_texture(^Texture, ^Camera)
    }
    return
}

delete_point_light :: proc(pl: Point_Light) {
    if pl.render_shadows {
        #unroll for cam in pl.shadow_cameras {
            delete_camera(cam)
        }
    }
}

DIRECTIONAL_LIGHT_NEAR_SHADOW_MAP_RES :: 1024
DIRECTIONAL_LIGHT_FAR_SHADOW_MAP_RES :: 1024
DIRECTIONAL_CASCADES :: 3

make_directional_light :: proc(direction: [3]f32, color: [4]f32 = 1, render_shadows: bool = true) -> (dl: Directional_Light) {
    dl.direction = direction
    dl.color = color
    dl.render_shadows = render_shadows
    if render_shadows {
        //make texture from RTT
        //need to add that proc
        //make_texture_2D_render_target(width, height)
        //render_to_texture(^Texture, ^Camera)
    }
    return
}

SPOT_LIGHT_SHADOW_MAP_RES :: 1024

make_spot_light :: proc(position: [3]f32, direction: [3]f32, inner_angle: f32, outer_angle: f32 = 0, color: [4]f32 = 1, render_shadows: bool = true) -> (sl: Spot_Light) {
    sl.position = position
    sl.direction = direction
    sl.inner_angle = inner_angle
    sl.outer_angle = outer_angle == 0?inner_angle:outer_angle
    sl.color = color
    sl.render_shadows = render_shadows
    if render_shadows {
        sl.shadow_camera = make_camera({0, 0, SPOT_LIGHT_SHADOW_MAP_RES, SPOT_LIGHT_SHADOW_MAP_RES}, 0.1, 0, sl.outer_angle*2)
    }
    return
}

delete_spot_light :: proc(sl: Spot_Light) {
    if sl.render_shadows {
        delete_camera(sl.shadow_camera)
    }
}

Light_Draw :: struct {
    light: union {
        Point_Light,
        Directional_Light,
        Spot_Light,
    },
    transform: matrix[4,4]f32,
    layer_mask: Layer_Mask,
}

Lights :: struct {
    point_lights: []Point_Light,
    directional_lights: []Directional_Light,
    spot_lights: []Spot_Light,
    shadow_cameras: []Camera_Draw, //point, directional, spot
    num_point_shadows: int,
    num_directional_shadows: int,
    num_spot_shadows: int,
}

vecpos :: proc(p: [3]f32) -> [4]f32 {
    return {p.x, p.y, p.z, 1}
}

vecdir :: proc(d: [3]f32) -> [4]f32 {
    return {d.x, d.y, d.z, 0}
}


calculate_lights :: proc(lights: []Light_Draw, cameras: []Camera_Draw) -> Lights {
    point_lights := make([dynamic]Point_Light)
    directional_lights := make([dynamic]Directional_Light)
    spot_lights := make([dynamic]Spot_Light)
    shadow_cameras := make([dynamic]Camera_Draw)
    num_point_shadows: int = 0
    num_directional_shadows: int = 0
    num_spot_shadows: int = 0
    for light in lights {
        passing: bool
        for cam in cameras {
            if (light.layer_mask & cam.layer_mask) != 0 {
                passing = true
                break
            }
        }
        if !passing do continue

        switch l in light.light {
        case Point_Light:
            pl := l
            pl.position = (light.transform * vecpos(l.position)).xyz
            //perform frustum culling here, early exit if it passes at least one camera.
            if pl.render_shadows {
                //pl.shadow_index = num_point_shadows
                //num_point_shadows += 1
                //for i in 0..<6 {
                //append(&shadow_cameras, calculate_camera(...))
                //}
            }
            append(&point_lights, pl)
        case Directional_Light:
            dl := l
            dl.direction = (light.transform * vecdir(l.direction)).xyz
            if dl.render_shadows {
                //dl.shadow_index = num_directional_shadows
                //num_directional_shadows += 1
                //for i in 0..<num_cascades * num_cameras {
                //append(&shadow_cameras, calculate_camera(...))
                //}
            }
            append(&directional_lights, dl)
        case Spot_Light:
            sl := l
            sl.position = (light.transform * vecpos(sl.position)).xyz
            sl.direction = (light.transform * vecdir(sl.direction)).xyz
            if sl.render_shadows {
                sl.shadow_camera.layer_mask = light.layer_mask //don't render filtered objects to the shadow map
                sl.shadow_index = num_spot_shadows
                num_spot_shadows += 1

                //handle parallel-to-up case
                world_up := [3]f32{0, 1, 0}
                if linalg.abs(linalg.dot(sl.direction, world_up)) >= 0.9 {
                    world_up = {0, 0, 1}
                }

                look_at(&sl.shadow_camera, sl.position, sl.position + sl.direction, world_up)
                append(&shadow_cameras, calculate_camera(sl.shadow_camera))
            }
            append(&spot_lights, sl)
        }
    }

    light_count := Light_Count{
        point = u32(len(point_lights)),
        directional = u32(len(directional_lights)),
        spot = u32(len(spot_lights)),
        total = u32(len(point_lights) + len(directional_lights) + len(spot_lights))
    }
    if !light_count_buffer_init {
        light_count_buffer = wgpu.DeviceCreateBuffer(ren.device, &{usage = {.Uniform, .CopyDst}, size = size_of(Light_Count)})
        light_count_buffer_init = true
    }
    wgpu.QueueWriteBuffer(ren.queue, light_count_buffer, 0, &light_count, size_of(Light_Count))

    //create textures
    if u32(num_spot_shadows) > wgpu.TextureGetDepthOrArrayLayers(ren.spot_light_shadow_depth.image) {
        delete_texture(ren.spot_light_shadow_depth)
        size: [2]uint = {SPOT_LIGHT_SHADOW_MAP_RES, SPOT_LIGHT_SHADOW_MAP_RES}
        ren.spot_light_shadow_depth = make_render_target_array(size, .Depth32Float, uint(num_spot_shadows))
        delete_texture(ren.spot_light_shadow_color)
        ren.spot_light_shadow_color = make_render_target_array(size, .RGBA8Unorm, uint(num_spot_shadows))
    }
    
    return Lights{
        point_lights[:], directional_lights[:], spot_lights[:], shadow_cameras[:],
        num_point_shadows, num_directional_shadows, num_spot_shadows,
    }
}

delete_lights :: proc(lights: Lights) {
    delete(lights.point_lights)
    delete(lights.directional_lights)
    delete(lights.spot_lights)
    delete(lights.shadow_cameras)
}

Lights_Uniforms :: struct {
    point_lights: []Point_Light_Uniforms,
    directional_lights: []Directional_Light_Uniforms,
    spot_lights: []Spot_Light_Uniforms,
}

Shadow_Offsets :: struct {
    p, d, s: int,
}
shadow_offsets :: proc(lights: Lights, cameras: []Camera_Draw) -> (offsets: Shadow_Offsets) {
    offsets.p = 0
    offsets.d = lights.num_point_shadows * 6
    offsets.s = offsets.d + lights.num_directional_shadows * len(cameras) * DIRECTIONAL_CASCADES
    return
}

calculate_lights_uniforms :: proc(lights: Lights, camera: Camera_Uniforms, offsets: Shadow_Offsets) -> Lights_Uniforms {
    //convert lights to view-space & pack into uniform buffers

    point_light_uniforms := make([]Point_Light_Uniforms, len(lights.point_lights))
    for &pl, i in point_light_uniforms {
        pl_in := lights.point_lights[i]
        pl.position.xyz = (camera.view * vecpos(pl_in.position)).xyz
        pl.position.w = pl_in.radius
        pl.color = pl_in.color
        if pl_in.render_shadows {
            //light_cam = lights.shadow_cameras[pl_in.shadow_index]
            //matrix not needed...
            pl.shadow_index = i32(pl_in.shadow_index)
        } else {
            pl.shadow_index = -1
        }
    }

    directional_light_uniforms := make([]Directional_Light_Uniforms, len(lights.directional_lights))
    for &dl, i in directional_light_uniforms {
        dl_in := lights.directional_lights[i]
        dl.direction.xyz = linalg.normalize((camera.view * vecdir(dl_in.direction)).xyz)
        dl.color = dl_in.color;
        if dl_in.render_shadows {
            //light_cam = lights.shadow_cameras[dl_in.shadow_index]
            //do that for each cascade...
            dl.shadow_index = i32(dl_in.shadow_index)
        } else {
            dl.shadow_index = -1
        }
    }

    spot_light_uniforms := make([]Spot_Light_Uniforms, len(lights.spot_lights))
    for &sl, i in spot_light_uniforms {
        sl_in := lights.spot_lights[i]
        sl.position.xyz = (camera.view * vecpos(sl_in.position)).xyz
        sl.position.w = linalg.cos(sl_in.inner_angle)
        sl.direction.xyz = linalg.normalize((camera.view * vecdir(sl_in.direction)).xyz)
        sl.direction.w = linalg.cos(sl_in.outer_angle)
        sl.color = sl_in.color;
        if sl_in.render_shadows {
            light_cam := lights.shadow_cameras[offsets.s + sl_in.shadow_index]
            sl.shadow_index = i32(sl_in.shadow_index)
            sl.view_to_shadow = light_cam.projection * light_cam.view * inverse_view(camera.view)
        }
    }

    return {point_light_uniforms[:], directional_light_uniforms[:], spot_light_uniforms[:]}
}

delete_lights_uniforms :: proc(lights: Lights_Uniforms) {
    delete(lights.point_lights)
    delete(lights.directional_lights)
    delete(lights.spot_lights)
}

light_bind_group: wgpu.BindGroup
light_bind_group_created: bool

Light_Buffer :: struct {
    size_aligned: int,
    capacity: int,
    buffer: wgpu.Buffer,
}

pl_buffer, dl_buffer, sl_buffer: Light_Buffer

import "base:runtime"

//since lights are buffered per-camera we need to offset them so that queueWriteBuffer doesn't overwrite.
realloc_light_buffers :: proc(lights: Lights, num_cameras: int) {
    p_size := len(lights.point_lights) * size_of(Point_Light_Uniforms)
    d_size := len(lights.directional_lights) * size_of(Directional_Light_Uniforms)
    s_size := len(lights.spot_lights) * size_of(Spot_Light_Uniforms)

    rebind := false
    p_min_size := max(storage_alignment, size_of(Point_Light_Uniforms))
    p_size_aligned := max(runtime.align_forward(p_size, storage_alignment), p_min_size)
    d_min_size := max(storage_alignment, size_of(Directional_Light_Uniforms))
    d_size_aligned := max(runtime.align_forward(d_size, storage_alignment), d_min_size)
    s_min_size := max(storage_alignment, size_of(Spot_Light_Uniforms))
    s_size_aligned := max(runtime.align_forward(s_size, storage_alignment), s_min_size)
    if p_size_aligned != pl_buffer.size_aligned ||
        d_size_aligned != dl_buffer.size_aligned ||
        s_size_aligned != sl_buffer.size_aligned {
            rebind = true
        }
    pl_buffer.size_aligned = p_size_aligned
    dl_buffer.size_aligned = d_size_aligned
    sl_buffer.size_aligned = s_size_aligned

    if pl_buffer.size_aligned * num_cameras > pl_buffer.capacity {
        if pl_buffer.capacity > 0 {
            wgpu.BufferRelease(pl_buffer.buffer)
        }
        pl_buffer.buffer = wgpu.DeviceCreateBuffer(ren.device, &{usage = {.Storage, .CopyDst}, size = u64(pl_buffer.size_aligned * num_cameras)})
        pl_buffer.capacity = int(wgpu.BufferGetSize(pl_buffer.buffer))
        rebind = true
    }
    if dl_buffer.size_aligned * num_cameras > dl_buffer.capacity {
        if dl_buffer.capacity > 0 {
            wgpu.BufferRelease(dl_buffer.buffer)
        }
        dl_buffer.buffer = wgpu.DeviceCreateBuffer(ren.device, &{usage = {.Storage, .CopyDst}, size = u64(dl_buffer.size_aligned * num_cameras)})
        dl_buffer.capacity = int(wgpu.BufferGetSize(dl_buffer.buffer))
        rebind = true
    }
    if sl_buffer.size_aligned * num_cameras > sl_buffer.capacity {
        if sl_buffer.capacity > 0 {
            wgpu.BufferRelease(sl_buffer.buffer)
        }
        sl_buffer.buffer = wgpu.DeviceCreateBuffer(ren.device, &{usage = {.Storage, .CopyDst}, size = u64(sl_buffer.size_aligned * num_cameras)})
        sl_buffer.capacity = int(wgpu.BufferGetSize(sl_buffer.buffer))
        rebind = true
    }

    if rebind {
        if light_bind_group_created {
            wgpu.BindGroupRelease(light_bind_group)
        }
        bindings := []wgpu.BindGroupEntry{
            {binding = 0, buffer = pl_buffer.buffer, size = u64(pl_buffer.size_aligned * num_cameras)},
            {binding = 1, buffer = dl_buffer.buffer, size = u64(dl_buffer.size_aligned * num_cameras)},
            {binding = 2, buffer = sl_buffer.buffer, size = u64(sl_buffer.size_aligned * num_cameras)},
            {binding = 3, buffer = light_count_buffer, size = u64(size_of(Light_Count))},
            {binding = 4, sampler=ren.shadow_depth_sampler},
            {binding = 5, sampler=ren.shadow_color_sampler},
            {binding = 6, textureView=ren.spot_light_shadow_depth.view},
            {binding = 7, textureView=ren.spot_light_shadow_color.view},
        }
        light_bind_group = wgpu.DeviceCreateBindGroup(ren.device, &{
            layout = lights_layout,
            entryCount = len(bindings),
            entries = raw_data(bindings),
        })
        light_bind_group_created = true
    }
}

write_light_buffers :: proc(lights: Lights, cameras: []Camera_Draw, offsets: Shadow_Offsets) {
    realloc_light_buffers(lights, len(cameras))
    for camera, i in cameras {
        lights_uniforms := calculate_lights_uniforms(lights, camera, offsets)
        defer delete_lights_uniforms(lights_uniforms)
        if len(lights_uniforms.point_lights) > 0 {
            pl_offset := u64(i * int(pl_buffer.size_aligned))
            wgpu.QueueWriteBuffer(ren.queue, pl_buffer.buffer, pl_offset, raw_data(lights_uniforms.point_lights), uint(pl_buffer.size_aligned))
        }
        if len(lights_uniforms.directional_lights) > 0 {
            dl_offset := u64(i * int(dl_buffer.size_aligned))
            wgpu.QueueWriteBuffer(ren.queue, dl_buffer.buffer, dl_offset, raw_data(lights_uniforms.directional_lights), uint(dl_buffer.size_aligned))
        }
        if len(lights_uniforms.spot_lights) > 0 {
            sl_offset := u64(i * int(sl_buffer.size_aligned))
            wgpu.QueueWriteBuffer(ren.queue, sl_buffer.buffer, sl_offset, raw_data(lights_uniforms.spot_lights), uint(sl_buffer.size_aligned))
        }
    }
}

bind_lights :: proc(render_pass: wgpu.RenderPassEncoder, slot: u32, camera_index: u32) {
    dynamic_offsets := [?]u32{
        camera_index * u32(pl_buffer.size_aligned),
        camera_index * u32(dl_buffer.size_aligned),
        camera_index * u32(sl_buffer.size_aligned),
    }
    wgpu.RenderPassEncoderSetBindGroup(render_pass, slot, light_bind_group, dynamic_offsets[:])
}

delete_lights_buffer :: proc() {
    if light_bind_group != nil {
        wgpu.BindGroupRelease(light_bind_group)
    }
    if pl_buffer.capacity > 0 {
        wgpu.BufferRelease(pl_buffer.buffer)
    }
    if dl_buffer.capacity > 0 {
        wgpu.BufferRelease(dl_buffer.buffer)
    }
    if sl_buffer.capacity > 0 {
        wgpu.BufferRelease(sl_buffer.buffer)
    }
}
