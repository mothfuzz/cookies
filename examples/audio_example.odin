package main

import "../engine"
import "../engine/window"
import "../engine/input"
import "../engine/audio"

import "core:fmt"

bonk: audio.Sound
bonk_playing: audio.PlayingSound
music: [dynamic]audio.Sound = {}
now_playing: int = 0
now_playing_sound: audio.PlayingSound
previously_playing_sound: audio.PlayingSound

init :: proc() {
    bonk = audio.make_sound_from_file(#load("bonk.wav"))
    append(&music, audio.make_sound_from_file(#load("eh.mp3")))
    append(&music, audio.make_sound_from_file(#load("stop_time.ogg")))
    fmt.println(music)
    fmt.println("bonk", bonk)
    window.set_size(320, 200)
    window.set_title("hahehe")
    now_playing_sound = audio.play_sound(music[now_playing], true, 1000);
}

tick :: proc() {
    if input.key_pressed(.Key_B) {
        bonk_playing = audio.play_sound(bonk, false)
    }
    if input.key_pressed(.Key_P) {
        if audio.sound_is_playing(&now_playing_sound) {
            fmt.println("pausing");
            audio.pause_sound(&now_playing_sound, 500)
        } else {
            fmt.println("playing");
            audio.resume_sound(&now_playing_sound, 500)
        }
    }
    if input.key_pressed(.Key_S) {
        audio.stop_sound(&now_playing_sound)
    }
    if input.key_pressed(.Key_K) {
        //for making sure music calls are non-blocking
        fmt.println("K!!!")
    }
    if input.key_pressed(.Key_Q) {
        fmt.println("queuing...")
        if previously_playing_sound != {} {
            //make sure to stop prior sound if it was fading out
            audio.stop_sound(&previously_playing_sound)
        }
        previously_playing_sound = now_playing_sound
        audio.pause_sound(&previously_playing_sound, 1000)
        now_playing += 1
        now_playing %= len(music)
        now_playing_sound = audio.play_sound(music[now_playing], true, 1000)
    }
}

main :: proc() {
    engine.boot(init, tick, nil, nil)
}
