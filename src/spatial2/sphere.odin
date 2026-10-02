package spatial2

import "core:math/linalg"

Sphere :: struct {
    center: [3]f32,
    radius: f32,
}

sphere_extents :: proc(s: Sphere, t: matrix[4,4]f32) -> [2][3]f32 {
    center := (t * [4]f32{**s.center, 1}).xyz
    e: [3]f32
    e[0] = s.radius * linalg.length(t[0].xyz)
    e[1] = s.radius * linalg.length(t[1].xyz)
    e[2] = s.radius * linalg.length(t[2].xyz)
    return {center - e, center + e}
}

sphere_sphere :: proc(a, b: Sphere) -> bool {
    v := b.center - a.center
    r := a.radius + b.radius
    //dot product of displacement vector with itself == squared distance
    return linalg.dot(v, v) <= r * r
}

sphere_aabb :: proc(a: Sphere, b: Box) -> bool {
    mini := b.center - b.half_extents
    maxi := b.center + b.half_extents
    closest := linalg.clamp(b.center, mini, maxi)
    distance := linalg.length2(closest - b.center)
    return distance <= a.radius * a.radius
}

transform_sphere :: proc(s: Sphere, t: matrix[4,4]f32) -> (st: Sphere) {
    st.center = (t*[4]f32{**s.center, 1}).xyz
    max_scale := linalg.sqrt(max(linalg.length2(t[0].xyz), linalg.length2(t[0].xyz), linalg.length2(t[0].xyz)))
    st.radius = s.radius * max_scale
    return
}

sphere_overlapping :: proc(a: Sphere, atrans: matrix[4,4]f32, b: Shape, btrans: matrix[4,4]f32) -> bool {
    #partial switch b in b {
        case Box:
        return box_overlapping(b, btrans, a, atrans)
        case Sphere:
        return sphere_sphere(transform_sphere(a, atrans), transform_sphere(b, btrans))
    }
    return false
}
