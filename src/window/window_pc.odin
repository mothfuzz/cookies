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
get_size :: proc() -> (w, h: uint) {
    rect: [2]i32
    sdl3.GetWindowSize(window, &rect.x, &rect.y)
    return uint(rect.x), uint(rect.y)
}

@(export)
set_title :: proc(title: string) {
    title := strings.clone_to_cstring(title, context.temp_allocator)
    sdl3.SetWindowTitle(window, title)
}

@(export)
set_fullscreen :: proc(fullscreen: bool) {
    sdl3.SetWindowFullscreen(window, fullscreen)
    sdl3.SyncWindow(window)
}

@(export)
get_fullscreen :: proc() -> bool {
    return .FULLSCREEN in sdl3.GetWindowFlags(window)
}

@(export)
set_pointer_lock :: proc(locked: bool) {
    ok := sdl3.SetWindowRelativeMouseMode(window, locked)
    if !ok {
        log.error("Could not set mouse relative mode!")
    }
}
@(export)
get_pointer_lock :: proc() -> bool {
    return sdl3.GetWindowRelativeMouseMode(window)
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
