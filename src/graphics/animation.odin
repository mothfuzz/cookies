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
    scene: ^Scene,
    animations: []Animation_Instance,
}

animate :: proc(scene: ^Scene) -> (anim: Animation_State) {
    anim.scene = scene
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

deanimate :: proc(anim: ^Animation_State) {
    for &a in anim.animations {
        delete(a.channels)
    }
    delete(anim.animations)
}

@(private)
progress :: proc(anim: ^Animation_State, dt: f64) {
    for &a, i in anim.animations {
        if a.playing {
            a.current_time = a.current_time + f32(dt) * a.speed
            current_time := a.current_time
            //animate individual channels...
            source_channels := &anim.scene.animations[i].channels
            for &channel, c in a.channels {
                source_channel := &source_channels[c]
                last_frame: uint = len(source_channel.input) - 1
                if a.speed > 0 {
                    if current_time > a.duration {
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
                    if current_time < 0 {
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

                t: f32 = 0
                if channel.prev_frame != channel.next_frame {
                    prev_time := source_channel.input[channel.prev_frame]
                    next_time := source_channel.input[channel.next_frame]
                    t = (a.current_time - prev_time) / (next_time - prev_time)
                }
                //note: even though it's interpolated already,
                //we're doing additional interpolation in the transform itself
                //in case of switching animations or other active transforms
                switch o in source_channel.output {
                case Keyframes_Translation:
                    prev_frame := o[channel.prev_frame]
                    next_frame := o[channel.next_frame]
                    translation := linalg.lerp(prev_frame, next_frame, t)
                    transform.set_position(&anim.scene.nodes[source_channel.target_node].transform, translation, true)
                case Keyframes_Rotation:
                    prev_frame := o[channel.prev_frame]
                    next_frame := o[channel.next_frame]
                    rotation := linalg.quaternion_slerp(prev_frame, next_frame, t)
                    transform.set_orientation_quaternion(&anim.scene.nodes[source_channel.target_node].transform, rotation, true)
                case Keyframes_Scale:
                    prev_frame := o[channel.prev_frame]
                    next_frame := o[channel.next_frame]
                    scale := linalg.lerp(prev_frame, next_frame, t)
                    transform.set_scale(&anim.scene.nodes[source_channel.target_node].transform, scale, true)
                }
            }
        }
    }
}


play :: proc(anim: ^Animation_State, id: int, looping: bool = false, speed: f32 = 1.0) {
    a := &anim.animations[id]
    a.current_time = 0
    for &c, i in a.channels {
        last_frame := uint(len(anim.scene.animations[id].channels[i].input)) - 1
        if speed > 0 {
            c.next_frame = min(1, last_frame)
            c.prev_frame = 0
        } else {
            c.next_frame = last_frame
            c.prev_frame = 0
        }
    }
    a.playing = true
    a.looping = looping
    a.speed = speed
}
stop :: proc(anim: ^Animation_State, id: int, return_to_rest: bool = false) {
    a := &anim.animations[id]
    a.playing = false
    a.current_time = 0
    for &c, i in a.channels {
        c.next_frame = 0
        c.prev_frame = 0
        if return_to_rest {
            source_channel := &anim.scene.animations[id].channels[i]
            node := &anim.scene.nodes[source_channel.target_node]
            transform.set_position(&node.transform, node.original_position, true)
            transform.set_orientation_quaternion(&node.transform, node.original_orientation, true)
            transform.set_scale(&node.transform, node.original_scale, true)
        }
    }
}
pause :: proc(anim: ^Animation_State, id: int) {
    anim.animations[id].playing = false
}
resume :: proc(anim: ^Animation_State, id: int) {
    anim.animations[id].playing = true
}

//graphics.animate(&my_scene) -> Animation_State
//graphics.play(&anim, 0, looping=true, speed=0.5)
//graphics.stop(&anim, 0)
//graphics.draw_scene(&my_scene, t, root_transform, &animation_state) //will animate according to that...

//also support similar API for animating textures even if the underlying behaviour is different.
