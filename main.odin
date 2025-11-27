package main

//example starter project
//can be run in one line with:
//odin run . -out:bin/cookies.exe

import "core:fmt"
import "engine"
import "engine/window"
import "engine/input"
import "engine/scene"
import "engine/graphics"
import "engine/transform"
import "engine/spatial"
import "core:math"

main_scene: scene.Scene = {name="Eve"}
triangle: graphics.Mesh
quad: graphics.Mesh
tex: graphics.Texture
tex2: graphics.Texture
mat: graphics.Material
mat2: graphics.Material
text_mat: graphics.Material
triangle_trans := transform.ORIGIN
quad_trans := transform.ORIGIN
floor_trans := transform.ORIGIN
cam: graphics.Camera
cam2: graphics.Camera
unifont: graphics.Font

my_light: graphics.Point_Light
sun_light: graphics.Directional_Light

emantaller: engine.Scene

brick_color: graphics.Texture
brick_norm: graphics.Texture
brick_pbr: graphics.Texture
brick_mat: graphics.Material

TestActor :: struct {
    i: i32,
    f: f32,
}

MyEvent :: struct {
    f: f32,
}

my_event_handler :: proc(a: ^scene.Actor, e: ^scene.Event) {
    self := (^TestActor)(a.data)
    event := (^MyEvent)(e.data)
    fmt.println("actor", a.id, "got a float:", event.f)
}

test_tick :: proc(a: ^scene.Actor) {
    self := (^TestActor)(a.data)
    if input.key_pressed(.Key_K) {
        scene.kill(a.scene, a.id)
        return
    }
    if input.key_pressed(.Key_E) {
        scene.send(a.scene, 1, MyEvent{3.14})
    }
}

test_init :: proc(a: ^scene.Actor) {
    fmt.println("hi! my name is", a.name, "and I belong to", a.scene.name)
    scene.subscribe(a.scene, a.id, MyEvent, my_event_handler)
}

test_kill :: proc(a: ^scene.Actor) {
    fmt.println("I was killed!!")
}

screen_size: [2]f32 = {640, 400}

init :: proc() {
    window.set_size(uint(screen_size.x), uint(screen_size.y))
    engine.set_tick_rate(30)

    graphics.set_background_color({0.8, 0.4, 0.6})
    graphics.set_render_distance(2048.0+1024.0)
    graphics.set_fog_distance(2048.0)

    for i := 0; i < 16; i += 1 {
        a := scene.spawn(&main_scene, TestActor{i=3, f=4}, {init=test_init, tick=test_tick, kill=test_kill}, "Joe")
        fmt.println(a)
    }

    triangle = graphics.make_mesh([]graphics.Vertex{
        {position={+0.0, +0.5, 0.0}, texcoord={0.5, 0.0}, color={1, 0, 0, 1}},
        {position={-0.5, -0.5, 0.0}, texcoord={0.0, 1.0}, color={0, 1, 0, 1}},
        {position={+0.5, -0.5, 0.0}, texcoord={1.0, 1.0}, color={0, 0, 1, 1}},
    }, {0, 1, 2})
    img := []u32{
        0xffffffff, 0xff0000ff, 0xffffffff, 0xff000000,
        0xff000000, 0xffffffff, 0xff000000, 0xffffffff,
        0xffffffff, 0xff000000, 0xffffffff, 0xff000000,
        0xff000000, 0xffffffff, 0xff000000, 0xffffffff,
    }
    //img2 := graphics.make_scaled_image_nearest(img, {4, 4}, {1024, 1024})
    //tex = graphics.make_texture_2D(img2, {1024, 1024})
    //delete(img2)
    tex = graphics.make_texture_2D(img, {4, 4})
    mat = graphics.make_material(base_color=tex, filtering=false)


    quad = graphics.make_mesh([]graphics.Vertex{
        {position={-0.5, +0.5, 0.0}, texcoord={0.0, 0.0}, color={1, 1, 1, 1}},
        {position={+0.5, +0.5, 0.0}, texcoord={1.0, 0.0}, color={1, 1, 1, 1}},
        {position={+0.5, -0.5, 0.0}, texcoord={1.0, 1.0}, color={1, 1, 1, 1}},
        {position={-0.5, -0.5, 0.0}, texcoord={0.0, 1.0}, color={1, 1, 1, 1}},
    }, {2, 1, 0, 3, 2, 0})
    tex2 = graphics.make_texture_from_image(#load("resources/frasier.png"))
    mat2 = graphics.make_material(base_color=tex2)

    transform.set_scale(&triangle_trans, 200)

    transform.set_position(&quad_trans, {0, f32(100+128/2)/200, 0})
    transform.set_scale(&quad_trans, 1.0/200)

    transform.set_position(&floor_trans, {0, -320, -320})
    transform.set_scale(&floor_trans, 640*4)
    transform.rotatex(&floor_trans, -0.5 * math.PI)

    transform.link(&triangle_trans, &quad_trans)

    cam = graphics.make_camera({0, 0, screen_size.x/2, screen_size.y})
    cam2 = graphics.make_camera({screen_size.x/2 - 1, 0, screen_size.x/2, screen_size.y})
    //cam = graphics.make_camera({0, 0, screen_size.x, screen_size.y})
    //cam2 = graphics.make_camera({0, 0, screen_size.x, screen_size.y})
    graphics.look_at(&cam, {0, 0, 0}, {0, 0, graphics.z_2d(&cam)})
    graphics.look_at(&cam2, {0, 0, 0}, {0, 0, graphics.z_2d(&cam2)})

    //fmt.println("loading font...")
    unifont = graphics.make_font_from_file(#load("resources/unifont.otf"), 32)

    text_mat = graphics.make_material(unifont.texture, filtering=false)

    engine.preload("emantaller.png", #load("resources/emantaller.png"))
    emantaller = engine.make_scene_from_file("emantaller.gltf", #load("resources/emantaller.gltf"), true)
    transform.set_scale(&emantaller.active_layout.roots[0].transform, {100, 100, 100})
    transform.set_position(&emantaller.active_layout.roots[0].transform, {0, 0, -100})

    spatial.transform_tri_mesh(&emantaller.colliders[0], transform.compute(&emantaller.active_layout.roots[0].transform))
    fmt.println(emantaller.colliders[0])

    my_light = graphics.make_point_light({0, -160, -320}, 600, {1, 1, 0, 1})
    sun_light = graphics.make_directional_light({-0.5, -0.5, 0}, {1, 1, 1, 0.0})

    brick_color = graphics.make_texture_from_image(#load("resources/brick4/basecolor.jpg"))
    brick_norm = graphics.make_texture_from_image(#load("resources/brick4/normal.jpg"), true)
    brick_ambient := #load("resources/brick4/ambient.jpg")
    brick_roughness := #load("resources/brick4/roughness.jpg")
    brick_pbr = graphics.make_pbr_texture_from_images(ambient=brick_ambient, roughness=brick_roughness)
    brick_mat = graphics.make_material(brick_color, brick_norm, brick_pbr)
}

camera_pos: [3]f32 = {0, 0, 0}
camera_angle: f32 = 270*math.PI/180.0
camera_pitch: f32 = 0
move_speed: f32 = 25

str := "yippeeeeee!!!!!!!!!!!!!!"
text_counter := 0

accumulator: int = 0
tick :: proc() {
    accumulator += 1
    if accumulator > 30 {
        //prints every 1 second
        fmt.println("tick...")
        accumulator = 0
    }
    if accumulator % 2 == 1 && text_counter < len(str) {
        text_counter += 1
    }
    if input.key_down(.Key_W) {
        camera_pos.z += math.sin(camera_angle)*move_speed
        camera_pos.x += math.cos(camera_angle)*move_speed
    }
    if input.key_down(.Key_S) {
        camera_pos.z -= math.sin(camera_angle)*move_speed
        camera_pos.x -= math.cos(camera_angle)*move_speed
    }
    if input.key_down(.Key_A) {
        camera_pos.z -= math.cos(camera_angle)*move_speed
        camera_pos.x += math.sin(camera_angle)*move_speed
    }
    if input.key_down(.Key_D) {
        camera_pos.z += math.cos(camera_angle)*move_speed
        camera_pos.x -= math.sin(camera_angle)*move_speed
    }
    if input.key_down(.Key_Space) {
        camera_pos.y += move_speed
    }
    if input.key_down(.Key_LeftShift) {
        camera_pos.y -= move_speed
    }
    if input.key_down(.Key_Left) {
        camera_angle -= 0.1
    }
    if input.key_down(.Key_Right) {
        camera_angle += 0.1
    }
    if input.key_down(.Key_Up) {
        camera_pitch += move_speed
    }
    if input.key_down(.Key_Down) {
        camera_pitch -= move_speed
    }
    if input.key_pressed(.Key_Space) {
        fmt.println("JUMP:", accumulator)
    }
    if input.key_pressed(.Key_Escape) {
        window.close()
    }
    if input.mouse_down(.Left) {
        //fmt.println("click!!!", accumulator)
        fmt.println(input.mouse_position)
        transform.set_position(&triangle_trans, {f32(input.mouse_position.x), f32(input.mouse_position.y), 0})
    }
    if input.mouse_pressed(.Right) {
        fmt.println("right click!!!", accumulator)
    }
    if input.mouse_pressed(.Middle) {
        fmt.println("middle click!!!", accumulator)
    }
    if input.key_pressed(.Key_P) {
        scene.publish(&main_scene, MyEvent{4.13})
    }
    scene.tick(&main_scene)
    transform.rotatez(&triangle_trans, 0.01)
    transform.rotatez(&quad_trans, -0.01)

    forward := [3]f32{camera_pos.x + math.cos(camera_angle)*graphics.z_2d(&cam),
                      camera_pos.y + camera_pitch,
                      camera_pos.z + math.sin(camera_angle)*graphics.z_2d(&cam)}
    offset_x := math.sin(camera_angle) * 20
    offset_z := math.cos(camera_angle) * 20
    graphics.look_to(&cam, {camera_pos.x-offset_x, camera_pos.y, camera_pos.z+offset_z}, forward)
    graphics.look_to(&cam2, {camera_pos.x+offset_x, camera_pos.y, camera_pos.z-offset_z}, forward)


    transform.rotatey(&emantaller.active_layout.roots[0].transform, 0.01)
}

draw :: proc(t: f64) {

    screen_size.x = f32(window.get_size().x)
    screen_size.y = f32(window.get_size().y)
    graphics.set_viewport(&cam, {0, 0, screen_size.x/2, screen_size.y})
    graphics.set_viewport(&cam2, {screen_size.x/2 - 1, 0, screen_size.x/2, screen_size.y})

    graphics.set_cameras({&cam, &cam2})
    scene.draw(&main_scene, t)
    graphics.draw_mesh(triangle, brick_mat, transform.smooth(&triangle_trans, t))
    graphics.draw_sprite(mat2, transform.smooth(&quad_trans, t), {64, 64, 128, 128}, {1, 0, 0, 1})
    graphics.draw_mesh(quad, brick_mat, transform.compute(&floor_trans))
    plus_one := floor_trans
    transform.translate(&plus_one, {0, 2, 0})
    graphics.draw_mesh(quad, text_mat, transform.compute(&plus_one), clip_rect=graphics.get_char(unifont, '@'), tint={1, 0, 1, 1})

    offset: [2]f32
    offset.x = -screen_size.x/2
    offset.y = +screen_size.y/2
    graphics.ui_draw_rect({0, offset.y-48/2, screen_size.x, 48}, {0, 0, 0, 0.5})
    graphics.ui_draw_text(str[0:text_counter], unifont, offset, {0, 0, 0, 1})
    graphics.ui_draw_text(str[0:text_counter], unifont, offset+{1, -1}, {1, 1, 1, 1})

    text_trans := transform.ORIGIN
    transform.translate(&text_trans, {-16*3, 0, 1})
    graphics.draw_text("Hello!!", unifont, transform.compute(&text_trans), {0, 1, 1, 1})

    engine.draw_scene(&emantaller, t)

    graphics.draw_point_light(my_light)
    graphics.draw_directional_light(sun_light)
}

kill :: proc() {
    scene.destroy(&main_scene)
    graphics.delete_mesh(triangle)
    graphics.delete_mesh(quad)
    graphics.delete_material(mat)
    graphics.delete_material(mat2)
    graphics.delete_texture(tex)
    graphics.delete_texture(tex2)
    graphics.delete_camera(cam)
    graphics.delete_camera(cam2)
    graphics.delete_font(unifont)

    graphics.delete_material(brick_mat)
    graphics.delete_texture(brick_color)
    graphics.delete_texture(brick_norm)
    graphics.delete_texture(brick_pbr)
}

main :: proc() {
    fmt.println("HEWWO!!!")
    engine.boot(init, tick, draw, kill)
}
