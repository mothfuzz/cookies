package spatial2

import "core:mem"
import "base:runtime"
import "core:math"
import "core:math/linalg"

Hull_Data :: struct {
    points: [][3]f32, //MUST be first
    center: [3]f32,
    allocator: runtime.Allocator,
}

Convex_Hull :: struct {
    using data: ^Hull_Data
}

Hull_Error :: enum {
    None,
    Empty,
    Allocator_Error,
}

@(private)
hull_mem_layout :: proc(n: int) -> (points_offset, size: int) {
    points_offset = mem.align_forward_int(size_of(Hull_Data), align_of([3]f32))
    size = points_offset + n * size_of([3]f32)
    return
}

make_hull :: proc(points: [][3]f32, allocator := context.allocator) -> (Convex_Hull, Hull_Error) {
    if len(points) == 0 do return {}, .Empty

    //memory shenanigans so we don't have to allocate both the struct and the slice
    points_offset, size := hull_mem_layout(len(points))
    bytes, err := mem.alloc_bytes(size, align_of(Hull_Data), allocator)
    if err != nil do return {}, Hull_Error(err)

    data := cast(^Hull_Data)(raw_data(bytes))
    dst := ([^][3]f32)(raw_data(bytes[points_offset:]))[:len(points)]
    copy(dst, points)

    center: [3]f32
    for p in dst do center += p
    data^ = {points = dst, center = center / f32(len(dst)), allocator = allocator}
    return {data}, .None
}

delete_hull :: proc(hull: Convex_Hull) {
    if hull.data == nil do return
    _, size := hull_mem_layout(len(hull.points))
    mem.free_with_size(hull.data, size, hull.allocator)
}

hull_support :: proc(hull: Convex_Hull, dir: [3]f32) -> [3]f32 {
    //brute force currently, works for small hulls
    maxd := math.NEG_INF_F32
    best := hull.points[0]
    for p in hull.points {
        d := linalg.dot(p, dir)
        if d > maxd {
            maxd = d
            best = p
        }
    }
    return best
}
