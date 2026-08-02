struct Camera {
    view: mat4x4<f32>,
    inv_view: mat4x4<f32>,
    projection: mat4x4<f32>,
    color: vec4<f32>, //rgb + exposure
    fog_distance: vec2<f32>, //fog onset + render distance
}
@group(0) @binding(0) var<uniform> camera: Camera;


@group(1) @binding(0) var smp: sampler;
@group(1) @binding(1) var base_color: texture_2d<f32>;
@group(1) @binding(2) var normal: texture_2d<f32>;
@group(1) @binding(3) var pbr: texture_2d<f32>; //ambient roughness metallic
@group(1) @binding(4) var emissive: texture_2d<f32>;

struct PointLight {
    position: vec4<f32>, //view space xyz+radius
    color: vec4<f32>, //rgb+intensity
    shadow_index: vec4<i32>,
}
@group(3) @binding(0) var<storage, read> point_lights: array<PointLight>;

const DIRECTIONAL_CASCADES = 4;

struct DirectionalLight {
    direction: vec4<f32>, //view space xyz+radius
    color: vec4<f32>, //rgb+intensity
    view_to_shadow: array<mat4x4<f32>, DIRECTIONAL_CASCADES>,
    cascade_splits: vec4<f32>,
    shadow_index: vec4<i32>,
}
@group(3) @binding(1) var<storage, read> directional_lights: array<DirectionalLight>;

struct SpotLight {
    position: vec4<f32>,//xyz+inner angle
    direction: vec4<f32>,//xyz+outer angle
    color: vec4<f32>,
    view_to_shadow: mat4x4<f32>,
    shadow_index: i32,
    range: f32,
}
@group(3) @binding(2) var<storage, read> spot_lights: array<SpotLight>;

struct LightCount {
    point: u32,
    directional: u32,
    spot: u32,
    total: u32,
}
@group(3) @binding(3) var<uniform> light_count: LightCount;
@group(3) @binding(4) var shadow_depth_sampler: sampler_comparison;
@group(3) @binding(5) var shadow_color_sampler: sampler;
@group(3) @binding(6) var point_light_shadow_depth: texture_depth_cube_array;
@group(3) @binding(7) var point_light_shadow_color: texture_cube_array<f32>;
@group(3) @binding(8) var directional_light_shadow_depth: texture_depth_2d_array;
@group(3) @binding(9) var directional_light_shadow_color: texture_2d_array<f32>;
@group(3) @binding(10) var spot_light_shadow_depth: texture_depth_2d_array;
@group(3) @binding(11) var spot_light_shadow_color: texture_2d_array<f32>;
@group(3) @binding(12) var environment_probes: texture_cube_array<f32>;
@group(3) @binding(13) var environment_probe_sampler: sampler;

struct Vertex {
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) tangent: vec4<f32>,
    @location(3) texcoord: vec2<f32>,
    @location(4) color: vec4<f32>,
    @location(5) bones: vec4<f32>,
    @location(6) weights: vec4<f32>,
    @location(7) modelview_0: vec4<f32>,
    @location(8) modelview_1: vec4<f32>,
    @location(9) modelview_2: vec4<f32>,
    @location(10) modelview_3: vec4<f32>,
    @location(11) clip_rect: vec4<f32>,
    @location(12) base_color_tint: vec4<f32>,
    @location(13) pbr_tint: vec4<f32>, //ambient, metallic, roughness
    @location(14) emissive_tint: vec4<f32>, //rgb
    @location(15) indices: vec4<i32>, //the last one we have... use it wisely
}

struct VSOut {
    @builtin(position) out_position: vec4<f32>,
    @location(0) position: vec4<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) tangent: vec4<f32>,
    @location(3) @interpolate(perspective) texcoord: vec2<f32>,
    @location(4) color: vec4<f32>,
    @location(5) base_color_tint: vec4<f32>,
    @location(6) pbr_tint: vec4<f32>,
    @location(7) emissive_tint: vec4<f32>,
    @location(8) @interpolate(flat) indices: vec4<i32>,
}

fn ident() -> mat4x4<f32> {
    return mat4x4<f32>(
        vec4<f32>(1.0, 0.0, 0.0, 0.0),
        vec4<f32>(0.0, 1.0, 0.0, 0.0),
        vec4<f32>(0.0, 0.0, 1.0, 0.0),
        vec4<f32>(0.0, 0.0, 0.0, 1.0),
    );
}

@group(2) @binding(0) var<storage, read> skeletons: array<mat4x4<f32>>;
//@group(2) @binding(1) var<uniform> skeleton_len: u32;
fn calculate_bones(vertex: Vertex, instance_index: u32) -> mat4x4<f32> {
    if(all(vertex.weights == vec4<f32>(0.0))) {
        return ident();
    }
    let skeleton_offset = u32(vertex.indices.x);
    let bone1 = skeletons[skeleton_offset + u32(vertex.bones.x)] * vertex.weights.x;
    let bone2 = skeletons[skeleton_offset + u32(vertex.bones.y)] * vertex.weights.y;
    let bone3 = skeletons[skeleton_offset + u32(vertex.bones.z)] * vertex.weights.z;
    let bone4 = skeletons[skeleton_offset + u32(vertex.bones.w)] * vertex.weights.w;
    return bone1 + bone2 + bone3 + bone4;
}

@vertex
fn vs_main(vertex: Vertex, @builtin(vertex_index) vertex_index: u32, @builtin(instance_index) instance_index: u32) -> VSOut {
    var v: VSOut;
    let modelview = mat4x4<f32>(vertex.modelview_0, vertex.modelview_1, vertex.modelview_2, vertex.modelview_3);
    let bones = calculate_bones(vertex, instance_index);
    let bones3 = mat3x3<f32>(bones[0].xyz, bones[1].xyz, bones[2].xyz);
    v.position = modelview * bones * vec4<f32>(vertex.position, 1.0);
    v.normal = normalize((modelview * vec4<f32>(normalize(bones3 * vertex.normal), 0.0)).xyz);
    let tangent = normalize((modelview * vec4<f32>(normalize(bones3 * vertex.tangent.xyz), 0.0)).xyz);
    v.tangent = vec4<f32>(tangent, vertex.tangent.w);
    v.out_position = camera.projection * v.position;
    let tex_offset = vertex.clip_rect.xy;
    let tex_factor = vertex.clip_rect.zw;
    v.texcoord = vertex.texcoord*tex_factor+tex_offset;
    v.color = vertex.color;
    v.base_color_tint = vertex.base_color_tint;
    v.pbr_tint = vertex.pbr_tint;
    v.emissive_tint = vertex.emissive_tint;
    v.indices = vertex.indices;
    return v;
}

fn calculate_influence_phong(n: vec3<f32>, v: vec3<f32>, l: vec3<f32>, radiance: vec3<f32>) -> vec4<f32> {
    let diffuse = max(dot(n, l), 0.0);
    let specular = pow(max(dot(v, reflect(-l, n)), 0.0), 256.0);
    return vec4<f32>((diffuse + specular) * radiance, 0.0);
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

fn calculate_influence_pbr(n: vec3<f32>, v: vec3<f32>, l: vec3<f32>, radiance: vec3<f32>, base_color: vec4<f32>, roughness: f32, metallic: f32) -> vec3<f32> {
    let h = normalize(v + l);
    let cos_theta = max(dot(h, v), 0.0);
    var base_reflectance = vec3<f32>(0.04); //base dielectric reflectance
    base_reflectance = mix(base_reflectance, base_color.rgb, metallic);
    let reflectance = fresnel_schlick_reflectance(cos_theta, base_reflectance);

    let normal_distribution = normal_distribution_ggx(n, h, roughness);
    let geometry_attenuation = geometry_attenuation_smith(n, v, l, roughness);

    let numerator = normal_distribution * geometry_attenuation * reflectance;
    let denominator = 4.0 * max(dot(n, v), 0.0) * max(dot(n, l), 0.0) + 0.0001; //extra epsilon to prevent divide-by-zero
    let specular = numerator / denominator;

    let translucency = 1.0 - base_color.a;
    let transmission = base_color.rgb * translucency;

    let diffuse_ratio = (1.0 - metallic) * (vec3<f32>(1.0) - reflectance);
    let diffuse = diffuse_ratio * base_color.rgb / PI * (1.0 - translucency);

    let albedo = max(diffuse_ratio.r, max(diffuse_ratio.g, diffuse_ratio.b));

    let diffuse_color = diffuse * max(dot(n, l), 0.0) * radiance;
    let specular_color = specular * max(dot(n, l), 0.0) * radiance;
    let transmission_color = transmission * max(dot(-n, l), 0.0) * radiance;

    return (diffuse_color + transmission_color)*base_color.a + specular_color;
}

struct LightInput {
    position: vec4<f32>,
    n: vec3<f32>,
    v: vec3<f32>,
    surface_color: vec4<f32>,
    roughness: f32,
    metallic: f32,
}

fn apply_point_light(in: LightInput, p: PointLight) -> vec3<f32> {
    if(p.color.a == 0) {
        return vec3<f32>(0);
    }
    let l = normalize(p.position.xyz - in.position.xyz);
    let d = distance(in.position.xyz, p.position.xyz);
    let r = p.position.w;
    if d < r {
        var light_factor = vec3<f32>(1.0); //transmittance + opaque shadowing
        let layer = p.shadow_index.r;
        if(layer != -1) {
            light_factor = vec3<f32>(0.0);
            let texelSize = 2.0 / f32(textureDimensions(point_light_shadow_depth).x); //cubemap faces are -1 to 1, so 2x UV space
            var up = vec3<f32>(0, 1, 0);
            let dir_view = in.position.xyz - p.position.xyz;
            let dir_world = normalize((camera.inv_view * vec4<f32>(dir_view, 0.0)).xyz); //cubemaps must be sampled in world space
            if(abs(dir_world.y) > 0.99) {
                up = vec3<f32>(1, 0, 0);
            }
            let right = normalize(cross(up, dir_world));
            up = cross(dir_world, right);
            let near = 0.1;
            let far = p.position.w; //radius
            let depth_ref = near / (far - near) * (far / d - 1.0);
            let bias = max(0.05 * (1.0 - dot(in.n, l)), 0.005);
            for(var x = -1; x <= 1; x++) {
                for(var y = -1; y <= 1; y++) {
                    let offset_x = right * f32(x) * texelSize;
                    let offset_y = up * f32(y) * texelSize;
                    let offset_dir = normalize(dir_world + offset_x + offset_y);
                    let visibility = textureSampleCompare(point_light_shadow_depth, shadow_depth_sampler, offset_dir, layer, depth_ref + bias);
                    let transmittance = textureSample(point_light_shadow_color, shadow_color_sampler, offset_dir, layer).rgb;
                    light_factor += visibility * transmittance;
                }
            }
            light_factor /= 9.0;
        }

        if(all(light_factor > vec3<f32>(0))) {
            let attenuation = smoothstep(r, 0.0, d);
            let radiance = p.color.rgb * p.color.a * attenuation * light_factor;
            //let attenuation = 1.0 / (d*d);
            //return calculate_influence_phong(in.n, in.v, l, radiance);
            return calculate_influence_pbr(in.n, in.v, l, radiance, in.surface_color, in.roughness, in.metallic);
        }
    }
    return vec3<f32>(0);
    
}

fn apply_directional_light(in: LightInput, d: DirectionalLight) -> vec3<f32> {
    if(d.color.a == 0) {
        return vec3<f32>(0);
    }
    let depth = -in.position.z;
    var cascade = 0;
    for(var i = 0; i < DIRECTIONAL_CASCADES; i++) {
        if(depth < d.cascade_splits[i]) {
            cascade = i;
            break;
        }
    }
    let l = normalize(-d.direction.xyz);
    var light_factor = vec3<f32>(1.0); //transmittance + opaque shadowing
    let layer = d.shadow_index.r + cascade;
    if(layer != -1) {
        light_factor = vec3<f32>(0.0);
        let frag_in_light = d.view_to_shadow[cascade] * in.position;
        let ndc = frag_in_light.xyz / frag_in_light.w;
        var shadow_uv = ndc.xy * 0.5 + vec2<f32>(0.5);
        shadow_uv.y = 1.0 - shadow_uv.y;
        let depth_ref = ndc.z;
        let bias = max(0.05 * (1.0 - dot(in.n, l)), 0.005);
        let texel_size = vec2<f32>(1.0) / vec2<f32>(textureDimensions(directional_light_shadow_depth));
        for(var x = -1; x <= 1; x++) {
            for(var y = -1; y <= 1; y++) {
                let offset = vec2<f32>(f32(x), f32(y)) * texel_size;
                let visibility = textureSampleCompare(directional_light_shadow_depth, shadow_depth_sampler, shadow_uv + offset, layer, depth_ref + bias);
                let transmittance = textureSample(directional_light_shadow_color, shadow_color_sampler, shadow_uv + offset, layer).rgb;
                light_factor += visibility * transmittance;
            }
        }
        light_factor /= 9.0;
    }
    if(all(light_factor > vec3<f32>(0))) {
        let radiance = d.color.rgb * d.color.a * light_factor;
        //return calculate_influence_phong(in.n, in.v, l, radiance);
        return calculate_influence_pbr(in.n, in.v, l, radiance, in.surface_color, in.roughness, in.metallic);
    }
    return vec3<f32>(0);
}

fn apply_spot_light(in: LightInput, s: SpotLight) -> vec3<f32> {
    if(s.color.a == 0) {
        return vec3<f32>(0);
    }
    let l = normalize(s.position.xyz - in.position.xyz);
    let d = distance(in.position.xyz, s.position.xyz);
    if(d > s.range) {
        return vec3<f32>(0);
    }
    let theta = dot(l, normalize(-s.direction.xyz));
    let inner_cutoff = s.position.w;
    let outer_cutoff = s.direction.w;
    if(theta < outer_cutoff) {
        return vec3<f32>(0);
    }
    var light_factor = vec3<f32>(1.0); //transmittance + opaque shadowing
    let layer = s.shadow_index;
    if(layer != -1) {
        light_factor = vec3<f32>(0.0);
        let frag_in_light = s.view_to_shadow * in.position;
        let ndc = frag_in_light.xyz / frag_in_light.w;
        var shadow_uv = ndc.xy * 0.5 + vec2<f32>(0.5);
        shadow_uv.y = 1.0 - shadow_uv.y;
        let depth_ref = ndc.z;
        let bias = max(0.05 * (1.0 - dot(in.n, l)), 0.005);
        let texel_size = vec2<f32>(1.0) / vec2<f32>(textureDimensions(spot_light_shadow_depth));
        for(var x = -1; x <= 1; x++) {
            for(var y = -1; y <= 1; y++) {
                let offset = vec2<f32>(f32(x), f32(y)) * texel_size;
                let visibility = textureSampleCompare(spot_light_shadow_depth, shadow_depth_sampler, shadow_uv + offset, layer, depth_ref + bias);
                let transmittance = textureSample(spot_light_shadow_color, shadow_color_sampler, shadow_uv + offset, layer).rgb;
                light_factor += visibility * transmittance;
            }
        }
        light_factor /= 9.0;
    }
    if(all(light_factor > vec3<f32>(0))) {
        let epsilon = inner_cutoff - outer_cutoff;
        let falloff = clamp((theta - outer_cutoff)/epsilon, 0.0, 1.0);
        let attenuation = smoothstep(s.range, 0.0, d);
        let radiance = s.color.rgb * s.color.a * falloff * attenuation * light_factor;
        //return calculate_influence_phong(in.n, in.v, l, radiance);
        return calculate_influence_pbr(in.n, in.v, l, radiance, in.surface_color, in.roughness, in.metallic);
    }
    return vec3<f32>(0);
}

fn calculate_environment_pbr(in: LightInput, environment: vec3<f32>, ambient: vec3<f32>) -> vec3<f32> {
    let cos_theta = max(dot(in.n, in.v), 0.0);
    var base_reflectance = vec3<f32>(0.04); //base dielectric reflectance
    base_reflectance = mix(base_reflectance, in.surface_color.rgb, in.metallic);
    let reflectance = fresnel_schlick_reflectance(cos_theta, base_reflectance);

    let specular_color = reflectance * environment;
    let diffuse_color = (1.0 - in.metallic) * (vec3<f32>(1.0) - reflectance) * in.surface_color.rgb * ambient; //base diffuse ambient

    return diffuse_color * in.surface_color.a + specular_color;
}

fn apply_light_environment(in: VSOut, in_color: vec4<f32>) -> vec4<f32> {
    var final_color = in_color;
    var light = final_color.rgb;

    if(light_count.total > 0) {

        let pbr = textureSample(pbr, smp, in.texcoord) * in.pbr_tint;
        let ambient_occlusion = pbr.r;
        let roughness = pbr.g;
        let metallic = pbr.b;

        light = vec3<f32>(0.0);

        var n = normalize(in.normal);
        if(all(in.tangent.xyz != vec3<f32>(0.0))) {
            //if we have tangents, do extra calculations & use the normal map
            //let tangent = normalize(v.tangent - dot(v.tangent, v.normal) * v.normal); //re-orthogonalize
            let binormal = normalize(cross(in.normal, in.tangent.xyz) * in.tangent.w);
            let tangent_to_view = mat3x3<f32>(in.tangent.xyz, binormal, in.normal);
            //let view_to_tangent = transpose(mat3x3<f32>(v.tangent, normalize(cross(v.normal, v.tangent)), v.normal));
            n = normalize(tangent_to_view * (textureSample(normal, smp, in.texcoord).rgb * 2.0 - 1.0));
        }
        let v = normalize(-in.position.xyz); //already in view space

        let light_input = LightInput(in.position, n, v, final_color, roughness, metallic);

        if(in.indices[1] != -1) {
            let n_world = normalize((camera.inv_view * vec4<f32>(n, 0.0)).xyz);
            let v_world = normalize((camera.inv_view * vec4<f32>(v, 0.0)).xyz);
            let r = reflect(-v_world, n_world);

            let max_mip = f32(textureNumLevels(environment_probes) - 1);

            let env = textureSampleLevel(environment_probes, environment_probe_sampler, r, in.indices[1], roughness * max_mip);
            let ambient = textureSampleLevel(environment_probes, environment_probe_sampler, n_world, in.indices[1], max_mip);
            light += calculate_environment_pbr(light_input, env.rgb, ambient.rgb);
        } else {
            light += calculate_environment_pbr(light_input, vec3<f32>(0.0), vec3<f32>(0.03));
        }
        light *= ambient_occlusion;

        for (var i: u32 = 0; i < light_count.point; i++) {
            light += apply_point_light(light_input, point_lights[i]);
        }
        for (var i: u32 = 0; i < light_count.directional; i++) {
            light += apply_directional_light(light_input, directional_lights[i]);
        }
        for (var i: u32 = 0; i < light_count.spot; i++) {
            light += apply_spot_light(light_input, spot_lights[i]);
        }
    }

    //reinhard tonemap for PBR
    //light = light / (light + vec3<f32>(1.0));
    //light = pow(light, vec3<f32>(1.0/2.2));
    final_color = vec4<f32>(light, in_color.a);
    return final_color;
}

fn apply_fog(in_position: vec4<f32>, in_color: vec4<f32>) -> vec4<f32> {
    if camera.fog_distance[1] == 0 {
        return in_color;
    }
    var final_color = in_color;
    let fog_max = camera.fog_distance[1];
    var fog_min = camera.fog_distance[0];
    let dist = abs(in_position.z / in_position.w);
    let fog_factor = clamp((fog_max - dist) / (fog_max - fog_min), 0, 1);
    var fog_color = vec4<f32>(camera.color.rgb, final_color.a);
    final_color = mix(fog_color, final_color, fog_factor);
    return final_color;
}

@fragment
fn solid_main(in: VSOut) -> @location(0) vec4<f32> {
    let base_color = textureSample(base_color, smp, in.texcoord) * in.base_color_tint;
    var final_color = base_color;
    if final_color.a < 0.9 {
        discard;
    }
    final_color = apply_light_environment(in, final_color);
    let emissive_color = textureSample(emissive, smp, in.texcoord) * in.emissive_tint;
    final_color = vec4<f32>(final_color.rgb + emissive_color.rgb, final_color.a);
    final_color = apply_fog(in.position, final_color);

    return final_color * camera.color.a;
}

struct TransOut {
    @location(0) accum: vec4<f32>,
    @location(1) revealage: f32,
}

@fragment
fn trans_main(in: VSOut) -> TransOut {
    var out: TransOut;
    let base_color = textureSample(base_color, smp, in.texcoord) * in.base_color_tint * in.color;
    if !(base_color.a > 0 && base_color.a < 1) {
        discard;
    }
    var final_color = base_color;
    final_color = apply_light_environment(in, final_color);
    let emissive_color = textureSample(emissive, smp, in.texcoord) * in.emissive_tint;
    final_color = vec4<f32>(final_color.rgb + emissive_color.rgb, final_color.a);
    final_color = apply_fog(in.position, final_color);
    //final_color.a = base_color.a;
    final_color = vec4<f32>(final_color.rgb * camera.color.a, final_color.a);

    let most_color = max(max(final_color.r, final_color.g), final_color.b);
    let weight = max(min(1.0, most_color * final_color.a), final_color.a) *
        clamp(0.03 / (1e-5 + pow(in.position.z / 200, 4.0)), 1e-2, 3e3);

    out.accum = vec4<f32>(final_color.rgb * final_color.a, final_color.a) * weight;
    out.accum = clamp(out.accum, vec4<f32>(-1e4), vec4<f32>(1e4)); //prevent accum saturation
    out.revealage = final_color.a;

    return out;
}

@fragment
fn solid_shadow_main(in: VSOut) -> @location(0) vec4<f32> {
    let base_color = textureSample(base_color, smp, in.texcoord) * in.base_color_tint;
    if base_color.a < 0.9 {
        discard;
    }
    return vec4<f32>(1, 1, 1, 1);
}

@fragment
fn trans_shadow_main(in: VSOut) -> @location(0) vec4<f32> {
    let base_color = textureSample(base_color, smp, in.texcoord) * in.base_color_tint;
    if !(base_color.a > 0 && base_color.a < 1) {
        discard;
    }
    //let t = pow(base_color.a, 0.5);
    return vec4<f32>(mix(vec3(1.0), base_color.rgb, base_color.a), 1.0);
}
