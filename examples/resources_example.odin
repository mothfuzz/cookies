package main

import "cookies:engine"
import "cookies:graphics"
import "cookies:resources"

Frasier :: struct {
    frasier_mat: graphics.Material,
}

New_Frasier :: Frasier{
    frasier_mat = {
        base_color = "../resources/frasier.png"
    },
}

frasier := New_Frasier

cam: graphics.Camera

init :: proc() {
    resources.load_all(&frasier)

    cam = graphics.make_camera()
    graphics.look_at(&cam, {0, 0, graphics.z_2d(cam)}, {0, 0, 0})

    graphics.set_background_color({1, 0, 1})
}

draw :: proc(alpha, delta: f64) {
    graphics.draw_camera(&cam)
    graphics.draw_sprite(frasier.frasier_mat)
}

quit :: proc() {
    resources.unload_all(&frasier)
    graphics.delete_camera(cam)
}

main :: proc() {
    //resources.preload("frasier.png", #load("../resources/frasier.png"))
    engine.boot(init, nil, draw, quit)
}
