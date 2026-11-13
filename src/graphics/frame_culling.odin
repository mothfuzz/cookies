package graphics

import "core:math/linalg"

Draw_Data :: struct {
    //indexed per-view-per-batch (v*len(batches)+b)
    draws: [dynamic]Draw_Range,
    instance_ids: [dynamic]u32, //emitted per-view-per-batch
}

//indirect args, essentially
Draw_Range :: struct {
    first_instance: u32,
    instance_count: u32,
}

sphere_in_frustum :: proc(view: View, bounding_center: [3]f32, bounding_radius: f32) -> bool {
    for p in view.frustum_planes {
        if linalg.dot(p.xyz, bounding_center) + p.w < -bounding_radius {
            return false
        }
    }
    return true 
}

bounds_in_frustum :: proc(view: View, bounding_center: [3]f32, bounding_axes: [3][3]f32) -> bool {
    for p in view.frustum_planes {
        n := p.xyz
        //project OBB axes onto plane's normal, then it becomes roughly the same as sphere check
        r := abs(linalg.dot(n, bounding_axes[0])) +
            abs(linalg.dot(n, bounding_axes[1])) +
            abs(linalg.dot(n, bounding_axes[2]))
        if linalg.dot(n, bounding_center) + p.w < -r {
            return false
        }
    }
    return true
}

@(private)
cull_views :: proc(f: ^Render_Frame) {
    resize(&f.draws, len(f.views)*len(f.batches))
    for view, v in f.views {
        for batch, b in f.batches {
            draw := &f.draws[v*len(f.batches) + b]
            draw.first_instance = u32(len(f.instance_ids))
            for id in batch.first_instance ..< batch.first_instance + batch.instance_count {
                c := f.culls[id]
                if view.layer_mask & c.layer_mask == 0 do continue
                if !sphere_in_frustum(view, c.center, c.radius) do continue
                if !bounds_in_frustum(view, c.center, c.axes) do continue
                append(&f.instance_ids, id)
            }
            draw.instance_count = u32(len(f.instance_ids)) - draw.first_instance
        }
    }
}
