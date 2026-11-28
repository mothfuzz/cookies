package main

import "cookies:engine"
import "cookies:window"
import "cookies:input"
import "cookies:graphics"
import "cookies:transform"
import "core:math/linalg"
import "core:fmt"

cam: graphics.Camera
cam_trans: transform.Transform

quad: graphics.Mesh
quad_tex: graphics.Texture
quad_mat: graphics.Material

wall: graphics.Mesh
stained_glass_tex: graphics.Texture
stained_glass_mat: graphics.Material

teapot: graphics.Scene
teapot_trans: transform.Transform

light: graphics.Directional_Light
light_trans: transform.Transform

ref: graphics.Reflection_Probe

skybox: graphics.Texture

/* TODO
switch background types when the user presses a key:
P = use the probe
E = use the environment
C = use the background color

in the color case, have a sky-blue 1x1 background image for the sky 
and set background.color to actual radiance (much lower).
 */

init :: proc() {
    window.set_size(800, 800)

    skybox = graphics.make_cubemap_from_images(
        #load("../resources/skybox/px.jpg"),
        #load("../resources/skybox/nx.jpg"),
        #load("../resources/skybox/py.jpg"),
        #load("../resources/skybox/ny.jpg"),
        #load("../resources/skybox/pz.jpg"),
        #load("../resources/skybox/nz.jpg"),
    )

    cam = graphics.make_camera()
    cam.background.environment = skybox
    //cam.background.color = {0.6, 0.8, 1.0} //actual sky color
    //cam.background.color = {0.0, 0.1, 0.2} //actual sky radiance
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
    quad_tex = graphics.make_texture(img, {4, 4})
    quad_mat = graphics.make_material(quad_tex, filtering=false)

    wall = graphics.make_mesh([]graphics.Vertex{
        //front side
        {position={-0.5, +1.0, -0.5}, texcoord={0.0, 0.0}, color={1, 1, 1, 1}},
        {position={+0.5, +1.0, -0.5}, texcoord={1.0, 0.0}, color={1, 1, 1, 1}},
        {position={+0.5, -0.0, -0.5}, texcoord={1.0, 1.0}, color={1, 1, 1, 1}},
        {position={-0.5, -0.0, -0.5}, texcoord={0.0, 1.0}, color={1, 1, 1, 1}},
        //back side
        //{position={-0.5, -0.0, -0.5}, texcoord={0.0, 1.0}, color={1, 1, 1, 1}},
        //{position={+0.5, -0.0, -0.5}, texcoord={1.0, 1.0}, color={1, 1, 1, 1}},
        //{position={+0.5, +1.0, -0.5}, texcoord={1.0, 0.0}, color={1, 1, 1, 1}},
        //{position={-0.5, +1.0, -0.5}, texcoord={0.0, 0.0}, color={1, 1, 1, 1}},
    }, {2, 1, 0, 3, 2, 0})
        //6, 5, 4, 7, 6, 4})

    stained_glass_tex = graphics.make_texture_from_image(#load("../resources/darksanctuary.png"))
    stained_glass_mat = graphics.make_material(base_color=stained_glass_tex)

    teapot = graphics.make_scene_from_file("teapot.gltf", #load("../resources/teapot.gltf"))
    fmt.println(teapot.models[0].primitives)
    teapot.models[0].primitives[0].params.pbr_mul = {1, 0.2, 1}
    teapot.models[0].primitives[0].params.pbr_add = {0, 0, 0}
    transform.init_node(teapot.root, {translation={0, 0.2, 0}, scale=0.01})

    light = graphics.make_directional_light({0, -0.6, 0.4}, {0.4, 0.5, 1.0, 4})
    light_trans = transform.make()

    //room-sized reflection at roughly the height of the teapot
    ref = graphics.make_reflection_probe({0, 0.5, 0}, 1, capture_offset = {0, -0.3, 0}, layers = graphics.Layer_Mask(~u64(1)))
    ref.camera.background.environment = skybox
}

tick :: proc() {
    if input.key_pressed(.Key_Escape) {
        window.close()
    }

    cam_trans := transform.local(&cam_trans)
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
    trans := transform.local(&light_trans)
    trans.rotation = transform.rotation_from_angles({0, 0, sin})

    transform.rotatey(teapot.root, 0.01)

}

draw :: proc(alpha, delta: f64) {
    graphics.draw_camera(cam, cam_trans)
    graphics.draw_mesh(quad, quad_mat, material_params=graphics.mat_params(metallic_mul=0, roughness_mul = 0.2))
    graphics.draw_mesh(wall, stained_glass_mat, material_params=graphics.mat_params(metallic_mul=0), double_sided=true)
    graphics.draw_scene(teapot, layers=1)
    graphics.draw_directional_light(light, light_trans)
    graphics.draw_reflection_probe(ref)
}

quit :: proc() {
    graphics.delete_material(quad_mat)
    graphics.delete_texture(quad_tex)
    graphics.delete_mesh(quad)
    graphics.delete_material(stained_glass_mat)
    graphics.delete_texture(stained_glass_tex)
    graphics.delete_mesh(wall)
    graphics.delete_scene(teapot)
    graphics.delete_reflection_probe(ref)
    graphics.delete_texture(skybox)
}

main :: proc() {
    engine.boot(init, tick, draw, quit)
}
