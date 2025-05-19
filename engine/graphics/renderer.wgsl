@group(0) @binding(0) var<uniform> screen_size: vec2<f32>;

struct VSOut {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) @interpolate(linear) texcoord: vec2<f32>,
}

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32, @builtin(instance_index) instance_index: u32) -> VSOut {
    let positions = array(
        vec2<f32>(0.0, 0.5),
        vec2<f32>(-0.5, -0.5),
        vec2<f32>(0.5, -0.5),
    );
    let colors = array(
        vec4<f32>(1, 0, 0, 1),
        vec4<f32>(0, 1, 0, 1),
        vec4<f32>(0, 0, 1, 1),
    );
    var v: VSOut;
    v.position = vec4<f32>(positions[vertex_index], 0.0, 1.0);
    v.color = colors[vertex_index];
    return v;
}


@fragment
fn fs_main(v: VSOut) -> @location(0) vec4<f32> {
    return mix(v.color, vec4<f32>(v.position.x/screen_size.x, v.position.y/screen_size.y, 1.0, 1.0), 0.0);
    //return v.color;
}
