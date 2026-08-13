#+build js
package engine

import "core:log"
import "core:sys/wasm/js"

import "cookies:window"
import "cookies:graphics"
import "cookies:input"
import "cookies:audio"
import "cookies:resources"
import "cookies:transform"

user_init: proc() = nil
user_tick: proc() = nil
user_draw: proc(f64, f64) = nil
user_quit: proc() = nil


initialized: bool = false
accumulator: f64 = 0

logger: log.Logger

@(export)
step :: proc(delta_time: f64) -> bool {
    context.logger = logger

    if !graphics.ren.ready {
        return true
    }

    if !initialized {
        resources.register_loaders()
        if user_init != nil {
            user_init()
        }
        initialized = true
        return true
    }

    if window.closed {
        if user_quit != nil {
            user_quit()
        }
        graphics.wait_idle()
        graphics.quit()
        transform.delete_tree(transform.tree_allocator)
        free(transform.tree_allocator)
        audio.quit()
        resources.unregister_loaders()
        resources.unload_files()
        log.destroy_console_logger(logger)
        return false
    }
    accumulator += delta_time
    time_step := 1.0/f64(tick_rate)
    for ; accumulator >= time_step; accumulator -= time_step {
        if user_tick != nil {
            user_tick()
        }
        input.update()
    }
    alpha := accumulator / time_step
    if user_draw != nil {
        user_draw(alpha, delta_time)
    }
    graphics.render_frame()
    return true
}

fullscreen_event :: proc(e: js.Event) {
    context.logger = logger
    if window.get_fullscreen() {
        rect := js.get_bounding_client_rect("canvas")
        window.set_size(uint(rect.width), uint(rect.height))
    } else {
        window.set_size(window.previous_resolution.x, window.previous_resolution.y)
    }
}

boot :: proc(init: proc(), tick: proc(), draw: proc(f64, f64), quit: proc()) {

    logger = log.create_console_logger()
    context.logger = logger

    user_init = init
    user_tick = tick
    user_draw = draw
    user_quit = quit

    js.add_document_event_listener(.Fullscreen_Change, nil, fullscreen_event)
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
        w, h := window.get_size()
        input.current_mouse_position.x = i32(pos.x) - i32(w/2)
        input.current_mouse_position.y = i32(h/2) - i32(pos.y)
    })

    transform.tree_allocator = new(transform.Tree)
    transform.tree_allocator^ = transform.make_tree()

    graphics.init(window.get_wgpu_surface, {window.get_size()})
    window.resize_hook = graphics.window_resized
}
