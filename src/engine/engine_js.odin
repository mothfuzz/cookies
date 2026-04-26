#+build js
package engine

import "core:sys/wasm/js"

import "cookies:window"
import "cookies:graphics"
import "cookies:input"
import "cookies:audio"

user_init: proc() = nil
user_tick: proc() = nil
user_draw: proc(f64, f64) = nil
user_quit: proc() = nil


initialized: bool = false
accumulator: f64 = 0

@(export)
step :: proc(delta_time: f64) -> bool {
    if !graphics.ren.ready {
        return true
    }

    if !initialized {
        /*for hook in init_hooks {
            hook()
        }*/
        if user_init != nil {
            user_init()
        }
        graphics.configure_surface(window.get_size())
        graphics.configure_render_targets()
        initialized = true
        return true
    }

    if window.closed {
        if user_quit != nil {
            user_quit()
        }
        /*for hook in quit_hooks {
            hook()
        }*/
        graphics.quit()
        audio.quit()
        return false
    }
    accumulator += delta_time
    time_step := 1.0/f64(tick_rate)
    for ; accumulator >= time_step; accumulator -= time_step {
        /*for hook in pre_tick_hooks {
            hook()
        }*/
        if user_tick != nil {
            user_tick()
        }
        /*for hook in post_tick_hooks {
            hook()
        }*/
        input.update()
    }
    alpha := accumulator / time_step
    if user_draw != nil {
        user_draw(alpha, delta_time)
    }
    /*for hook in draw_hooks {
        hook(1.0)
    }*/
    return true
}

import "core:fmt"
resize_event :: proc(e: js.Event) {
    fmt.println("JS: Resize event fired!!!")
    graphics.configure_surface(window.get_size())
    graphics.configure_render_targets()
    /*for hook in resize_hooks {
        hook()
    }*/
}

boot :: proc(init: proc(), tick: proc(), draw: proc(f64, f64), quit: proc()) {

    user_init = init
    user_tick = tick
    user_draw = draw
    user_quit = quit

    js.add_window_event_listener(.Resize, nil, resize_event)
    //js.add_event_listener("canvas", .Resize, nil, resize_event)
    js.add_event_listener("canvas", .Key_Down, nil, proc(e: js.Event) {
        js.event_prevent_default()
        js.event_stop_propagation()
        input.keys_pressed[input.js2key(e)] = true
        input.keys_current[input.js2key(e)] = true
    })
    js.add_event_listener("canvas", .Key_Up, nil, proc(e: js.Event) {
        js.event_prevent_default()
        js.event_stop_propagation()
        input.keys_released[input.js2key(e)] = true
        input.keys_current[input.js2key(e)] = false
    })
    js.add_event_listener("canvas", .Mouse_Down, nil, proc(e: js.Event) {
        input.mouse_buttons_pressed[input.Mouse_Button(e.mouse.button)] = true
        input.mouse_buttons_current[input.Mouse_Button(e.mouse.button)] = true
    })
    js.add_event_listener("canvas", .Mouse_Up, nil, proc(e: js.Event) {
        input.mouse_buttons_released[input.Mouse_Button(e.mouse.button)] = true
        input.mouse_buttons_current[input.Mouse_Button(e.mouse.button)] = false
    })
    js.add_event_listener("canvas", .Mouse_Move, nil, proc(e: js.Event) {
        pos := e.mouse.offset
        rect := window.get_size()
        input.current_mouse_position.x = i32(pos.x) - i32(rect.x/2)
        input.current_mouse_position.y = i32(rect.y/2) - i32(pos.y)
    })


    graphics.init(window.get_wgpu_surface, window.get_size())
}
