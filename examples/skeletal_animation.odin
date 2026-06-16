package main

import "cookies:engine"
import "cookies:window"
import "cookies:input"
import "cookies:graphics"
import "cookies:transform"
import "cookies:resources"
import "core:fmt"

tree: transform.Tree

cam: graphics.Camera

light: graphics.Directional_Light

brainstem: graphics.Scene
brainstem_trans: transform.Node
brainstem_anim: graphics.Animation_State

brainstem2: graphics.Scene
brainstem2_trans: transform.Node
brainstem2_anim: graphics.Animation_State

init :: proc() {
    window.set_size(800, 800)

    graphics.set_background_color({1, 0, 1})
    graphics.set_render_distance(0)
    graphics.set_fog_distance(0)

    tree = transform.make_tree()

    cam = graphics.make_camera()
    graphics.look_at(&cam, {0, 0, 10}, {0, 0, 0})

    light = graphics.make_directional_light({0.6, 0.4, 0}, {1, 0, 0, 10})
    
    brainstem = graphics.make_scene_from_file("BrainStem.gltf", #load("../resources/BrainStem.gltf"), &tree)
    brainstem_trans = transform.create_node(&tree, {translation={0, -1, 5}})
    graphics.link_scene_transform(&brainstem, brainstem_trans)
    brainstem_anim = graphics.animate(&brainstem)
    graphics.play(&brainstem_anim, 0, true, 0.5)
    fmt.printfln("%#v", brainstem.nodes[0])

    brainstem2 = graphics.copy_scene(&brainstem)
    brainstem2_trans = transform.create_node(&tree, {translation={2, -1, 2}, scale=0.5})
    graphics.link_scene_transform(&brainstem2, brainstem2_trans)
    brainstem2_anim = graphics.animate(&brainstem2)
    graphics.play(&brainstem2_anim, 0, true)
    fmt.printfln("%#v", brainstem2.nodes[0])
}

up_or_down: bool
tick :: proc() {
    if input.key_pressed(.Key_Escape) {
        window.close()
    }
    brainstem_trans := transform.write(&tree, brainstem_trans)
    //transform.rotatex(brainstem_trans, math.to_radians(f32(-5)))
    if input.key_down(.Key_Up) {
        brainstem_trans.translation -= {0, 0, 0.25}
    }
    if input.key_down(.Key_Down) {
        brainstem_trans.translation += {0, 0, 0.25}
    }
    if input.key_down(.Key_Left) {
        brainstem_trans.translation -= {0.25, 0, 0}
    }
    if input.key_down(.Key_Right) {
        brainstem_trans.translation += {0.25, 0, 0}
    }
    if up_or_down {
        //brainstem_trans.scale *= 0.99
        if brainstem_trans.scale.x < 0.5 {
            up_or_down = false
        }
    } else {
        //brainstem_trans.scale *= 1.11
        if brainstem_trans.scale.x > 1.5 {
            up_or_down = true
        }
    }
}

draw :: proc(a: f64, dt: f64) {
    graphics.draw_camera(&cam)
    graphics.draw_scene(brainstem, a, dt, &brainstem_anim)
    graphics.draw_scene(brainstem2, a, dt, &brainstem2_anim)
    graphics.draw_light(light)
}

quit :: proc() {
    graphics.delete_camera(cam)
    graphics.deanimate(brainstem_anim)
    graphics.delete_scene(brainstem)
    graphics.deanimate(brainstem2_anim)
    graphics.delete_scene(brainstem2)
    resources.unload_files()
    transform.delete_tree(&tree)
}

main :: proc() {
    engine.set_tick_rate(125)
    engine.boot(init, tick, draw, quit)
}
