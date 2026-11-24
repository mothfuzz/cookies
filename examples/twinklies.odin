package main

import "cookies:engine"
import "cookies:window"
import "cookies:input"
import "cookies:graphics"
import "cookies:transform"
import "core:math/rand"
import "core:math/linalg"
import "core:fmt"

Twinklies :: struct {
    cam: graphics.Camera,
    cam_trans: transform.Transform,
    cam_angle: f32,

    quad: graphics.Mesh,
    quad_tex: graphics.Texture,
    quad_mat: graphics.Material,

    teapot_base: graphics.Scene,
    teapots: [64]graphics.Scene,

    lights_resolution: int, //len(lights) == res*res
    lights: [dynamic]graphics.Point_Light,

    font: graphics.Font
}

rebuild_lights :: proc(t: ^Twinklies) {
    clear(&t.lights)
    for i in 0..<t.lights_resolution {
        for j in 0..<t.lights_resolution {
            x := -0.5 + f32(i) / f32(t.lights_resolution)
            z := -0.5 + f32(j) / f32(t.lights_resolution)
            color: [4]f32
            color.r = rand.float32()
            color.g = rand.float32()
            color.b = rand.float32()
            color.a = 1
            append(&t.lights, graphics.make_point_light(position={x, 0.02, z}, color=color, range=0.15*8.0/f32(t.lights_resolution), render_shadows=false))
        }
    }
}

init :: proc(t: ^Twinklies) {
    window.set_size(640, 400)
    t.cam = graphics.make_camera()
    t.cam_trans = transform.make({translation={0, 0.2, 0.7}})
    transform.look_at(&t.cam_trans, {0, 0, 0})

    t.quad = graphics.make_mesh([]graphics.Vertex{
        {position={-0.5, 0.0, -0.5}, texcoord={0.0, 0.0}, color={1, 1, 1, 1}},
        {position={+0.5, 0.0, -0.5}, texcoord={4.0, 0.0}, color={1, 1, 1, 1}},
        {position={+0.5, 0.0, +0.5}, texcoord={4.0, 4.0}, color={1, 1, 1, 1}},
        {position={-0.5, 0.0, +0.5}, texcoord={0.0, 4.0}, color={1, 1, 1, 1}},
    }, {2, 1, 0, 3, 2, 0})
    img := []u32{
        0xffffffff, 0xff000000,
        0xff000000, 0xffffffff,
    }
    t.quad_tex = graphics.make_texture_2D(img, {2, 2})
    t.quad_mat = graphics.make_material(t.quad_tex, filtering=false, tiling=true)

    t.teapot_base = graphics.make_scene_from_file("teapot.gltf", #load("../resources/teapot.gltf"))
    for i in 0..<8 {
        for j in 0..<8 {
            teapot := &t.teapots[i*8+j]
            teapot^ = graphics.copy_scene(&t.teapot_base)
            x := -0.5 + (1.0/16.0) + f32(i)/8
            z := -0.5 + (1.0/16.0) + f32(j)/8
            transform.init_node(teapot.root, {translation={x, 0.02, z}, scale=0.001})
        }
    }

    t.lights_resolution = 8
    rebuild_lights(t)

    t.font = graphics.make_font_from_file(#load("../resources/unifont.otf"), 32)
}

move_camera :: proc(t: ^Twinklies) {
    cam_local := transform.local(&t.cam_trans)
    cam_pos := &cam_local.translation

    s := linalg.sin(t.cam_angle)
    c := linalg.cos(t.cam_angle)

    speed :: 0.005

    if input.key_down(.Key_W) {
        cam_pos.z -= speed * c
        cam_pos.x += speed * s
    }
    if input.key_down(.Key_S) {
        cam_pos.z += speed * c
        cam_pos.x -= speed * s
    }
    if input.key_down(.Key_A) {
        cam_pos.z -= speed * s
        cam_pos.x -= speed * c
    }
    if input.key_down(.Key_D) {
        cam_pos.z += speed * s
        cam_pos.x += speed * c
    }
    if input.key_down(.Key_Left) {
        t.cam_angle -= speed*2
    }
    if input.key_down(.Key_Right) {
        t.cam_angle += speed*2
    }
    //graphics.look_at(&cam, cam_pos^, cam_pos^ + {s, 0, -c})
    transform.look_at(&t.cam_trans, cam_pos^ + {s, 0, -c})
}

tick :: proc(t: ^Twinklies) {
    if input.key_pressed(.Key_Escape) {
        window.close()
    }
    if input.key_pressed(.Key_C) {
        graphics.visualize_clusters = !graphics.visualize_clusters
    }
    if input.key_pressed(.Key_Q) {
        t.lights_resolution -= 1
        rebuild_lights(t)
    }
    if input.key_pressed(.Key_E) {
        t.lights_resolution += 1
        rebuild_lights(t)
    }
    if input.key_pressed(.Key_F11) {
        window.set_fullscreen(!window.get_fullscreen())
    }
    move_camera(t)
}

draw :: proc(t: ^Twinklies, alpha, delta: f64) {
    graphics.draw_camera(t.cam, t.cam_trans)
    graphics.draw_mesh(t.quad, t.quad_mat)
    for tt in t.teapots {
        graphics.draw_scene(tt)
    }
    for l in t.lights {
        graphics.draw_light(l)
    }

    ui_txt := fmt.tprintf("fps: %f\nlights: %d", 1.0/delta, t.lights_resolution * t.lights_resolution)
    //window.set_title(fps)
    width := f32(graphics.screen_resolution.x)
    height := f32(graphics.screen_resolution.y)
    graphics.ui_draw_text(ui_txt, t.font, {-width/2, +height/2}, {1, 1, 1, 1})
}

quit :: proc(t: ^Twinklies) {
    graphics.delete_material(t.quad_mat)
    graphics.delete_texture(t.quad_tex)
    graphics.delete_mesh(t.quad)
    transform.delete(t.cam_trans)
    for tt in t.teapots {
        graphics.delete_scene(tt)
    }
    graphics.delete_scene(t.teapot_base)
    graphics.delete_font(t.font)
}

main :: proc() {
    engine.boot_with(Twinklies, init, tick, draw, quit)
}
