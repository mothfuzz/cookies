package graphics

Combined_Material :: struct {
    using base: Material,
    using dyn: Dynamic_Material,
}

Model :: struct {
    meshes: []^Mesh, //'primitives'
    materials: []^Combined_Material,
}
draw_model :: proc(frame: ^Frame, model: Model, trans: matrix[4,4]f32=1, bones: []matrix[4,4]f32 = nil) {
    for mesh, i in model.meshes {
        dyn := model.materials[i].dyn
        bones := bones
        if bones != nil {
            //hate this but we gotta
            owned_bones := make([]matrix[4,4]f32, len(bones))
            copy(owned_bones, bones)
            bones = owned_bones
        }
        draw_mesh(frame, mesh^, model.materials[i], trans, dyn.clip_rect,
                  dyn.base_color_tint, dyn.pbr_tint.r, dyn.pbr_tint.g, dyn.pbr_tint.b, dyn.emissive_tint.rgb,
                  false, false, bones)
    }
}
