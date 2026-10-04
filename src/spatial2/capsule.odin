package spatial2

import "core:math/linalg"

Capsule :: struct {
    a, b: [3]f32,
    radius: f32,
}

capsule_support :: proc(c: Capsule, d: [3]f32) -> [3]f32 {
    endpoint := linalg.dot(d, c.b - c.a) > 0 ? c.b : c.a
    return sphere_support(Sphere{endpoint, c.radius}, d)
}

transform_capsule :: proc(c: Capsule, t: matrix[4,4]f32) -> (ct: Capsule) {
    ct.a = (t * [4]f32{**c.a, 1}).xyz
    ct.b = (t * [4]f32{**c.b, 1}).xyz
    max_scale := linalg.sqrt(max(linalg.length2(t[0].xyz), linalg.length2(t[1].xyz), linalg.length2(t[2].xyz)))
    ct.radius = c.radius * max_scale
    return
}

//need to think about types/semantics for character capsules (always upright, struct{radius, half_height, up_vector})

point_on_segment :: proc(p, a, b: [3]f32) -> [3]f32 {
    ba := b - a
    pa := p - a
    t := linalg.dot(pa, ba) / linalg.dot(ba, ba)
    return linalg.lerp(a, b, linalg.clamp(t, 0, 1))
}

capsule_capsule :: proc(a, b: Capsule) -> bool {

    d0 := linalg.length2(b.a - a.a)
    d1 := linalg.length2(b.b - a.a)
    d2 := linalg.length2(b.a - a.b)
    d3 := linalg.length2(b.b - a.b)

    closest_a := a.a
    if d2 < d0 || d2 < d1 || d3 < d0 || d3 < d1 {
        closest_a = a.b
    }

    closest_b := point_on_segment(closest_a, b.a, b.b)
    closest_a = point_on_segment(closest_b, a.a, a.b)

    a_sphere := Sphere{center=closest_a, radius=a.radius}
    b_sphere := Sphere{center=closest_b, radius=b.radius}
    return sphere_sphere(a_sphere, b_sphere)
}

capsule_sphere :: proc(a: Capsule, b: Sphere) -> bool {
    closest_a := point_on_segment(b.center, a.a, a.b)
    a_sphere := Sphere{center=closest_a, radius=a.radius}
    return sphere_sphere(a_sphere, b)
}

capsule_box :: proc(a: Capsule, b: Box) -> bool {
    center := (a.a + a.b)/2
    mini := b.center - b.half_extents
    maxi := b.center + b.half_extents
    closest_b := linalg.clamp(center, mini, maxi)
    closest_a := point_on_segment(closest_b, a.a, a.b)
    return linalg.length2(closest_b - closest_a) <= a.radius * a.radius
}

capsule_overlapping :: proc(a: Capsule, atrans: matrix[4,4]f32, b: Shape, btrans: matrix[4,4]f32) -> bool {
    #partial switch b in b {
        case Sphere:
        return capsule_sphere(transform_capsule(a, atrans), transform_sphere(b, btrans))
        case Capsule:
        return capsule_capsule(transform_capsule(a, atrans), transform_capsule(b, btrans))
        case Box:
        return box_overlapping(b, btrans, a, atrans)
    }
    return false
}
