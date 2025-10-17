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
