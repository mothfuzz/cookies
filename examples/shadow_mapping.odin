package main

import "cookies:engine"
import "cookies:window"
import "cookies:input"
import "cookies:graphics"
import "cookies:transform"
import "core:math/linalg"

cam: graphics.Camera
cam_pos: [3]f32 = {0, 0.5, 1}

quad: graphics.Mesh
quad_tex: graphics.Texture
quad_mat: graphics.Material

teapot: graphics.Scene
teapot_trans: transform.Transform

spot_light: graphics.Spot_Light
spot_light_trans: transform.Transform

init :: proc() {
    window.set_size(800, 800)

    cam = graphics.make_camera()

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
    transform.init(&teapot_trans, position={0, 0.2, 0}, scale=0.01)
    graphics.link_scene_transform(&teapot, &teapot_trans)

    spot_light = graphics.make_spot_light({0, 0, 0}, {0, -1, 0}, 0.1, 0.2, {1, 1, 1, 5})
    transform.init(&spot_light_trans, position={0, 2, 0})
}

tick :: proc() {
    if input.key_pressed(.Key_Escape) {
        window.close()
    }

    if input.key_down(.Key_W) {
        cam_pos.z -= 0.01
    }
    if input.key_down(.Key_S) {
        cam_pos.z += 0.01
    }
    if input.key_down(.Key_A) {
        cam_pos.x -= 0.01
    }
    if input.key_down(.Key_D) {
        cam_pos.x += 0.01
    }
    graphics.look_to(&cam, cam_pos, {0, 0.2, 0})

    @static counter: f32 = 0.0
    counter += 0.01
    light_angle_range: f32 = 10
    sin := linalg.sin(counter)*linalg.to_radians(light_angle_range)
    transform.set_orientation(&spot_light_trans, {sin, 0, sin}, true)
}

draw :: proc(alpha, delta: f64) {
    f := graphics.Frame{}

    graphics.draw_camera(&f, &cam, alpha)
    graphics.draw_mesh(&f, quad, quad_mat)
    graphics.draw_scene(&f, teapot, alpha, delta)
    graphics.draw_spot_light(&f, spot_light, transform.smooth(&spot_light_trans, alpha))
    
    graphics.render_frame(f)
}

quit :: proc() {
    graphics.delete_camera(cam)
    graphics.delete_material(quad_mat)
    graphics.delete_texture(quad_tex)
    graphics.delete_mesh(quad)
    graphics.delete_scene(teapot)
    graphics.delete_spot_light(spot_light)
}

main :: proc() {
    engine.boot(init, tick, draw, quit)
}
