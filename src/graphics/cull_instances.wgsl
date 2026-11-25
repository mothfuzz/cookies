struct DrawIndirectAtomic {
    count: u32,
    instance_count: atomic<u32>,
    first: u32,
    base_vertex: u32,
    first_instance: u32,
}
@group(0) @binding(0) var<storage, read_write> draws: array<DrawIndirectAtomic>;
@group(0) @binding(1) var<storage, read_write> instance_ids: array<u32>;

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
    mirrored: u32, reserved: u32,
    cascade_offset: u32, cascade_count: u32,
    cascade_splits: vec4<f32>,
    xy_scale: vec2<f32>, xy_bias: vec2<f32>,
    z_scale: f32, z_bias: f32,
    grid_size: u32, //4xu8s
    header_offset: u32,
}
@group(0) @binding(2) var<storage, read> cameras: array<Camera>;

struct CullCounts {
    num_bins: u32,
    num_batches: u32,
}
@group(0) @binding(3) var<uniform> counts: CullCounts;

struct InstanceBin {
    center: vec3<f32>, radius: f32,
    axes: array<f32, 9>,
    //padding
    batch: u32,
    layer_mask: vec2<u32>,
}
@group(0) @binding(4) var<storage, read> bins: array<InstanceBin>;
@group(0) @binding(5) var<storage, read> batch_offsets: array<u32>;

fn sphere_in_frustum(cam: Camera, center: vec3<f32>, radius: f32) -> bool {
    for(var p = 0; p < 6; p++) {
        let plane = cam.frustum_planes[p];
        if dot(plane.xyz, center) + plane.w < -radius {
            return false;
        }
    }
    return true;
}
fn bounds_in_frustum(cam: Camera, center: vec3<f32>, axes: array<f32, 9>) -> bool {
    let ax0 = vec3<f32>(axes[0], axes[1], axes[2]);
    let ax1 = vec3<f32>(axes[3], axes[4], axes[5]);
    let ax2 = vec3<f32>(axes[6], axes[7], axes[8]);
    for(var p = 0; p < 6; p++) {
        let plane = cam.frustum_planes[p];
        let n = plane.xyz;
        let r = abs(dot(n, ax0)) + abs(dot(n, ax1)) + abs(dot(n, ax2));
        if(dot(n, center) + plane.w < -r) {
            return false;
        }
    }
    return true;
}

@compute @workgroup_size(64)
fn cull_instances(@builtin(global_invocation_id) gid: vec3<u32>) {
    let b = gid.x;
    let c = gid.y;
    if b >= counts.num_bins { return; }
    let bin = bins[b];
    let cam = cameras[c];
    if all((cam.layer_mask & bin.layer_mask) == vec2<u32>(0)) { return; }
    if !sphere_in_frustum(cam, bin.center, bin.radius) { return; }
    if !bounds_in_frustum(cam, bin.center, bin.axes) { return; }

    let draw_index = c * counts.num_batches + bin.batch;
    let slot = atomicAdd(&draws[draw_index].instance_count, 1u);
    instance_ids[c * counts.num_bins + batch_offsets[bin.batch] + slot] = b;
}
