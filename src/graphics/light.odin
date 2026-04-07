package graphics

import "vendor:wgpu"
import "core:math/linalg"
import "core:fmt"

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
    view_to_shadow: matrix[4,4]f32,
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

Light :: union {
    Point_Light,
    Directional_Light,
    Spot_Light,
}

vecpos :: proc(p: [3]f32) -> [4]f32 {
    return {p.x, p.y, p.z, 1}
}

vecdir :: proc(d: [3]f32) -> [4]f32 {
    return {d.x, d.y, d.z, 0}
}

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

point_lights: [dynamic]Point_Light
draw_point_light :: proc(pl: Point_Light, trans: matrix[4,4]f32 = 1) {
    pl := pl
    //transform position directly
    pl.position = (trans * vecpos(pl.position)).xyz
    //scale radius by largest scale factor
    pl.radius *= max(linalg.length(trans[0].xyz), linalg.length(trans[1].xyz), linalg.length(trans[2].xyz))
    append(&point_lights, pl)
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

directional_lights: [dynamic]Directional_Light
draw_directional_light :: proc(dl: Directional_Light, trans: matrix[4,4]f32 = 1) {
    dl := dl
    //transform direction directly
    dl.direction = (trans * vecdir(dl.direction)).xyz
    //dl.color = dl.color
    append(&directional_lights, dl)
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

spot_lights: [dynamic]Spot_Light
draw_spot_light :: proc(sl: Spot_Light, trans: matrix[4,4]f32 = 1) {
    sl := sl
    sl.position = (trans * vecpos(sl.position)).xyz
    sl.direction = (trans * vecdir(sl.direction)).xyz
    append(&spot_lights, sl)
}

clear_lights :: proc() {
    clear(&point_lights)
    clear(&directional_lights)
    clear(&spot_lights)
}

current_light_bind_group: wgpu.BindGroup
current_point_lights_buffer: wgpu.Buffer
current_directional_lights_buffer: wgpu.Buffer
current_spot_lights_buffer: wgpu.Buffer

lights_bound: bool = false
bind_lights :: proc(render_pass: wgpu.RenderPassEncoder, slot: u32, cam: ^Camera) {
    if lights_bound {
        wgpu.BindGroupRelease(current_light_bind_group)
        wgpu.BufferRelease(current_point_lights_buffer)
        wgpu.BufferRelease(current_directional_lights_buffer)
        wgpu.BufferRelease(current_spot_lights_buffer)
    }

    //defaults!!!
    //if no lights at all, create a default "2D" directional light (facing z-forward)
    if len(point_lights) == 0 && len(directional_lights) == 0 && len(spot_lights) == 0 {
        //append(&directional_lights, Directional_Light{direction={0, 0, 1}, color=1})
        //unlit...
    }
    //otherwise just add default lights with no influence
    if len(point_lights) == 0 {
        append(&point_lights, Point_Light{color=0})
    }
    if len(directional_lights) == 0 {
        append(&directional_lights, Directional_Light{color=0})
    }
    if len(spot_lights) == 0 {
        append(&spot_lights, Spot_Light{color=0})
    }

    point_light_uniforms := make([]Point_Light_Uniforms, len(point_lights))
    defer delete(point_light_uniforms)
    //convert to view-space
    for &pl, i in point_light_uniforms {
        pl.position.xyz = (cam.view * vecpos(point_lights[i].position)).xyz
        pl.position.w = point_lights[i].radius
        pl.color = point_lights[i].color
    }
    current_point_lights_buffer = wgpu.DeviceCreateBufferWithDataSlice(ren.device, &{usage={.Storage}}, point_light_uniforms[:])

    directional_light_uniforms := make([]Directional_Light_Uniforms, len(directional_lights))
    defer delete(directional_light_uniforms)
    //convert to view-space
    for &dl, i in directional_light_uniforms {
        dir := directional_lights[i].direction
        dl.direction.xyz = linalg.normalize((cam.view * vecdir(dir)).xyz)
        dl.color = directional_lights[i].color;
    }
    current_directional_lights_buffer = wgpu.DeviceCreateBufferWithDataSlice(ren.device, &{usage={.Storage}}, directional_light_uniforms[:])

    spot_light_uniforms := make([]Spot_Light_Uniforms, len(spot_lights))
    defer delete(spot_light_uniforms)
    //convert to view-space
    for &sl, i in spot_light_uniforms {
        dir := spot_lights[i].direction
        //dir.y = -dir.y
        sl.position.xyz = (cam.view * vecpos(spot_lights[i].position)).xyz
        sl.position.w = linalg.cos(spot_lights[i].inner_angle)
        sl.direction.xyz = linalg.normalize((cam.view * vecdir(dir)).xyz)
        sl.direction.w = linalg.cos(spot_lights[i].outer_angle)
        sl.color = spot_lights[i].color;
    }
    current_spot_lights_buffer = wgpu.DeviceCreateBufferWithDataSlice(ren.device, &{usage={.Storage}}, spot_light_uniforms[:])


    bindings := []wgpu.BindGroupEntry{
        {binding = 0, buffer=current_point_lights_buffer, size=size_of(Point_Light_Uniforms)*u64(len(point_light_uniforms))},
        {binding = 1, buffer=current_directional_lights_buffer, size=size_of(Directional_Light_Uniforms)*u64(len(directional_light_uniforms))},
        {binding = 2, buffer=current_spot_lights_buffer, size=size_of(Spot_Light_Uniforms)*u64(len(spot_light_uniforms))},
    }
    current_light_bind_group = wgpu.DeviceCreateBindGroup(ren.device, &{
        layout = lights_layout,
        entryCount = len(bindings),
        entries = raw_data(bindings),
    })
    wgpu.RenderPassEncoderSetBindGroup(render_pass, slot, current_light_bind_group)
    lights_bound = true
}

delete_lights :: proc() {
    delete(point_lights)
    delete(directional_lights)
    delete(spot_lights)
}
