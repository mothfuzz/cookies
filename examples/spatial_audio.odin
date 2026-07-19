package main

import "cookies:engine"
import "cookies:window"
import "cookies:input"
import "cookies:graphics"
import "cookies:transform"
import "core:math/linalg"
import "cookies:audio"
import "cookies:resources"

tree: transform.Tree

cam: graphics.Camera
cam_trans: transform.Node
cam_angle := f32(0)

quad: graphics.Mesh
quad_tex: graphics.Texture
quad_mat: graphics.Material

spot_light: graphics.Spot_Light

maxwell: graphics.Scene
maxwell_trans: transform.Node

the_power_snd: audio.Sound
the_power: audio.Playing_Sound

init :: proc() {
    window.set_size(800, 800)

    tree = transform.make_tree()

    cam = graphics.make_camera()
    cam_trans = transform.create_node(&tree, {translation={0, 0.25, 1}})

    quad = graphics.make_mesh([]graphics.Vertex{
        {position={-0.5, 0.0, -0.5}, texcoord={0.0, 0.0}, color={1, 1, 1, 1}},
        {position={+0.5, 0.0, -0.5}, texcoord={1.0, 0.0}, color={1, 1, 1, 1}},
        {position={+0.5, 0.0, +0.5}, texcoord={1.0, 1.0}, color={1, 1, 1, 1}},
        {position={-0.5, 0.0, +0.5}, texcoord={0.0, 1.0}, color={1, 1, 1, 1}},
    }, {2, 1, 0, 3, 2, 0})
    img := []u32{
        0xffffffff, 0xff000000, 0xffffffff, 0xff000000,
        0xff000000, 0xffffffff, 0xff000000, 0xffffffff,
        0xffffffff, 0xff000000, 0xffffffff, 0xff000000,
        0xff000000, 0xffffffff, 0xff000000, 0xffffffff,
    }
    quad_tex = graphics.make_texture_2D(img, {4, 4})
    quad_mat = graphics.make_material(quad_tex, filtering=false)

    spot_light = graphics.make_spot_light({0, 2, 0}, {0, -1, 0}, 0.1, 0.2, {1, 1, 1, 5})

    resources.preload("textures/dingus_baseColor.jpeg", #load("../resources/maxwell/textures/dingus_baseColor.jpeg"))
    resources.preload("textures/whiskers_baseColor.png", #load("../resources/maxwell/textures/whiskers_baseColor.png"))
    resources.preload("scene.bin", #load("../resources/maxwell/scene.bin"))
    maxwell = graphics.make_scene_from_file("scene.gltf", #load("../resources/maxwell/scene.gltf"), &tree)
    maxwell_trans = transform.create_node(&tree, {scale=0.01})
    graphics.link_scene_transform(&maxwell, maxwell_trans)

    the_power_snd = audio.make_sound_from_file(#load("../resources/the_power.mp3"))
    the_power = audio.play_sound(the_power_snd, true)
}

tick :: proc() {
    if input.key_pressed(.Key_Escape) {
        window.close()
    }

    cam_trans := transform.write(&tree, cam_trans)
    cam_pos := &cam_trans.translation

    s := linalg.sin(cam_angle)
    c := linalg.cos(cam_angle)

    if input.key_down(.Key_W) {
        cam_pos.z -= 0.01 * c
        cam_pos.x += 0.01 * s
    }
    if input.key_down(.Key_S) {
        cam_pos.z += 0.01 * c
        cam_pos.x -= 0.01 * s
    }
    if input.key_down(.Key_A) {
        cam_pos.z -= 0.01 * s
        cam_pos.x -= 0.01 * c
    }
    if input.key_down(.Key_D) {
        cam_pos.z += 0.01 * s
        cam_pos.x += 0.01 * c
    }
    if input.key_down(.Key_Left) {
        cam_angle -= 0.01
    }
    if input.key_down(.Key_Right) {
        cam_angle += 0.01
    }
    //graphics.look_at(&cam, cam_pos^, cam_pos^ + {s, 0, -c})
    transform.look_at(cam_trans, cam_pos^ + {s, 0, -c})

    audio.set_listener_position(cam_pos^)
    audio.set_listener_orientation({s, 0, -c})

    @static counter: f32 = 0
    counter += 0.01
    maxwell_trans := transform.write(&tree, maxwell_trans)
    maxwell_trans.translation = {0, 0.1 + 0.05 * linalg.sin(counter), 0}
    transform.rotatey(maxwell_trans, 0.02)
    audio.set_sound_position(&the_power, maxwell_trans.translation)
}

draw :: proc(alpha, delta: f64) {

    graphics.draw_camera(cam, transform.get_world_smooth(&tree, cam_trans, alpha))
    graphics.draw_mesh(quad, quad_mat)

    graphics.draw_spot_light(spot_light)

    graphics.draw_scene(maxwell, alpha)
}

quit :: proc() {
    graphics.delete_camera(cam)
    graphics.delete_material(quad_mat)
    graphics.delete_texture(quad_tex)
    graphics.delete_mesh(quad)
    graphics.delete_spot_light(spot_light)
    graphics.delete_scene(maxwell)

    audio.delete_sound(the_power_snd)

    transform.delete_tree(&tree)
}

main :: proc() {
    engine.boot(init, tick, draw, quit)
}
