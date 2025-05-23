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

main_scene: scene.Scene = {name="Eve"}
triangle: graphics.Mesh
tex: graphics.Texture
mat: graphics.Material
mat2: graphics.Material
triangle_trans := transform.origin()
triangle_trans2 := transform.origin()

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

init :: proc() {
    window.set_size(640, 400)
    engine.set_tick_rate(30)

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
        0xffffffff, 0xff000000, 0xffffffff, 0xff000000,
        0xff000000, 0xffffffff, 0xff000000, 0xffffffff,
        0xffffffff, 0xff000000, 0xffffffff, 0xff000000,
        0xff000000, 0xffffffff, 0xff000000, 0xffffffff,
    }
    img2 := graphics.make_scaled_image_nearest(img, {4, 4}, {1024, 1024})
    tex = graphics.make_texture_2D(img2, {1024, 1024})
    delete(img2)
    mat = graphics.make_material(albedo=tex)
    mat2 = graphics.make_material(albedo=tex)
    transform.translate(&triangle_trans, {0, 0, 0.5})
    transform.translate(&triangle_trans2, {0, 0, 0.5})
}

accumulator: int = 0
tick :: proc() {
    accumulator += 1
    if accumulator > 30 {
        //prints every 1 second
        fmt.println("tick...")
        accumulator = 0
    }
    if input.key_down(.Key_A) {
        fmt.println("LEFT")
    }
    if input.key_down(.Key_D) {
        fmt.println("RIGHT")
    }
    if input.key_pressed(.Key_Space) {
        fmt.println("JUMP:", accumulator)
    }
    if input.key_pressed(.Key_Escape) {
        window.close()
    }
    if input.mouse_pressed(.Left) {
        fmt.println("click!!!", accumulator)
        fmt.println(input.mouse_position)
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
    transform.rotatey(&triangle_trans, 0.1)
    //transform.scale(&triangle_trans, {0.99, 0.99, 0.99})
    //transform.translate(&triangle_trans, {0.01, 0, 0})
    transform.rotatez(&triangle_trans2, 0.1)
}

draw :: proc(t: f64) {
    scene.draw(&main_scene, t)
    //graphics.draw_mesh(triangle, mat, transform.compute(&triangle_trans))
    graphics.draw_mesh(triangle, mat, transform.smooth(&triangle_trans, t))
    graphics.draw_mesh(triangle, mat, transform.smooth(&triangle_trans, t))
    graphics.draw_mesh(triangle, mat, transform.smooth(&triangle_trans, t))
    graphics.draw_mesh(triangle, mat, transform.smooth(&triangle_trans, t))
    graphics.draw_mesh(triangle, mat2, transform.smooth(&triangle_trans2, t))
}

kill :: proc() {
    scene.destroy(&main_scene)
    graphics.delete_mesh(triangle)
    graphics.delete_material(mat)
    graphics.delete_texture(tex)
}

main :: proc() {
    fmt.println("HEWWO!!!")
    engine.boot(init, tick, draw, kill)
}
