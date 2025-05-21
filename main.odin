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
triangle_trans := transform.origin()

/*TODO:
we need to restructure window/input/graphics etc.
no more hooks, no more separation of concerns
these systems are inherently intertwined and the code should reflect that.

Current problems leading me to want to rework:
- on desktop, input rate is limited to tick rate. Off-tick inputs will just be dropped.
- web doesn't run as init() gets called before the graphics device is actually initialized.

we need to have one, single control flow so that the game portion of the app only starts when everything is actually ready
and events are fired as fast as possible, but the actual input-transfer happens per-tick.
*/

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
    window.set_tick_rate(10)
    window.set_size(640, 400)

    for i := 0; i < 16; i += 1 {
        a := scene.spawn(&main_scene, TestActor{i=3, f=4}, {init=test_init, tick=test_tick, kill=test_kill}, "Joe")
        fmt.println(a)
    }

    triangle = graphics.make_mesh([]graphics.Vertex{
        {position={+0.0, +0.5, 0.0}, texcoord={0.5, 1.0}, color={1, 0, 0, 1}},
        {position={-0.5, -0.5, 0.0}, texcoord={0.0, 0.0}, color={0, 1, 0, 1}},
        {position={+0.5, -0.5, 0.0}, texcoord={1.0, 0.0}, color={0, 0, 1, 1}},
    }, {0, 1, 2})
    transform.translate(&triangle_trans, {0, 0, 0.5})
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
}

draw :: proc(t: f64) {
    scene.draw(&main_scene, t)
    //graphics.draw_mesh(triangle, transform.compute(&triangle_trans))
    graphics.draw_mesh(triangle, transform.smooth(&triangle_trans, t))
}

kill :: proc() {
    scene.destroy(&main_scene)
    graphics.delete_mesh(triangle)
}

main :: proc() {
    fmt.println("HEWWO!!!")
    engine.boot(init, tick, draw, kill)
}
