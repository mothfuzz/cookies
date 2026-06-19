package main

import "cookies:engine"
import "cookies:window"
import "cookies:graphics"
import "cookies:resources"


Frasier :: struct {
    frasier: graphics.Texture,
    frasier2: graphics.Texture,
    frasier3: graphics.Texture,
}

f := Frasier {
    frasier = {path="frasier.png"},
    frasier2 = {path="frasier.png"},
    frasier3 = {path="frasier.png"},
}

init :: proc() {
    resources.load_all(&f)
    //frasier = graphics.make_texture_from_image(#load("../resources/frasier.png"))
    window.set_size(500, 500)
}

draw :: proc(t: f64, dt: f64) {
    graphics.ui_draw_rect({0, 0, 500, 500}, color=1, texture=f.frasier)
}

kill :: proc() {
    resources.unload_all(&f)
    //graphics.delete_texture(frasier)
}

main :: proc() {
    resources.preload("frasier.png", #load("../resources/frasier.png"))
    engine.boot(init, nil, draw, kill)
}
