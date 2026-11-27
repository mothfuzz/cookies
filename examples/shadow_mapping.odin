package main

import "cookies:engine"
import "cookies:window"
import "cookies:input"
import "cookies:graphics"
import "cookies:transform"
import "core:math/linalg"

cam: graphics.Camera
cam_trans: transform.Transform

quad: graphics.Mesh
quad_tex: graphics.Texture
quad_mat: graphics.Material

teapot: graphics.Scene

teapot2: graphics.Scene

teapot3: graphics.Scene

spot_light: graphics.Spot_Light
spot_light_trans: transform.Transform

point_light: graphics.Point_Light

directional_light: graphics.Directional_Light

init :: proc() {
    window.set_size(800, 800)

    cam = graphics.make_camera()
    cam_trans = transform.make({translation={0, 0.5, 1}})

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

    teapot = graphics.make_scene_from_file("teapot.gltf", #load("../resources/teapot.gltf"))
    //teapot.models[0].materials[0].base_color_tint = {1, 0, 0, 0.5}
    transform.set_translation(teapot.root, {0, 0.2, 0})
    transform.set_scale(teapot.root, 0.01)

    teapot2 = graphics.copy_scene(&teapot)
    //teapot2.models[0].materials[0].base_color_tint = {0, 1, 0, 0.5}
    transform.set_translation(teapot2.root, {0.1, 0.4, 0})
    transform.set_scale(teapot2.root, 0.01)

    teapot3 = graphics.copy_scene(&teapot)
    //teapot3.models[0].materials[0].base_color_tint = {0, 0, 1, 0.5}
    transform.set_translation(teapot3.root, {-0.1, 0.4, 0})
    transform.set_scale(teapot3.root, 0.01)

    spot_light = graphics.make_spot_light({0, 0, 0}, {0, -1, 0}, 0.1, 0.2, {0, 1, 0, 5})
    spot_light_trans = transform.make({translation={0, 2, 0}})

    point_light = graphics.make_point_light({0.4, 2, -0.2}, {1, 0, 0, 10})

    directional_light = graphics.make_directional_light({0, -1, 0}, {0, 0, 1, 3})
}

tick :: proc() {
    if input.key_pressed(.Key_Escape) {
        window.close()
    }

    if input.key_down(.Key_W) {
        transform.translate(&cam_trans, {0, 0, -0.01})
    }
    if input.key_down(.Key_S) {
        transform.translate(&cam_trans, {0, 0, +0.01})
    }
    if input.key_down(.Key_A) {
        transform.translate(&cam_trans, {-0.01, 0, 0})
    }
    if input.key_down(.Key_D) {
        transform.translate(&cam_trans, {+0.01, 0, 0})
    }
    //graphics.look_at(&cam, cam_pos, {0, 0.2, 0})
    transform.look_at(&cam_trans, {0, 0.2, 0})

    @static counter: f32 = 0.0
    counter += 0.01
    light_angle_range: f32 = 10
    sin := linalg.sin(counter)*linalg.to_radians(light_angle_range)
    transform.local(&spot_light_trans).rotation = transform.rotation_from_angles({sin, 0, sin})
}

draw :: proc(alpha, delta: f64) {
    graphics.draw_camera(cam, cam_trans)
    graphics.draw_mesh(quad, quad_mat)
    graphics.draw_scene(teapot)
    graphics.draw_scene(teapot2)
    graphics.draw_scene(teapot3)
    graphics.draw_point_light(point_light)
    graphics.draw_directional_light(directional_light)
    graphics.draw_spot_light(spot_light, spot_light_trans)
}

quit :: proc() {
    graphics.delete_material(quad_mat)
    graphics.delete_texture(quad_tex)
    graphics.delete_mesh(quad)
    graphics.delete_scene(teapot)
    graphics.delete_scene(teapot2)
    graphics.delete_scene(teapot3)
}

main :: proc() {
    engine.boot(init, tick, draw, quit)
}
