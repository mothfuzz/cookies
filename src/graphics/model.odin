package graphics

Model :: struct {
    meshes: []^Mesh, //'primitives'
    materials: []^Material,
}
draw_model :: proc(model: Model, trans: matrix[4,4]f32=1) {
    for mesh, i in model.meshes {
        draw_mesh(mesh^, model.materials[i]^, trans)
    }
}
