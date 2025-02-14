#+build !js

package audio

import "vendor:sdl2"
import "vendor:sdl2/mixer"
import "core:fmt"
import "core:math"
import "base:runtime"

Sound :: ^mixer.Chunk
Music :: ^mixer.Music
PlayingSound :: struct {
    channel: i32,
    gen: u16,
    sound: Sound,
}
ActiveChannel :: struct {
    gen: u16,
    looping: bool,
    sound: Sound,
}
active_channels: map[i32]ActiveChannel = {}
active_music: Music
music_playing_flag: bool = false
music_played: f64 = 0.0
music_paused: f64 = 0.0
music_looped: bool = true
music_fade_in: int = 0

finished :: proc "c" (channel: i32) {
    if active_channel, ok := &active_channels[channel]; ok {
        if active_channel.looping {
            mixer.PlayChannel(channel, active_channel.sound, 0)
        } else {
            active_channel.gen += 1
        }
    }
}

music_finished :: proc "c" () {

    if music_playing_flag {
        play_music(active_music)
        return
    }

    if music_played > 0 {
        music_paused = f64(sdl2.GetTicks())/1000.0 - music_played
        music_played = 0
    }
    if music_fade_in > 0 {
        resume_music(music_fade_in)
        music_fade_in = 0
    }


}

init :: proc() {
    mixer.OpenAudio(mixer.DEFAULT_FREQUENCY, mixer.DEFAULT_FORMAT, mixer.DEFAULT_CHANNELS, 128)
    mixer.ChannelFinished(finished)
    mixer.HookMusicFinished(music_finished)
}

load_sound :: proc(filedata: []u8) -> Sound {
    return mixer.LoadWAV_RW(sdl2.RWFromMem(raw_data(filedata), i32(len(filedata))), true)
}

play_sound :: proc(sound: Sound, looped: bool = false) -> PlayingSound {
    num_channels := mixer.AllocateChannels(-1)
    if num_channels < i32(len(active_channels) + 1) {
        mixer.AllocateChannels(num_channels * 2)
    }
    //can't use the built-in looping because we want to be able to start and stop it after the fact
    //channel := mixer.PlayChannel(-1, sound, looped? -1 : 0)
    channel := mixer.PlayChannel(-1, sound, 0)
    playing_sound := PlayingSound{channel, 0, sound}
    if active_channel, ok := &active_channels[channel]; ok {
        playing_sound.gen = active_channel.gen
        active_channel.looping = looped
        active_channel.sound = sound
    } else {
        active_channels[channel] = ActiveChannel{0, looped, sound}
    }
    fmt.println(playing_sound)
    return playing_sound
}
loop_sound :: proc(playing_sound: ^PlayingSound, looped: bool = true) {
    if active_channel, ok := &active_channels[playing_sound.channel]; ok {
        if active_channel.gen == playing_sound.gen {
            //sound is live, loop it
            active_channel.looping = looped
        } else {
            //sound is dead, replay a new sound if we set loop on
            if looped {
                playing_sound^ = play_sound(playing_sound.sound, looped)
            }
        }
    }
}
stop_sound :: proc(playing_sound: ^PlayingSound, finish_playing: bool = false) {
    if active_channel, ok := &active_channels[playing_sound.channel]; ok {
        if active_channel.gen == playing_sound.gen {
            active_channel.looping = false
            if !finish_playing {
                mixer.HaltChannel(playing_sound.channel)
            }
        }
    }
}
pause_sound :: proc(playing_sound: ^PlayingSound) {
    if active_channel, ok := &active_channels[playing_sound.channel]; ok {
        if active_channel.gen == playing_sound.gen {
            mixer.Pause(playing_sound.channel)
        }
    }

}
resume_sound :: proc(playing_sound: ^PlayingSound) {
    if active_channel, ok := &active_channels[playing_sound.channel]; ok {
        if active_channel.gen == playing_sound.gen {
            mixer.Resume(playing_sound.channel)
        } else {
            //looped=false since if it were looping the sound wouldn't have died.
            playing_sound^ = play_sound(playing_sound.sound)
        }
    }
}

load_music :: proc(filedata: []u8) -> Music {
    return mixer.LoadMUS_RW(sdl2.RWFromMem(raw_data(filedata), i32(len(filedata))), true)
}

play_music :: proc "c" (music: Music, fade: int = 0) {
    active_music = music
    music_paused = 0
    resume_music(fade)
}
stop_music :: proc(fade: int = 0) {
    music_played = 0
    music_paused = 0
    pause_music(fade)
}
pause_music :: proc(fade: int = 0) {
    music_playing_flag = false
    if mixer.FadingMusic() == mixer.FADING_OUT {
        return;
    }
    mixer.FadeOutMusic(i32(fade))
}
resume_music :: proc "c" (fade: int = 0) {
    //only resume once pause fade completes because otherwise this blocks
    if mixer.FadingMusic() == mixer.NO_FADING {
        music_playing_flag = true
        mixer.FadeInMusic(active_music, 0, i32(fade))
        mixer.SetMusicPosition(music_paused)
        music_played = f64(sdl2.GetTicks())/1000.0 - music_paused
        music_paused = 0
    } else {
        music_fade_in = fade
    }
}
queue_music :: proc(new_music: Music, fade_out: int = 0, fade_in: int = 0) {
    stop_music(fade_out)
    play_music(new_music, fade_in)
}

music_playing :: proc "c" () -> bool {
    return music_playing_flag
}
