#+build !js

package window

import "core:log"
import "core:strings"
import "vendor:sdl3"

window: ^sdl3.Window

@(export)
set_size :: proc(width: uint, height: uint) {
    sdl3.SetWindowSize(window, i32(width), i32(height))
    sdl3.SetWindowPosition(window, sdl3.WINDOWPOS_CENTERED, sdl3.WINDOWPOS_CENTERED)
}
@(export)
get_size :: proc() -> [2]uint {
    rect: [2]i32
    sdl3.GetWindowSize(window, &rect.x, &rect.y)
    return {uint(rect.x), uint(rect.y)}
}

@(export)
set_title :: proc(title: string) {
    title := strings.clone_to_cstring(title, context.temp_allocator)
    sdl3.SetWindowTitle(window, title)
}

@(export)
close :: proc() {
    e: sdl3.Event = {}
    e.type = .QUIT
    success := sdl3.PushEvent(&e)
    if !success {
        log.panic("Unable to send quit event!")
    }
}
