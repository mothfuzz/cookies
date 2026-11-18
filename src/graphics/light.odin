package graphics

import "vendor:wgpu"
import "core:math/linalg"

Point_Light :: struct {
    position: [3]f32,
    color: [4]f32,
    range: f32,
    render_shadows: bool,
}
Point_Light_Uniforms :: struct #align(16) {
    color: [4]f32,
    position: [3]f32, range: f32,
    layer_mask: Layer_Mask, //u64
}

POINT_SHADOW_RES :: #config(POINT_SHADOW_RES, 1024)

Directional_Light :: struct {
    direction: [3]f32,
    color: [4]f32,
    render_shadows: bool,
}

Directional_Light_Uniforms :: struct #align(16) {
    color: [4]f32,
    direction: [4]f32,
    layer_mask: Layer_Mask,
    //padding here
    //cascades handled by Camera
}

DIRECTIONAL_SHADOW_RES :: #config(DIRECTIONAL_SHADOW_RES, 2048)
DIRECTIONAL_CASCADES :: #config(DIRECTIONAL_CASCADES, 4)
DIRECTIONAL_CASCADE_SPLIT_WEIGHT :: #config(DIRECTIONAL_CASCADE_SPLIT_WEIGHT, 0.5)
Directional_Cascades :: enum u8 {
    Default,
    Off,
    One, Two, Three, Four,
}
num_directional_cascades :: proc(d: Directional_Cascades) -> (cascade_count: u32) {
    switch d {
    case .Default: cascade_count = DIRECTIONAL_CASCADES
    case .Off: cascade_count = 0
    case .One: cascade_count = 1
    case .Two: cascade_count = 2
    case .Three: cascade_count = 3
    case .Four: cascade_count = 4
    }
    return
}

Spot_Light :: struct {
    position: [3]f32,
    direction: [3]f32,
    inner_angle: f32,
    outer_angle: f32,
    color: [4]f32,
    range: f32,
    render_shadows: bool,
}
Spot_Light_Uniforms :: struct #align(16) {
    color: [4]f32,
    position: [3]f32, range: f32,
    direction: [4]f32,
    inner_angle, outer_angle: f32,
    layer_mask: Layer_Mask,
}

SPOT_SHADOW_RES :: #config(SPOT_SHADOW_RES, 1024)

LIGHT_MINIMUM :: 0.001 //~= 0

make_point_light :: proc(position: [3]f32 = 0, color: [4]f32 = 1, range: f32 = 0, render_shadows: bool = true) -> (pl: Point_Light) {
    pl.position = position
    pl.color = color
    if range == 0 {
        pl.range = linalg.sqrt(color.a / LIGHT_MINIMUM)
    } else {
        pl.range = range
    }
    pl.render_shadows = render_shadows
    return
}

make_directional_light :: proc(direction: [3]f32 = {0, 0, -1}, color: [4]f32 = 1, render_shadows: bool = true) -> (dl: Directional_Light) {
    dl.direction = direction
    dl.color = color
    dl.render_shadows = render_shadows
    return
}

make_spot_light :: proc(position: [3]f32 = 0, direction: [3]f32 = {0, 0, -1}, inner_angle: f32, outer_angle: f32 = 0, color: [4]f32 = 1, range: f32 = 0, render_shadows: bool = true) -> (sl: Spot_Light) {
    sl.position = position
    sl.direction = direction
    sl.inner_angle = inner_angle
    sl.outer_angle = outer_angle == 0?inner_angle:outer_angle
    sl.color = color
    if range == 0 {
        sl.range = linalg.sqrt(color.a / LIGHT_MINIMUM)
    } else {
        sl.range = range
    }
    sl.render_shadows = render_shadows
    return
}
