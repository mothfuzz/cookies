package graphics

import "vendor:wgpu"
import "core:math/linalg"

Point_Light :: struct {
    position: [3]f32,
    color: [4]f32,
    range: f32,
    render_shadows: bool,
    shadow_index: int,
}
Point_Light_Uniforms :: struct #packed {
    position: [4]f32, //view space xyz + radius
    color: [4]f32, //rgb+intensity
    shadow_index: [4]i32,
}
Directional_Light :: struct {
    direction: [3]f32,
    color: [4]f32,
    render_shadows: bool,
    shadow_index: int,
}

DIRECTIONAL_CASCADES :: 4

Directional_Light_Uniforms :: struct #packed {
    direction: [4]f32,
    color: [4]f32,
    view_to_shadow: [DIRECTIONAL_CASCADES]matrix[4,4]f32,
    cascade_splits: [4]f32,
    shadow_index: [4]i32,
}
Spot_Light :: struct {
    position: [3]f32,
    direction: [3]f32,
    inner_angle: f32,
    outer_angle: f32,
    color: [4]f32,
    range: f32,
    render_shadows: bool,
    shadow_index: int,
}
Spot_Light_Uniforms :: struct #packed {
    position: [4]f32, //xyz + inner angle
    direction: [4]f32, //xyz + outer angle
    color: [4]f32,
    view_to_shadow: matrix[4,4]f32,
    shadow_index: i32,
    range: f32,
    _: [2]f32,
}

LIGHT_MINIMUM :: 0.001 //~= 0

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
        sampler = {type = .Filtering}
    },
    //point light depth shadows
    wgpu.BindGroupLayoutEntry{
        binding = 6,
        visibility = {.Fragment},
        texture = {sampleType = .Depth, viewDimension = .CubeArray, multisampled=false},
    },
    //point light color shadows
    wgpu.BindGroupLayoutEntry{
        binding = 7,
        visibility = {.Fragment},
        texture = {sampleType = .Float, viewDimension = .CubeArray, multisampled=false},
    },
    //directional light depth shadows
    wgpu.BindGroupLayoutEntry{
        binding = 8,
        visibility = {.Fragment},
        texture = {sampleType = .Depth, viewDimension = ._2DArray, multisampled=false},
    },
    //directional light color shadows
    wgpu.BindGroupLayoutEntry{
        binding = 9,
        visibility = {.Fragment},
        texture = {sampleType = .Float, viewDimension = ._2DArray, multisampled=false},
    },
    //spot light depth shadows
    wgpu.BindGroupLayoutEntry{
        binding = 10,
        visibility = {.Fragment},
        texture = {sampleType = .Depth, viewDimension = ._2DArray, multisampled=false},
    },
    //spot light color shadows
    wgpu.BindGroupLayoutEntry{
        binding = 11,
        visibility = {.Fragment},
        texture = {sampleType = .Float, viewDimension = ._2DArray, multisampled=false},
    },
    //cubemaps texture
    wgpu.BindGroupLayoutEntry{
        binding = 12,
        visibility = {.Fragment},
        texture = {sampleType = .Float, viewDimension = .CubeArray, multisampled=false},
    },
    //cubemaps sampler
    wgpu.BindGroupLayoutEntry{
        binding = 13,
        visibility = {.Fragment},
        sampler = {type = .Filtering}
    },
    //cubemaps box buffer
    wgpu.BindGroupLayoutEntry{
        binding = 14,
        visibility = {.Fragment},
        buffer = {type = .ReadOnlyStorage},
    }
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


Lights_Uniforms :: struct {
    point_lights: []Point_Light_Uniforms,
    directional_lights: []Directional_Light_Uniforms,
    spot_lights: []Spot_Light_Uniforms,
}
