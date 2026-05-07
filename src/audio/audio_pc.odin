#+build !js

package audio

import "base:runtime"
import "vendor:sdl3"
import ma "vendor:miniaudio"
import "core:fmt"

Sound :: struct {
    frames_len: u64,
    frames_ptr: rawptr, //should be freed
    format: ma.format,
    channels: u32,
    sample_rate: u32,
}
Playing_Sound :: struct {
    data: Sound,
    sound: ^ma.sound,
    audio_buffer: ^ma.audio_buffer,
    is_spatial: bool,
    position: [3]f32,
    //0 = use global distance
    min_distance: f32,
    max_distance: f32,
}

ctx: runtime.Context
engine: ma.engine
live_sounds: map[^ma.sound]Playing_Sound
dead_sounds: map[^ma.sound]Playing_Sound
global_min_distance: f32 = 1.0
global_max_distance: f32 = 20.0

data_callback :: proc "c" (userdata: rawptr, buffer: [^]u8, buffer_size_bytes: i32) {
    context = (^runtime.Context)(userdata)^
    buffer_size_frames := u64(buffer_size_bytes) / u64(ma.get_bytes_per_frame(.f32, ma.engine_get_channels(&engine)))
    ma.engine_read_pcm_frames(&engine, buffer, buffer_size_frames, nil)
}
sdl_audio_callback :: proc "c" (userdata: rawptr, stream: ^sdl3.AudioStream, additional_amount: i32, total_amount: i32) {
    context = (^runtime.Context)(userdata)^
    if additional_amount > 0 {
        data := make([]u8, additional_amount, context.temp_allocator)
        data_callback(userdata, raw_data(data), additional_amount)
        sdl3.PutAudioStreamData(stream, raw_data(data), additional_amount)
    }
}


init :: proc() {
    engine_config := ma.engine_config_init()
    engine_config.channels = 2
    engine_config.sampleRate = 48000
    engine_config.listenerCount = 1
    engine_config.noDevice = true

    engine_init_result := ma.engine_init(&engine_config, &engine)
    if engine_init_result != .SUCCESS {
        fmt.panicf("failed to init audio engine: %v", engine_init_result)
    }

    ctx = context
    spec := sdl3.AudioSpec{.F32, i32(ma.engine_get_channels(&engine)), i32(ma.engine_get_sample_rate(&engine))}
    stream := sdl3.OpenAudioDeviceStream(sdl3.AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, sdl_audio_callback, &ctx)
    sdl3.ResumeAudioDevice(sdl3.GetAudioStreamDevice(stream))
}

quit :: proc() {
    //fmt.println("live_sounds:", len(live_sounds))
    //fmt.println("dead_sounds:", len(dead_sounds))
    for _, sound in live_sounds {
        ma.sound_uninit(sound.sound)
        ma.audio_buffer_uninit(sound.audio_buffer)
    }
    for _, sound in dead_sounds {
        ma.sound_uninit(sound.sound)
        ma.audio_buffer_uninit(sound.audio_buffer)
    }
    ma.engine_uninit(&engine)
}

make_sound_from_file :: proc(filedata: []u8) -> (sound: Sound) {
    frames_len: u64
    frames_ptr: rawptr
    decoder_config: ma.decoder_config
    result := ma.decode_memory(raw_data(filedata), len(filedata), &decoder_config, &sound.frames_len, &sound.frames_ptr)
    if(result != .SUCCESS) {
        fmt.panicf("failed to load sound: %v", result)
    }
    sound.format = decoder_config.format
    sound.channels = decoder_config.channels
    sound.sample_rate = decoder_config.sampleRate
    return
}
delete_sound :: proc(sound: Sound) {
    //miniaudio doesn't want us to free the memory actually
    //free(sound.frames_ptr)
}

@(private)
get_new_sound :: proc() -> (playing_sound: Playing_Sound) {
    for key, sound in dead_sounds {
        playing_sound = sound
        //free old sound
        ma.sound_uninit(sound.sound)
        ma.audio_buffer_uninit(sound.audio_buffer)
        //free(sound.audio_buffer)
        delete_key(&dead_sounds, key)
        break
    }
    if playing_sound.sound == nil {
        playing_sound.sound = new(ma.sound)
    }
    live_sounds[playing_sound.sound] = playing_sound
    return
}

@(private)
sound_end :: proc "c" (pUserData: rawptr, pSound: ^ma.sound) {
    context = (^runtime.Context)(pUserData)^
    playing_sound := live_sounds[pSound]
    delete_key(&live_sounds, pSound)
    dead_sounds[pSound] = playing_sound
}

play_sound :: proc(sound: Sound, looped: bool = false, fade_in: uint = 0) -> (playing_sound: Playing_Sound){
    playing_sound = get_new_sound()
    playing_sound.data = sound

    audio_buffer_config := ma.audio_buffer_config{
        format = sound.format,
        channels = sound.channels,
        sampleRate = sound.sample_rate,
        sizeInFrames = sound.frames_len,
        pData = sound.frames_ptr,
    }
    ma.audio_buffer_alloc_and_init(&audio_buffer_config, &playing_sound.audio_buffer)

    sound_config := ma.sound_config_init_2(&engine)
    sound_config.flags = {.STREAM}
    sound_config.pDataSource = playing_sound.audio_buffer.ref.ds.pCurrent
    sound_config.endCallback = sound_end
    ctx = context
    sound_config.pEndCallbackUserData = &ctx
    sound_config.isLooping = b32(looped)
    sound_result := ma.sound_init_ex(&engine, &sound_config, playing_sound.sound)
    if sound_result != .SUCCESS {
        fmt.panicf("failed to init sound file from memory: %v", sound_result)
    }
    ma.sound_set_fade_in_milliseconds(playing_sound.sound, 0.0, 1.0, u64(fade_in))
    ma.sound_start(playing_sound.sound)
    return
}

@(private)
replay_sound :: proc(playing_sound: ^Playing_Sound, looped: bool, fade_in: uint) {
    if playing_sound.is_spatial {
        position := playing_sound.position
        min_distance := playing_sound.min_distance
        max_distance := playing_sound.max_distance
        playing_sound^ = play_sound(playing_sound.data, looped, fade_in)
        playing_sound.position = position
        playing_sound.min_distance = min_distance
        playing_sound.max_distance = max_distance
        set_sound_spatial(playing_sound)
    } else {
        playing_sound^ = play_sound(playing_sound.data, looped, fade_in)
    }
}

loop_sound :: proc(playing_sound: ^Playing_Sound, looped: bool = true) {
    if playing_sound.sound in live_sounds {
        ma.sound_set_looping(playing_sound.sound, b32(looped))
    } else {
        replay_sound(playing_sound, looped, 0)
    }
}
sound_is_looping :: proc(playing_sound: ^Playing_Sound) -> bool {
    if playing_sound.sound in live_sounds {
        return bool(ma.sound_is_looping(playing_sound.sound))
    } else {
        return false
    }
}

stop_sound :: proc(playing_sound: ^Playing_Sound, finish_playing: bool = false) {
    if playing_sound.sound in live_sounds {
        if finish_playing {
            ma.sound_set_looping(playing_sound.sound, false)
        } else {
            ma.sound_stop(playing_sound.sound)
            ma.sound_seek_to_pcm_frame(playing_sound.sound, 0)
            //move to dead since sound_stop doesn't call the sound_end callback
            delete_key(&live_sounds, playing_sound.sound)
            dead_sounds[playing_sound.sound] = playing_sound^
        }
    }
}

sound_is_playing :: proc(playing_sound: ^Playing_Sound) -> bool {
    if playing_sound.sound in live_sounds {
        return bool(ma.sound_is_playing(playing_sound.sound))
    }
    return false
}

pause_sound :: proc(playing_sound: ^Playing_Sound, fade_out: uint = 0) {
    if playing_sound.sound in live_sounds {
        if fade_out > 0 {
            ma.sound_stop_with_fade_in_milliseconds(playing_sound.sound, u64(fade_out))
        } else {
            ma.sound_stop(playing_sound.sound)
        }
    }
}
resume_sound :: proc(playing_sound: ^Playing_Sound, fade_in: uint = 0) {
    if playing_sound.sound in live_sounds {
        ma.sound_set_stop_time_in_milliseconds(playing_sound.sound, ~u64(0)) //workaround for if sound was scheduled to stop
        if fade_in > 0 {
            ma.sound_set_fade_in_milliseconds(playing_sound.sound, -1, 1.0, u64(fade_in))
        } else {
            ma.sound_start(playing_sound.sound)
        }
    } else {
        replay_sound(playing_sound, false, fade_in)
    }
}

@(private)
set_sound_spatial :: proc(playing_sound: ^Playing_Sound) {
    playing_sound.is_spatial = true
    ma.sound_set_position(playing_sound.sound, expand_values(playing_sound.position))
    mnd := playing_sound.min_distance==0?global_min_distance:playing_sound.min_distance
    mxd := playing_sound.max_distance==0?global_max_distance:playing_sound.max_distance
    ma.sound_set_min_distance(playing_sound.sound, mnd)
    ma.sound_set_max_distance(playing_sound.sound, mxd)
}

set_sound_position :: proc(playing_sound: ^Playing_Sound, position: [3]f32) {
    playing_sound.position = position
    set_sound_spatial(playing_sound)
}

set_sound_min_distance :: proc(playing_sound: ^Playing_Sound, d: f32) {
    playing_sound.min_distance = d
    set_sound_spatial(playing_sound)
}
set_sound_max_distance :: proc(playing_sound: ^Playing_Sound, d: f32) {
    playing_sound.max_distance = d
    set_sound_spatial(playing_sound)
}

set_listener_position :: proc(position: [3]f32, listener_index: uint = 0) {
    ma.engine_listener_set_position(&engine, u32(listener_index), expand_values(position))
}

set_listener_orientation :: proc(direction: [3]f32, up: [3]f32 = {0, 1, 0}, listener_index: uint = 0) {
    ma.engine_listener_set_direction(&engine, u32(listener_index), expand_values(direction))
    if up != {0, 1, 0} {
        ma.engine_listener_set_world_up(&engine, u32(listener_index), expand_values(up))
    }
}

set_global_min_distance :: proc(d: f32) {
    global_min_distance = d
    for ma_sound, sound in live_sounds {
        ma.sound_set_min_distance(ma_sound, sound.min_distance==0?global_min_distance:sound.min_distance)
    }
}
set_global_max_distance :: proc(d: f32) {
    global_max_distance = d
    for ma_sound, sound in live_sounds {
        ma.sound_set_max_distance(ma_sound, sound.max_distance==0?global_max_distance:sound.max_distance)
    }
}
