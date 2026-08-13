#+build js

package window

import "core:log"

foreign import window_imports "window_imports"
@(default_calling_convention="contextless")
foreign window_imports {
    canvas_request_fullscreen :: proc() ---
    document_exit_fullscreen :: proc() ---
    canvas_is_fullscreen :: proc() -> bool ---
    canvas_request_pointer_lock :: proc() ---
    document_exit_pointer_lock :: proc() ---
    canvas_is_pointer_lock :: proc() -> bool ---
}

previous_resolution: [2]uint
set_fullscreen :: proc(fullscreen: bool) {
    if fullscreen {
        previous_resolution = {get_size()}
        canvas_request_fullscreen()
    } else {
        document_exit_fullscreen()
    }
}
get_fullscreen :: canvas_is_fullscreen
set_pointer_lock :: proc(locked: bool) {
    if locked {
        canvas_request_pointer_lock()
    } else {
        document_exit_pointer_lock()
    }
}
get_pointer_lock :: canvas_is_pointer_lock

import "core:sys/wasm/js"

set_size :: proc(width: uint, height: uint) {
    js.set_element_key_f64("canvas", "width", f64(width))
    js.set_element_key_f64("canvas", "height", f64(height))
    resize_hook({width, height})
}
get_size :: proc() -> (w, h: uint) {
    w = uint(js.get_element_key_f64("canvas", "width"))
    h = uint(js.get_element_key_f64("canvas", "height"))
    return
}
set_title :: proc(title: string) {
    js.set_element_key_string("title", "innerText", title)
}

closed: bool = false
close :: proc() {
    closed = true
}

