#+build js

package audio

Sound :: distinct u32
Playing_Sound :: struct #packed {
    id: u32, //4
    gen: u16, //2
    sound_id: Sound,
}

foreign import audio "audio"
@(default_calling_convention="contextless")
foreign audio {
    make_sound_from_file :: proc(filedata: []u8) -> Sound ---
    delete_sound :: proc(sound: Sound) ---
    play_sound_ptr :: proc(sound: Sound, looped: bool, fade_in: uint, playing_sound: ^Playing_Sound) ---
    loop_sound :: proc(playing_sound: ^Playing_Sound, looped: bool = true) ---
    sound_is_looping :: proc(playing_sound: ^Playing_Sound) -> bool ---
    stop_sound :: proc(playing_sound: ^Playing_Sound, finish_playing: bool = false) ---
    sound_is_playing :: proc(playing_sound: ^Playing_Sound) -> bool ---
    pause_sound :: proc(playing_sound: ^Playing_Sound, fade_out: uint = 0) ---
    resume_sound :: proc(playing_sound: ^Playing_Sound, fade_in: uint = 0) ---
    quit :: proc() ---

    /*
    play_sound_spatial :: proc(sound: Sound, position: [3]f32, looped: bool = false) -> Playing_Sound ---
    set_sound_position :: proc(playing_sound: ^Playing_Sound, position: [3]f32) ---
    set_listener_position :: proc(position: [3]f32) ---
    */
}

play_sound :: proc(sound: Sound, looped: bool = false, fade_in: uint = 0) -> (playing_sound: Playing_Sound) {
    play_sound_ptr(sound, looped, fade_in, &playing_sound)
    return
}
