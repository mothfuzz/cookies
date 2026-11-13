const fullscreen_vertices = array<vec2<f32>, 3>(
    vec2<f32>(-1, 3),
    vec2<f32>(3, -1),
    vec2<f32>(-1, -1),
);
@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> @builtin(position) vec4<f32> {
    return vec4<f32>(fullscreen_vertices[vertex_index], 0, 1);
}

@group(0) @binding(0) var accum: texture_multisampled_2d<f32>;
@group(0) @binding(1) var revealage: texture_multisampled_2d<f32>;
@fragment
fn fs_main(@builtin(position) pos: vec4<f32>, @builtin(sample_index) s: u32) -> @location(0) vec4<f32> {
    let p = vec2<i32>(pos.xy);
    let revealage = textureLoad(revealage, p, i32(s)).r;
    if(revealage > 1.0 - 1e-5) {
        discard;
    }
    let accum = textureLoad(accum, p, i32(s));
    let avg_rgb = accum.rgb / max(accum.a, 1e-5);
    let opacity = 1.0 - revealage;
    return vec4<f32>(avg_rgb * opacity, opacity);
}
