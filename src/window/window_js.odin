#+build js

package window


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

closed: bool = false
close :: proc() {
    closed = true
}

