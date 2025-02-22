package engine

//bit of glue code so that these packages can work somewhat independently

import "window"
import "input"
import "audio"

@(init)
init_dylib :: proc() {
    //actually this might be better handled by the modules themselves
}

boot :: proc(init: proc(), tick: proc(), draw: proc(f64), quit: proc()) {
    append(&window.init_hooks, input.init)
    append(&window.post_tick_hooks, input.update)
    append(&window.init_hooks, audio.init)
    window.run(init, tick, draw, quit)
}
