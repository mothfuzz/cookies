package main

//example starter project
//can be run in one line with:
//odin run . -out:bin/cookies.exe -collection:cookies=src

import "cookies:engine"
import "cookies:window"
import "cookies:input"
import "cookies:actors"
import "cookies:graphics"
import "cookies:transform"
import "cookies:resources/file_map"
import "core:fmt"
import "core:math"

main_scene: actors.Stage = {name="Eve"}
triangle: graphics.Mesh
quad: graphics.Mesh
tex: graphics.Texture
tex2: graphics.Texture
mat: graphics.Material
mat2: graphics.Material
text_mat: graphics.Material
triangle_trans: transform.Transform
quad_trans: transform.Transform
floor_trans: transform.Transform
cam: graphics.Camera
cam2: graphics.Camera
unifont: graphics.Font

my_light: graphics.Point_Light
sun_light: graphics.Directional_Light
spot_light: graphics.Spot_Light

emantaller: graphics.Scene
cheese1: graphics.Scene
cheese2: graphics.Scene
cheese2_anim: graphics.Animation_Player

brainstem: graphics.Scene
brainstem_anim: graphics.Animation_Player

brick_color: graphics.Texture
brick_norm: graphics.Texture
brick_pbr: graphics.Texture
brick_mat: graphics.Material

metal_color: graphics.Texture
metal_norm: graphics.Texture
metal_pbr: graphics.Texture
metal_mat: graphics.Material

TestActor :: struct {
    using actor: actors.Actor,
    init: proc(^TestActor),
    tick: proc(^TestActor),
    kill: proc(^TestActor),
    i: i32,
    f: f32,
}

MyEvent :: struct {
    f: f32,
}

my_event_handler :: proc(a: ^TestActor, e: ^MyEvent) {
    fmt.println("actor", a.handle, "got a float:", e.f)
}

test_tick :: proc(a: ^TestActor) {
    if input.key_pressed(.Key_K) {
        actors.kill(&main_scene, a)
        return
    }
    if input.key_pressed(.Key_E) {
        actors.send(&main_scene, a, MyEvent{3.14})
    }
}

test_init :: proc(a: ^TestActor) {
    fmt.println("hi! my name is", a.name, "and I belong to", main_scene.name)
    actors.subscribe(&main_scene, a, my_event_handler)
}

test_kill :: proc(a: ^TestActor) {
    fmt.println("I was killed!!")
}

screen_size: [2]f32 = {640, 400}

init :: proc() {
    window.set_size(uint(screen_size.x), uint(screen_size.y))

    for i := 0; i < 16; i += 1 {
        a := actors.spawn(&main_scene, TestActor{i=3, f=4, init=test_init, tick=test_tick, kill=test_kill}, "Joe")
        fmt.println(a)
    }

    triangle = graphics.make_mesh([]graphics.Vertex{
        {position={+0.0, +0.5, 0.0}, texcoord={0.5, 0.0}, color={1, 0, 0, 0.9}},
        {position={-0.5, -0.5, 0.0}, texcoord={0.0, 1.0}, color={0, 1, 0, 0.8}},
        {position={+0.5, -0.5, 0.0}, texcoord={1.0, 1.0}, color={0, 0, 1, 0.7}},
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

    triangle_trans = transform.make({scale = 200})

    quad_trans = transform.make({translation = {0, f32(100+128/2)/200, 0}, scale = 1.0/200})

    floor_trans = transform.make({
        translation = {0, -320, -320},
        rotation = transform.rotation_from_angles({-0.5 * math.PI, 0, 0}),
        scale = 640*4,
    })

    transform.link(triangle_trans, quad_trans)

    cam = graphics.make_camera({0, 0, screen_size.x/2, screen_size.y})
    cam2 = graphics.make_camera({screen_size.x/2 - 1, 0, screen_size.x/2, screen_size.y})
    //cam = graphics.make_camera({0, 0, screen_size.x, screen_size.y})
    //cam2 = graphics.make_camera({0, 0, screen_size.x, screen_size.y})

    graphics.set_background_color(&cam, {0.8, 0.4, 0.6})
    graphics.set_draw_distance(&cam, 2048.0+1024.0)
    graphics.set_fog_onset(&cam, 2048.0)
    graphics.set_background_color(&cam2, {0.8, 0.4, 0.6})
    graphics.set_draw_distance(&cam2, 2048.0+1024.0)
    graphics.set_fog_onset(&cam2, 2048.0)

    //fmt.println("loading font...")
    unifont = graphics.make_font_from_file(#load("resources/unifont.otf"), 32)

    text_mat = graphics.make_material(unifont.texture, filtering=false)

    file_map.preload("emantaller.png", #load("resources/emantaller.png"))
    emantaller = graphics.make_scene_from_file("emantaller.gltf", #load("resources/emantaller.gltf"))
    cheese1 = graphics.copy_scene(&emantaller)
    cheese1_trans := transform.write(cheese1.root)
    cheese1_trans.scale = 100
    cheese1_trans.translation = {0, 0, -100}
    cheese2 = graphics.copy_scene(&emantaller)
    cheese2_trans := transform.write(cheese2.root)
    cheese2_trans.scale = 500
    cheese2_trans.translation = {0, 0, -500}
    cheese2_anim = graphics.animate(&cheese2)
    graphics.play(&cheese2_anim, 0, true)

    brainstem = graphics.make_scene_from_file("resources/BrainStem.gltf", #load("resources/BrainStem.gltf"))
    brainstem_trans := transform.write(brainstem.root)
    brainstem_trans.translation = {500, 0, 0}
    brainstem_trans.scale = 500
    brainstem_anim = graphics.animate(&brainstem)
    graphics.play(&brainstem_anim, 0, true)

    my_light = graphics.make_point_light({0, -160, -320}, {1, 1, 0, 1}, 600)
    sun_light = graphics.make_directional_light({-0.75, -0.25, 0}, {1, 1, 1, 1})
    spot_light = graphics.make_spot_light({0, 0, 0}, {0, -1, 0}, math.to_radians_f32(45), math.to_radians_f32(60), {0, 0, 1, 1})

    brick_color = graphics.make_texture_from_image(#load("resources/brick4/basecolor.jpg"))
    brick_norm = graphics.make_texture_from_image(#load("resources/brick4/normal.jpg"), true)
    brick_ambient := #load("resources/brick4/ambient.jpg")
    brick_roughness := #load("resources/brick4/roughness.jpg")
    brick_pbr = graphics.make_pbr_texture_from_images(ambient=brick_ambient, roughness=brick_roughness)
    brick_mat = graphics.make_material(brick_color, brick_norm, brick_pbr)

    metal_color = graphics.make_texture_from_image(#load("resources/metal41b/basecolor.jpg"))
    metal_norm = graphics.make_texture_from_image(#load("resources/metal41b/normal.jpg"), true)
    metal_metallic := #load("resources/metal41b/metallic.jpg")
    metal_roughness := #load("resources/metal41b/roughness.jpg")
    metal_pbr = graphics.make_pbr_texture_from_images(metallic=metal_metallic, roughness=metal_roughness)
    metal_mat = graphics.make_material(metal_color, metal_norm, metal_pbr)

    cam_trans = transform.make({translation = {0, 0, -graphics.z_2d(cam)}})
    cam2_trans = transform.make({translation = {0, 0, -graphics.z_2d(cam2)}})
}

cam_trans: transform.Transform
cam2_trans: transform.Transform
camera_pos: [3]f32 = {0, 0, 0}
camera_angle: f32 = 90*math.PI/180.0
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
        camera_pos.z -= math.sin(camera_angle)*move_speed
        camera_pos.x += math.cos(camera_angle)*move_speed
    }
    if input.key_down(.Key_S) {
        camera_pos.z += math.sin(camera_angle)*move_speed
        camera_pos.x -= math.cos(camera_angle)*move_speed
    }
    if input.key_down(.Key_A) {
        camera_pos.z -= math.cos(camera_angle)*move_speed
        camera_pos.x -= math.sin(camera_angle)*move_speed
    }
    if input.key_down(.Key_D) {
        camera_pos.z += math.cos(camera_angle)*move_speed
        camera_pos.x += math.sin(camera_angle)*move_speed
    }
    if input.key_down(.Key_Space) {
        camera_pos.y += move_speed
    }
    if input.key_down(.Key_LeftShift) {
        camera_pos.y -= move_speed
    }
    if input.key_down(.Key_Left) {
        camera_angle += 0.1
    }
    if input.key_down(.Key_Right) {
        camera_angle -= 0.1
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
        fmt.println(input.mouse_position())
        transform.write(triangle_trans).translation = {f32(input.mouse_position().x), f32(input.mouse_position().y), 0}
    }
    if input.mouse_pressed(.Right) {
        fmt.println("right click!!!", accumulator)
    }
    if input.mouse_pressed(.Middle) {
        fmt.println("middle click!!!", accumulator)
    }
    if input.key_pressed(.Key_P) {
        actors.publish(&main_scene, MyEvent{4.13})
    }
    actors.tick(&main_scene)
    transform.rotatez(triangle_trans, 0.01)
    transform.rotatez(quad_trans, -0.01)

    forward := [3]f32{camera_pos.x + math.cos(camera_angle)*graphics.z_2d(cam),
                      camera_pos.y + camera_pitch,
                      camera_pos.z - math.sin(camera_angle)*graphics.z_2d(cam)}
    offset_x := math.sin(camera_angle) * 50
    offset_z := math.cos(camera_angle) * 50
    cam_trans := transform.write(cam_trans)
    cam_trans.translation = {camera_pos.x+offset_x, camera_pos.y, camera_pos.z+offset_z}
    transform.look_at(cam_trans, forward)
    cam2_trans := transform.write(cam2_trans)
    cam2_trans.translation = {camera_pos.x-offset_x, camera_pos.y, camera_pos.z-offset_z}
    transform.look_at(cam2_trans, forward)

    transform.rotatey(cheese1.root, 0.01)

    if input.key_pressed(.Key_C) {
        graphics.stop(&cheese2_anim, 0, true)
    }
    if input.key_pressed(.Key_V) {
        graphics.play(&cheese2_anim, 0, true)
        fmt.printfln("%#v", cheese2)
    }
}

draw :: proc(a: f64, dt: f64) {
    screen_size.x = f32(window.get_size().x)
    screen_size.y = f32(window.get_size().y)
    graphics.set_viewport(&cam, {0, 0, screen_size.x/2, screen_size.y})
    graphics.set_viewport(&cam2, {screen_size.x/2 - 1, 0, screen_size.x/2, screen_size.y})

    graphics.draw_camera(cam, transform.world(cam_trans, a))
    graphics.draw_camera(cam2, transform.world(cam2_trans, a))

    actors.draw(&main_scene, a, dt)
    graphics.draw_mesh(triangle, brick_mat, transform.world(triangle_trans, a))
    graphics.draw_sprite(mat2, transform.world(quad_trans, a), {64, 64, 128, 128}, {1, 0, 0, 0.2}) //frasier
    graphics.draw_mesh(quad, metal_mat, transform.world(floor_trans), base_color_tint={1,1,1,0.9})
    plus_one := transform.read(floor_trans)
    plus_one.translation += {0, 1, 0}
    //graphics.draw_mesh(quad, text_mat, transform.compute(plus_one), clip_rect=graphics.get_char(unifont, '@'), base_color_tint={1, 0, 1, 1})

    offset: [2]f32
    offset.x = -screen_size.x/2
    offset.y = +screen_size.y/2
    graphics.ui_draw_rect({0, offset.y-48/2, screen_size.x, 48}, {0, 0, 0, 0.5})
    graphics.ui_draw_text(str[0:text_counter], unifont, offset, {0, 0, 0, 1})
    graphics.ui_draw_text(str[0:text_counter], unifont, offset+{1, -1}, {1, 1, 1, 1})

    text_trans := transform.ORIGIN
    text_trans.translation = {-16*3, 0, 1}
    graphics.draw_text("Hello!!", unifont, transform.compute(text_trans), {0, 1, 1, 1})

    graphics.draw_scene(cheese1, a)
    graphics.progress(&cheese2_anim, dt)
    graphics.draw_scene(cheese2, a)

    graphics.progress(&brainstem_anim, dt)
    graphics.draw_scene(brainstem, a)

    graphics.draw_point_light(my_light)
    graphics.draw_directional_light(sun_light)
    graphics.draw_spot_light(spot_light)
}

kill :: proc() {
    actors.delete_stage(&main_scene)
    graphics.delete_mesh(triangle)
    graphics.delete_mesh(quad)
    graphics.delete_material(mat)
    graphics.delete_material(mat2)
    graphics.delete_texture(tex)
    graphics.delete_texture(tex2)
    graphics.delete_font(unifont)

    graphics.delete_material(brick_mat)
    graphics.delete_texture(brick_color)
    graphics.delete_texture(brick_norm)
    graphics.delete_texture(brick_pbr)

    graphics.delete_scene(emantaller)
    graphics.delete_scene(cheese1)
    graphics.deanimate(cheese2_anim)
    graphics.delete_scene(cheese2)

    graphics.deanimate(brainstem_anim)
    graphics.delete_scene(brainstem)
}

import "core:mem"
main :: proc() {
    when ODIN_OS != .JS {
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)
    }

    fmt.println("HEWWO!!!")
    engine.set_tick_rate(30)
    engine.boot(init, tick, draw, kill)

    when ODIN_OS != .JS {
        if len(track.allocation_map) > 0 {
            fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
            for _, entry in track.allocation_map {
                fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
            }
        }
        if len(track.bad_free_array) > 0 {
            fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
            for entry in track.bad_free_array {
                fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
            }
        }
        mem.tracking_allocator_destroy(&track)
    }
}
