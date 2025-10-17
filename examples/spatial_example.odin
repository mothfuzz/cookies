package main

import "../engine"
import "../engine/arena"
import "../engine/transform"
import "../engine/spatial"

import "../engine/graphics"
import "../engine/window"
import "../engine/input"

import "core:math"
import "core:math/rand"

import "core:fmt"

Screen_Width :: 400
Screen_Height :: 400

TheGuy :: struct {
    trans: transform.Transform,
    hitbox: spatial.Bounding_Box,
    colliding: bool,
}

guy_tex: graphics.Texture
guy_mat: graphics.Material
cam: graphics.Camera

make_guy :: proc() -> (guy: TheGuy) {
    guy.trans = transform.ORIGIN
    //clustered around the middle of the screen
    guy.trans.position.x = (rand.float32() - 0.5) * Screen_Width / 2
    guy.trans.position.y = (rand.float32() - 0.5) * Screen_Height / 2
    transform.reset(&guy.trans)
    guy.hitbox = {{-16, -16, -16}, {16, 16, 16}}
    return
}

guys: arena.Arena(TheGuy)
guy_grid := spatial.init(spatial.Grid(arena.Handle, 16))

init :: proc() {

    window.set_size(Screen_Width, Screen_Height)
    engine.set_tick_rate(30)

    cam = graphics.make_camera({0, 0, Screen_Width, Screen_Height})
    graphics.look_at(&cam, {0, 0, graphics.z_2d(&cam)}, {0, 0, 0})
    graphics.set_camera(&cam)

    guy_tex = graphics.make_texture_from_image(#load("frasier-32.png"))
    guy_mat = graphics.make_material(albedo = guy_tex)

    guys = arena.make(arena.Arena(TheGuy))

    for i in 0..<10 {
        g := arena.insert(&guys, make_guy())
        guy := arena.get(&guys, g)
        spatial.insert(&guy_grid, g, guy.hitbox)
    }
}

cleanup :: proc() {
    arena.delete(&guys)
    spatial.clear(&guy_grid)

    graphics.delete_material(guy_mat)
    graphics.delete_texture(guy_tex)
    graphics.delete_camera(cam)
}

update_guys :: proc() {
    it: arena.Iterator
    for handle, guy in arena.iter(&guys, &it) {
        transform.rotatez(&guy.trans, 0.005 * math.TAU)
        spatial.update(&guy_grid, handle, transform.compute(&guy.trans))
        guy.colliding = false
    }

    calculate_collisions()

    if input.key_pressed(.Key_Escape) {
        window.close()
    }
}

calculate_collisions :: proc() {
    it: arena.Iterator
    for handle_a in arena.iter(&guys, &it) {
        for handle_b in spatial.overlapping(&guy_grid, handle_a) {
            guy_a := arena.get(&guys, handle_a)
            guy_b := arena.get(&guys, handle_b)

            guy_a.colliding = true
            guy_b.colliding = true
        }
    }
}

draw_guys :: proc(t: f64) {
    it: arena.Iterator
    for handle, guy in arena.iter(&guys, &it) {
        trans := transform.smooth(&guy.trans, t)
        hitbox := spatial.transform(guy.hitbox, trans)
        position := (hitbox.min + hitbox.max)/2
        scale := hitbox.max - hitbox.min
        graphics.draw_sprite(guy_mat, trans)
        graphics.ui_draw_rect({position.x, position.y, scale.x, scale.y}, guy.colliding?{0,1,0,0.5}:{1,0,0,0.5})
    }
}

main :: proc() {
    engine.boot(init, update_guys, draw_guys, cleanup)
}
