package main

import "../engine"
import "../engine/window"
import "../engine/input"
import "../engine/audio"

import "core:fmt"

bonk: audio.Sound
bonk_playing: audio.PlayingSound
music: [dynamic]audio.Music = {}
now_playing: int = 0

init :: proc() {
    bonk = audio.load_sound(#load("bonk.wav"))
    append(&music, audio.load_music(#load("eh.mp3")))
    append(&music, audio.load_music(#load("stop_time.ogg")))
    fmt.println(music)
    fmt.println("bonk", bonk)
    window.set_size(320, 200)
    window.set_title("hahehe")
    audio.play_music(music[now_playing], 1000);
}

tick :: proc() {
    if input.key_pressed(.Key_B) {
        bonk_playing = audio.play_sound(bonk, false)
    }
    if input.key_pressed(.Key_P) {
        if audio.music_playing() {
            fmt.println("pausing");
            audio.pause_music(500)
        } else {
            fmt.println("playing");
            audio.resume_music(500)
        }
    }
    if input.key_pressed(.Key_S) {
        audio.stop_music(1000)
    }
    if input.key_pressed(.Key_K) {
        //for making sure music calls are non-blocking
        fmt.println("K!!!")
    }
    if input.key_pressed(.Key_Q) {
        fmt.println("queuing...")
        now_playing += 1
        now_playing %= len(music)
        audio.queue_music(music[now_playing], 1000, 1000)
    }
}

main :: proc() {
    engine.boot(init, tick, nil, nil)
}
