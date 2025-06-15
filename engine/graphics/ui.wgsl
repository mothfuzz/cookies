//@group(0) @binding(0) var<uniform> screen_size: vec2<f32>;

@group(0) @binding(0) var smp: sampler;
@group(0) @binding(1) var tex: texture_2d<f32>;

struct UiInstanceData {
    @location(0) fill_rect: vec4<f32>,
    @location(1) color: vec4<f32>,
    @location(2) clip_rect: vec4<f32>,
}

struct VSOut {
    @builtin(position) position: vec4<f32>,
    @location(0) @interpolate(perspective) texcoord: vec2<f32>,
    @location(1) @interpolate(flat) color: vec4<f32>,
}

const vertices = array<vec2<f32>, 4>(
    vec2<f32>(-1, -1),
    vec2<f32>(-1, 1),
    vec2<f32>(1, 1),
    vec2<f32>(1, -1),
);
const texcoords = array<vec2<f32>, 4>(
    vec2<f32>(0, 1),
    vec2<f32>(0, 0),
    vec2<f32>(1, 0),
    vec2<f32>(1, 1),
);
const indices = array<u32, 6>(0, 1, 2, 0, 2, 3);

@vertex
fn vs_main(instance: UiInstanceData, @builtin(vertex_index) vertex_index: u32, @builtin(instance_index) instance_index: u32) -> VSOut {
    var v: VSOut;
    var base: vec2<f32> = instance.fill_rect.xy;
    var size: vec2<f32> = instance.fill_rect.zw;
    var position: vec2<f32> = vertices[indices[vertex_index]];
    v.position = vec4<f32>(position*size/2 + base, 0.0, 1.0);
    let tex_offset = instance.clip_rect.xy;
    let tex_factor = instance.clip_rect.zw;
    var texcoord: vec2<f32> = texcoords[indices[vertex_index]];
    v.texcoord = texcoord * tex_factor + tex_offset;
    v.color = instance.color;
    return v;
}

@fragment
fn fs_main(v: VSOut) -> @location(0) vec4<f32> {
    var tex_color = textureSample(tex, smp, v.texcoord);
    return tex_color * v.color;
}
