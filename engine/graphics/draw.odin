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


draw_sprite :: proc(material: Material, model: matrix[4, 4]f32 = 0, clip_rect: [4]f32 = 0, billboard: bool = true) {
    draw_mesh(quad_mesh, material, model, clip_rect, true, billboard)
}

//0,0 is center, rect is -1:1 xywh, clip_rect is xywh, 0:w & 0:h of texture
ui_draw_rect :: proc(rect: [4]f32, color: [4]f32 = 1, texture: Texture = white_tex, clip_rect: [4]f32 = 0) {
    sx := f32(screen_size.x)/2
    sy := f32(screen_size.y)/2
    fill_rect := [4]f32{
        rect[0]/sx,
        rect[1]/sy,
        rect[2]/sx,
        rect[3]/sy,
    }
    tx := f32(texture.size.x)
    ty := f32(texture.size.y)
    clip_rect := [4]f32{
        clip_rect[0]/tx,
        clip_rect[1]/ty,
        clip_rect[2]/tx,
        clip_rect[3]/ty,
    }
    draw_ui(fill_rect, color, texture, clip_rect)
}
