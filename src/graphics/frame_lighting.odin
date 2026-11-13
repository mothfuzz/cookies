package graphics

import "vendor:wgpu"
import "core:math/linalg"


// TODO: reintroduce the _Uniforms suffix.
// View -> Camera_Uniforms
// 'view' is ambiguous with view matrix, viewport, and TextureView anyway. it's a camera.
// Local_Light -> Positional_Light_Uniforms
// Global_Light -> Directional_Light_Uniforms
// Instance -> Instance_Uniforms
// skeletons is just matrix[4,4]f32
// and material is just a bind group
// Environment_Probe_Box_Uniforms? wordy... Probe_Box_Uniforms?
// what if the same data structure is used for decals? Culling in general? need to think on it


// SHADOW_INDEX is: layer into texture array AND index into transform AND index into lights. make it work.

Light_Data :: struct {
    point_lights: [dynamic]Point_Light_Uniforms,
    spot_lights: [dynamic]Spot_Light_Uniforms,
    directional_lights: [dynamic]Directional_Light_Uniforms,
    light_ids: [dynamic]u32, //spots followed by points, directionals don't get culled, to be replaced with froxels
    //this should be one transforms array
    spot_transforms: [dynamic]matrix[4,4]f32, //len = L
    cascade_transforms: [dynamic]matrix[4,4]f32, //len = L*V*C(v)
}

//VIEW needs:
//cascade_offset, cascade_count, cascade_splits: [4]f32
//cascade count should be implicitly capped at 4, with a warning.
//splits need to be computed per-frame since we fit to scene bounds. It's fine.

//SHADER needs:
//shadow_transforms: two bindings, same data, just matrices
//for global lights: len = L*V*C(v)
//for local lights: len = L (spots only)
//this implies where fit_cascades(&f) should come in the frame construction sequence.

Point_Light_Uniforms :: struct #align(16) {
    color: [4]f32,
    position: [3]f32, range: f32,
    shadow_index: i32,
    //padding here
    layer_mask: Layer_Mask, //u64
}

Spot_Light_Uniforms :: struct #align(16) {
    color: [4]f32,
    position: [3]f32, range: f32,
    //indexes both shadow map array and transforms - no transform for unshadowed lights
    direction: [3]f32, shadow_index: i32,
    inner_angle, outer_angle: f32,
    layer_mask: Layer_Mask,
}

Directional_Light_Uniforms :: struct #align(16) {
    color: [4]f32,
    direction: [3]f32, shadow_index: i32,
    layer_mask: Layer_Mask,
    //padding here
    //cascades handled by view, View gets cascade_count and cascade_offset
    //needs a cascade buffer with the transforms
}

local_lights_buffer: wgpu.Buffer
global_lights_buffer: wgpu.Buffer

local_lights_transform_buffer: wgpu.Buffer //spots only realistically
global_lights_transform_buffer: wgpu.Buffer //variably sized entries, number of cascades

//realloc_light_buffers :: proc() {}

//depends only on light data, can be prior to other procs
@(private)
gather_lights :: proc(f: ^Render_Frame, lights: []Light_Draw) {
    for light in lights {
        switch l in light.light {
        case Point_Light:
            max_scale := linalg.sqrt(max(
                linalg.length2(light.transform[0]),
                linalg.length2(light.transform[1]),
                linalg.length2(light.transform[2]),
            ))
            ll := Local_Light{
                color = l.color,
                position = (light.transform * [4]f32{**l.position, 1}).xyz,
                range = l.range * max_scale,
                inner_angle = -1,
                outer_angle = -1,
                shadow_index = -1,
                layer_mask = light.layer_mask,
            }
            if l.render_shadows {
                ll.shadow_index = i32(f.point_shadow_count)
                f.point_shadow_count += 1
                append(&f.local_shadows, len(f.local_lights))
            }
            append(&f.local_lights, ll)
        case Spot_Light:
            max_scale := linalg.sqrt(max(
                linalg.length2(light.transform[0]),
                linalg.length2(light.transform[1]),
                linalg.length2(light.transform[2]),
            ))
            ll := Local_Light{
                color = l.color,
                position = (light.transform * [4]f32{**l.position, 1}).xyz,
                range = l.range * max_scale,
                direction = linalg.normalize((light.transform * [4]f32{**l.direction, 0}).xyz),
                inner_angle = linalg.cos(l.inner_angle),
                outer_angle = linalg.cos(l.outer_angle),
                shadow_index = -1,
                layer_mask = light.layer_mask,
            }
            if l.render_shadows {
                ll.shadow_index = i32(f.point_shadow_count)
                f.point_shadow_count += 1
                append(&f.local_shadows, len(f.local_lights))
            }
            append(&f.local_lights, ll)
        case Directional_Light:
            gl := Global_Light{
                color = l.color,
                direction = linalg.normalize((light.transform * [4]f32{**l.direction, 0}).xyz),
                shadow_index = -1,
                layer_mask = light.layer_mask,
            }
            if l.render_shadows {
                append(&f.global_shadows, len(f.global_lights))
            }
            append(&f.global_lights, gl)
        }
    }
}

//requires main views
//could be done on GPU, but would need some way to avoid readback
@(private)
bin_lights :: proc(f: ^Render_Frame) {
    //culling per-camera & building index lists
    //directional/global lights don't get culled
    for &view in f.views {
        view.local_offset = len(f.light_ids)
        for light, i in f.local_lights {
            if sphere_in_frustum(view, light.position, light.range) {
                append(&f.positional_ids, u32(i))
            }
        }
        view.local_count = len(f.light_ids) - view.local_offset
        for light, i in f.global_lights {
            append(&f.light_ids, u32(i))
        }
    }
}

//cascade_cam -> Camera_Draw
//point_face_cam -> Camera_Draw
//spot_cam -> Camera_Draw

Cascade_Sphere :: struct {
    center: [3]f32,
    radius: f32,
}

//directional lights are infinte, so use main camera & scene bounds
@(private)
fit_cascades :: proc(cam: ^Camera_Uniforms, scene_aabb: [8][3]f32) -> (c: [4]Cascade_Sphere) {
    //get near/far from camera/scene
    scale_x := cam.projection[0, 0] //1/aspect*tan(fov/2)
    scale_y := cam.projection[1, 1] //1/tan(fov/2)
    nf1 := cam.projection[2, 2] //-(f+n)/(f-n)
    nf2 := cam.projection[2, 3] //-2fn/(f-n)

    //start with camera near/far (might be infinite)
    cam_near := -nf2 / (nf1 - 1) //+z
    cam_far := -nf2 / (nf1 + 1) //+z
    near := cam_near
    far := cam_far

    //remap near/far to scene extents for tighter fit
    first_in_front := false
    for p, i in scene_aabb {
        z := (cam.view * [4]f32{**p, 1}).z
        if z >= 0 do continue //+z, behind camera, can't use
        depth := -z
        if !first_in_front {
            //need to map range to roughly first object actually in front of the camera
            near, far = depth, depth
            first_in_front = true
        } else {
            near = min(near, depth)
            far = max(far, depth)
        }
    }
    near = max(near, cam_near)
    far = min(far, cam_far)

    splits: [5]f32
    for i in 0..=cam.cascade_count {
        //basic parallel-split cascades
        l := f32(DIRECTIONAL_CASCADE_SPLIT_WEIGHT)
        n := f32(cam.cascade_count)
        log_term := near * linalg.pow(far/near, f32(i)/n)
        lin_term := near + (far-near) * f32(i)/n 
        splits[i] = l * log_term + (1-l) * lin_term
    }

    for i in 0..<cam.cascade_count {
        near, far := splits[i], splits[i+1]
        //use cam.inv_view + split near/far to get center/radius
        nw := near / scale_x
        nh := near / scale_y
        fw := far / scale_x
        fh := far / scale_y
        frustum: [8][3]f32 = {
            {-nw, -nh, -near}, {+nw, -nh, -near}, {-nw, +nh, -near}, {+nw, +nh, -near},
            {-fw, -fh, -far}, {+fw, -fh, -far}, {-fw, +fh, -far}, {+fw, +fh, -far},
        }

        center: [3]f32 = 0
        for p in frustum do center += p
        center /= 8

        radius: f32 = 0
        for p in frustum do radius = max(radius, linalg.length(p - center))
        center = (cam.inv_view * [4]f32{**center, 1}).xyz

        c[i] = {center, radius}
        cam.cascade_splits[i] = far
    }


    return
}

@(private)
//per main view x global light x cascade_count
cascade_cam :: proc(c: Cascade_Sphere, direction, world_up: [3]f32, scene_aabb: [8][3]f32) -> (cam: Camera_Draw) {
    cam.view = linalg.matrix4_look_at(c.center - direction * c.radius, c.center, world_up)
    z_min, z_max := -2*c.radius, f32(0)
    for p in scene_aabb {
        z := (cam.view * [4]f32{**p, 1}).z
        z_min = min(z_min, z)
        z_max = max(z_max, z)
    }
    //ortho projection
    l := -c.radius
    r := +c.radius
    t := +c.radius
    b := -c.radius
    cam.projection[0, 0] = 2/(r - l)
    cam.projection[0, 3] = -(r + l)/(r - l)
    cam.projection[1, 1] = 2/(t - b)
    cam.projection[1, 3] = -(t + b)/(t - b)
    cam.projection[2, 2] = 1/(z_max - z_min)
    cam.projection[2, 3] = -z_min/(z_max - z_min)
    cam.projection[3, 3] = 1
    cam.flip = calculate_frustum(&cam)
    cam.viewport = {0, 0, DIRECTIONAL_SHADOW_RES, DIRECTIONAL_SHADOW_RES}
    return
}

//add_shadow_passes comes after, simply writing shadow cameras computed per light (directionals use cascades)
//also writes shadow_index & world_to_shadow into local/global_transforms, since cascades are there.
