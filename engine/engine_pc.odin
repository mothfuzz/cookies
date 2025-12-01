#+build !js
package engine

import "core:fmt"
import "core:time"
import "vendor:sdl3"

import "window"
import "graphics"
import "input"
import "audio"

boot :: proc(init: proc(), tick: proc(), draw: proc(f64), quit: proc()) {
    success := sdl3.Init({.VIDEO, .AUDIO})
    if !success {
        fmt.panicf("Unable to initialize SDL3")
    }
    defer sdl3.Quit()
    window.window = sdl3.CreateWindow("hehe", 640, 400, sdl3.WINDOW_RESIZABLE)
    defer sdl3.DestroyWindow(window.window)

    img := #load("icon.bmp")
    icon := sdl3.LoadBMP_IO(sdl3.IOFromConstMem(raw_data(img), len(img)), true)
    sdl3.SetWindowIcon(window.window, icon)
    sdl3.DestroySurface(icon)

    audio.init()

    graphics.init(window.get_wgpu_surface, window.get_size())
    //for hook in init_hooks {
        //hook()
    //}
    if init != nil {
        init()
    }

    then := sdl3.GetTicks()
    accumulator: f64 = 0
    interpolator: time.Tick = {}
    time.tick_lap_time(&interpolator)
    main_loop: for {
        e: sdl3.Event
        for sdl3.PollEvent(&e) {
            if e.type == .QUIT {
                break main_loop
            }
            if e.type == .WINDOW_RESIZED {
                graphics.configure_surface(window.get_size())
                graphics.configure_render_targets()
                /*for hook in resize_hooks {
                    hook()
                }*/
            }
            if e.type == .KEY_DOWN {
                input.keys_pressed[input.sdl2key(e)] = true
                input.keys_current[input.sdl2key(e)] = true
            }
            if e.type == .KEY_UP {
                input.keys_released[input.sdl2key(e)] = true
                input.keys_current[input.sdl2key(e)] = false
            }
            if e.type == .MOUSE_BUTTON_DOWN {
                if e.button.button == sdl3.BUTTON_LEFT {
                    input.mouse_buttons_pressed[.Left] = true
                    input.mouse_buttons_current[.Left] = true
                }
                if e.button.button == sdl3.BUTTON_MIDDLE {
                    input.mouse_buttons_pressed[.Middle] = true
                    input.mouse_buttons_current[.Middle] = true
                }
                if e.button.button == sdl3.BUTTON_RIGHT {
                    input.mouse_buttons_pressed[.Right] = true
                    input.mouse_buttons_current[.Right] = true
                }
            }
            if e.type == .MOUSE_BUTTON_UP {
                if e.button.button == sdl3.BUTTON_LEFT {
                    input.mouse_buttons_released[.Left] = true
                    input.mouse_buttons_current[.Left] = false
                }
                if e.button.button == sdl3.BUTTON_MIDDLE {
                    input.mouse_buttons_released[.Left] = true
                    input.mouse_buttons_current[.Middle] = false
                }
                if e.button.button == sdl3.BUTTON_RIGHT {
                    input.mouse_buttons_released[.Left] = true
                    input.mouse_buttons_current[.Right] = false
                }
            }
            if e.type == .MOUSE_MOTION {
                rect := window.get_size()
                input.mouse_position.x = i32(e.motion.x) - i32(rect.x)/2
                input.mouse_position.y = i32(rect.y)/2 - i32(e.motion.y)
            }
        }
        now := sdl3.GetTicks()
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
