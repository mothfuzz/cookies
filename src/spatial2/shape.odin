package spatial2

import "core:math/linalg"

Shape :: union {
    Box,
    Sphere,
    Capsule,
    Convex_Hull, //ID, not verts
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
        return 0
        //return hull_support(s, dir)
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

shape_overlapping :: proc(a: Shape, atrans: matrix[4,4]f32, b: Shape, btrans: matrix[4,4]f32) -> bool {
    #partial switch a in a {
        case Box: return box_overlapping(a, atrans, b, btrans)
        case Sphere: return sphere_overlapping(a, atrans, b, btrans)
        case Capsule: return capsule_overlapping(a, atrans, b, btrans)
    }
    return false
}

Convex_Hull :: distinct int
