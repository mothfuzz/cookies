package graphics
import "core:fmt"
import stbtt "vendor:stb/truetype"

/*TODO:
we're gonna do this how stb_truetype wants us to do it.
Pack an atlas.
Use instancing - the geometry is just a single quad.
Transform vertices according to current_point & the current char's recorded width/height.
Upload the whole texture as an atlas, use the sub-coordinates as instanced data.
*/

Font :: struct {
    texture: Texture,
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
    font.height = f32(font_size)
    return
}
delete_font :: proc(font: Font) {
    delete_texture(font.texture)
}

ui_draw_text :: proc(txt: string, font: Font, pos: [2]f32 = 0, color: [4]f32 = 1) {
    x: f32
    y: f32
    //render a quad for every rune in txt...
    for c, i in txt {
        quad: stbtt.aligned_quad
        stbtt.GetBakedQuad(raw_data(font.baked_chars), FONT_RES, FONT_RES, i32(c), &x, &y, &quad, true)
        w := quad.x1 - quad.x0
        h := quad.y1 - quad.y0
        sx := f32(screen_size.x)/2
        sy := f32(screen_size.y)/2
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
