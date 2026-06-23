package main

import "cookies:engine"
import "cookies:graphics"
import "cookies:resources"

Bulbasaur :: struct {
    bulba_mesh: graphics.Mesh,
    bulba_mat: graphics.Material,
}

New_Bulbasaur :: Bulbasaur{
    bulba_mesh = {path = "../resources/bulbasaur.obj"},
    bulba_mat = {
        base_color = "../resources/bulbasaur.png"
    },
}

bulba := New_Bulbasaur

cam: graphics.Camera

init :: proc() {
    resources.load_all(&bulba)

    cam = graphics.make_camera()
    graphics.look_at(&cam, {0, 50, 100}, {0, 10, 0})

    graphics.set_background_color({1, 0, 1})
}

draw :: proc(alpha, delta: f64) {
    graphics.draw_camera(&cam)
    graphics.draw_mesh(bulba.bulba_mesh, bulba.bulba_mat)
}

quit :: proc() {
    resources.unload_all(&bulba)
    graphics.delete_camera(cam)
}

main :: proc() {
    engine.boot(init, nil, draw, quit)
}
