package spatial

import "core:math/linalg"
import "core:math"

Tri :: struct {
    vertices: [3][3]f32,
    position: [3]f32, //centroid
    normal: [3]f32,
    extents: [2][3]f32,
}

Tri_Mesh :: struct {
    tris: []Tri,
    extents: [2][3]f32,
}


@(private)
update_extents :: proc(extents: ^[2][3]f32, new_vertex: [3]f32) {
    if new_vertex.x < extents[0].x {
        extents[0].x = new_vertex.x
    }
    if new_vertex.y < extents[0].y {
        extents[0].y = new_vertex.y
    }
    if new_vertex.z < extents[0].z {
        extents[0].z = new_vertex.z
    }
    if new_vertex.x > extents[1].x {
        extents[1].x = new_vertex.x
    }
    if new_vertex.y > extents[1].y {
        extents[1].y = new_vertex.y
    }
    if new_vertex.z > extents[1].z {
        extents[1].z = new_vertex.z
    }
}

calc :: proc(tri: ^Tri) {
    tri.position = (tri.vertices[0] + tri.vertices[1] + tri.vertices[2]) / 3
    ba := tri.vertices[1] - tri.vertices[0]
    ca := tri.vertices[2] - tri.vertices[0]
    tri.normal = linalg.normalize(linalg.cross(ba, ca))
    for vertex in tri.vertices {
        update_extents(&tri.extents, vertex)
    }
}

import "base:runtime"
import "core:fmt"
make_tri_mesh :: proc(vertices: [][3]f32, indices: []u32 = nil, allocator: runtime.Allocator = context.allocator) -> (tm: Tri_Mesh) {
    tm.tris = make([dynamic]Tri, len(indices)/3, allocator)[:]
    tm.extents[0] = math.INF_F32//+infinity, -infinity
    tm.extents[1] = math.NEG_INF_F32
    for &v, i in tm.tris {
        v.vertices[0] = vertices[indices[i*3+0]]
        v.vertices[1] = vertices[indices[i*3+1]]
        v.vertices[2] = vertices[indices[i*3+2]]
        calc(&v)
        update_extents(&tm.extents, v.extents[0])
        update_extents(&tm.extents, v.extents[1])
    }
    return
}
delete_tri_mesh :: proc(tm: Tri_Mesh) {
    delete(tm.tris)
}

//NOTE: only supports in-place - won't produce a new mesh.
transform_tri_mesh :: proc(mesh: ^Tri_Mesh, trans: matrix[4,4]f32) {
    mesh.extents[0] = math.INF_F32
    mesh.extents[1] = math.NEG_INF_F32
    for &tri in mesh.tris {
        for &v in tri.vertices {
            new_vertex := [4]f32{v.x, v.y, v.z, 1}
            v = (trans * new_vertex).xyz
        }
        calc(&tri)
        update_extents(&mesh.extents, tri.extents[0])
        update_extents(&mesh.extents, tri.extents[1])
    }
}

sphere_line :: proc(s: Sphere, a, b: [3]f32) -> bool {
    d := b - a
    proj := linalg.dot(s.center - a, d) //project p - a onto d (length sqr)
    t := proj / linalg.length2(d) //distance along projection / length of line = percentage to nearest perpendicular point
    if t >= 0 && t <= 1 {
        return linalg.length2(s.center - (a + t * d)) <= s.radius * s.radius
    }
    return false
}

tri_line :: proc(o: [3]f32, p: [3]f32, tri: Tri) -> bool {
    direction := 0
    for i in 0..<3 {
        v0 := tri.vertices[(i+0)%3] - p
        v1 := tri.vertices[(i+1)%3] - p
        n := linalg.normalize(linalg.cross(v1, v0))
        angle := linalg.dot(p - o, n)
        if direction == 0 {
            direction = angle < 0?-1:1
        } else if direction == -1 && angle > 0 {
            return false
        } else if direction == 1 && angle < 0 {
            return false
        }
    }
    return true
}

//TODO: make a little demo project and test this out.
move :: proc(input_position: [3]f32, input_radius: f32, input_velocity: [3]f32, all_meshes: []Tri_Mesh) -> (output_velocity: [3]f32) {
    output_velocity = input_velocity
    for mesh in all_meshes {
        if sphere_aabb({input_position+input_velocity, input_radius}, {mesh.extents[0], mesh.extents[1]}) {
            for tri in mesh.tris {
                position := input_position + output_velocity
                //don't double-wall
                if linalg.dot(position-tri.position, tri.normal) < 0 ||
                    linalg.dot(linalg.normalize(output_velocity), tri.normal) > 0 {
                    continue
                }
                test_sphere := Sphere{position, input_radius}
                if sphere_aabb(test_sphere, {tri.extents[0], tri.extents[1]}) {
                    displacement := linalg.projection(tri.position - position, tri.normal) //vector perpendicular to surface pointing to object
                    //closest_point := position - displacement //closest point on surface
                    //overlap := input_radius - length(closest_point - position)
                    overlap := input_radius - linalg.vector_length(displacement)
                    if overlap > 0 {
                        //final check... if it's inside the triangle
                        if sphere_point(test_sphere, Point{tri.vertices[0]}) ||
                            sphere_point(test_sphere, Point{tri.vertices[1]}) ||
                            sphere_point(test_sphere, Point{tri.vertices[1]}) ||
                            sphere_line(test_sphere, tri.vertices[0], tri.vertices[1]) ||
                            sphere_line(test_sphere, tri.vertices[1], tri.vertices[2]) ||
                            sphere_line(test_sphere, tri.vertices[2], tri.vertices[0]) ||
                            tri_line(position, position+displacement, tri) {
                                adj := tri.normal * linalg.dot(output_velocity, tri.normal) //* 2.0 //bouncy :3
                                output_velocity -= adj
                                //output_velocity += overlap * tri.normal
                        }
                    }
                }
            }

        }
    }
    return
}
