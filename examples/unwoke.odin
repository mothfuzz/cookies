package main

import "../engine"
import "../engine/window"
import "../engine/graphics"

frasier: graphics.Texture

init :: proc() {
    frasier = graphics.make_texture_from_image(#load("../frasier.png"))
    window.set_size(500, 500)
}

draw :: proc(t: f64) {
    graphics.ui_draw_rect({0, 0, 500, 500}, color=1, texture=frasier)
}

kill :: proc() {
    graphics.delete_texture(frasier)
}

main :: proc() {
    engine.boot(init, nil, draw, kill)
}
