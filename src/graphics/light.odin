package graphics

import "vendor:wgpu"
import "core:math/linalg"

Point_Light :: struct {
    position: [3]f32,
    radius: f32,
    color: [4]f32,
    render_shadows: bool,
    shadow_map: Texture,
}
Point_Light_Uniforms :: struct {
    position: [4]f32, //view space xyz + radius
    color: [4]f32, //rgb+intensity
    view_to_shadow: matrix[4,4]f32,
}
Directional_Light :: struct {
    direction: [3]f32,
    color: [4]f32,
    render_shadows: bool,
    shadow_map_near: Texture,
    shadow_map_far: Texture,
}
Directional_Light_Uniforms :: struct {
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
    shadow_map: Texture,
}
Spot_Light_Uniforms :: struct {
    position: [4]f32, //xyz + inner angle
    direction: [4]f32, //xyz + outer angle
    color: [4]f32,
    view_to_shadow: matrix[4,4]f32,
}

lights_layout_entries := []wgpu.BindGroupLayoutEntry{
    //point lights
    wgpu.BindGroupLayoutEntry{
        binding = 0,
        visibility = {.Vertex, .Fragment},
        buffer = {type=.ReadOnlyStorage},
    },
    //directional lights
    wgpu.BindGroupLayoutEntry{
        binding = 1,
        visibility = {.Vertex, .Fragment},
        buffer = {type=.ReadOnlyStorage},
    },
    //spot lights
    wgpu.BindGroupLayoutEntry{
        binding = 2,
        visibility = {.Vertex, .Fragment},
        buffer = {type=.ReadOnlyStorage},
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
    if render_shadows {
        //make texture from RTT
        //need to add that proc
        //make_texture_2D_render_target(width, height)
        //render_to_texture(^Texture, ^Camera)
    }
    return
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
    directional_lights: []Directional_Light,
    spot_lights: []Spot_Light,
}

vecpos :: proc(p: [3]f32) -> [4]f32 {
    return {p.x, p.y, p.z, 1}
}

vecdir :: proc(d: [3]f32) -> [4]f32 {
    return {d.x, d.y, d.z, 0}
}


calculate_lights :: proc(lights: []Light_Draw) -> Lights {
    point_lights := make([dynamic]Point_Light)
    directional_lights := make([dynamic]Directional_Light)
    spot_lights := make([dynamic]Spot_Light)
    for light in lights {
        switch l in light.light {
        case Point_Light:
            pl := l
            pl.position = (light.transform * vecpos(l.position)).xyz
            append(&point_lights, pl)
        case Directional_Light:
            dl := l
            dl.direction = (light.transform * vecdir(l.direction)).xyz
            append(&directional_lights, dl)
        case Spot_Light:
            sl := l
            sl.position = (light.transform * vecpos(sl.position)).xyz
            sl.direction = (light.transform * vecdir(sl.direction)).xyz
            append(&spot_lights, sl)
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
    return Lights{point_lights[:], directional_lights[:], spot_lights[:]}
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

calculate_lights_uniforms :: proc(lights: Lights, camera: Camera) -> Lights_Uniforms {
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
    }
    light_bind_group := wgpu.DeviceCreateBindGroup(ren.device, &{
        layout = lights_layout,
        entryCount = len(bindings),
        entries = raw_data(bindings),
    })
    defer wgpu.BindGroupRelease(light_bind_group)

    wgpu.RenderPassEncoderSetBindGroup(render_pass, slot, light_bind_group)
}
