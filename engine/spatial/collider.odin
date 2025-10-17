package spatial

SimpleShape :: union {
    Bounding_Box,
    Sphere,
    Capsule,
    //Box,
}

ComplexShape :: union {
    Convex_Hull,
    Tri_Mesh,
}

//would be easier if we could just `using` the other 2 but that's okay
Shape :: union {
    Point,
    Bounding_Box,
    Sphere,
    Capsule,
    Convex_Hull,
    Tri_Mesh,
}

shape_extents :: proc(c: Shape) -> [2][3]f32 {
    switch c in c {
    case Point:
        return point_extents(c)
    case Bounding_Box:
        return aabb_extents(c)
    case Sphere:
        return sphere_extents(c)
    case Capsule:
        return capsule_extents(c)

    //complex shapes not implemented yet
    case Convex_Hull:
        return 0
    case Tri_Mesh:
        return 0
    }
    return 0
}

extents :: proc{point_extents, aabb_extents, sphere_extents, capsule_extents, shape_extents}

transform_shape :: proc(c: Shape, t: matrix[4,4]f32) -> Shape {
    switch c in c {
    case Point:
        return transform_point(c, t)
    case Bounding_Box:
        return transform_aabb(c, t)
    case Sphere:
        return transform_sphere(c, t)
    case Capsule:
        return transform_capsule(c, t)

    //complex shapes not implemented yet
    case Convex_Hull:
        return c
    case Tri_Mesh:
        return c
    }
    return c
}

transform :: proc{transform_point, transform_aabb, transform_sphere, transform_capsule, transform_shape}


overlaps :: proc{
    point_point,
    point_aabb, aabb_point,
    point_sphere, sphere_point,
    point_capsule, capsule_point,
    aabb_aabb,
    aabb_sphere, sphere_aabb,
    aabb_capsule, capsule_aabb,
    sphere_sphere,
    sphere_capsule, capsule_sphere,
    capsule_capsule,
    shape_overlaps}


//Have the 'Collider' keep track of changes so that the Spatial structures don't need to know anything.
Collider :: struct {
    shape: Shape,
    trans: matrix[4,4]f32,
    extents: [2][3]f32,
    transformed_shape: Shape,
    transformed_extents: [2][3]f32,
}

shape_overlaps :: proc(a: Shape, b: Shape) -> bool {
    #partial switch a in a {
        case Point:
        #partial switch b in b {
            case Point:         return point_point(a, b)
            case Bounding_Box:  return point_aabb(a, b)
            case Sphere:        return point_sphere(a, b)
            case Capsule:       return point_capsule(a, b)
        }
        case Bounding_Box:
        #partial switch b in b {
            case Point:         return aabb_point(a, b)
            case Bounding_Box:  return aabb_aabb(a, b)
            case Sphere:        return aabb_sphere(a, b)
            case Capsule:       return aabb_capsule(a, b)
        }
        case Sphere:
        #partial switch b in b {
            case Point:         return sphere_point(a, b)
            case Bounding_Box:  return sphere_aabb(a, b)
            case Sphere:        return sphere_sphere(a, b)
            case Capsule:       return sphere_capsule(a, b)
        }
        case Capsule:
        #partial switch b in b {
            case Point:         return capsule_point(a, b)
            case Bounding_Box:  return capsule_aabb(a, b)
            case Sphere:        return capsule_sphere(a, b)
            case Capsule:       return capsule_capsule(a, b)
        }
    }
    return false
}
