package main

import "core:fmt"

//be sure to build the engine as a DLL first.

import lib "cookies:lib"
cookies: lib.Cookies

init :: proc "c" () {
    context = lib.get_context()
    fmt.println("Hi!!!")
}

tick :: proc "c" () {
    context = lib.get_context()
    if cookies.key_pressed(.Key_Escape) {
        fmt.println("Bye!!!")
        cookies.window_close()
    }
}

main :: proc() {
    lib.set_context(context)
    cookies = lib.init(true)
    cookies.set_tick_rate(60)
    cookies.boot(init, tick, nil, nil)
    lib.uninit(&cookies)
}
