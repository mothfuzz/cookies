package graphics
import stbtt "vendor:stb/truetype"

/*
we're gonna do this how stb_truetype wants us to do it.
Pack an atlas.
Use instancing - the geometry is just a single quad.
Transform vertices according to current_point & the current char's recorded width/height.
Upload the whole texture as an atlas, use the sub-coordinates as instanced data.
*/

Font :: struct {
    texture: Texture,
    material: Material,
    baked_chars: []stbtt.bakedchar,
    height: f32,
}

FONT_RES :: 512
make_font_from_file :: proc(filedata: []byte, font_size: uint, num_chars: uint = 128) -> (font: Font) {
    bitmap := make([]u8, FONT_RES*FONT_RES)
    defer delete(bitmap)
    font.baked_chars = make([]stbtt.bakedchar, num_chars)
    stbtt.BakeFontBitmap(raw_data(filedata), 0, f32(font_size), raw_data(bitmap), FONT_RES, FONT_RES, 0, i32(num_chars), raw_data(font.baked_chars))
    //convert it into an RGBA texture...
    image := make([]u32, FONT_RES*FONT_RES)
    defer delete(image)
    for pixel, i in image {
        if(bitmap[i] > 0) {
            image[i] = (u32(bitmap[i]) << 24) | 0xffffff
        }
    }
    font.texture = make_texture_2D(image, {FONT_RES, FONT_RES})
    font.material = make_material(base_color=font.texture, filtering=false)
    font.height = f32(font_size)
    return
}
delete_font :: proc(font: Font) {
    delete_material(font.material)
    delete_texture(font.texture)
}

//returns char for use in clip_rect
get_char :: proc(font: Font, c: rune) -> (clip_rect: [4]f32) {
    quad: stbtt.aligned_quad
    x, y: f32
    stbtt.GetBakedQuad(raw_data(font.baked_chars), FONT_RES, FONT_RES, i32(c), &x, &y, &quad, true)
    clip_rect = {quad.s0, quad.t0, quad.s1 - quad.s0, quad.t1 - quad.t0}
    clip_rect *= FONT_RES
    return
}

//no accurate way to get width and height, really
//origin is center of the window, positive y is up, that's all I can say...
ui_draw_text :: proc(text: string, font: Font, pos: [2]f32 = 0, color: [4]f32 = 1) {
    x: f32
    y: f32
    //render a quad for every rune in txt...
    for c, i in text {
        quad: stbtt.aligned_quad
        stbtt.GetBakedQuad(raw_data(font.baked_chars), FONT_RES, FONT_RES, i32(c), &x, &y, &quad, true)
        w := quad.x1 - quad.x0
        h := quad.y1 - quad.y0
        sx := screen_uniforms.size.x/2
        sy := screen_uniforms.size.y/2
        fill_rect := [4]f32{
            (pos.x+quad.x0+w/2)/sx, (pos.y-font.height-quad.y0-h/2)/sy,
            w/sx, h/sy,
        }
        clip_rect := [4]f32{
            quad.s0,
            quad.t0,
            quad.s1 - quad.s0,
            quad.t1 - quad.t0,
        }
        draw_ui(fill_rect, color, font.texture, clip_rect)
    }
}

/*lord*/ char_quad: Mesh
draw_text :: proc(text: string, font: Font, model: matrix[4,4]f32 = 1, color: [4]f32 = 1, sprite: bool=true, billboard: bool=false) {

    if char_quad.size == 0 {
        char_quad = make_mesh([]Vertex{
            {position={-0.5, +0.5, 0}, texcoord={0, 0}, color={1, 1, 1, 1}},
            {position={+0.5, +0.5, 0}, texcoord={1, 0}, color={1, 1, 1, 1}},
            {position={+0.5, -0.5, 0}, texcoord={1, 1}, color={1, 1, 1, 1}},
            {position={-0.5, -0.5, 0}, texcoord={0, 1}, color={1, 1, 1, 1}},
        }, []u32{2, 1, 0, 3, 2, 0})
    }

    x: f32
    y: f32
    for c, i in text {
        quad: stbtt.aligned_quad
        stbtt.GetBakedQuad(raw_data(font.baked_chars), FONT_RES, FONT_RES, i32(c), &x, &y, &quad, true)
        w := quad.x1 - quad.x0
        h := quad.y1 - quad.y0
        trans: matrix[4,4]f32 = {
            1, 0, 0, x,
            0, 1, 0, h/2-y,
            0, 0, 1, 0,
            0, 0, 0, 1,
        }
        clip_rect := [4]f32{
            quad.s0*FONT_RES,
            quad.t0*FONT_RES,
            (quad.s1 - quad.s0)*FONT_RES,
            (quad.t1 - quad.t0)*FONT_RES,
        }
        draw_mesh(char_quad, font.material, model * trans, clip_rect, color, sprite, billboard)
    }

}
