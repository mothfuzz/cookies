package spatial2

import "core:math/linalg"

Shape :: union #no_nil {
    Box,
    Sphere,
    Capsule,
    Convex_Hull,
}

//until we can get the named tag directly in Odin
Shape_Kind :: enum {
    Box,
    Sphere,
    Capsule,
    Convex_Hull,
}

shape_kind :: proc(s: Shape) -> Shape_Kind {
    switch s in s {
    case Box: return .Box
    case Sphere: return .Sphere
    case Capsule: return .Capsule
    case Convex_Hull: return .Convex_Hull
    }
    return nil
}

shape_support :: proc(s: Shape, dir: [3]f32) -> [3]f32 {
    //dispatch logic here
    switch s in s {
    case Box:
        return box_support(s, dir)
    case Sphere:
        return sphere_support(s, dir)
    case Capsule:
        return capsule_support(s, dir)
    case Convex_Hull:
        return hull_support(s, dir)
    }
    return 0
}

//transform dir to local space, get support, then transform back to world space
shape_support_world :: proc(s: Shape, t: matrix[4,4]f32, dir: [3]f32) -> [3]f32 {
    local_dir := [3]f32{
        linalg.dot(t[0].xyz, dir),
        linalg.dot(t[1].xyz, dir),
        linalg.dot(t[2].xyz, dir),
    }
    return (t * [4]f32{**shape_support(s, local_dir), 1}).xyz
}

shape_extents :: proc(s: Shape, t: matrix[4,4]f32) -> (e: [2][3]f32) {
    for i in 0..<3 {
        d: [3]f32; d[i] = 1
        e[1][i] = shape_support_world(s, t, +d)[i]
        e[0][i] = shape_support_world(s, t, -d)[i]
    }
    return
}

EPS :: 1e-5
uniform_scale :: proc(t: matrix[4,4]f32) -> bool {
    basis := cast(matrix[3,3]f32)(t)
    scale := [3]f32{linalg.length2(basis[0]), linalg.length2(basis[1]), linalg.length2(basis[2])}
    maxi := max(scale.x, scale.y, scale.z)
    mini := min(scale.x, scale.y, scale.z)
    return maxi - mini <= EPS * maxi
}

orthogonal :: proc(t: matrix[4,4]f32) -> bool {
    basis := cast(matrix[3,3]f32)(t)
    scale := [3]f32{linalg.length2(basis[0]), linalg.length2(basis[1]), linalg.length2(basis[2])}
    if min(scale.x, scale.y, scale.z) == 0 do return false
    a := linalg.dot(basis[0], basis[1])
    b := linalg.dot(basis[0], basis[2])
    c := linalg.dot(basis[1], basis[2])
    EPS2 :: EPS * EPS
    return a*a <= EPS2*scale.x*scale.y &&
        b*b <= EPS2*scale.x*scale.z &&
        c*c <= EPS2*scale.y*scale.z
}

similarity :: proc(t: matrix[4,4]f32) -> bool {
    return orthogonal(t) && uniform_scale(t)
}

axis_aligned :: proc(t: matrix[4,4]f32) -> bool {
    basis := cast(matrix[3,3]f32)(t)
    for i in 0..<3 {
        col := basis[i]
        threshold := EPS * EPS * linalg.length2(col)
        if int(col.x*col.x > threshold) +
            int(col.y*col.y > threshold) +
            int(col.z*col.z > threshold) != 1 {
                return false
            }
    }
    return true
}

rigid_inverse :: proc(t: matrix[4,4]f32) -> (inv: matrix[4,4]f32, scale: [3]f32) {
    scale = {linalg.length(t[0].xyz), linalg.length(t[1].xyz), linalg.length(t[2].xyz)}
    inv = 1
    for i in 0..<3 {
        axis := t[i].xyz / scale[i]
        inv[i, 0] = axis.x
        inv[i, 1] = axis.y
        inv[i, 2] = axis.z
        inv[i, 3] = -linalg.dot(axis, t[3].xyz)
    }
    return
}

box_rotated :: proc(b: Box, t: matrix[4,4]f32) -> (box: Box, rot: matrix[3,3]f32) {
    scale := [3]f32{linalg.length(t[0].xyz), linalg.length(t[1].xyz), linalg.length(t[2].xyz)}
    for i in 0..<3 {
        axis := t[i].xyz / scale[i]
        rot[0, i] = axis.x
        rot[1, i] = axis.y
        rot[2, i] = axis.z
    }
    box.center = (t * [4]f32{**b.center, 1}).xyz
    box.half_extents = b.half_extents * scale
    return
}

shape_overlapping :: proc(a: Shape, atrans: matrix[4,4]f32, b: Shape, btrans: matrix[4,4]f32) -> bool {
    a, b := a, b
    atrans, btrans := atrans, btrans
    if shape_kind(a) > shape_kind(b) {
        a, b = b, a
        atrans, btrans = btrans, atrans
    }

    //reframe to A when A is Box+orthonormal for OBB tests
    if shape_kind(a) == .Box && orthogonal(atrans) {
        inv, scale := rigid_inverse(atrans)
        a = Box{a.(Box).center * scale, a.(Box).half_extents * scale}
        atrans = 1
        btrans = inv * btrans
    }
    
    //fast paths
    switch ([2]Shape_Kind{shape_kind(a), shape_kind(b)}) {
    case {.Box, .Box}:
        if atrans == 1 && orthogonal(btrans) {
            bb, rot := box_rotated(b.(Box), btrans)
            if axis_aligned(btrans) {
                abs_rot := rot
                abs_rot[0] = linalg.abs(abs_rot[0])
                abs_rot[1] = linalg.abs(abs_rot[1])
                abs_rot[2] = linalg.abs(abs_rot[2])
                bext := abs_rot * bb.half_extents
                return aabb_aabb(box_aabb(a.(Box)), {bb.center - bext, bb.center + bext})
            } else {
                return box_box(a.(Box), bb, rot)
            }
        }
    case {.Box, .Sphere}:
        if atrans == 1 && similarity(btrans) {
            return sphere_box(transform_sphere(b.(Sphere), btrans), a.(Box))
        }
    case {.Sphere, .Sphere}:
        if similarity(atrans) && similarity(btrans) {
            return sphere_sphere(
                transform_sphere(a.(Sphere), atrans),
                transform_sphere(b.(Sphere), btrans))
        }
    case {.Sphere, .Capsule}:
        if similarity(atrans) && similarity(btrans) {
            return capsule_sphere(
                transform_capsule(b.(Capsule), btrans),
                transform_sphere(a.(Sphere), atrans))
        }
    case {.Capsule, .Capsule}:
        if similarity(atrans) && similarity(btrans) {
            return capsule_capsule(
                transform_capsule(a.(Capsule), atrans),
                transform_capsule(b.(Capsule), btrans)) //TODO fix capsule-capsule
        }
    }
    //everything else gets GJK
    return boolean_gjk(a, atrans, b, btrans)
}

