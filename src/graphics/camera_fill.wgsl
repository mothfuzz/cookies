struct Camera {
    view: mat4x4<f32>,
    inv_view: mat4x4<f32>,
    projection: mat4x4<f32>,
    inv_viewproj: mat4x4<f32>,
    color: vec4<f32>, //rgb + exposure
    fog_distance: vec2<f32>, //fog onset + render distance
}
@group(0) @binding(0) var<uniform> camera: Camera;

struct CameraFillOut {
    @builtin(position) position: vec4<f32>,
    @location(0) ndc: vec2<f32>,
}

const fullscreen_vertices = array<vec2<f32>, 3>(
    vec2<f32>(-1, 3),
    vec2<f32>(3, -1),
    vec2<f32>(-1, -1),
);

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> CameraFillOut {
    var out: CameraFillOut;
    let xy = fullscreen_vertices[vertex_index];
    out.position = vec4<f32>(xy, 0, 1);
    out.ndc = xy;
    return out;
}

@group(1) @binding(0) var smp: sampler;
@group(1) @binding(1) var skybox: texture_cube<f32>;
@group(1) @binding(2) var background: texture_2d<f32>;
@fragment
fn fs_main(in: CameraFillOut) -> @location(0) vec4<f32> {
    var color = camera.color.rgb * camera.color.a;

    //need to use an arbitrary point bc camera might be infinite
    let world_pos = camera.inv_viewproj * vec4<f32>(in.ndc, 1.0, 1.0);
    let camera_pos = camera.inv_view[3].xyz;
    let sample_ray = normalize(world_pos.xyz - camera_pos * world_pos.w);
    let skybox_color = textureSample(skybox, smp, sample_ray);
    color = mix(color, skybox_color.rgb, skybox_color.a);

    let background_color = textureSample(background, smp, in.ndc * 0.5 + 0.5);
    color = mix(color, background_color.rgb, background_color.a);

    return vec4<f32>(color, 1.0);
}
