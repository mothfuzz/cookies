struct CameraFillOut {
    @builtin(position) position: vec4<f32>,
}

const fullscreen_vertices = array<vec2<f32>, 3>(
    vec2<f32>(-1, 3),
    vec2<f32>(3, -1),
    vec2<f32>(-1, -1),
);

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> CameraFillOut {
    var out: CameraFillOut;
    out.position = vec4<f32>(fullscreen_vertices[vertex_index], 0, 1);
    return out;
}

struct Camera {
    view: mat4x4<f32>,
    projection: mat4x4<f32>,
    color: vec4<f32>, //rgb + exposure
    fog_distance: vec2<f32>, //fog onset + render distance
}
@group(0) @binding(0) var<uniform> camera: Camera;
@fragment
fn fs_main(in: CameraFillOut) -> @location(0) vec4<f32> {
    return vec4<f32>(camera.color.rgb*camera.color.a, 1.0);
}
