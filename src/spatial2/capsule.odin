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

//per Real-Time Collision Detection (Ericson)
closest_points_segments :: proc(a1, a2, b1, b2: [3]f32) -> (c1, c2: [3]f32) {
    EPSILON :: 1e-6
    da := a2 - a1
    db := b2 - b1
    offset := a1 - b1
    a := linalg.dot(da, da) //length2 of a
    b := linalg.dot(db, db) //length2 of b
    proj_a := linalg.dot(da, offset)
    proj_b := linalg.dot(db, offset)

    s, t: f32
    if a <= EPSILON && b <= EPSILON {
        //both segments are points
        return a1, b1
    }
    if a <= EPSILON {
        //segment a is a point (s implicitly 0)
        t = clamp(proj_b / b, 0, 1)
    } else {
        if b <= EPSILON {
            //segment b is a point (t implicitly 0)
            s = clamp(-proj_a / a, 0, 1)
        } else {
            //full form
            d := linalg.dot(da, db)
            denom := a*b - d*d
            s = denom != 0 ? clamp((d*proj_b - proj_a*b) / denom, 0, 1) : 0
            t = (d*s + proj_b)/b
            //if t is outside [0, 1], clamp it and recompute s for that t
            if t < 0 {
                t = 0
                s = clamp(-proj_a / a, 0, 1)
            } else if t > 1 {
                t = 1
                s = clamp((d - proj_a) / a, 0, 1)
            }
        }
    }
    return a1 + da*s, b1 + db*t
}

capsule_capsule :: proc(a, b: Capsule) -> bool {
    ca, cb := closest_points_segments(a.a, a.b, b.a, b.b)
    r := a.radius + b.radius
    return linalg.length2(cb - ca) <= r * r
}

capsule_sphere :: proc(a: Capsule, b: Sphere) -> bool {
    closest_a := point_on_segment(b.center, a.a, a.b)
    a_sphere := Sphere{center=closest_a, radius=a.radius}
    return sphere_sphere(a_sphere, b)
}
