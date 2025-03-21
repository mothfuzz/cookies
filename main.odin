package main

//example starter project
//can be run in one line with:
//odin run . -out:bin/cookies.exe

import "core:fmt"
import "engine"
import "engine/window"
import "engine/input"
import "engine/scene"

main_scene: scene.Scene = {name="Eve"}

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
    window.set_tick_rate(30)
    window.set_size(640, 400)

    for i := 0; i < 16; i += 1 {
        a := scene.spawn(&main_scene, TestActor{i=3, f=4}, {init=test_init, tick=test_tick, kill=test_kill}, "Joe")
        fmt.println(a)
    }
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
}

draw :: proc(t: f64) {
    scene.draw(&main_scene, t)
}

kill :: proc() {
    scene.destroy(&main_scene)
}

main :: proc() {
    fmt.println("HEWWO!!!")
    engine.boot(init, tick, draw, kill)
}
