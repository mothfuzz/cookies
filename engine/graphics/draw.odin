package graphics

import "core:fmt"

//'top level' draw functions go here
//draw_mesh, draw_sprite, draw_ui, draw_lines, draw_line_strip, draw_line_loop

MeshDraw :: struct {
    model: matrix[4,4]f32,
    clip_rect: [4]f32,
    is_sprite: bool,
    is_billboard: bool,
}

//more often do we have the same mesh with different textures
//than we have the same texture on different meshes
batches: map[Mesh]map[Material][dynamic]MeshDraw

draw_mesh :: proc(mesh: Mesh, material: Material, model: matrix[4, 4]f32 = 0, clip_rect: [4]f32 = 0, sprite: bool = false, billboard: bool = false) {
    model := model
    if !(mesh in batches) {
        batches[mesh] = {}
    }
    batch := &batches[mesh]
    if !(material in batch) {
        //create instance buffer
        batch[material] = make([dynamic]MeshDraw, 0)
    }
    instances := &batch[material]
    append(instances, MeshDraw{model, clip_rect, sprite, billboard})
}

sprite_mesh: Mesh

draw_sprite :: proc(material: Material, model: matrix[4, 4]f32 = 0, clip_rect: [4]f32 = 0, billboard: bool = true) {
    if sprite_mesh.size == 0 {
        sprite_mesh = make_mesh([]Vertex{
            {position={-0.5, +0.5, 0.0}, texcoord={0.0, 0.0}, color={1, 1, 1, 1}},
            {position={+0.5, +0.5, 0.0}, texcoord={1.0, 0.0}, color={1, 1, 1, 1}},
            {position={+0.5, -0.5, 0.0}, texcoord={1.0, 1.0}, color={1, 1, 1, 1}},
            {position={-0.5, -0.5, 0.0}, texcoord={0.0, 1.0}, color={1, 1, 1, 1}},
        }, {0, 1, 2, 0, 2, 3})
    }
    draw_mesh(sprite_mesh, material, model, clip_rect, true, billboard)
}
