#+build !js

package window

import "core:fmt"
import "core:strings"
import "core:time"
import "vendor:sdl3"

window: ^sdl3.Window

set_size :: proc "c" (width: uint, height: uint) {
    sdl3.SetWindowSize(window, i32(width), i32(height))
}
get_size :: proc "c" () -> [2]uint {
    rect: [2]i32
    sdl3.GetWindowSize(window, &rect.x, &rect.y)
    return {uint(rect.x), uint(rect.y)}
}

set_title :: proc(title: string) {
    title := strings.clone_to_cstring(title, context.temp_allocator)
    sdl3.SetWindowTitle(window, title)
}

close :: proc() {
    e: sdl3.Event = {}
    e.type = .QUIT
    success := sdl3.PushEvent(&e)
    if !success {
        fmt.panicf("Unable to send quit event")
    }
}
