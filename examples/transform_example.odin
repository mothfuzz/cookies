package main

import "core:fmt"
import "../engine"
import "../engine/window"
import "../engine/transform"

parent: transform.Transform = transform.ORIGIN
trans: transform.Transform = transform.ORIGIN
prev_t: f64 = 0.0

init :: proc() {
    engine.set_tick_rate(15) //abysmal tick rate so we can lerp
    window.set_size(640, 400)

    transform.set_position(&parent, {100, 0, 0})
    transform.set_scale(&parent, {10, 10, 10})
    transform.set_position(&trans, {0, 0, 0}) //200, 100, 100
    transform.set_scale(&trans, {5, 5, 5}) //50, 50, 50
    transform.link(&parent, &trans)
}

accumulator: int = 0
tick :: proc() {
    accumulator += 1
    if accumulator > 1 {
        //so I can check the results.
        window.close()
    }
    transform.translate(&trans, {10, 10, 10})
}

draw :: proc(t: f64) {
    if abs(t - prev_t) > 0.01 {
        fmt.println("T:", t)
        fmt.println(transform.smooth(&trans, t))
        fmt.println(transform.get_position(&trans))
        prev_t = t
    }
}

main :: proc() {
    engine.boot(init, tick, draw, nil)
}
