@group(0) @binding(0) var<uniform> screen_size: vec2<f32>;
@group(0) @binding(1) var<uniform> screen_color_blend: f32;

struct Camera {
    eye: vec4<f32>,
    center: vec4<f32>,
    view: mat4x4<f32>,
    projection: mat4x4<f32>,
}
@group(1) @binding(0) var<uniform> camera: Camera;

@group(2) @binding(0) var smp: sampler;
@group(2) @binding(1) var albedo: texture_2d<f32>;

struct Vertex {
    @location(0) position: vec3<f32>,
    @location(1) texcoord: vec2<f32>,
    @location(2) color: vec4<f32>,
    @location(3) mvp_0: vec4<f32>,
    @location(4) mvp_1: vec4<f32>,
    @location(5) mvp_2: vec4<f32>,
    @location(6) mvp_3: vec4<f32>,
    @location(7) clip_rect: vec4<f32>,
}

struct VSOut {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) @interpolate(perspective) texcoord: vec2<f32>,
}

@vertex
fn vs_main(vertex: Vertex, @builtin(vertex_index) vertex_index: u32, @builtin(instance_index) instance_index: u32) -> VSOut {
    var v: VSOut;
    let mvp = mat4x4<f32>(vertex.mvp_0, vertex.mvp_1, vertex.mvp_2, vertex.mvp_3);
    v.position = mvp * vec4<f32>(vertex.position, 1.0);
    let tex_offset = vertex.clip_rect.xy;
    let tex_factor = vertex.clip_rect.zw;
    v.texcoord = (vertex.texcoord + tex_offset)*tex_factor;
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
