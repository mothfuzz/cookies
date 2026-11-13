package graphics

//construct views & passes

import "vendor:wgpu"
import "core:math/linalg"

Pass_Data :: struct {
    cameras: [dynamic]Camera_Uniforms, //sliced for each stage
    rasters: [dynamic]Camera_Raster, //same indices as cameras
    shadows: [dynamic]Shadow_Pass,
    captures: [dynamic]Capture_Pass,
    screen: Main_Pass,
}

//it's 480 bytes, align to 256 so we can get 512 bytes and not have to do any math
//need all the previously CPU-only data on the GPU struct now if we want to do GPU culling
Camera_Uniforms :: struct #align(256) {
    view, inv_view, projection, viewproj, inv_viewproj: matrix[4,4]f32, //5x64
    frustum_planes: [6][4]f32, //left, right, bottom, top, near, far
    color: [4]f32, //rgb + exposure
    cascade_splits: [4]f32,
    fog_distance: [2]f32,
    layer_mask: Layer_Mask, //vec2<u32>
    cascade_offset, cascade_count: u32,
    local_offset, local_count: u32,
    //padding
}

Camera_Raster :: struct {
    viewport: [4]f32,
    bg_bind_group: wgpu.BindGroup, //nil = no fill
    flip: bool, //swap triangle cull mode back/front
}

Shadow_Pass :: struct {
    cam: int,
    attachments: Shadow_Attachments,
}

/*
can reduce to one BeginRenderPass if I bind all output attachments:
- attach all three targets (msaa, accum, revealage) plus depth to one pass
- solid pipeline declares all three color targets, with writeMask = .None on accum and revealage
- trans pipeline declares all three, with writeMask = .None on the solid target
- set pipeline, render_pass(solid...), set pipeline, render_pass(trans...)

should work for both main & shadow
*/
Main_Pass :: struct {
    first_cam, cam_count: int,
    //resolve target varies: user-RTT is owned, cubemaps slice the cubemaps texture, screen is swapchain
    resolve: wgpu.TextureView,
    attachments: Main_Attachments,
}

Capture_Pass :: struct {
    using main: Main_Pass,
    copy_info: Copy_Info,
    mips: []Mip_Draw, //can be nil
}

Copy_Info :: struct {
    src, dst: wgpu.TexelCopyTextureInfo,
    size: wgpu.Extent3D,
}

Shadow_Attachments :: struct {
    color, depth: wgpu.TextureView,
}

Main_Attachments :: struct {
    msaa, depth: wgpu.TextureView,
    accum, revealage: wgpu.TextureView,
    oit_composite_bind_group: wgpu.BindGroup,
}


// TODO in order:
// 1. finish renderer_bindings.odin so that you have growable_buffer/growable_texture_array
// 2. have the shadowing code use growable_texture_array and the lighting code use growable_buffer
// 3. finish add_shadow_passes using the new GTA.layer_views

add_shadow_passes :: proc(f: ^Render_Frame, scene_extents: [2][3]f32) {

    main_count := len(f.cameras)
    total_cascades: int

    for &cam in f.cameras[:main_count] {
        cam.cascade_offset = u32(total_cascades)
        total_cascades += cam.cascade_count
    }

    resize(&f.cameras, main_count + total_cascades)
    resize(&f.rasters, main_count + total_cascades)
    resize(&f.shadows, total_cascades)
    resize(&f.cascade_transforms, total_cascades)

    mini := scene_extents[0]
    maxi := scene_extents[1]
    scene_aabb := [8][3]f32{
        {mini.x, mini.y, mini.z}, {maxi.x, mini.y, mini.z},
        {mini.x, maxi.y, mini.z}, {maxi.x, maxi.y, mini.z},
        {mini.x, mini.y, maxi.z}, {maxi.x, mini.y, maxi.z},
        {mini.x, maxi.y, maxi.z}, {maxi.x, maxi.y, maxi.z},
    }

    main_cams := &f.cameras[:main_count]
    cascade_cams := &f.cameras[main_count:]
    
    //directional: loop order must match offset + layer*count + c
    for &camera in main_cams {

        spheres := fit_cascades(camera, scene_aabb)

        for &light, i in f.directional_lights {

            light.shadow_index = i

            world_up := [3]f32{0, 1, 0}
            if linalg.abs(linalg.dot(light.direction, world_up)) >= 0.9 {
                world_up = {0, 0, 1}
            }

            for c in 0..<cam.cascade_count {
                layer := int(cam.cascade_offset) + i*cam.cascade_count + c
                attachments: Shadow_Attachments
                //need to get color & depth slices from layer
                append(&f.shadows, Shadow_Pass{len(f.cameras), target})

                shadow_cam := cascade_cam(spheres[c], light.direction, world_up, scene_aabb)
                shadow_cam.layer_mask = light.layer_mask //don't shadow instances that aren't lit either.

                cascade_cams[layer] = shadow_cam
                f.rasters[main_count + layer] = shadow_cam
                f.shadows[layer] = Shadow_Pass{main_count+layer, attachments}
                f.cascade_transforms[layer] = shadow_cam.viewproj
            }
        }
    }

    //spot: 1 pass per light
    //point: 6 passes, i.e. 1 pass per face (potentially optimize?)
    resize(&f.local_transforms, f.spot_shadow_count)
    for id in f.local_shadows {
        light := f.local_lights[id]
        if light.outer_angle < 0 {
            //point
            for face in 0..<6 {
                layer := int(light.shadow_index)*6 + face
                //append Shadow_Pass{len(f.cameras), point attachments @ layer}, face cam -> views/rasters
            }
        } else {
            //spot
            layer := int(light.shadow_index)
            // append Shadow_Pass{len(f.cameras), spot attachments @ layer}, spot cam -> views/rasters
            f.local_transforms[layer] = spot_cam.viewproj
        }
    }
}

add_probe_passes :: proc(f: ^Render_Frame, probes: []Environment_Probe) {
    // TODO: call realloc_cubemaps here, since the size is known.
    //probes: flat submission
    for p in probes do for face in schedule_faces(p) { //writes to capture_state once
        pass := probe_pass(p, face)
        pass.first_view = len(f.views)
        pass.view_count = 1
        append(&f.captures, pass)
        cam := probe_face_cam(p, face)
        append(&f.views, cam)
        append(&f.rasters, cam)
    }
}

add_user_passes :: proc(f: ^Render_Frame, rts: []Render_Target_Draw) {
    //RTT: needs to be grouped by target for multi-camera
    first := len(f.captures)
    seen := make(map[Render_Target_Hash]int, context.temp_allocator)
    //gather
    for rt in rts {
        t, ok := seen[rt.target.hash]
        if !ok {
            t = len(f.captures)
            seen[rt.target.hash] = t
            append(&f.captures, user_pass(rt))
        }
        f.captures[t].view_count += 1
    }
    //prefix sum
    offset := len(f.views)
    for &t in f.captures[first:] {
        t.first_view = offset
        offset += t.view_count
        t.view_count = 0
    }
    resize(&f.views, offset)
    resize(&f.rasters, offset)
    //scatter
    for rt in rts {
        t := &f.captures[seen[rt.target.hash]]
        index := t.first_view + t.view_count
        f.views[index] = rt.camera
        f.rasters[index] = rt.camera
        t.view_count += 1
    }
}

add_screen_pass :: proc(f: ^Render_Frame, swapchain: wgpu.TextureView, cameras: []Camera_Draw) {
    f.screen.first_view = len(f.views)
    f.screen.view_count = len(cameras)
    for cam in cameras {
        append(&f.views, cam)
        append(&f.rasters, cam)
    }
    f.screen.resolve = swapchain
    f.screen.attachments = {
        msaa = ren.main_target.msaa.view,
        depth = ren.main_target.depth.view,
        accum = ren.main_target.accum.view,
        revealage = ren.main_target.revealage.view,
        oit_composite_bind_group = ren.main_target.oit_composite_bind_group,
    }
}
