package graphics

CombinedMaterial :: struct {
    using base: Material,
    using dyn: DynamicMaterial,
}

Model :: struct {
    meshes: []^Mesh, //'primitives'
    materials: []^CombinedMaterial,
}
draw_model :: proc(model: Model, trans: matrix[4,4]f32=1, bones: []matrix[4,4]f32 = nil) {
    for mesh, i in model.meshes {
        draw_mesh(mesh^, model.materials[i], trans, tint=model.materials[i].tint, clip_rect=model.materials[i].clip_rect, bones=bones)
    }
}
