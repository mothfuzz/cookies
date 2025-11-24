struct Screen {
    size: vec4<f32>, //width, height, near plane, far plane
    color: vec4<f32>, //rgb, fog starting distance
}
@group(0) @binding(0) var<uniform> screen: Screen;


struct Camera {
    eye: vec4<f32>,
    center: vec4<f32>,
    view: mat4x4<f32>,
    projection: mat4x4<f32>,
}
@group(1) @binding(0) var<uniform> camera: Camera;


@group(2) @binding(0) var smp: sampler;
@group(2) @binding(1) var base_color: texture_2d<f32>;
@group(2) @binding(2) var normal: texture_2d<f32>;
@group(2) @binding(3) var pbr: texture_2d<f32>; //ambient roughness metallic
@group(2) @binding(4) var emissive: texture_2d<f32>;

struct PointLight {
    position: vec4<f32>, //xyz+radius
}
@group(3) @binding(0) var<storage, read> point_lights: array<PointLight>;

struct Vertex {
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) tangent: vec3<f32>,
    @location(3) texcoord: vec2<f32>,
    @location(4) color: vec4<f32>,
    @location(5) bones: vec4<f32>,
    @location(6) weights: vec4<f32>,
    @location(7) modelview_0: vec4<f32>,
    @location(8) modelview_1: vec4<f32>,
    @location(9) modelview_2: vec4<f32>,
    @location(10) modelview_3: vec4<f32>,
    @location(11) clip_rect: vec4<f32>,
    @location(12) tint: vec4<f32>,
    //@location(13) pbr_tint: vec3<f32>, //ambient, metallic, roughness
    //@location(14) emmissive_tint: vec4<f32>, //rgb + intensity
}

struct VSOut {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) @interpolate(perspective) texcoord: vec2<f32>,
    @location(2) tint: vec4<f32>,
    @location(3) view_position: vec4<f32>,
}

@vertex
fn vs_main(vertex: Vertex, @builtin(vertex_index) vertex_index: u32, @builtin(instance_index) instance_index: u32) -> VSOut {
    var v: VSOut;
    let modelview = mat4x4<f32>(vertex.modelview_0, vertex.modelview_1, vertex.modelview_2, vertex.modelview_3);
    v.view_position = modelview * vec4<f32>(vertex.position, 1.0);
    v.position = camera.projection * v.view_position;
    let tex_offset = vertex.clip_rect.xy;
    let tex_factor = vertex.clip_rect.zw;
    v.texcoord = vertex.texcoord*tex_factor+tex_offset;
    v.color = vertex.color;
    v.tint = vertex.tint;
    //v.world_position =
    return v;
}

@fragment
fn fs_main(v: VSOut) -> @location(0) vec4<f32> {
    let base_color = textureSample(base_color, smp, v.texcoord) * v.tint;
    let screen_color = vec4<f32>(v.position.x/screen.size.x, v.position.y/screen.size.y, 1.0, 1.0);
    let color = mix(v.color, screen_color, 0.0);
    var final_color = base_color * color;

    if !(final_color.a > 0) {
        discard;
    }

    let ndc = v.position.z * 2.0 - 1.0;
    let near = screen.size[2];
    let far = screen.size[3];
    let linear_depth = (2.0 * near * far) / (far + near - ndc * (far - near));
    let render_depth = false;
    if render_depth {
        final_color.r = linear_depth/far;
        final_color.g = linear_depth/far;
        final_color.b = linear_depth/far;
    } else {
        let fog_max = screen.size[3];
        var fog_min = screen.color[3];
        if fog_min == 0.0 {
            fog_min = (far - near)*0.5; //fog starts at halfway by default
        }
        let dist = abs(v.view_position.z / v.view_position.w);
        let fog_factor = clamp((fog_max - dist) / (fog_max - fog_min), 0, 1);
        let fog_color = vec4<f32>(screen.color.rgb, final_color.a);
        final_color = mix(fog_color, final_color, fog_factor);
    }
    return final_color;
}
