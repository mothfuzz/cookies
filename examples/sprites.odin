package main

import "core:fmt"
import "cookies:engine"
import "cookies:window"
import "cookies:input"
import "cookies:graphics"
import "cookies:transform"

frasier_tex: graphics.Texture
frasier_mat: graphics.Material
frasier_trans := transform.ORIGIN
camera: graphics.Camera
camera_position: [2]f32 = {0, 0}

frasier_velocity: f32

init :: proc() {
    window.set_size(500, 500)
    graphics.set_background_color({0.5, 0.2, 0.8})
    frasier_tex = graphics.make_texture_from_image(#load("../resources/frasier.png"))
    frasier_mat = graphics.make_material(base_color=frasier_tex)
    camera = graphics.make_camera()
    graphics.look_at(&camera, {0, 0, graphics.z_2d(camera)}, {0, 0, 0})
}

move_camera :: proc() {
    graphics.look_to(&camera,
                     eye={camera_position.x, camera_position.y, graphics.z_2d(camera)},
                     center={camera_position.x, camera_position.y, 0})
} 

tick :: proc() {
    if input.key_pressed(.Key_Escape) {
        window.close()
    }
    if input.key_down(.Key_Left) {
        frasier_velocity += 0.02
    }
    if input.key_down(.Key_Right) {
        frasier_velocity -= 0.02
    }

    frasier_velocity *= 0.95
    if abs(frasier_velocity) < 0.01 {
        frasier_velocity = 0
    }

    transform.rotate(&frasier_trans, {0, 0, frasier_velocity})

    if input.key_down(.Key_Up) {
        frasier_velocity = 0
        transform.set_orientation(&frasier_trans, 0)
    }

    if input.key_down(.Key_W) {
        camera_position.y += 4
    }
    if input.key_down(.Key_S) {
        camera_position.y -= 4
    }
    if input.key_down(.Key_D) {
        camera_position.x += 4
    }
    if input.key_down(.Key_A) {
        camera_position.x -= 4
    }
    move_camera()
}

draw :: proc(alpha, delta: f64) {
    f := graphics.Frame{}
    graphics.draw_camera(&f, &camera, alpha)
    graphics.draw_sprite(&f, frasier_mat, transform.smooth(&frasier_trans, alpha)) //draw a single frasier in the center of the screen
    graphics.render_frame(f)
}

quit :: proc() {
    graphics.delete_material(frasier_mat)
    graphics.delete_texture(frasier_tex)
    graphics.delete_camera(camera)
}

main :: proc() {
    engine.set_tick_rate(60)
    engine.boot(init, tick, draw, quit)
}
