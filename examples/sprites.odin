package main

import "core:fmt"
import "cookies:engine"
import "cookies:window"
import "cookies:input"
import "cookies:graphics"
import "cookies:transform"

Sprites_Example :: struct {
    frasier_tex: graphics.Texture,
    frasier_mat: graphics.Material,
    camera: graphics.Camera,
    frasier_trans: transform.Transform,
    camera_trans: transform.Transform,
    frasier_velocity: f32,
}


init :: proc(s: ^Sprites_Example) {
    window.set_size(500, 500)

    s.frasier_tex = graphics.make_texture_from_image(#load("../resources/frasier.png"))
    s.frasier_mat = graphics.make_material(base_color=s.frasier_tex)
    s.camera = graphics.make_camera()
    graphics.set_background_color(&s.camera, {0.5, 0.2, 0.8})

    s.frasier_trans = transform.make()
    s.camera_trans = transform.make()

    //2D camera looking straight down
    camera_trans := transform.write(s.camera_trans)
    camera_trans.translation = {0, 0, graphics.z_2d(s.camera)}
    transform.look_at(camera_trans, {0, 0, 0})
}

tick :: proc(s: ^Sprites_Example) {
    if input.key_pressed(.Key_Escape) {
        window.close()
    }
    if input.key_down(.Key_Left) {
        s.frasier_velocity += 0.02
    }
    if input.key_down(.Key_Right) {
        s.frasier_velocity -= 0.02
    }

    s.frasier_velocity *= 0.95
    if abs(s.frasier_velocity) < 0.01 {
        s.frasier_velocity = 0
    }

    frasier_trans := transform.write(s.frasier_trans)
    transform.rotate(frasier_trans, {0, 0, s.frasier_velocity})

    if input.key_down(.Key_Up) {
        s.frasier_velocity = 0
        frasier_trans.rotation = 1
    }

    camera_pos := &transform.write(s.camera_trans).translation
    if input.key_down(.Key_W) {
        camera_pos.y += 4
    }
    if input.key_down(.Key_S) {
        camera_pos.y -= 4
    }
    if input.key_down(.Key_D) {
        camera_pos.x += 4
    }
    if input.key_down(.Key_A) {
        camera_pos.x -= 4
    }
}

draw :: proc(s: ^Sprites_Example, alpha, delta: f64) {
    graphics.draw_camera(s.camera, transform.world(s.camera_trans, alpha))
    graphics.draw_sprite(s.frasier_mat, transform.world(s.frasier_trans, alpha)) //draw a single frasier in the center of the screen
}

quit :: proc(s: ^Sprites_Example) {
    graphics.delete_material(s.frasier_mat)
    graphics.delete_texture(s.frasier_tex)
}

main :: proc() {
    engine.set_tick_rate(60)
    engine.boot_with(Sprites_Example, init, tick, draw, quit)
}
