package main

//example starter project
//can be run in one line with:
//odin run . -out:bin/cookies.exe

import "core:fmt"
import "engine"
import "engine/window"
import "engine/input"
import "engine/scene"

main_scene: scene.Scene

TestActor :: struct {
    i: i32,
    f: f32,
}

test_tick :: proc(a: ^scene.Actor) {
    self := (^TestActor)(a.data)
    fmt.println("there's a thing:", self.i, self.f)
}

init :: proc() {
    window.set_tick_rate(30)
    window.set_size(640, 400)

    a := scene.spawn(&main_scene, TestActor{i=3, f=4}, {tick=test_tick})
    fmt.println(a)
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
    scene.tick(&main_scene)
}

draw :: proc(t: f64) {
    scene.draw(&main_scene, t)
}

main :: proc() {
    fmt.println("HEWWO!!!")
    engine.boot(init, tick, draw, nil)
}
