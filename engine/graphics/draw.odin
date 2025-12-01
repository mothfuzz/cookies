package graphics

import "core:fmt"

//'top level' draw functions go here
//draw_mesh, draw_sprite, draw_ui, draw_lines, draw_line_strip, draw_line_loop

MeshDraw :: struct {
    model: matrix[4,4]f32,
    using dynamic_material: DynamicMaterial,
    is_sprite: bool,
    is_billboard: bool,
}

//more often do we have the same mesh with different textures
//than we have the same texture on different meshes
solid_batches: map[Mesh]map[Material][dynamic]MeshDraw
trans_batches: map[Mesh]map[Material][dynamic]MeshDraw

clear_batches :: proc() {
    for mesh, &batch in solid_batches {
        for material, &instances in batch {
            clear(&instances)
        }
    }
    for mesh, &batch in trans_batches {
        for material, &instances in batch {
            clear(&instances)
        }
    }
}

delete_batches :: proc() {
    for mesh, &batch in solid_batches {
        for material, &instances in batch {
            delete(instances)
        }
        delete(batch)
    }
    delete(solid_batches)
    for mesh, &batch in trans_batches {
        for material, &instances in batch {
            delete(instances)
        }
        delete(batch)
    }
    delete(trans_batches)
}

draw_mesh :: proc(mesh: Mesh, material: Material, model: matrix[4, 4]f32 = 0,
                  clip_rect: [4]f32 = 0, tint: [4]f32 = 1,
                  sprite: bool = false, billboard: bool = false) {
    model := model
    batch: ^map[Material][dynamic]MeshDraw
    if mesh.transparent || material.base_color.transparent || (tint.a < 1 && tint.a > 0) {
        if !(mesh in trans_batches) {
            trans_batches[mesh] = {}
        }
        batch = &trans_batches[mesh]
        if !(material in batch) {
            //create instance buffer
            batch[material] = make([dynamic]MeshDraw, 0)
        }
        instances := &batch[material]
        append(instances, MeshDraw{model, {clip_rect, tint}, sprite, billboard})
    }
    if mesh.solid && material.base_color.solid && tint.a == 1.0 {
        //fmt.println("transparent draw")
        if !(mesh in solid_batches) {
            solid_batches[mesh] = {}
        }
        batch = &solid_batches[mesh]
        if !(material in batch) {
            //create instance buffer
            batch[material] = make([dynamic]MeshDraw, 0)
        }
        instances := &batch[material]
        append(instances, MeshDraw{model, {clip_rect, tint}, sprite, billboard})
    }
}


draw_sprite :: proc(material: Material, model: matrix[4, 4]f32 = 0,
                    clip_rect: [4]f32 = 0, tint: [4]f32 = 1,
                    billboard: bool = true) {
    draw_mesh(quad_mesh, material, model, clip_rect, tint, true, billboard)
}

//0,0 is center, rect is -1:1 xywh, clip_rect is xywh, 0:w & 0:h of texture
ui_draw_rect :: proc(rect: [4]f32, color: [4]f32 = 1, texture: Texture = white_tex, clip_rect: [4]f32 = 0) {
    sx := screen_uniforms.size.x/2
    sy := screen_uniforms.size.y/2
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
        (clip_rect[2]==0?tx:clip_rect[2])/tx,
        (clip_rect[3]==0?ty:clip_rect[2])/ty,
    }
    draw_ui(fill_rect, color, texture, clip_rect)
}
