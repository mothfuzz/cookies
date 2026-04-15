package graphics

import "core:fmt"
import "vendor:cgltf"

import "cookies:transform"
import "core:math/linalg"

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
    next_frame: uint,
    prev_frame: uint,
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

deanimate :: proc(a: ^Animation_State) {
    for &anim in a.animations {
        delete(anim.channels)
    }
    delete(a.animations)
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
                last_frame: uint = len(source_channel.input) - 1
                if a.speed > 0 {
                    if a.current_time > a.duration {
                        if a.looping {
                            a.current_time = 0
                            channel.next_frame = 0
                            channel.prev_frame = last_frame
                        } else {
                            a.current_time = a.duration
                            channel.next_frame = last_frame
                            channel.prev_frame = last_frame
                        }
                    } else {
                        next_frame := min(channel.next_frame + 1, last_frame)
                        if a.current_time > source_channel.input[next_frame] {
                            channel.prev_frame = channel.next_frame
                            channel.next_frame = next_frame
                        }
                    }
                }
                if a.speed < 0 {
                    if a.current_time < 0 {
                        if a.looping {
                            a.current_time = a.duration
                            channel.next_frame = last_frame
                            channel.prev_frame = 0
                        } else {
                            a.current_time = 0
                            channel.next_frame = 0
                            channel.prev_frame = 0
                        }
                    } else {
                        next_frame := max(channel.next_frame - 1, 0)
                        if a.current_time < source_channel.input[next_frame] {
                            channel.prev_frame = channel.next_frame
                            channel.next_frame = next_frame
                        }
                    }
                }

                // TODO: now all we gots to do is adjust the node's transform.
                //source_channel.target_node...
                prev_time := source_channel.input[channel.prev_frame]
                next_time := source_channel.input[channel.next_frame]
                t := (a.current_time - prev_time) / (next_time - prev_time)
                switch o in source_channel.output {
                case Keyframes_Translation:
                    prev_frame := o[channel.prev_frame]
                    next_frame := o[channel.next_frame]
                    translation := linalg.lerp(prev_frame, next_frame, t)
                    transform.set_position(&scene.nodes[source_channel.target_node].transform, translation)
                case Keyframes_Rotation:
                    prev_frame := o[channel.prev_frame]
                    next_frame := o[channel.next_frame]
                    rotation := linalg.quaternion_slerp(prev_frame, next_frame, t)
                    transform.set_orientation_quaternion(&scene.nodes[source_channel.target_node].transform, rotation)
                case Keyframes_Scale:
                    prev_frame := o[channel.prev_frame]
                    next_frame := o[channel.next_frame]
                    scale := linalg.lerp(prev_frame, next_frame, t)
                    transform.set_scale(&scene.nodes[source_channel.target_node].transform, scale)
                }
            }
        }
    }
}


play :: proc(a: ^Animation_State, id: int, looping: bool = false, speed: f32 = 1.0) {
    anim := &a.animations[id]
    anim.current_time = 0
    for &c in anim.channels {
        c.next_frame = 0
        c.prev_frame = 0
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
        c.next_frame = 0
        c.prev_frame = 0
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
