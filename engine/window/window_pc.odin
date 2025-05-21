#+build !js

package window

import "core:strings"
import "core:time"
import "vendor:sdl2"

window: ^sdl2.Window

set_size :: proc "c" (width: uint, height: uint) {
    sdl2.SetWindowSize(window, i32(width), i32(height))
}
get_size :: proc "c" () -> [2]uint {
    rect: [2]i32
    sdl2.GetWindowSize(window, &rect.x, &rect.y)
    return {uint(rect.x), uint(rect.y)}
}

set_title :: proc(title: string) {
    title := strings.clone_to_cstring(title, context.temp_allocator)
    sdl2.SetWindowTitle(window, title)
}

close :: proc() {
    e: sdl2.Event = {}
    e.type = .QUIT
    sdl2.PushEvent(&e)
}
