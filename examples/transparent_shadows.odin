package main

import "cookies:engine"
import "cookies:window"
import "cookies:input"
import "cookies:graphics"
import "cookies:transform"
import "core:math/linalg"

cam: graphics.Camera
cam_trans: transform.Node

tree: transform.Tree

quad: graphics.Mesh
quad_tex: graphics.Texture
quad_mat: graphics.Material

wall: graphics.Mesh
stained_glass_tex: graphics.Texture
stained_glass_mat: graphics.Material

teapot: graphics.Scene
teapot_trans: transform.Node

spot_light: graphics.Spot_Light
spot_light_trans: transform.Node

init :: proc() {
    window.set_size(800, 800)

    tree = transform.make_tree()

    cam = graphics.make_camera()
    cam_trans = transform.create_node(&tree, {translation={0, 0.5, 1}})

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

    wall = graphics.make_mesh([]graphics.Vertex{
        //front side
        {position={-0.5, +1.0, -0.5}, texcoord={0.0, 0.0}, color={1, 1, 1, 1}},
        {position={+0.5, +1.0, -0.5}, texcoord={1.0, 0.0}, color={1, 1, 1, 1}},
        {position={+0.5, -0.0, -0.5}, texcoord={1.0, 1.0}, color={1, 1, 1, 1}},
        {position={-0.5, -0.0, -0.5}, texcoord={0.0, 1.0}, color={1, 1, 1, 1}},
        //back side
        {position={-0.5, -0.0, -0.5}, texcoord={0.0, 1.0}, color={1, 1, 1, 1}},
        {position={+0.5, -0.0, -0.5}, texcoord={1.0, 1.0}, color={1, 1, 1, 1}},
        {position={+0.5, +1.0, -0.5}, texcoord={1.0, 0.0}, color={1, 1, 1, 1}},
        {position={-0.5, +1.0, -0.5}, texcoord={0.0, 0.0}, color={1, 1, 1, 1}},
    }, {2, 1, 0, 3, 2, 0,
        6, 5, 4, 7, 6, 4})

    stained_glass_tex = graphics.make_texture_from_image(#load("../resources/darksanctuary.png"))
    stained_glass_mat = graphics.make_material(base_color=stained_glass_tex)

    teapot = graphics.make_scene_from_file("teapot.gltf", #load("../resources/teapot.gltf"), &tree)
    teapot_trans = transform.create_node(&tree, {translation={0, 0.2, 0}, scale=0.01})
    graphics.link_scene_transform(&teapot, teapot_trans)

    spot_light = graphics.make_spot_light({0, 0, 0}, {0, -0.6, 0.4}, 0.1, 0.2, {1, 1, 1, 5})
    spot_light_trans = transform.create_node(&tree, {translation={0, 2, -1.5}})
}

tick :: proc() {
    if input.key_pressed(.Key_Escape) {
        window.close()
    }

    cam_trans := transform.write(&tree, cam_trans)
    if input.key_down(.Key_W) {
        cam_trans.translation.z -= 0.01
    }
    if input.key_down(.Key_S) {
        cam_trans.translation.z += 0.01
    }
    if input.key_down(.Key_A) {
        cam_trans.translation.x -= 0.01
    }
    if input.key_down(.Key_D) {
        cam_trans.translation.x += 0.01
    }
    //graphics.look_at(&cam, cam_pos, {0, 0.2, 0})
    transform.look_at(cam_trans, {0, 0.2, 0})

    @static counter: f32 = 0.0
    counter += 0.01
    light_angle_range: f32 = 10
    sin := linalg.sin(counter)*linalg.to_radians(light_angle_range)
    trans := transform.write(&tree, spot_light_trans)
    trans.rotation = transform.rotation_from_angles({0, 0, sin})

}

draw :: proc(alpha, delta: f64) {
    graphics.draw_camera(cam, transform.get_world_smooth(&tree, cam_trans, alpha))
    graphics.draw_mesh(quad, quad_mat, base_color_tint={1, 1, 1, 1})
    graphics.draw_mesh(wall, stained_glass_mat, base_color_tint={1, 1, 1, 1})
    graphics.draw_scene(teapot, alpha)
    graphics.draw_spot_light(spot_light, transform.get_world_smooth(&tree, spot_light_trans, alpha))
}

quit :: proc() {
    graphics.delete_camera(cam)
    graphics.delete_material(quad_mat)
    graphics.delete_texture(quad_tex)
    graphics.delete_mesh(quad)
    graphics.delete_material(stained_glass_mat)
    graphics.delete_texture(stained_glass_tex)
    graphics.delete_mesh(wall)
    graphics.delete_scene(teapot)
    graphics.delete_spot_light(spot_light)
}

main :: proc() {
    engine.boot(init, tick, draw, quit)
}
