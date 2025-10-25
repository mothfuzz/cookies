package spatial

Tri_Mesh :: struct {
    vertices: [][3]f32,
}

import "base:runtime"
make_tri_mesh :: proc(vertices: [][3]f32, allocator: runtime.Allocator = context.allocator) -> (tm: Tri_Mesh) {
    tm.vertices = make([dynamic][3]f32, len(vertices), allocator)[:]
    copy(vertices, tm.vertices)
    return
}
delete_tri_mesh :: proc(tm: Tri_Mesh) {
    delete(tm.vertices)
}


//TODO: integrate this.
import "core:math"

dot :: proc(a: [3]f32, b: [3]f32) -> f32 {
    return a.x * b.x + a.y * b.y + a.z * b.z
}

length2 :: proc(v: [3]f32) -> f32 {
    return dot(v, v)
}

length :: proc(v: [3]f32) -> f32 {
    return math.sqrt(length2(v))
}

//project length of a in direction of b
project :: proc(a: [3]f32, b: [3]f32) -> [3]f32 {
    return dot(a, b)/dot(b, b) * b
}

Surface :: struct {
    position: [3]f32,
    normal: [3]f32,
}

move :: proc(input_position: [3]f32, input_radius: f32, input_velocity: [3]f32, surfaces: []Surface) -> (output_position: [3]f32) {
    output_velocity := input_velocity
    for surface in surfaces {
        position := input_position + output_velocity
        displacement := project(surface.position - position, surface.normal) //vector perpendicular to surface pointing to object
        //closest_point := position - displacement //closest point on surface
        //overlap := input_radius - length(closest_point - position)
        overlap := input_radius - length(displacement)
        if overlap > 0 {
            output_velocity += overlap * surface.normal
        }
    }
    output_position = input_position + output_velocity
    return
}
