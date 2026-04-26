package main

import "cookies:engine"
import "cookies:window"
import "cookies:input"
import "cookies:graphics"
import "cookies:transform"
import "core:fmt"
import "core:math"

cam: graphics.Camera

light: graphics.Directional_Light

brainstem: graphics.Scene
brainstem_trans := transform.ORIGIN
brainstem_anim: graphics.Animation_State

brainstem2: graphics.Scene
brainstem2_trans := transform.ORIGIN
brainstem2_anim: graphics.Animation_State

init :: proc() {
    window.set_size(800, 800)

    graphics.set_background_color({1, 0, 1})
    graphics.set_render_distance(0)
    graphics.set_fog_distance(0)

    cam = graphics.make_camera()
    graphics.look_at(&cam, {0, 0, 10}, {0, 0, 0})

    light = graphics.make_directional_light({0.6, 0.4, 0}, {1, 0, 0, 10})
    
    brainstem = graphics.make_scene_from_file("BrainStem.gltf", #load("../resources/BrainStem.gltf"))
    graphics.link_scene_transform(&brainstem, &brainstem_trans)
    transform.set_position(&brainstem_trans, {0, -1, 5})
    brainstem_anim = graphics.animate(&brainstem)
    graphics.play(&brainstem_anim, 0, true, 0.5)
    fmt.printfln("%#v", brainstem.nodes[0])

    brainstem2 = graphics.copy_scene(&brainstem)
    graphics.link_scene_transform(&brainstem2, &brainstem2_trans)
    transform.set_position(&brainstem2_trans, {2, -1, 2})
    transform.set_scale(&brainstem2_trans, 0.5)
    brainstem2_anim = graphics.animate(&brainstem2)
    graphics.play(&brainstem2_anim, 0, true)
    fmt.printfln("%#v", brainstem2.nodes[0])
}

up_or_down: bool
tick :: proc() {
    if input.key_pressed(.Key_Escape) {
        window.close()
    }
    //transform.rotatex(&brainstem_trans, math.to_radians(f32(-5)))
    if input.key_down(.Key_Up) {
        transform.translate(&brainstem_trans, {0, 0, -0.25})
    }
    if input.key_down(.Key_Down) {
        transform.translate(&brainstem_trans, {0, 0, 0.25})
    }
    if input.key_down(.Key_Left) {
        transform.translate(&brainstem_trans, {-0.25, 0, 0.0})
    }
    if input.key_down(.Key_Right) {
        transform.translate(&brainstem_trans, {0.25, 0, 0.0})
    }
    if up_or_down {
        //transform.scale(&brainstem_trans, 0.99)
        if transform.get_scale(&brainstem_trans).x < 0.5 {
            up_or_down = false
        }
    } else {
        //transform.scale(&brainstem_trans, 1.11)
        if transform.get_scale(&brainstem_trans).x > 1.5 {
            up_or_down = true
        }
    }
}

draw :: proc(a: f64, dt: f64) {
    f := graphics.Frame{}
    graphics.draw_camera(&f, &cam, a)
    graphics.draw_scene(&f, brainstem, a, dt, &brainstem_anim)
    graphics.draw_scene(&f, brainstem2, a, dt, &brainstem2_anim)
    graphics.draw_light(&f, light)
    graphics.render_frame(f)
}

quit :: proc() {
    graphics.delete_camera(cam)
    graphics.deanimate(brainstem_anim)
    graphics.delete_scene(brainstem)
    graphics.deanimate(brainstem2_anim)
    graphics.delete_scene(brainstem2)
    graphics.unload_files()
}

main :: proc() {
    engine.set_tick_rate(125)
    engine.boot(init, tick, draw, quit)
}
