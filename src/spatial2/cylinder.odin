package spatial2

import "core:math/linalg"

Cylinder :: struct {
    a, b: [3]f32,
    radius: f32,
}

cylinder_support :: proc(c: Cylinder, dir: [3]f32) -> [3]f32 {
    axis := c.b - c.a
    tip := linalg.dot(dir, axis) > 0 ? c.b : c.a
    perp := dir - axis * (linalg.dot(dir, axis) / linalg.dot(axis, axis))
    l := linalg.length2(perp)
    if l < 1e-12 do return tip //dir is parallel to axis: any point on the tip is valid
    return tip + perp * (c.radius / linalg.sqrt(l))
}
