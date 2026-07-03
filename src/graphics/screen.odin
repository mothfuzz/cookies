package graphics

Color_Profile :: enum u32 {
    LDR, //no tonemapping, PBR gets clamped to white
    HDR, //full PBR + tonemapping
}

Screen_Uniforms :: struct #packed {
    brightness: [2]f32, //brightness, black point
    color_profile: u32,
}

screen_uniforms: Screen_Uniforms = {{1.0, 0.0}, u32(Color_Profile.LDR)}


@(export)
set_color_profile :: proc(p: Color_Profile) {
    screen_uniforms.color_profile = u32(p)
}

@(export)
set_brightness :: proc(brightness: f32) {
    screen_uniforms.brightness[0] = brightness
}

@(export)
set_black_point :: proc(black_point: f32) {
    screen_uniforms.brightness[1] = black_point
}
