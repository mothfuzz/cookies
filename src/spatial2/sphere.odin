package spatial2

import "core:math/linalg"

Sphere :: struct {
    center: [3]f32,
    radius: f32,
}

sphere_support :: proc(s: Sphere, dir: [3]f32) -> [3]f32 {
    l := linalg.length2(dir)
    if l < 1e-12 do return s.center //avoid NaN
    return s.center + dir * (s.radius / linalg.sqrt(l))
}

sphere_extents :: proc(s: Sphere, t: matrix[4,4]f32) -> [2][3]f32 {
    center := (t * [4]f32{**s.center, 1}).xyz
    axes := [3][3]f32{t[0].xyz * s.radius, t[1].xyz * s.radius, t[2].xyz * s.radius}
    e: [3]f32
    for i in 0..<3 {
        row := [3]f32{t[i, 0], t[i, 1], t[i, 2]}
        e[i] = s.radius * linalg.length(row)
    }
    return {center - e, center + e}
}

sphere_sphere :: proc(a, b: Sphere) -> bool {
    v := b.center - a.center
    r := a.radius + b.radius
    return linalg.length2(v) <= r * r
}

sphere_box :: proc(a: Sphere, b: Box) -> bool {
    mini := b.center - b.half_extents
    maxi := b.center + b.half_extents
    closest := linalg.clamp(a.center, mini, maxi)
    distance := linalg.length2(closest - a.center)
    return distance <= a.radius * a.radius
}

transform_sphere :: proc(s: Sphere, t: matrix[4,4]f32) -> (st: Sphere) {
    st.center = (t*[4]f32{**s.center, 1}).xyz
    max_scale := linalg.sqrt(max(linalg.length2(t[0].xyz), linalg.length2(t[1].xyz), linalg.length2(t[2].xyz)))
    st.radius = s.radius * max_scale
    return
}

sphere_overlapping :: proc(a: Sphere, atrans: matrix[4,4]f32, b: Shape, btrans: matrix[4,4]f32) -> bool {
    #partial switch b in b {
        case Sphere:
        return sphere_sphere(transform_sphere(a, atrans), transform_sphere(b, btrans))
        case Box:
        return box_overlapping(b, btrans, a, atrans)
        case Capsule:
        return capsule_overlapping(b, btrans, a, atrans)
    }
    return false
}
