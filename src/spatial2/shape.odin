package spatial2

Shape :: union {
    Box,
    Sphere,
    Capsule,
    Convex_Hull, //ID, not verts
}

shape_extents :: proc(s: Shape, t: matrix[4,4]f32) -> [2][3]f32 {
    #partial switch s in s {
        case Box: return box_extents(s, t)
        case Sphere: return sphere_extents(s, t)
        case Capsule: return capsule_extents(s, t)
    }
    return 0
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
