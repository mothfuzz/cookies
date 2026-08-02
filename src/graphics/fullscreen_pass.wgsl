struct VSOut {
    @builtin(position) position: vec4<f32>,
    @location(0) @interpolate(perspective) texcoord: vec2<f32>,
}

const fullscreen_vertices = array<vec2<f32>, 3>(
    vec2<f32>(-1, 3),
    vec2<f32>(3, -1),
    vec2<f32>(-1, -1),
);
const fullscreen_texcoords = array<vec2<f32>, 3>(
    vec2<f32>(0, 2),
    vec2<f32>(2, 0),
    vec2<f32>(0, 0),
);
@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VSOut {
    var out: VSOut;
    out.position = vec4<f32>(fullscreen_vertices[vertex_index], 0, 1);
    out.texcoord = fullscreen_texcoords[vertex_index];
    out.texcoord.y = 1.0-out.texcoord.y;
    return out;
}

@group(0) @binding(0) var smp: sampler;
@group(0) @binding(1) var tex: texture_2d<f32>;
@fragment
fn fs_main(in: VSOut) -> @location(0) vec4<f32> {
    //return vec4<f32>(1, 0, 0, 1);
    return textureSample(tex, smp, in.texcoord);
}
