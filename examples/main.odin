package main

import "core:fmt"
import "../engine"
import "../window"
import "../input"

init :: proc() {
    window.set_tick_rate(30)
    window.set_size(640, 400)
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
}

main :: proc() {
    fmt.println("HEWWO!!!")
    engine.boot(init, tick, nil, nil)
}
