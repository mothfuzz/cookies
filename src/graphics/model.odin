package graphics

CombinedMaterial :: struct {
    material: Material,
    base_color_tint: [4]f32,
}

Model :: struct {
    meshes: []^Mesh, //'primitives'
    materials: []^CombinedMaterial,
}
draw_model :: proc(model: Model, trans: matrix[4,4]f32=1, bones: []matrix[4,4]f32) {
    for mesh, i in model.meshes {
        draw_mesh(mesh^, model.materials[i].material, trans, tint=model.materials[i].base_color_tint, bones=bones)
    }
}
