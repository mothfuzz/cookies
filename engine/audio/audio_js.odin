#+build js

package audio

import "core:fmt"

Sound :: distinct u32
PlayingSound :: struct #packed {
    id: u32, //4
    gen: u16, //2
    sound_id: Sound,
}

foreign import audio "audio"
@(default_calling_convention="contextless")
foreign audio {
    make_sound_from_file :: proc(filedata: []u8) -> Sound ---
    delete_sound :: proc(sound: Sound) ---
    play_sound_ptr :: proc(sound: Sound, looped: bool, fade_in: uint, playing_sound: ^PlayingSound) ---
    loop_sound :: proc(playing_sound: ^PlayingSound, looped: bool = true) ---
    sound_is_looping :: proc(playing_sound: ^PlayingSound) -> bool ---
    stop_sound :: proc(playing_sound: ^PlayingSound, finish_playing: bool = false) ---
    sound_is_playing :: proc(playing_sound: ^PlayingSound) -> bool ---
    pause_sound :: proc(playing_sound: ^PlayingSound, fade_out: uint = 0) ---
    resume_sound :: proc(playing_sound: ^PlayingSound, fade_in: uint = 0) ---
    quit :: proc() ---

    /*
    play_sound_spatial :: proc(sound: Sound, position: [3]f32, looped: bool = false) -> PlayingSound ---
    set_sound_position :: proc(playing_sound: ^PlayingSound, position: [3]f32) ---
    set_listener_position :: proc(position: [3]f32) ---
    */
}

play_sound :: proc(sound: Sound, looped: bool = false, fade_in: uint = 0) -> (playing_sound: PlayingSound) {
    play_sound_ptr(sound, looped, fade_in, &playing_sound)
    return
}
