package main

import "core:fmt"
import "../engine"
import "../engine/window"
import "../engine/transform"

parent: transform.Transform = transform.origin()
trans: transform.Transform = transform.origin()
prev_t: f64 = 0.0

init :: proc() {
    window.set_tick_rate(15) //abysmal tick rate so we can lerp
    window.set_size(640, 400)

    transform.set_translation(&parent, {100, 0, 0})
    transform.set_scale(&parent, {10, 10, 10})
    transform.set_translation(&trans, {0, 0, 0}) //200, 100, 100
    transform.set_scale(&trans, {5, 5, 5}) //50, 50, 50
    transform.parent(&parent, &trans)
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
        fmt.println(trans.world_translation)
        prev_t = t
    }
}

main :: proc() {
    engine.boot(init, tick, draw, nil)
}
