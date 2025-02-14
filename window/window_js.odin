#+build js

package window

user_tick: proc() = nil
user_draw: proc() = nil
user_quit: proc() = nil

started: bool = false
stopped: bool = false
accumulator: f64 = 0

import "base:runtime"
main_context: runtime.Context

//leaving this here so I remember how to do JS imports when I actually need to
/*foreign import window_imports "window_imports"
@(default_calling_convention="contextless")
foreign window_imports {
    set_size :: proc(width: uint, height: uint) ---
}*/

import "core:sys/wasm/js"

set_size :: proc(width: uint, height: uint) {
    js.set_element_key_f64("canvas", "width", f64(width))
    js.set_element_key_f64("canvas", "height", f64(height))
}
get_size :: proc() -> [2]uint {
    bounding_rect := js.get_bounding_client_rect("canvas")
    return {uint(bounding_rect.width), uint(bounding_rect.height)}
}
set_title :: proc(title: string) {
    js.set_element_key_string("title", "innerText", title)
}

close :: proc() {
    stopped = true
}

@(export)
step :: proc "c" (delta_time: f64) -> bool {
    context = main_context
    if !started {
        return true
    }
    if stopped {
        if user_quit != nil {
            user_quit()
        }
        return false
    }
    accumulator += delta_time
    for ; accumulator > 0; accumulator -= 1000.0/tick_rate {
        for hook in pre_tick_hooks {
            hook()
        }
        if user_tick != nil {
            user_tick()
        }
        for hook in post_tick_hooks {
            hook()
        }
    }
    for hook in draw_hooks {
        hook()
    }
    if user_draw != nil {
        user_draw()
    }
    return true
}

run :: proc(init: proc(), tick: proc(), draw: proc(), quit: proc()) {
    main_context = context

    for hook in init_hooks {
        hook()
    }
    if init != nil {
        init()
    }
    user_tick = tick
    user_draw = draw
    user_quit = quit
    started = true
}
