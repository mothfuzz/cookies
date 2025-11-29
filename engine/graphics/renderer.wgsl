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
    position: vec4<f32>, //view space xyz+radius
    color: vec4<f32>, //rgb+intensity
    view_to_shadow: mat4x4<f32>,
}
@group(3) @binding(0) var<storage, read> point_lights: array<PointLight>;

struct DirectionalLight {
    direction: vec4<f32>, //view space xyz+radius
    color: vec4<f32>, //rgb+intensity
    view_to_shadow: mat4x4<f32>,
}
@group(3) @binding(1) var<storage, read> directional_lights: array<DirectionalLight>;

struct SpotLight {
    position: vec4<f32>,//xyz+inner angle
    direction: vec4<f32>,//xyz+outer angle
    color: vec4<f32>,
    view_to_shadow: mat4x4<f32>,
}
@group(3) @binding(2) var<storage, read> spot_lights: array<SpotLight>;

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
    @builtin(position) out_position: vec4<f32>,
    @location(0) position: vec4<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) tangent: vec3<f32>,
    @location(3) @interpolate(perspective) texcoord: vec2<f32>,
    @location(4) color: vec4<f32>,
    @location(5) tint: vec4<f32>,
}

@vertex
fn vs_main(vertex: Vertex, @builtin(vertex_index) vertex_index: u32, @builtin(instance_index) instance_index: u32) -> VSOut {
    var v: VSOut;
    let modelview = mat4x4<f32>(vertex.modelview_0, vertex.modelview_1, vertex.modelview_2, vertex.modelview_3);
    v.position = modelview * vec4<f32>(vertex.position, 1.0);
    v.normal = normalize((modelview * vec4<f32>(vertex.normal, 0.0)).xyz);
    v.tangent = normalize((modelview * vec4<f32>(vertex.tangent, 0.0)).xyz);
    v.out_position = camera.projection * v.position;
    let tex_offset = vertex.clip_rect.xy;
    let tex_factor = vertex.clip_rect.zw;
    v.texcoord = vertex.texcoord*tex_factor+tex_offset;
    v.color = vertex.color;
    v.tint = vertex.tint;
    return v;
}

fn calculate_influence_phong(n: vec3<f32>, v: vec3<f32>, l: vec3<f32>, radiance: vec3<f32>) -> vec3<f32> {
    let diffuse = max(dot(n, l), 0.0);
    let specular = pow(max(dot(v, reflect(-l, n)), 0.0), 256.0);
    return (diffuse + specular)*radiance;
}

const PI = radians(180.0);
fn fresnel_schlick_reflectance(cos_theta: f32, base_reflectance: vec3<f32>) -> vec3<f32> {
    return base_reflectance + (1.0 - base_reflectance) * pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
}
fn normal_distribution_ggx(n: vec3<f32>, h: vec3<f32>, roughness: f32) -> f32 {
    let a = roughness * roughness;
    let a2 = a*a;
    let nh = max(dot(n, h), 0.0);
    let factor = (nh*nh * (a2 - 1.0) + 1.0);
    return a2 / (PI * factor * factor);
}
fn geometry_attenuation_ggx_schlick(cos_angle: f32, roughness: f32) -> f32 {
    let r = roughness + 1.0;
    let k = (r * r) / 8.0;
    return cos_angle / (cos_angle * (1.0 - k) + k);
}
fn geometry_attenuation_smith(n: vec3<f32>, v: vec3<f32>, l: vec3<f32>, roughness: f32) -> f32 {
    //a microfacet has blocked the light from hitting another microfacet
    let shadowing = geometry_attenuation_ggx_schlick(max(dot(n, v), 0.0), roughness);
    //a microfacet has blocked the light from coming back to the viewer
    let masking = geometry_attenuation_ggx_schlick(max(dot(n, l), 0.0), roughness);

    return shadowing * masking;
}
fn calculate_influence_pbr(n: vec3<f32>, v: vec3<f32>, l: vec3<f32>, radiance: vec3<f32>, base_color: vec3<f32>, roughness: f32, metallic: f32) -> vec3<f32> {
    let h = normalize(v + l);
    let cos_theta = max(dot(h, v), 0.0);
    var base_reflectance = vec3<f32>(0.04); //base dielectric reflectance
    base_reflectance = mix(base_reflectance, base_color, metallic);
    let reflectance = fresnel_schlick_reflectance(cos_theta, base_reflectance);

    let normal_distribution = normal_distribution_ggx(n, h, roughness);
    let geometry_attenuation = geometry_attenuation_smith(n, v, l, roughness);

    let numerator = normal_distribution * geometry_attenuation * reflectance;
    let denominator = 4.0 * max(dot(n, v), 0.0) * max(dot(n, l), 0.0) + 0.0001; //extra epsilon to prevent divide-by-zero
    let specular = numerator / denominator;

    let diffuse_ratio = (1.0 - metallic) * (vec3<f32>(1.0) - reflectance);
    let diffuse = diffuse_ratio * base_color / PI;

    return (diffuse + specular) * radiance * max(dot(n, l), 0.0);
}

@fragment
fn fs_main(in: VSOut) -> @location(0) vec4<f32> {
    let base_color = textureSample(base_color, smp, in.texcoord) * in.tint;
    let screen_color = vec4<f32>(in.position.x/screen.size.x, in.position.y/screen.size.y, 1.0, 1.0);
    let color = mix(in.color, screen_color, 0.0);
    var final_color = base_color * color;

    if !(final_color.a > 0) {
        discard;
    }

    var lights: bool = true;
    if arrayLength(&point_lights) == 1 && point_lights[0].color.a == 0 &&
        arrayLength(&directional_lights) == 1 && directional_lights[0].color.a == 0 &&
        arrayLength(&spot_lights) == 1 && spot_lights[0].color.a == 0 {
        //if all lights are default lights, render fullbright
        lights = false;
    }

    if lights {
        let pbr = textureSample(pbr, smp, in.texcoord);// * in.pbr_tint;
        let ambient_occlusion = pbr.r;
        let roughness = pbr.g;
        let metallic = pbr.b;

        //let tangent = normalize(v.tangent - dot(v.tangent, v.normal) * v.normal); //re-orthogonalize
        let tangent_to_view = mat3x3<f32>(in.tangent, normalize(cross(in.normal, in.tangent)), in.normal);
        //let view_to_tangent = transpose(mat3x3<f32>(v.tangent, normalize(cross(v.normal, v.tangent)), v.normal));
        let n = normalize(tangent_to_view * (textureSample(normal, smp, in.texcoord).rgb * 2.0 - 1.0));
        //let n = normalize(v.normal);
        let v = normalize(-in.position.xyz); //already in view space

        var light = vec3<f32>(0.03) * final_color.rgb * ambient_occlusion; //initial ambient value
        for (var i: u32 = 0; i < arrayLength(&point_lights); i++) {
            let l = normalize(point_lights[i].position.xyz - in.position.xyz);

            let d = distance(in.position.xyz, point_lights[i].position.xyz);
            let r = point_lights[i].position.w;
            if d < r {
                let attenuation = smoothstep(r, 0.0, d);
                let radiance = point_lights[i].color.rgb * point_lights[i].color.a * attenuation;
                //let attenuation = 1.0 / (d*d);
                //light += calculate_influence_phong(n, v, l, radiance);
                light += calculate_influence_pbr(n, v, l, radiance, final_color.rgb, roughness, metallic);
            }
        }
        for (var i: u32 = 0; i < arrayLength(&directional_lights); i++) {
            let l = normalize(-directional_lights[i].direction.xyz);
            let radiance = directional_lights[i].color.rgb * directional_lights[i].color.a;
            //light += calculate_influence_phong(n, v, l, radiance);
            light += calculate_influence_pbr(n, v, l, radiance, final_color.rgb, roughness, metallic);
        }
        for (var i: u32 = 0; i < arrayLength(&spot_lights); i++) {
            let l = normalize(spot_lights[i].position.xyz - in.position.xyz);
            let theta = dot(l, normalize(-spot_lights[i].direction.xyz));
            let inner_cutoff = spot_lights[i].position.w;
            let outer_cutoff = spot_lights[i].direction.w;
            let epsilon = inner_cutoff - outer_cutoff;
            let falloff = clamp((theta - outer_cutoff)/epsilon, 0.0, 1.0);
            let radiance = spot_lights[i].color.rgb * spot_lights[i].color.a * falloff;
            //light += calculate_influence_phong(n, v, l, radiance);
            light += calculate_influence_pbr(n, v, l, radiance, final_color.rgb, roughness, metallic);
        }

        //reinhard tonemap for PBR
        //light = light / (light + vec3<f32>(1.0));
        //light = pow(light, vec3<f32>(1.0/2.2));
        final_color = vec4<f32>(light, 1.0);
    }

    let near = select(screen.size[2], 0.1, screen.size[2] == 0);
    let far = select(screen.size[3], 2048.0, screen.size[3] == 0);
    let fog_max = far;
    var fog_min = screen.color[3];
    if fog_min == 0.0 {
        fog_min = (far - near)*0.5; //fog starts at halfway by default
    }
    let dist = abs(in.position.z / in.position.w);
    let fog_factor = clamp((fog_max - dist) / (fog_max - fog_min), 0, 1);
    var fog_color = vec4<f32>(screen.color.rgb, final_color.a);
    final_color = mix(fog_color, final_color, fog_factor);

    return final_color;
}
