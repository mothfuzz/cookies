#+build js

package audio

//loaded fully, possibly spatial
Sound :: distinct u32
PlayingSound :: struct {
    id: u32, //4
    gen: u16, //2
    sound_id: Sound,
}
//streamed, omnipresent
Music :: distinct u32

foreign import audio "audio"
@(default_calling_convention="contextless")
foreign audio {
    load_sound :: proc(filedata: []u8) -> Sound ---
    play_sound_ptr :: proc(sound: Sound, looped: bool, playing_sound: ^PlayingSound) ---
    loop_sound :: proc(playing_sound: ^PlayingSound, looped: bool = true) ---
    stop_sound :: proc(playing_sound: ^PlayingSound, finish_playing: bool = false) ---
    pause_sound :: proc(playing_sound: ^PlayingSound) ---
    resume_sound :: proc(playing_sound: ^PlayingSound) ---

    /*
    play_sound_spatial :: proc(sound: Sound, position: [3]f32, looped: bool = false) -> PlayingSound ---
    set_sound_position :: proc(playing_sound: ^PlayingSound, position: [3]f32) ---
    set_listener_position :: proc(position: [3]f32) ---
    */

    load_music :: proc(filedata: []u8) -> Music ---
    play_music :: proc(music: Music, fade: int = 0) ---
    stop_music :: proc(fade: int = 0) ---
    pause_music :: proc(fade: int = 0) ---
    resume_music :: proc(fade: int = 0) ---
    queue_music :: proc(new_music: Music, fade_out: int = 0, fade_in: int = 0) ---
    music_playing :: proc() -> bool ---
}

init :: proc() {
    //no need on JS
}

play_sound :: proc(sound: Sound, looped: bool = false) -> (playing_sound: PlayingSound) {
    play_sound_ptr(sound, looped, &playing_sound)
    return
}
