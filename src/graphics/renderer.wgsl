struct Camera {
    view: mat4x4<f32>,
    world: mat4x4<f32>,
    projection: mat4x4<f32>,
    viewproj: mat4x4<f32>,
    inv_viewproj: mat4x4<f32>,
    frustum_planes: array<vec4<f32>, 6>,
    color: vec4<f32>, //rgb + exposure
    fog_distance: vec2<f32>, //fog onset + render distance
    layer_mask: vec2<u32>,
    reserved: vec2<u32>,
    cascade_offset: u32, cascade_count: u32,
    cascade_splits: vec4<f32>,
    xy_scale: vec2<f32>, xy_bias: vec2<f32>,
    z_scale: f32, z_bias: f32,
    grid_size: u32, //4xu8s
    header_offset: u32,
}
@group(0) @binding(0) var<uniform> camera: Camera;
@group(0) @binding(1) var environment_sampler: sampler;
@group(0) @binding(2) var environment: texture_cube<f32>;
@group(0) @binding(3) var background: texture_2d<f32>;

@group(1) @binding(0) var smp: sampler;
@group(1) @binding(1) var base_color: texture_2d<f32>;
@group(1) @binding(2) var normal: texture_2d<f32>;
@group(1) @binding(3) var pbr: texture_2d<f32>; //ambient roughness metallic
@group(1) @binding(4) var emissive: texture_2d<f32>;

struct PointLight {
    color: vec4<f32>, //rgb+intensity
    position: vec3<f32>, range: f32,
    layer_mask: vec2<u32>,
}
@group(3) @binding(0) var<storage, read> point_lights: array<PointLight>;

struct DirectionalLight {
    color: vec4<f32>, //rgb+intensity
    direction: vec4<f32>,
    layer_mask: vec2<u32>,
}
@group(3) @binding(1) var<storage, read> directional_lights: array<DirectionalLight>;

struct SpotLight {
    color: vec4<f32>,
    position: vec3<f32>,  inner_angle: f32,
    direction: vec3<f32>, outer_angle: f32,
    layer_mask: vec2<u32>,
    range: f32,
}
@group(3) @binding(2) var<storage, read> spot_lights: array<SpotLight>;

struct LightCounts {
    total_lights: u32,
    directional_lights: u32,
    point_shadows: u32,
    directional_shadows: u32,
    spot_shadows: u32,
    visualize_clusters: u32,
}
@group(3) @binding(3) var<uniform> light_counts: LightCounts;
@group(3) @binding(4) var shadow_depth_sampler: sampler_comparison;
@group(3) @binding(5) var shadow_color_sampler: sampler;
@group(3) @binding(6) var point_light_shadow_depth: texture_depth_cube_array;
@group(3) @binding(7) var point_light_shadow_color: texture_cube_array<f32>;
@group(3) @binding(8) var directional_light_shadow_depth: texture_depth_2d_array;
@group(3) @binding(9) var directional_light_shadow_color: texture_2d_array<f32>;
@group(3) @binding(10) var spot_light_shadow_depth: texture_depth_2d_array;
@group(3) @binding(11) var spot_light_shadow_color: texture_2d_array<f32>;

struct ReflectionProbe {
    position: vec3<f32>, slot: u32,
    half_extents: vec3<f32>, flags: u32,
    capture_offset: vec3<f32>, edge_blend: f32,
}
@group(3) @binding(12) var cubemaps: texture_cube_array<f32>;
@group(3) @binding(13) var cubemaps_sampler: sampler;
@group(3) @binding(14) var<storage, read> reflection_probes: array<ReflectionProbe>;

@group(3) @binding(15) var<storage, read> clusters: array<u32>;
@group(3) @binding(16) var<storage, read> shadow_transforms: array<mat4x4<f32>>;

struct Vertex {
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) tangent: vec4<f32>,
    @location(3) texcoord: vec2<f32>,
    @location(4) color: vec4<f32>,
    @location(5) bones: vec4<u32>,
    @location(6) weights: vec4<f32>,
    @location(7) instance: u32,
}

struct Instance {
    model: mat4x4<f32>,
    clip_rect: vec4<f32>,
    base_color_mul: vec4<f32>,
    base_color_add: vec4<f32>,
    pbr_mul: vec3<f32>,      skeleton_offset: i32,
    pbr_add: vec3<f32>,      probe_a: i32,
    emissive_mul: vec3<f32>, probe_b: i32,
    emissive_add: vec3<f32>, flags: u32,
}
const INSTANCE_BILLBOARD: u32 = 1;
const INSTANCE_UNLIT: u32 = 2;
@group(2) @binding(0) var<storage, read> instances: array<Instance>;

struct VSOut {
    @builtin(position) out_position: vec4<f32>,
    @location(0) position: vec4<f32>, //xyz in world space, w = view space z
    @location(1) normal: vec3<f32>,
    @location(2) tangent: vec4<f32>,
    @location(3) @interpolate(perspective) texcoord: vec2<f32>,
    @location(4) color: vec4<f32>,
    @location(5) @interpolate(flat) instance: u32,
}

fn ident() -> mat4x4<f32> {
    return mat4x4<f32>(
        vec4<f32>(1.0, 0.0, 0.0, 0.0),
        vec4<f32>(0.0, 1.0, 0.0, 0.0),
        vec4<f32>(0.0, 0.0, 1.0, 0.0),
        vec4<f32>(0.0, 0.0, 0.0, 1.0),
    );
}

@group(2) @binding(1) var<storage, read> skeletons: array<mat4x4<f32>>;
fn calculate_bones(skeleton_offset: u32, bones: vec4<u32>, weights: vec4<f32>) -> mat4x4<f32> {
    let bone1 = skeletons[skeleton_offset + bones.x] * weights.x;
    let bone2 = skeletons[skeleton_offset + bones.y] * weights.y;
    let bone3 = skeletons[skeleton_offset + bones.z] * weights.z;
    let bone4 = skeletons[skeleton_offset + bones.w] * weights.w;
    return bone1 + bone2 + bone3 + bone4;
}

@vertex
fn vs_main(vertex: Vertex, @builtin(vertex_index) vertex_index: u32, @builtin(instance_index) instance_index: u32) -> VSOut {
    var v: VSOut;

    v.instance = vertex.instance;
    let instance = instances[v.instance];

    var model: mat4x4<f32>;
    if((instance.flags & INSTANCE_BILLBOARD) == INSTANCE_BILLBOARD) {
        let cam_rot = mat3x3<f32>(
            camera.world[0].xyz,
            camera.world[1].xyz,
            camera.world[2].xyz,
        );
        let rotation_scale = cam_rot * mat3x3<f32>(
            instance.model[0].xyz,
            instance.model[1].xyz,
            instance.model[2].xyz,
        );
        model = mat4x4<f32>(
            vec4<f32>(rotation_scale[0], 0),
            vec4<f32>(rotation_scale[1], 0),
            vec4<f32>(rotation_scale[2], 0),
            instance.model[3],
        );
    } else {
        model = instance.model;
    }
    var bones = ident();
    if(instance.skeleton_offset != -1) {
        bones = calculate_bones(u32(instance.skeleton_offset), vertex.bones, vertex.weights);
    }
    v.position = model * bones * vec4<f32>(vertex.position, 1.0);
    v.out_position = camera.viewproj * v.position;
    let camera_z = vec4<f32>(
        camera.view[0].z,
        camera.view[1].z,
        camera.view[2].z,
        camera.view[3].z,
    );
    v.position.w = dot(camera_z, v.position);
    
    let bones3 = mat3x3<f32>(bones[0].xyz, bones[1].xyz, bones[2].xyz);
    let normal = bones3 * vertex.normal;
    if(dot(normal, normal) > 0.0) {
        v.normal = normalize((model * vec4<f32>(normalize(normal), 0.0)).xyz);
    }
    let tangent = bones3 * vertex.tangent.xyz;
    if(dot(tangent, tangent) > 0.0) {
        let model3 = mat3x3<f32>(model[0].xyz, model[1].xyz, model[2].xyz) * bones3;
        let v_tangent = normalize((model * vec4<f32>(normalize(tangent), 0.0)).xyz);
        v.tangent = vec4<f32>(v_tangent, vertex.tangent.w * sign(determinant(model3)));
    }

    let tex_offset = instance.clip_rect.xy;
    let tex_factor = instance.clip_rect.zw;
    v.texcoord = vertex.texcoord*tex_factor+tex_offset;

    v.color = vertex.color;

    return v;
}

fn cluster_header(frag_coord: vec2<f32>, view_z: f32) -> vec4<u32> {
    let g = unpack4xU8(camera.grid_size).xyz;
    var tile = floor(frag_coord * camera.xy_scale + camera.xy_bias);
    tile = clamp(tile, vec2<f32>(0.0), vec2<f32>(g.xy - 1));
    var slice = floor(log2(-view_z) * camera.z_scale + camera.z_bias);
    slice = clamp(slice, 0.0, f32(g.z - 1));
    //must match formula in cluster_index
    let c = (u32(tile.x) * g.y * g.z) + (u32(tile.y) * g.z) + u32(slice);
    let h = (camera.header_offset + c) * 4; //4 u32s per header, change if header changes
    return vec4<u32>(clusters[h], clusters[h+1], clusters[h+2], clusters[h+3]);
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
    surface_normal: vec3<f32>,
    base_normal: bool,
    n: vec3<f32>,
    t: vec3<f32>,
    v: vec3<f32>,
    surface_color: vec4<f32>,
    roughness: f32,
    metallic: f32,
}

//compute synthetic normals for points/lines that don't already have them
//kajiya-kay-esque, hence passing line direction into tangents
fn effective_normal(in: LightInput, l: vec3<f32>) -> vec3<f32> {
    if(in.base_normal) {
        return in.n;
    }
    var h = l + in.v;
    h -= in.t * dot(in.t, h);
    let l2 = dot(h, h);
    var n = select(in.n, h * inverseSqrt(l2), l2 > 1e-6); //return base normal if light is behind the primitive
    if(dot(n, in.v) < 0.0) {
        //clamp to the 'cylinder' sillhouette
        let s = cross(in.t, in.n);
        if(dot(s, s) > 1e-6) {
            n = normalize(s) * select(-1.0, 1.0, dot(n, s) >= 0.0);
        }
    }
    return n;
}

fn apply_point_light(in: LightInput, light_index: u32) -> vec3<f32> {
    let p = point_lights[light_index];
    if(p.color.a == 0) {
        return vec3<f32>(0);
    }
    let l = normalize(p.position.xyz - in.position.xyz);
    let n = effective_normal(in, l);
    let d = distance(in.position.xyz, p.position.xyz);
    let r = p.range;
    if d < r {
        var light_factor = vec3<f32>(1.0); //transmittance + opaque shadowing
        if(light_index < light_counts.point_shadows) {
            light_factor = vec3<f32>(0.0);
            let texelSize = 2.0 / f32(textureDimensions(point_light_shadow_depth).x); //cubemap faces are -1 to 1, so 2x UV space
            var up = vec3<f32>(0, 1, 0);
            let dir_world = normalize(in.position.xyz - p.position.xyz);
            if(abs(dir_world.y) > 0.99) {
                up = vec3<f32>(1, 0, 0);
            }
            let right = normalize(cross(up, dir_world));
            up = cross(dir_world, right);
            let near = 0.1;
            let far = r; //radius
            let depth_ref = near / (far - near) * (far / d - 1.0);
            let bias = max(0.05 * (1.0 - dot(n, l)), 0.005);
            for(var x = -1; x <= 1; x++) {
                for(var y = -1; y <= 1; y++) {
                    let offset_x = right * f32(x) * texelSize;
                    let offset_y = up * f32(y) * texelSize;
                    let offset_dir = normalize(dir_world + offset_x + offset_y);
                    let visibility = textureSampleCompare(point_light_shadow_depth, shadow_depth_sampler, offset_dir, light_index, depth_ref + bias);
                    let transmittance = textureSample(point_light_shadow_color, shadow_color_sampler, offset_dir, light_index).rgb;
                    light_factor += visibility * transmittance;
                }
            }
            light_factor /= 9.0;
        }

        if(all(light_factor > vec3<f32>(0))) {
            let attenuation = smoothstep(r, 0.0, d);
            let radiance = p.color.rgb * p.color.a * attenuation * light_factor;
            //let attenuation = 1.0 / (d*d);
            let area = select(max(dot(n, in.v), 0.0), 1.0, in.base_normal); //weight primitive lighting by area
            //return calculate_influence_phong(n, in.v, l, radiance) * area;
            return calculate_influence_pbr(n, in.v, l, radiance, in.surface_color, in.roughness, in.metallic) * area;
        }
    }
    return vec3<f32>(0);
    
}

fn apply_directional_light(in: LightInput, light_index: u32) -> vec3<f32> {
    let d = directional_lights[light_index];
    if(d.color.a == 0) {
        return vec3<f32>(0);
    }

    let l = normalize(-d.direction.xyz);
    let n = effective_normal(in, l);
    var light_factor = vec3<f32>(1.0); //transmittance + opaque shadowing
    if(light_index < light_counts.directional_shadows) {
        let depth = -in.position.w;
        var cascade: u32 = 0;
        for(var i: u32 = 0; i < camera.cascade_count; i++) {
            if(depth < camera.cascade_splits[i]) {
                cascade = i;
                break;
            }
        }
        let world_to_shadow = shadow_transforms[light_counts.spot_shadows + light_index + cascade];
        //get rough estimate of world-space texel density
        let ndc_per_world = length(vec3(world_to_shadow[0][0], world_to_shadow[1][0], world_to_shadow[2][0]));
        let texel_ndc = 2.0 / f32(textureDimensions(directional_light_shadow_depth).x);
        let texel_world = texel_ndc / ndc_per_world;

        //normal offset bias based on texel density
        let normal_bias = 2.0 * texel_world;
        let sample_position = vec4(in.position.xyz + in.surface_normal * normal_bias, 1.0);

        light_factor = vec3<f32>(0.0);
        let frag_in_light = world_to_shadow * sample_position;
        let ndc = frag_in_light.xyz / frag_in_light.w;
        var shadow_uv = ndc.xy * 0.5 + vec2<f32>(0.5);
        shadow_uv.y = 1.0 - shadow_uv.y;
        let depth_ref = ndc.z;
        let texel_size = vec2<f32>(1.0) / vec2<f32>(textureDimensions(directional_light_shadow_depth));
        for(var x = -1; x <= 1; x++) {
            for(var y = -1; y <= 1; y++) {
                let offset = vec2<f32>(f32(x), f32(y)) * texel_size;
                let visibility = textureSampleCompare(directional_light_shadow_depth, shadow_depth_sampler, shadow_uv + offset, light_index + cascade, depth_ref);
                let transmittance = textureSample(directional_light_shadow_color, shadow_color_sampler, shadow_uv + offset, light_index + cascade).rgb;
                light_factor += visibility * transmittance;
            }
        }
        light_factor /= 9.0;
    }
    if(all(light_factor > vec3<f32>(0))) {
        let radiance = d.color.rgb * d.color.a * light_factor;
        let area = select(max(dot(n, in.v), 0.0), 1.0, in.base_normal); //weight primitive lighting by area
        //return calculate_influence_phong(n, in.v, l, radiance) * area;
        return calculate_influence_pbr(n, in.v, l, radiance, in.surface_color, in.roughness, in.metallic) * area;
    }
    return vec3<f32>(0);
}

fn apply_spot_light(in: LightInput, light_index: u32) -> vec3<f32> {
    let s = spot_lights[light_index];
    if(s.color.a == 0) {
        return vec3<f32>(0);
    }
    let l = normalize(s.position.xyz - in.position.xyz);
    let n = effective_normal(in, l);
    let d = distance(in.position.xyz, s.position.xyz);
    if(d > s.range) {
        return vec3<f32>(0);
    }
    let theta = dot(l, normalize(-s.direction.xyz));
    let inner_cutoff = s.inner_angle;
    let outer_cutoff = s.outer_angle;
    if(theta < outer_cutoff) {
        return vec3<f32>(0);
    }
    var light_factor = vec3<f32>(1.0); //transmittance + opaque shadowing
    if(light_index < light_counts.spot_shadows) {
        //get rough estimate of world-space texel density
        let world_to_shadow = shadow_transforms[light_index];
        let ndc_per_world = length(vec3(world_to_shadow[0][0], world_to_shadow[1][0], world_to_shadow[2][0]));
        let texel_ndc = 2.0 / f32(textureDimensions(spot_light_shadow_depth).x);
        let texel_world = texel_ndc / ndc_per_world;

        //normal offset bias based on texel density
        let normal_bias = 2.0 * texel_world;
        let sample_position = vec4(in.position.xyz + in.surface_normal * normal_bias, 1.0);

        light_factor = vec3<f32>(0.0);
        let frag_in_light = world_to_shadow * sample_position;
        let ndc = frag_in_light.xyz / frag_in_light.w;
        var shadow_uv = ndc.xy * 0.5 + vec2<f32>(0.5);
        shadow_uv.y = 1.0 - shadow_uv.y;
        let depth_ref = ndc.z;
        let texel_size = vec2<f32>(1.0) / vec2<f32>(textureDimensions(spot_light_shadow_depth));
        for(var x = -1; x <= 1; x++) {
            for(var y = -1; y <= 1; y++) {
                let offset = vec2<f32>(f32(x), f32(y)) * texel_size;
                let visibility = textureSampleCompare(spot_light_shadow_depth, shadow_depth_sampler, shadow_uv + offset, light_index, depth_ref);
                let transmittance = textureSample(spot_light_shadow_color, shadow_color_sampler, shadow_uv + offset, light_index).rgb;
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
        let area = select(max(dot(n, in.v), 0.0), 1.0, in.base_normal); //weight primitive lighting by area
        //return calculate_influence_phong(n, in.v, l, radiance) * area;
        return calculate_influence_pbr(n, in.v, l, radiance, in.surface_color, in.roughness, in.metallic) * area;
    }
    return vec3<f32>(0);
}

fn calculate_reflection_pbr(in: LightInput, radiance: vec3<f32>, ambient: vec3<f32>) -> vec3<f32> {
    let cos_theta = max(dot(in.n, in.v), 0.0);
    var base_reflectance = vec3<f32>(0.04); //base dielectric reflectance
    base_reflectance = mix(base_reflectance, in.surface_color.rgb, in.metallic);
    let reflectance = fresnel_schlick_reflectance(cos_theta, base_reflectance);

    let specular_color = reflectance * radiance;
    let diffuse_color = (1.0 - in.metallic) * (vec3<f32>(1.0) - reflectance) * in.surface_color.rgb * ambient; //base diffuse ambient

    return diffuse_color * in.surface_color.a + specular_color;
}

fn box_project(r: vec3<f32>, position: vec3<f32>, probe: ReflectionProbe) -> vec3<f32> {
    if (probe.flags == 0) {
        return r;
    }
    let local = clamp(position - probe.position, -probe.half_extents, probe.half_extents);
    let tmax = (probe.half_extents - sign(r) * local) / abs(r); //nearest exit plane per axis
    let t = min(min(tmax.x, tmax.y), tmax.z);
    let hit = probe.position + local + r * t;
    return hit - (probe.position + probe.capture_offset);
}

override TOPOLOGY: u32 = 0; // 0 = triangles, 1 = lines, 2 = points

fn apply_light_environment(in: VSOut, in_color: vec4<f32>, front_facing: bool) -> vec4<f32> {

    let instance = instances[in.instance];
    
    var final_color = in_color;
    var light = final_color.rgb;

    if(light_counts.total_lights > 0) {

        let pbr = textureSample(pbr, smp, in.texcoord).rgb * instance.pbr_mul + instance.pbr_add;
        let ambient_occlusion = pbr.r;
        let roughness = pbr.g;
        let metallic = pbr.b;

        light = vec3<f32>(0.0);

        var light_input: LightInput;

        let v = normalize(camera.world[3].xyz - in.position.xyz);

        var n = in.normal;
        var t = in.tangent.xyz;
        if(TOPOLOGY != 0 && dot(n, n) < 1e-6) {
            //synthetic normals for lines/points
            n = v;
            if(TOPOLOGY == 1 && dot(t, t) > 0.0) {
                t = normalize(t);
                let p = v - t * dot(t, v); //view-facing & perpendicular to t
                if(dot(p, p) > 1e-6) {
                    n = normalize(p);
                }
            }
            light_input = LightInput(in.position, n, false, n, t, v, final_color, roughness, metallic);
        } else {
            //face normals from triangles/normal map
            n = normalize(n);
            t = vec3<f32>(0.0); //t == 0 means triangles
            if(all(in.tangent.xyz != vec3<f32>(0.0))) {
                //if we have tangents, do extra calculations & use the normal map
                //let tangent = normalize(v.tangent - dot(v.tangent, v.normal) * v.normal); //re-orthogonalize
                let binormal = normalize(cross(in.normal, in.tangent.xyz) * in.tangent.w);
                let tangent_to_world = mat3x3<f32>(in.tangent.xyz, binormal, in.normal);
                //let view_to_tangent = transpose(mat3x3<f32>(v.tangent, normalize(cross(v.normal, v.tangent)), v.normal));
                n = normalize(tangent_to_world * (textureSample(normal, smp, in.texcoord).rgb * 2.0 - 1.0));
            }
            n = select(-n, n, front_facing);
            light_input = LightInput(in.position, in.normal, true, n, t, v, final_color, roughness, metallic);
        }

        if(camera.grid_size != 0) {
            let header = cluster_header(in.out_position.xy, in.position.w);

            if(light_counts.visualize_clusters == 1) {
                return vec4<f32>(f32(header.z)/64.0, f32(header.w)/64.0, 1.0, 1.0);
            }
            
            let offset = header.x;
            let probe_count = header.y;
            let point_count = header.z;
            let spot_count = header.w;
            let probe_offset = offset;
            let point_offset = offset+probe_count;
            let spot_offset = offset+probe_count+point_count;

            var radiance = vec3<f32>(0.0);
            var ambient = vec3<f32>(0.0);
            var weight_accum = 0.0;
            let r = reflect(-v, n);
            for(var i = 0u; i < probe_count && weight_accum < 0.999; i++) {
                let probe = reflection_probes[clusters[probe_offset+i]];
                let r_env = box_project(r, in.position.xyz, probe);

                let d = probe.half_extents - abs(in.position.xyz - probe.position);
                let edge = min(d.x, min(d.y, d.z));
                if(edge <= -probe.edge_blend) {
                    continue;
                }
                //1 inside the box to the box edge, 0 at edge_blend units outside
                let weight = saturate(1.0 + edge / probe.edge_blend);

                if(weight > 0) {
                    let k = (1.0 - weight_accum) * weight; //prefer higher priority probes
                    weight_accum += k;
                    let max_mip = f32(textureNumLevels(cubemaps) - 1);
                    radiance += textureSampleLevel(cubemaps, cubemaps_sampler, r_env, probe.slot, roughness * max_mip).rgb * k;
                    ambient += textureSampleLevel(cubemaps, cubemaps_sampler, n, probe.slot, max_mip).rgb * k;
                }
            }
            let remaining_weight = 1.0 - weight_accum;
            if(remaining_weight > 0) {
                //fallback to the environment map
                let max_mip = f32(textureNumLevels(environment) - 1);
                let env_radiance = textureSampleLevel(environment, cubemaps_sampler, r, roughness * max_mip);
                let env_ambient = textureSampleLevel(environment, cubemaps_sampler, n, max_mip);
                radiance += mix(camera.color.rgb, env_radiance.rgb, env_radiance.a) * remaining_weight;
                ambient  += mix(camera.color.rgb, env_ambient.rgb, env_ambient.a) * remaining_weight;
            }
            radiance *= ambient_occlusion;
            ambient *= ambient_occlusion;
            light += calculate_reflection_pbr(light_input, radiance, ambient);
            
            for(var i = 0u; i < point_count; i++) {
                light += apply_point_light(light_input, clusters[point_offset+i]);
            }

            for(var i = 0u; i < spot_count; i++) {
                light += apply_spot_light(light_input, clusters[spot_offset+i]);
            }
        }
        for(var i: u32 = 0; i < light_counts.directional_lights; i++) {
            light += apply_directional_light(light_input, i);
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
    //let dist = abs(in_position.w); //depth fog
    let dist = distance(in_position.xyz, camera.world[3].xyz); //radial fog
    let fog_factor = clamp((fog_max - dist) / (fog_max - fog_min), 0, 1);
    var fog_color = vec4<f32>(camera.color.rgb, final_color.a);
    final_color = mix(fog_color, final_color, fog_factor);
    return final_color;
}

@fragment
fn solid_main(in: VSOut, @builtin(front_facing) front_facing: bool) -> @location(0) vec4<f32> {
    let instance = instances[in.instance];
    let base_color = textureSample(base_color, smp, in.texcoord) * instance.base_color_mul * in.color + instance.base_color_add;
    var final_color = base_color;
    if final_color.a < 0.99 {
        discard;
    }
    if((instance.flags & INSTANCE_UNLIT) == 0) {
        final_color = apply_light_environment(in, final_color, front_facing);
        let emissive_color = textureSample(emissive, smp, in.texcoord).rgb * instance.emissive_mul + instance.emissive_add;
        final_color = vec4<f32>(final_color.rgb + emissive_color, final_color.a);
    }
    final_color = apply_fog(in.position, final_color);

    return final_color * camera.color.a;
}

struct TransOut {
    @location(0) accum: vec4<f32>,
    @location(1) revealage: f32,
}

@fragment
fn trans_main(in: VSOut, @builtin(front_facing) front_facing: bool) -> TransOut {
    var out: TransOut;
    let instance = instances[in.instance];
    let base_color = textureSample(base_color, smp, in.texcoord) * instance.base_color_mul * in.color + instance.base_color_add;
    if !(base_color.a > 0 && base_color.a < 0.99) {
        discard;
    }
    var final_color = base_color;
    if((instance.flags & INSTANCE_UNLIT) == 0) {
        final_color = apply_light_environment(in, final_color, front_facing);
        let emissive_color = textureSample(emissive, smp, in.texcoord).rgb * instance.emissive_mul + instance.emissive_add;
        final_color = vec4<f32>(final_color.rgb + emissive_color, final_color.a);
    }
    final_color = apply_fog(in.position, final_color);
    //final_color.a = base_color.a;
    final_color = vec4<f32>(final_color.rgb * camera.color.a, final_color.a);

    let most_color = max(max(final_color.r, final_color.g), final_color.b);
    let weight = max(min(1.0, most_color * final_color.a), final_color.a) *
        clamp(0.03 / (1e-5 + pow(in.position.w / 200, 4.0)), 1e-2, 3e3);

    out.accum = vec4<f32>(final_color.rgb * final_color.a, final_color.a) * weight;
    out.accum = clamp(out.accum, vec4<f32>(-1e4), vec4<f32>(1e4)); //prevent accum saturation
    out.revealage = final_color.a;

    return out;
}

@fragment
fn solid_shadow_main(in: VSOut) -> @location(0) vec4<f32> {
    let instance = instances[in.instance];
    let base_color = textureSample(base_color, smp, in.texcoord) * instance.base_color_mul * in.color + instance.base_color_add;
    if base_color.a < 0.99 {
        discard;
    }
    return vec4<f32>(1, 1, 1, 1);
}

@fragment
fn trans_shadow_main(in: VSOut) -> @location(0) vec4<f32> {
    let instance = instances[in.instance];
    let base_color = textureSample(base_color, smp, in.texcoord) * instance.base_color_mul * in.color + instance.base_color_add;
    if !(base_color.a > 0 && base_color.a < 0.99) {
        discard;
    }
    //let t = pow(base_color.a, 0.5);
    return vec4<f32>(mix(vec3(1.0), base_color.rgb, base_color.a), 1.0);
}
