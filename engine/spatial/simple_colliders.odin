package spatial

import "core:math"
import "core:math/linalg"

Point :: struct {
    using p: [3]f32,
}
transform_point :: proc(p: Point, t: matrix[4, 4]f32) -> Point {
    p := [4]f32{p.x, p.y, p.z, 1}
    return Point{(t * p).xyz}
}
point_extents :: proc(p: Point) -> [2][3]f32 {
    return {p, p}
}

Bounding_Box :: struct {
    min: [3]f32,
    max: [3]f32,
}
transform_aabb_rotated :: proc(a: Bounding_Box, t: matrix[4, 4]f32) -> Bounding_Box {
    //this is returning a position=0 for some reason
    position := t[3].xyz
    corners: [8][4]f32
    new_min: [3]f32 = a.min + position
    new_max: [3]f32 = a.max + position
    c := 0
    for i in 0..<2 {
        for j in 0..<2 {
            for k in 0..<2 {
                corners[c] = {
                    i == 0 ? a.min.x : a.max.x,
                    j == 0 ? a.min.y : a.max.y,
                    k == 0 ? a.min.z : a.max.z,
                    1,
                }
                corners[c] = t * corners[c]
                p := corners[c].xyz
                new_min.x = p.x < new_min.x ? p.x : new_min.x
                new_min.y = p.y < new_min.y ? p.y : new_min.y
                new_min.z = p.z < new_min.z ? p.z : new_min.z
                new_max.x = p.x > new_max.x ? p.x : new_max.x
                new_max.y = p.y > new_max.y ? p.y : new_max.y
                new_max.z = p.z > new_max.z ? p.z : new_max.z
                c += 1
            }
        }
    }
    return {new_min, new_max}
}
transform_aabb_fixed :: proc(a: Bounding_Box, t: matrix[4,4]f32) -> Bounding_Box {
    scale: [3]f32
    scale.x = linalg.length(t[0])
    scale.y = linalg.length(t[1])
    scale.z = linalg.length(t[2])
    position := t[3].xyz
    center := (a.min + a.max) / 2
    size := linalg.abs(a.max - a.min)
    center += position
    size *= scale
    return {center - size/2, center + size/2}
}
transform_aabb :: proc(a: Bounding_Box, t: matrix[4,4]f32, expand_rotation: bool = true) -> Bounding_Box {
    if expand_rotation {
        return transform_aabb_rotated(a, t)
    } else {
        return transform_aabb_fixed(a, t)
    }
}
aabb_extents :: proc(a: Bounding_Box) -> [2][3]f32 {
    return {a.min, a.max}
}

Sphere :: struct {
    center: [3]f32,
    radius: f32,
}
transform_sphere :: proc(a: Sphere, t: matrix[4,4]f32) -> Sphere {
    scale := max(linalg.length(t[0]), linalg.length(t[1]), linalg.length(t[2]))
    position := t[3].xyz
    return {a.center + position, a.radius * scale}
}
sphere_extents :: proc(a: Sphere) -> [2][3]f32 {
    return {a.center - a.radius, a.center + a.radius}
}

Capsule :: struct {
    a: [3]f32,
    b: [3]f32,
    radius: f32,
}
transform_capsule :: proc(c: Capsule, t: matrix[4,4]f32) -> Capsule {
    a := [4]f32{c.a.x, c.a.y, c.a.z, 1} * t
    b := [4]f32{c.b.x, c.b.y, c.b.z, 1} * t
    scale := max(linalg.length(t[0]), linalg.length(t[1]), linalg.length(t[2]))
    return {a.xyz, b.xyz, c.radius * scale}
}
capsule_extents :: proc(c: Capsule) -> (extents: [2][3]f32) {
    extents[0].x = min(c.a.x, c.b.x)
    extents[0].y = min(c.a.y, c.b.y)
    extents[0].z = min(c.a.z, c.b.z)
    extents[1].x = max(c.a.x, c.b.x)
    extents[1].y = max(c.a.y, c.b.y)
    extents[1].z = max(c.a.z, c.b.z)
    extents[0] -= c.radius
    extents[1] += c.radius
    return
}

Box :: struct {
    vertices: [8][3]f32,
}

point_point :: proc(a, b: Point) -> bool {
    return a == b
}

sphere_sphere :: proc(a: Sphere, b: Sphere) -> bool {
    return linalg.length2(b.center - a.center) <=
    a.radius * a.radius + b.radius * b.radius
}

point_sphere :: proc(a: Point, b: Sphere) -> bool {
    return linalg.length2(b.center - a) <= b.radius * b.radius
}

sphere_point :: proc(a: Sphere, b: Point) -> bool {
    return point_sphere(b, a)
}


aabb_aabb :: proc(a: Bounding_Box, b: Bounding_Box) -> bool {
    return a.max.x >= b.min.x &&
            a.max.y >= b.min.y &&
            a.max.z >= b.min.z &&
            a.min.x <= b.max.x &&
            a.min.y <= b.max.y &&
            a.min.z <= b.max.z
}

aabb_point :: proc(a: Bounding_Box, b: Point) -> bool {
    return a.min.x <= b.x &&
            a.min.y <= b.y &&
            a.min.z <= b.z &&
            a.max.x >= b.x &&
            a.max.y >= b.y &&
            a.max.z >= b.z
}
point_aabb :: proc(a: Point, b: Bounding_Box) -> bool {
    return aabb_point(b, a)
}

aabb_sphere :: proc(a: Bounding_Box, b: Sphere) -> bool {
    closest := linalg.clamp(b.center, a.min, a.max)
    distance := linalg.length2(closest - b.center)
    return distance <= b.radius * b.radius
}

sphere_aabb :: proc(a: Sphere, b: Bounding_Box) -> bool {
    return aabb_sphere(b, a)
}

point_on_segment :: proc(p, a, b: [3]f32) -> [3]f32 {
    ba := b - a
    pa := p - a
    t := linalg.dot(pa, ba) / linalg.dot(ba, ba)
    return linalg.lerp(a, b, linalg.clamp(t, 0, 1))
}

capsule_tips :: proc(c: Capsule) -> (a, b: [3]f32) {
    line := c.b - c.a
    norm := linalg.normalize(line)
    offset := c.radius * norm
    a = c.a + offset
    b = c.b - offset
    return
}

capsule_capsule :: proc(a: Capsule, b: Capsule) -> bool {
    aa, ab := capsule_tips(a)
    ba, bb := capsule_tips(b)

    d0 := linalg.length2(ba - aa)
    d1 := linalg.length2(bb - aa)
    d2 := linalg.length2(ba - ab)
    d3 := linalg.length2(bb - ab)

    closest_a := aa
    if d2 < d0 || d2 < d1 || d3 < d0 || d3 < d1 {
        closest_a = ab
    }

    closest_b := point_on_segment(closest_a, ba, bb)
    closest_a = point_on_segment(closest_b, aa, ab)

    a_sphere := Sphere{center=closest_a, radius=a.radius}
    b_sphere := Sphere{center=closest_b, radius=b.radius}
    return sphere_sphere(a_sphere, b_sphere)
}

capsule_point :: proc(a: Capsule, b: Point) -> bool {
    aa, ab := capsule_tips(a)
    closest_a := point_on_segment(b, aa, ab)
    a_sphere := Sphere{center=closest_a, radius=a.radius}
    return sphere_point(a_sphere, b)
}

point_capsule :: proc(a: Point, b: Capsule) -> bool {
    return capsule_point(b, a)
}

capsule_sphere :: proc(a: Capsule, b: Sphere) -> bool {
    aa, ab := capsule_tips(a)
    closest_a := point_on_segment(b.center, aa, ab)
    a_sphere := Sphere{center=closest_a, radius=a.radius}
    return sphere_sphere(a_sphere, b)
}

sphere_capsule :: proc(a: Sphere, b: Capsule) -> bool {
    return capsule_sphere(b, a)
}

capsule_aabb :: proc(a: Capsule, b: Bounding_Box) -> bool {
    aa, ab := capsule_tips(a)
    center := (aa + ab)/2
    closest_b := linalg.clamp(center, b.min, b.max)
    closest_a := point_on_segment(closest_b, aa, ab)
    return linalg.length2(closest_b - closest_a) <= a.radius
}

aabb_capsule :: proc(a: Bounding_Box, b: Capsule) -> bool {
    return capsule_aabb(b, a)
}
