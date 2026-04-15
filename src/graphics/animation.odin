package graphics

import "core:fmt"
import "vendor:cgltf"

import "cookies:transform"

Interpolation :: enum {
    Linear,
    Step,
    //Cubic_Spline, //not supported yet
}

Keyframes_Translation :: distinct [][3]f32
Keyframes_Rotation :: distinct []quaternion128
Keyframes_Scale :: distinct [][3]f32
Keyframes :: union {
    Keyframes_Translation,
    Keyframes_Rotation,
    Keyframes_Scale,
    //Keyframes_Weights, //not supported yet
}
Animation_Channel :: struct {
    input: []f32, //timestamps
    output: Keyframes, //values at said timestamps
    interp: Interpolation,
    target_node: uint,
}
Animation :: struct {
    name: string,
    //samplers: []Animation_Sampler,
    channels: []Animation_Channel,
}

delete_animation :: proc(animation: Animation) {
    for channel in animation.channels {
        delete(channel.input)
        switch o in channel.output {
        case Keyframes_Translation:
            delete(o)
        case Keyframes_Rotation:
            delete(o)
        case Keyframes_Scale:
            delete(o)
        }
    }
    delete(animation.channels)
}

Animation_Channel_Instance :: struct {
    current_frame: uint,
}

Animation_Instance :: struct {
    //anim: uint, //not needed as it maps 1:1 with scene.animations
    current_time: f32,
    duration: f32, //max channel input timestamp
    playing: bool,
    looping: bool,
    speed: f32,
    channels: []Animation_Channel_Instance,
}

Animation_State :: struct {
    animations: []Animation_Instance,
}

animate :: proc(scene: ^Scene) -> (anim: Animation_State) {
    anim.animations = make([]Animation_Instance, len(scene.animations))
    //set duration to maximum timestamp
    for &a, i in scene.animations {
        anim.animations[i].channels = make([]Animation_Channel_Instance, len(a.channels))
        for &c in a.channels {
            for timestamp in c.input {
                if timestamp > anim.animations[i].duration {
                    anim.animations[i].duration = timestamp
                }
            }
        }
    }
    return
}

@(private)
progress :: proc(scene: ^Scene, a: ^Animation_State, dt: f64) {
    for &a, i in a.animations {
        if a.playing {
            a.current_time = a.current_time + f32(dt) * a.speed
            //animate individual channels...
            source_channels := &scene.animations[i].channels
            for &channel, c in a.channels {
                source_channel := &source_channels[c]
                if a.speed > 0 {
                    if a.current_time > a.duration {
                        if a.looping {
                            a.current_time = 0
                            channel.current_frame = 0
                        } else {
                            a.current_time = a.duration
                            channel.current_frame = len(source_channel.input)
                        }
                    } else {
                        next_frame := min(channel.current_frame + 1, uint(len(source_channel.input)))
                        if a.current_time > source_channel.input[next_frame] {
                            channel.current_frame = next_frame
                        }
                    }
                }
                if a.speed < 0 {
                    if a.current_time < 0 {
                        if a.looping {
                            a.current_time = a.duration
                            channel.current_frame = len(source_channel.input)
                        } else {
                            a.current_time = 0
                            channel.current_frame = 0
                        }
                    } else {
                        prev_frame := max(channel.current_frame - 1, 0)
                        if a.current_time < source_channel.input[prev_frame] {
                            channel.current_frame = prev_frame
                        }
                    }
                }
            }
        }
    }
}

play :: proc(a: ^Animation_State, id: int, looping: bool = false, speed: f32 = 1.0) {
    anim := &a.animations[id]
    anim.current_time = 0
    for &c in anim.channels {
        c.current_frame = 0
    }
    anim.playing = true
    anim.looping = looping
    anim.speed = speed
}
stop :: proc(a: ^Animation_State, id: int) {
    anim := &a.animations[id]
    anim.playing = false
    anim.current_time = 0
    for &c in anim.channels {
        c.current_frame = 0
    }
}
pause :: proc(a: ^Animation_State, id: int) {
    a.animations[id].playing = false
}
resume :: proc(a: ^Animation_State, id: int) {
    a.animations[id].playing = true
}

//graphics.animate(&my_scene) -> Animation_State
//graphics.play(&anim, 0, looping=true, speed=0.5)
//graphics.stop(&anim, 0)
//graphics.draw_scene(&my_scene, t, root_transform, &animation_state) //will animate according to that...

//also support similar API for animating textures even if the underlying behaviour is different.
