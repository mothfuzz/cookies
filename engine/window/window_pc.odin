#+build !js

package window

import "core:strings"
import "core:time"
import "vendor:sdl2"

window: ^sdl2.Window

set_size :: proc(width: uint, height: uint) {
    sdl2.SetWindowSize(window, i32(width), i32(height))
}
get_size :: proc() -> [2]uint {
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

run :: proc(init: proc(), tick: proc(), draw: proc(f64), quit: proc()) {
    sdl2.Init(sdl2.INIT_EVERYTHING)
    defer sdl2.Quit()
    window = sdl2.CreateWindow("hehe", sdl2.WINDOWPOS_UNDEFINED, sdl2.WINDOWPOS_UNDEFINED, 640, 400, sdl2.WINDOW_SHOWN)
    defer sdl2.DestroyWindow(window)

    for hook in init_hooks {
        hook()
    }
    if init != nil {
        init()
    }

    then := sdl2.GetTicks()
    accumulator: f64 = 0
    interpolator: time.Tick = {}
    time.tick_lap_time(&interpolator)
    main_loop: for {
        e: sdl2.Event
        for sdl2.PollEvent(&e) {
            if e.type == .QUIT {
                break main_loop
            }
        }
        now := sdl2.GetTicks()
        accumulator += f64(now - then)
        then = now //when will then be now? soon.
        for ; accumulator > 0; accumulator -= 1000.0/f64(tick_rate) {
            time.tick_lap_time(&interpolator)
            for hook in pre_tick_hooks {
                hook()
            }
            if tick != nil {
                tick()
            }
            for hook in post_tick_hooks {
                hook()
            }
        }
        t := time.duration_seconds(time.tick_since(interpolator))*f64(tick_rate)
        for hook in draw_hooks {
            hook(t)
        }
        if draw != nil {
            draw(t)
        }
    }

    if quit != nil {
        quit()
    }
}
