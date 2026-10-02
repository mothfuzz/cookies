package main

import "cookies:engine"
import "cookies:transform"
import spatial "cookies:spatial2"
import "cookies:graphics"
import "cookies:window"
import "cookies:input"

import "core:math"
import "core:math/rand"
import "core:container/handle_map"

Screen_Width :: 400
Screen_Height :: 400

Handle :: handle_map.Handle16

TheGuy :: struct {
    handle: Handle,
    trans: transform.Transform,
    colliding: bool,
}

guy_tex: graphics.Texture
guy_mat: graphics.Material
cam: graphics.Camera

make_guy :: proc() -> (guy: TheGuy) {
    //clustered around the middle of the screen
    rand_x := (rand.float32() - 0.5) * Screen_Width / 2
    rand_y := (rand.float32() - 0.5) * Screen_Height / 2
    guy.trans = transform.make({translation={rand_x, rand_y, 0}})
    return
}

guys: handle_map.Dynamic_Handle_Map(TheGuy, Handle)
guy_grid: spatial.Spatial(Handle, spatial.Grid(16))

init :: proc() {

    window.set_size(Screen_Width, Screen_Height)
    engine.set_tick_rate(30)

    cam = graphics.make_camera({0, 0, Screen_Width, Screen_Height})
    graphics.look_at(&cam, {0, 0, graphics.z_2d(cam)}, {0, 0, 0})
    graphics.set_background_color(&cam, {0, 0, 1})

    guy_tex = graphics.make_texture_from_image(#load("frasier-32.png"))
    guy_mat = graphics.make_material(base_color = guy_tex)

    handle_map.dynamic_init(&guys, context.allocator)
    
    for i in 0..<10 {
        g := handle_map.add(&guys, make_guy())
        spatial.insert(&guy_grid, g, spatial.Box{0, 16})
    }
}

cleanup :: proc() {
    it := handle_map.iterator_make(&guys)
    for guy, handle in handle_map.iterate(&it) {
        spatial.remove(&guy_grid, handle)
    }
    handle_map.dynamic_destroy(&guys)
    
    graphics.delete_material(guy_mat)
    graphics.delete_texture(guy_tex)
}

update_guys :: proc() {
    it := handle_map.iterator_make(&guys)
    for guy, handle in handle_map.iterate(&it) {
        transform.rotatez(&guy.trans, 0.005 * math.TAU)
        spatial.update(&guy_grid, handle, transform.world(guy.trans))
        guy.colliding = false
    }

    for pair in spatial.pairs(&guy_grid) {
        guy_a := handle_map.get(&guys, pair[0])
        guy_b := handle_map.get(&guys, pair[1])

        guy_a.colliding = true
        guy_b.colliding = true
    }

    if input.key_pressed(.Key_Escape) {
        window.close()
    }
}

draw_guys :: proc(alpha, delta: f64) {
    graphics.draw_camera(cam)
    it := handle_map.iterator_make(&guys)
    for guy, handle in handle_map.iterate(&it) {
        //trans := transform.world(guy.trans, alpha)
        graphics.draw_sprite(guy_mat, guy.trans)
        extents := spatial.world_extents(&guy_grid, handle)
        center := (extents[0].xy + extents[1].xy)/2
        size := extents[1] - extents[0]
        graphics.ui_draw_rect({center.x, center.y, size.x, size.y}, guy.colliding?{0,1,0,0.25}:{1,0,0,0.25})
    }
}

main :: proc() {
    engine.boot(init, update_guys, draw_guys, cleanup)
}
