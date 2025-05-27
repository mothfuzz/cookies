@group(0) @binding(0) var<uniform> screen_size: vec2<f32>;
@group(0) @binding(1) var<uniform> screen_color_blend: f32;
@group(1) @binding(0) var smp: sampler;
@group(1) @binding(1) var albedo: texture_2d<f32>;

struct Vertex {
    @location(0) position: vec3<f32>,
    @location(1) texcoord: vec2<f32>,
    @location(2) color: vec4<f32>,
    @location(3) model_0: vec4<f32>,
    @location(4) model_1: vec4<f32>,
    @location(5) model_2: vec4<f32>,
    @location(6) model_3: vec4<f32>,
}

struct VSOut {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) @interpolate(perspective) texcoord: vec2<f32>,
}

@vertex
fn vs_main(vertex: Vertex, @builtin(vertex_index) vertex_index: u32, @builtin(instance_index) instance_index: u32) -> VSOut {
    var v: VSOut;
    let model = mat4x4<f32>(vertex.model_0, vertex.model_1, vertex.model_2, vertex.model_3);
    v.position = model * vec4<f32>(vertex.position, 1.0);
    v.texcoord = vertex.texcoord;
    v.color = vertex.color;
    return v;
}

@fragment
fn fs_main(v: VSOut) -> @location(0) vec4<f32> {
    let albedo = textureSample(albedo, smp, v.texcoord);
    let screen_color = vec4<f32>(v.position.x/screen_size.x, v.position.y/screen_size.y, 1.0, 1.0);
    let color = mix(v.color, screen_color, screen_color_blend);
    return albedo * color;
}
