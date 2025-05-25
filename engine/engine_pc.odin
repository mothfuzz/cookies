#+build !js
package engine

import "core:fmt"
import "core:time"
import "vendor:sdl2"

import "window"
import "graphics"
import "input"
import "audio"

boot :: proc(init: proc(), tick: proc(), draw: proc(f64), quit: proc()) {
    sdl2.Init(sdl2.INIT_EVERYTHING)
    defer sdl2.Quit()
    window.window = sdl2.CreateWindow("hehe", sdl2.WINDOWPOS_UNDEFINED, sdl2.WINDOWPOS_UNDEFINED, 640, 400, sdl2.WINDOW_SHOWN | sdl2.WINDOW_RESIZABLE)
    defer sdl2.DestroyWindow(window.window)

    img := #load("icon.bmp")
    icon := sdl2.LoadBMP_RW(sdl2.RWFromConstMem(raw_data(img), i32(len(img))), true)
    sdl2.SetWindowIcon(window.window, icon)
    sdl2.FreeSurface(icon)

    audio.init()

    graphics.init(window.get_wgpu_surface, window.get_size())
    //for hook in init_hooks {
        //hook()
    //}
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
            if e.type == .WINDOWEVENT {
                if e.window.event == .RESIZED {
                    graphics.configure_surface(window.get_size())
                    /*for hook in resize_hooks {
                        hook()
                    }*/
                }
            }
            if e.type == .KEYDOWN {
                input.keys_pressed[input.sdl2key(e)] = true
                input.keys_current[input.sdl2key(e)] = true
            }
            if e.type == .KEYUP {
                input.keys_released[input.sdl2key(e)] = true
                input.keys_current[input.sdl2key(e)] = false
            }
            if e.type == .MOUSEBUTTONDOWN {
                if e.button.button == sdl2.BUTTON_LEFT {
                    input.mouse_buttons_pressed[.Left] = true
                    input.mouse_buttons_current[.Left] = true
                }
                if e.button.button == sdl2.BUTTON_MIDDLE {
                    input.mouse_buttons_pressed[.Middle] = true
                    input.mouse_buttons_current[.Middle] = true
                }
                if e.button.button == sdl2.BUTTON_RIGHT {
                    input.mouse_buttons_pressed[.Right] = true
                    input.mouse_buttons_current[.Right] = true
                }
            }
            if e.type == .MOUSEBUTTONUP {
                if e.button.button == sdl2.BUTTON_LEFT {
                    input.mouse_buttons_released[.Left] = true
                    input.mouse_buttons_current[.Left] = false
                }
                if e.button.button == sdl2.BUTTON_MIDDLE {
                    input.mouse_buttons_released[.Left] = true
                    input.mouse_buttons_current[.Middle] = false
                }
                if e.button.button == sdl2.BUTTON_RIGHT {
                    input.mouse_buttons_released[.Left] = true
                    input.mouse_buttons_current[.Right] = false
                }
            }
            if e.type == .MOUSEMOTION {
                rect := window.get_size()
                input.mouse_position.x = e.motion.x - i32(rect.x)/2
                input.mouse_position.y = e.motion.y - i32(rect.y)/2
            }
        }
        now := sdl2.GetTicks()
        accumulator += f64(now - then)
        then = now //when will then be now? soon.
        for ; accumulator > 0; accumulator -= 1000.0/f64(tick_rate) {
            time.tick_lap_time(&interpolator)
            /*for hook in pre_tick_hooks {
                hook()
            }*/
            if tick != nil {
                tick()
            }
            /*for hook in post_tick_hooks {
                hook()
            }*/
            input.update()
        }
        t := time.duration_seconds(time.tick_since(interpolator))*f64(tick_rate)
        if draw != nil {
            draw(t)
        }
        graphics.render(t)
        /*for hook in draw_hooks {
            hook(t)
        }*/
    }

    if quit != nil {
        quit()
    }
    /*for hook in quit_hooks {
        hook()
    }*/
    graphics.quit()
    audio.quit()
}
