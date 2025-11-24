package graphics

import "vendor:wgpu"

Point_Light :: struct {
    position: [3]f32,
    radius: f32,
    render_shadows: bool,
    shadow_map: Texture,
}
Point_Light_Uniforms :: struct {
    position: [4]f32,
}
Directional_Light :: struct {}
Spot_Light :: struct {}

Light :: union {
    Point_Light,
    Directional_Light,
    Spot_Light,
}
POINT_LIGHT_SHADOW_MAP_RES :: 1024

make_point_light :: proc(position: [3]f32, radius: f32, render_shadows: bool = true) -> (pl: Point_Light) {
    pl.position = position
    pl.radius = radius
    pl.render_shadows = render_shadows
    if render_shadows {
        //make texture from RTT
        //need to add that proc
        //make_texture_2D_render_target(width, height)
        //render_to_texture(^Texture, ^Camera)
    }
    return
}

point_lights: [dynamic]Point_Light_Uniforms
draw_point_light :: proc(pl: Point_Light, trans: matrix[4,4]f32 = 1) {

}
