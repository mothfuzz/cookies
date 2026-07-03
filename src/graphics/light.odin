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
}
Point_Light_Uniforms :: struct #packed {
    position: [4]f32, //view space xyz + radius
    color: [4]f32, //rgb+intensity
    view_to_shadow: matrix[4,4]f32, //just inverse view
}
Directional_Light :: struct {
    direction: [3]f32,
    color: [4]f32,
    render_shadows: bool,
    shadow_camera: Camera,
}
Directional_Light_Uniforms :: struct #packed {
    direction: [4]f32,
    color: [4]f32,
    view_to_shadow_near: matrix[4,4]f32,
    view_to_shadow_far: matrix[4,4]f32,
}
Spot_Light :: struct {
    position: [3]f32,
    direction: [3]f32,
    inner_angle: f32,
    outer_angle: f32,
    color: [4]f32,
    render_shadows: bool,
    shadow_camera: Camera,
}
Spot_Light_Uniforms :: struct #packed {
    position: [4]f32, //xyz + inner angle
    direction: [4]f32, //xyz + outer angle
    color: [4]f32,
    view_to_shadow: matrix[4,4]f32,
}

lights_layout_entries := []wgpu.BindGroupLayoutEntry{
    //point lights
    wgpu.BindGroupLayoutEntry{
        binding = 0,
        visibility = {.Fragment},
        buffer = {type=.ReadOnlyStorage},
    },
    //directional lights
    wgpu.BindGroupLayoutEntry{
        binding = 1,
        visibility = {.Fragment},
        buffer = {type=.ReadOnlyStorage},
    },
    //spot lights
    wgpu.BindGroupLayoutEntry{
        binding = 2,
        visibility = {.Fragment},
        buffer = {type=.ReadOnlyStorage},
    },
    //shadow depth sampler (must be Comparison for textureSampleCompare in WGSL)
    wgpu.BindGroupLayoutEntry{
        binding = 3,
        visibility = {.Fragment},
        sampler = {type = .Comparison}
    },
    //shadow color sampler
    wgpu.BindGroupLayoutEntry{
        binding = 4,
        visibility = {.Fragment},
        sampler = {type = .NonFiltering}
    },
    //spot light depth shadows
    wgpu.BindGroupLayoutEntry{
        binding = 5,
        visibility = {.Fragment},
        texture = {sampleType = .Depth, viewDimension = ._2DArray, multisampled=false},
    },
    //spot light color shadows
    wgpu.BindGroupLayoutEntry{
        binding = 6,
        visibility = {.Fragment},
        texture = {sampleType = .Float, viewDimension = ._2DArray, multisampled=false},
    },
}
lights_layout: wgpu.BindGroupLayout


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
}

Lights :: struct {
    point_lights: []Point_Light,
    point_light_shadow_cameras: []Camera_Draw,
    directional_lights: []Directional_Light,
    directional_light_shadow_cameras: []Camera_Draw,
    spot_lights: []Spot_Light,
    spot_light_shadow_cameras: []Camera_Draw,
}

vecpos :: proc(p: [3]f32) -> [4]f32 {
    return {p.x, p.y, p.z, 1}
}

vecdir :: proc(d: [3]f32) -> [4]f32 {
    return {d.x, d.y, d.z, 0}
}


calculate_lights :: proc(lights: []Light_Draw) -> Lights {
    point_lights := make([dynamic]Point_Light)
    point_light_shadow_cameras := make([dynamic]Camera_Draw)
    directional_lights := make([dynamic]Directional_Light)
    directional_light_shadow_cameras := make([dynamic]Camera_Draw)
    spot_lights := make([dynamic]Spot_Light)
    spot_light_shadow_cameras := make([dynamic]Camera_Draw)
    num_spot_lights_shadows: uint = 0
    for light in lights {
        switch l in light.light {
        case Point_Light:
            pl := l
            pl.position = (light.transform * vecpos(l.position)).xyz
            if pl.render_shadows {
                inject_at(&point_lights, 0, pl)
            } else {
                append(&point_lights, pl)
            }
        case Directional_Light:
            dl := l
            dl.direction = (light.transform * vecdir(l.direction)).xyz
            if dl.render_shadows {
                inject_at(&directional_lights, 0, dl)
            } else {
                append(&directional_lights, dl)
            }
        case Spot_Light:
            sl := l
            sl.position = (light.transform * vecpos(sl.position)).xyz
            sl.direction = (light.transform * vecdir(sl.direction)).xyz
            if sl.render_shadows {
                num_spot_lights_shadows += 1

                //handle parallel-to-up case
                world_up := [3]f32{0, 1, 0}
                if linalg.abs(linalg.dot(sl.direction, world_up)) >= 0.9 {
                    world_up = {0, 0, 1}
                }

                look_at(&sl.shadow_camera, sl.position, sl.position + sl.direction, world_up)
                inject_at(&spot_light_shadow_cameras, 0, calculate_camera(sl.shadow_camera))
                inject_at(&spot_lights, 0, sl)
            } else {
                append(&spot_lights, sl)
            }
        }
    }
    //make sure buffers are non-zero, add default lights with zero influence
    if len(point_lights) == 0 {
        append(&point_lights, Point_Light{color=0})
    }
    if len(directional_lights) == 0 {
        append(&directional_lights, Directional_Light{color=0})
    }
    if len(spot_lights) == 0 {
        append(&spot_lights, Spot_Light{color=0})
    }

    //create textures
    if u32(num_spot_lights_shadows) > wgpu.TextureGetDepthOrArrayLayers(ren.spot_light_shadow_depth.image) {
        delete_texture(ren.spot_light_shadow_depth)
        size: [2]uint = {SPOT_LIGHT_SHADOW_MAP_RES, SPOT_LIGHT_SHADOW_MAP_RES}
        ren.spot_light_shadow_depth = make_render_target_array(size, .Depth32Float, num_spot_lights_shadows)
        delete_texture(ren.spot_light_shadow_color)
        ren.spot_light_shadow_color = make_render_target_array(size, .RGBA8Unorm, num_spot_lights_shadows)
    }
    
    return Lights{point_lights[:], point_light_shadow_cameras[:],
                  directional_lights[:], directional_light_shadow_cameras[:],
                  spot_lights[:], spot_light_shadow_cameras[:]}
}

delete_lights :: proc(lights: Lights) {
    delete(lights.point_lights)
    delete(lights.directional_lights)
    delete(lights.spot_lights)
}

Lights_Uniforms :: struct {
    point_lights: []Point_Light_Uniforms,
    directional_lights: []Directional_Light_Uniforms,
    spot_lights: []Spot_Light_Uniforms,
}

calculate_lights_uniforms :: proc(lights: Lights, camera: Camera_Uniforms) -> Lights_Uniforms {
    //convert lights to view-space & pack into uniform buffers

    point_light_uniforms := make([]Point_Light_Uniforms, len(lights.point_lights))
    for &pl, i in point_light_uniforms {
        pl.position.xyz = (camera.view * vecpos(lights.point_lights[i].position)).xyz
        pl.position.w = lights.point_lights[i].radius
        pl.color = lights.point_lights[i].color
    }

    directional_light_uniforms := make([]Directional_Light_Uniforms, len(lights.directional_lights))
    for &dl, i in directional_light_uniforms {
        dir := lights.directional_lights[i].direction
        dl.direction.xyz = linalg.normalize((camera.view * vecdir(dir)).xyz)
        dl.color = lights.directional_lights[i].color;
    }

    spot_light_uniforms := make([]Spot_Light_Uniforms, len(lights.spot_lights))
    for &sl, i in spot_light_uniforms {
        dir := lights.spot_lights[i].direction
        //dir.y = -dir.y
        sl.position.xyz = (camera.view * vecpos(lights.spot_lights[i].position)).xyz
        sl.position.w = linalg.cos(lights.spot_lights[i].inner_angle)
        sl.direction.xyz = linalg.normalize((camera.view * vecdir(dir)).xyz)
        sl.direction.w = linalg.cos(lights.spot_lights[i].outer_angle)
        sl.color = lights.spot_lights[i].color;
        if lights.spot_lights[i].render_shadows {
            light_cam := lights.spot_light_shadow_cameras[i]
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


bind_lights :: proc(render_pass: wgpu.RenderPassEncoder, slot: u32, lights: Lights_Uniforms) {
    //lights := lights

    point_lights_buffer := wgpu.DeviceCreateBufferWithDataSlice(ren.device, &{usage={.Storage}}, lights.point_lights)
    defer wgpu.BufferRelease(point_lights_buffer)

    directional_lights_buffer := wgpu.DeviceCreateBufferWithDataSlice(ren.device, &{usage={.Storage}}, lights.directional_lights)
    defer wgpu.BufferRelease(directional_lights_buffer)

    spot_lights_buffer := wgpu.DeviceCreateBufferWithDataSlice(ren.device, &{usage={.Storage}}, lights.spot_lights)
    defer wgpu.BufferRelease(spot_lights_buffer)

    bindings := []wgpu.BindGroupEntry{
        {binding = 0, buffer=point_lights_buffer, size=size_of(Point_Light_Uniforms)*u64(len(lights.point_lights))},
        {binding = 1, buffer=directional_lights_buffer, size=size_of(Directional_Light_Uniforms)*u64(len(lights.directional_lights))},
        {binding = 2, buffer=spot_lights_buffer, size=size_of(Spot_Light_Uniforms)*u64(len(lights.spot_lights))},
        {binding = 3, sampler=ren.shadow_depth_sampler},
        {binding = 4, sampler=ren.shadow_color_sampler},
        {binding = 5, textureView=ren.spot_light_shadow_depth.view},
        {binding = 6, textureView=ren.spot_light_shadow_color.view},
    }
    light_bind_group := wgpu.DeviceCreateBindGroup(ren.device, &{
        layout = lights_layout,
        entryCount = len(bindings),
        entries = raw_data(bindings),
    })
    defer wgpu.BindGroupRelease(light_bind_group)

    wgpu.RenderPassEncoderSetBindGroup(render_pass, slot, light_bind_group)
}
