#+build js

package audio

Sound :: distinct u32
Playing_Sound :: struct #packed {
    id: u32, //4
    gen: u16, //2
    sound_id: Sound, //4
    //local data needed to 'reset' sound if it was freed
    is_spatial: u32, //4
    position_x: f32, //4
    position_y: f32, //4
    position_z: f32, //4
    min_distance: f32, //4
    max_distance: f32, //4
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

    set_sound_position_xyz :: proc(playing_sound: ^Playing_Sound, x, y, z: f32) ---
    set_sound_min_distance :: proc(playing_sound: ^Playing_Sound, d: f32) ---
    set_sound_max_distance :: proc(playing_sound: ^Playing_Sound, d: f32) ---
    set_listener_position_xyz :: proc(x, y, z: f32) ---
    set_listener_orientation_xyz :: proc(fx, fy, fz, ux, uy, uz: f32) ---
    set_global_min_distance :: proc(d: f32) ---
    set_global_max_distance :: proc(d: f32) ---
}

play_sound :: proc(sound: Sound, looped: bool = false, fade_in: uint = 0) -> (playing_sound: Playing_Sound) {
    play_sound_ptr(sound, looped, fade_in, &playing_sound)
    return
}

set_sound_position :: proc(ps: ^Playing_Sound, position: [3]f32) {
    set_sound_position_xyz(ps, expand_values(position))
}
play_sound_spatial :: proc(sound: Sound, position: [3]f32, looped: bool = false, fade_in: uint = 0) -> (playing_sound: Playing_Sound) {
    play_sound_ptr(sound, looped, fade_in, &playing_sound)
    set_sound_position(&playing_sound, position)
    return
}

set_listener_position :: proc(position: [3]f32) {
    set_listener_position_xyz(expand_values(position))
}
set_listener_orientation :: proc(direction: [3]f32, up: [3]f32 = {0, 1, 0}) {
    set_listener_orientation_xyz(expand_values(direction), expand_values(up))
}
