package spatial2

import "core:math/linalg"

Simplex :: struct {
    points: [4][3]f32,
    dim: int,
}

//push a new point to the simplex, rotating previous points out
push_simplex :: proc(simplex: ^Simplex, p: [3]f32) {
    simplex.points[3] = simplex.points[2]
    simplex.points[2] = simplex.points[1]
    simplex.points[1] = simplex.points[0]
    simplex.points[0] = p
    simplex.dim = min(simplex.dim + 1, 4)
}

//returns whether simplex encloses the origin
//updates simplex closer to the origin & dir to point toward the origin
next_simplex :: proc(simplex: ^Simplex, dir: ^[3]f32) -> bool {
    switch simplex.dim {
    case 2: return line_simplex(simplex, dir)
    case 3: return triangle_simplex(simplex, dir)
    case 4: return tetrahedron_simplex(simplex, dir)
    }
    return false
}

line_simplex :: proc(simplex: ^Simplex, dir: ^[3]f32) -> bool {
    a := simplex.points[0]
    b := simplex.points[1]
    ab := b - a
    ao := -a
    if linalg.dot(ab, ao) > 0 {
        //inside the segment, keep A & B
        dir^ = linalg.cross(linalg.cross(ab, ao), ab)
        abl := linalg.length2(ab)
        if linalg.length2(dir^) <= 1e-12 * abl * abl * abl {
            //origin is on the segment, thus colliding
            return true
        }
    } else {
        //outside the segment, origin is somewhere past A
        simplex.dim = 1
        dir^ = ao
    }
    return false
}

triangle_simplex :: proc(simplex: ^Simplex, dir: ^[3]f32) -> bool {
    a := simplex.points[0]
    b := simplex.points[1]
    c := simplex.points[2]
    ab := b - a
    ac := c - a
    //need not check bc because that would be 'backwards' away from the origin
    ao := -a
    abc := linalg.cross(ab, ac) //face normal
    if linalg.dot(linalg.cross(abc, ac), ao) > 0 {
        //origin is somwehere beyond AC
        //determine if AC-edge or A-vertex
        simplex.points[1] = c
        simplex.dim = 2
        return line_simplex(simplex, dir)
    } else {
        //origin is either somewhere beyond AB, or face
        if linalg.dot(linalg.cross(ab, abc), ao) > 0 {
            //determine if AB-edge or A-vertex
            simplex.dim = 2
            return line_simplex(simplex, dir)
        } else {
            //inside face region, determine which side
            if linalg.dot(abc, ao) > 0 {
                dir^ = abc
            } else {
                simplex.points[1] = c
                simplex.points[2] = b
                dir^ = -abc
            }
        }
    }
    return false
}

tetrahedron_simplex :: proc(simplex: ^Simplex, dir: ^[3]f32) -> bool {
    a := simplex.points[0]
    b := simplex.points[1]
    c := simplex.points[2]
    d := simplex.points[3]

    ab := b - a
    ac := c - a
    ad := d - a
    ao := -a

    abc := linalg.cross(ab, ac)
    acd := linalg.cross(ac, ad)
    adb := linalg.cross(ad, ab)

    if linalg.dot(abc, ao) > 0 {
        //outside abc-face region, drop d (implicit)
        simplex.dim = 3
        return triangle_simplex(simplex, dir)
    }
    if linalg.dot(acd, ao) > 0 {
        //outside acd-face region, drop b
        simplex.points[1] = c
        simplex.points[2] = d
        simplex.dim = 3
        return triangle_simplex(simplex, dir)
    }
    if linalg.dot(adb, ao) > 0 {
        //outside adb-face region, drop c
        simplex.points[1] = d
        simplex.points[2] = b
        simplex.dim = 3
        return triangle_simplex(simplex, dir)
    }

    //otherwise, it contains the origin!
    return true
}

//minkowski difference for two support points
support_diff :: proc(a: Shape, atrans: matrix[4,4]f32, b: Shape, btrans: matrix[4,4]f32, dir: [3]f32) -> [3]f32 {
    a := shape_support_world(a, atrans, +dir)
    b := shape_support_world(b, btrans, -dir)
    return a - b
}

shape_center :: proc(s: Shape) -> [3]f32 {
    switch s in s {
    case Box:
        return s.center
    case Sphere:
        return s.center
    case Capsule:
        return (s.a + s.b) / 2
    case Convex_Hull:
        return 0
    }
    return 0
}


boolean_gjk :: proc(a: Shape, atrans: matrix[4,4]f32, b: Shape, btrans: matrix[4,4]f32) -> bool {
    //start with a search direction that points between the two shapes
    ca := (atrans * [4]f32{**shape_center(a), 1}).xyz
    cb := (btrans * [4]f32{**shape_center(b), 1}).xyz
    dir := cb - ca
    //avoid degenerate case for concentric shapes
    if linalg.length2(dir) < 1e-12 {
        dir = {1, 0, 0}
    }

    //grab first support point and initialize the simplex/dir
    simplex: Simplex
    p := support_diff(a, atrans, b, btrans, dir)
    if linalg.dot(p, dir) < 0 {
        return false
    }
    push_simplex(&simplex, p)
    dir = -p

    for _ in 0..<64 {
        //get new support point
        p = support_diff(a, atrans, b, btrans, dir)

        d := linalg.dot(p, dir)
        //if the furthest point along dir didn't cross the origin, the shapes cannot be intersecting
        if d < -1e-12 {
            return false
        }
        //but if the furthest point is touching the origin, the shapes *are* intersecting
        if d < 1e-12 {
            return true
        }

        push_simplex(&simplex, p)

        //iteratively check if simplex contains the origin
        //or update simplex/dir based on features
        if next_simplex(&simplex, &dir) {
            return true
        }
    }

    return false
}
