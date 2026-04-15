package lib

import "base:runtime"
import "core:dynlib"
import "cookies:engine"
import "cookies:window"
import "cookies:input"
Scancode :: input.Scancode
Mouse_Button :: input.Mouse_Button

glb_ctx: runtime.Context
ctx_init: bool = false


/* Okay... hm. To make this whole engine c-compatible we'll have to do a few things.
 * 1. wrap generics to use IDs/opaque types instead (maybe user callbacks for get_item_from_id?)
 * 2. make most things contextless, not that we need it anyway. Might just need wrapper procs.
 * 3. in scripting languages specifically, use dynamic dispatch in place of procedure groups.
 * 4. for functions returning slices, return pointer/length pair. Might have to use out-pointers.
 * 5. For every API in the engine, do this within the module so it's less of a headache.
 */

@(export)
set_context :: proc "c" (ctx: runtime.Context) {
    glb_ctx = ctx
    ctx_init = true
}
@(export)
get_context :: proc "c" () -> runtime.Context {
    return glb_ctx
}

user_init: proc "c" ()
user_tick: proc "c" ()
user_draw: proc "c" (f64, f64)
user_quit: proc "c" ()

_init :: proc() {
    if user_init != nil {
        user_init()
    }
}
_tick :: proc() {
    if user_tick != nil {
        user_tick()
    }
}
_draw :: proc(alpha: f64, delta: f64) {
    if user_draw != nil {
        user_draw(alpha, delta)
    }
}
_quit :: proc() {
    if user_quit != nil {
        user_quit()
    }
}

@(export)
boot :: proc "c" (init: proc"c"(), tick: proc"c"(), draw: proc"c"(f64, f64), quit: proc"c"()) {
    context = get_context()

    user_init = init
    user_tick = tick
    user_draw = draw
    user_quit = quit

    engine.boot(_init, _tick, _draw, _quit)
}

//the whole engine goes here...
Cookies :: struct {
    __handle: dynlib.Library,
    set_context: type_of(set_context),
    get_context: type_of(get_context),
    //engine
    boot: type_of(boot),
    set_tick_rate: type_of(engine.set_tick_rate),
    //window
    window_close: type_of(window.close),
    window_get_size: type_of(window.get_size),
    window_set_size: type_of(window.set_size),
    window_set_title: type_of(window.set_title),
    //input
    key_down: type_of(input.key_down),
    key_up: type_of(input.key_up),
    key_pressed: type_of(input.key_pressed),
    key_released: type_of(input.key_released),
    mouse_down: type_of(input.mouse_down),
    mouse_up: type_of(input.mouse_up),
    mouse_pressed: type_of(input.mouse_pressed),
    mouse_released: type_of(input.mouse_released),
    mouse_position: type_of(input.mouse_position),
}

cookies_lib := Cookies{
    //engine
    boot = boot,
    set_tick_rate = engine.set_tick_rate,
    //window
    window_close = window.close,
    window_get_size = window.get_size,
    window_set_size = window.set_size,
    window_set_title = window.set_title,
    //input
    key_down = input.key_down,
    key_up = input.key_up,
    key_pressed = input.key_pressed,
    key_released = input.key_released,
    mouse_down = input.mouse_down,
    mouse_up = input.mouse_up,
    mouse_pressed = input.mouse_pressed,
    mouse_released = input.mouse_released,
    mouse_position = input.mouse_position,
}

import "core:fmt"
@(export)
init :: proc "c" (dyn: bool = false) -> (cookies: Cookies) {
    if !ctx_init {
        set_context(runtime.default_context())
    }
    context = get_context()
    if(dyn) {
        fmt.println("attempting to load engine library.")
        count, ok := dynlib.initialize_symbols(&cookies, "./cookies")
        if ok {
            fmt.println("loaded", count, "procs from cookies.")
            cookies.set_context(get_context()) //the lib ctx is different from the dll's own ctx.
            return
        } else {
            fmt.eprintln("Failed to load library! Falling back to static procs.")
        }
    }
    cookies = cookies_lib
    return
}

@(export)
uninit :: proc "c" (cookies: ^Cookies) {
    context = runtime.default_context()
    did_unload := dynlib.unload_library(cookies.__handle)
    if !did_unload {
        fmt.eprintln("Failed to unload engine library!")
    }
}




/*
import "cookies:audio"
Sound :: audio.Sound
Playing_Sound :: audio.Playing_Sound
make_sound_from_file: type_of(audio.make_sound_from_file) = audio.make_sound_from_file
delete_sound: type_of(audio.delete_sound) = audio.delete_sound
play_sound: type_of(audio.play_sound) = audio.play_sound
stop_sound: type_of(audio.stop_sound) = audio.stop_sound
pause_sound: type_of(audio.pause_sound) = audio.pause_sound
resume_sound: type_of(audio.resume_sound) = audio.resume_sound
loop_sound: type_of(audio.loop_sound) = audio.loop_sound
sound_is_playing: type_of(audio.sound_is_playing) = audio.sound_is_playing
sound_is_looping: type_of(audio.sound_is_looping) = audio.sound_is_looping

import "cookies:transform"
Transform :: transform.Transform
TRANSFORM_ORIGIN :: transform.ORIGIN
init_transform: type_of(transform.init) = transform.init
compute_transform: type_of(transform.compute) = transform.compute
smooth_transform: type_of(transform.smooth) = transform.smooth
extract_transform: type_of(transform.extract) = transform.extract
link_transform: type_of(transform.link) = transform.link
unlink_transform: type_of(transform.unlink) = transform.unlink
translate: type_of(transform.translate) = transform.translate
set_position: type_of(transform.set_position) = transform.set_position
get_position: type_of(transform.get_position) = transform.get_position
rotate: type_of(transform.rotate) = transform.rotate
rotatex: type_of(transform.rotatex) = transform.rotatex
rotatey: type_of(transform.rotatey) = transform.rotatey
rotatez: type_of(transform.rotatez) = transform.rotatez
set_orientation: type_of(transform.set_orientation) = transform.set_orientation
set_orientation_quaternion: type_of(transform.set_orientation_quaternion) = transform.set_orientation_quaternion
get_orientation: type_of(transform.get_orientation) = transform.get_orientation
get_orientation_quaternion: type_of(transform.get_orientation_quaternion) = transform.get_orientation_quaternion
scale: type_of(transform.scale) = transform.scale
set_scale: type_of(transform.set_scale) = transform.set_scale
get_scale: type_of(transform.get_scale) = transform.get_scale

import "cookies:spatial"
//I don't wanna do this right now :3

import "cookies:graphics"
//nor this.

//for the prior 2 modules I need to @(private) a LOT of stuff before I start to expose them
*/
