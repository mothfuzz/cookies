package graphics

import "core:math/linalg"
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
    weight: f32,
    channels: []Animation_Channel_Instance,
}

Animation_Player :: struct {
    scene: ^Scene,
    instances: []Animation_Instance, //'now playing' bookkeeping
}

animate :: proc(scene: ^Scene) -> (anim: Animation_Player) {
    anim.scene = scene
    anim.instances = make([]Animation_Instance, len(scene.animations))
    //set duration to maximum timestamp
    for &a, i in anim.scene.animations {
        instance := &anim.instances[i]
        instance.channels = make([]Animation_Channel_Instance, len(a.channels))
        for &c, j in a.channels {
            for timestamp in c.input {
                if timestamp > instance.duration {
                    instance.duration = timestamp
                }
            }
        }
    }
    return
}

deanimate :: proc(anim: Animation_Player) {
    for a in anim.instances {
        delete(a.channels)
    }
    delete(anim.instances)
}

progress :: proc(anim: ^Animation_Player, dt: f64) {
    //for weighted quaternion sum per-node
    rot_accum := make([]quaternion128, len(anim.scene.nodes), context.temp_allocator) 

    //pass 1: set to bind pose
    for &a, i in anim.instances {
        if a.weight == 0 do continue
        source_channels := &anim.scene.animations[i].channels
        for &channel, c in a.channels {
            node := anim.scene.nodes[source_channels[c].target_node]
            trans := transform.write(anim.scene.tree, node)
            trans^ = node.original_trans
        }
    }
    //pass 2: accumulate transforms
    for &a, i in anim.instances {
        source_channels := &anim.scene.animations[i].channels

        if a.playing {
            a.current_time = a.current_time + f32(dt) * a.speed
            current_time := a.current_time
            //animate individual channels...
            for &channel, c in a.channels {
                source_channel := &source_channels[c]
                last_frame: uint = len(source_channel.input) - 1
                //handle looping/clamping
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
                    }
                }

                //actually progress animation, skipping any keyframes we missed with a large dt
                if a.speed > 0 {
                    for channel.next_frame < last_frame && a.current_time > source_channel.input[channel.next_frame] {
                        channel.prev_frame = channel.next_frame
                        channel.next_frame += 1
                    }
                }
                if a.speed < 0 {
                    for channel.next_frame > 0 && a.current_time < source_channel.input[channel.next_frame] {
                        channel.prev_frame = channel.next_frame
                        channel.next_frame -= 1
                    }
                }

                t: f32 = 0
                if channel.prev_frame != channel.next_frame {
                    prev_time := source_channel.input[channel.prev_frame]
                    next_time := source_channel.input[channel.next_frame]
                    t = clamp((a.current_time - prev_time) / (next_time - prev_time), 0, 1)
                }

                if a.weight == 0 do continue //still progress time, but skip calcs

                node := anim.scene.nodes[source_channel.target_node]
                trans := transform.write(anim.scene.tree, node)
                switch o in source_channel.output {
                case Keyframes_Translation:
                    prev_frame := o[channel.prev_frame]
                    next_frame := o[channel.next_frame]
                    translation := linalg.lerp(prev_frame, next_frame, t)
                    trans.translation += a.weight * (translation - node.original_trans.translation)
                case Keyframes_Rotation:
                    prev_frame := o[channel.prev_frame]
                    next_frame := o[channel.next_frame]
                    rotation := linalg.quaternion_slerp(prev_frame, next_frame, t)
                    delta := rotation * linalg.quaternion_inverse(node.original_trans.rotation)
                    new_rot := quaternion(x=a.weight*delta.x, y=a.weight*delta.y, z=a.weight*delta.z, w=a.weight*delta.w)
                    if linalg.dot(rot_accum[source_channel.target_node], new_rot) < 0 {
                        //make sure weights are all in the same hemisphere
                        new_rot = -new_rot
                    }
                    rot_accum[source_channel.target_node] += new_rot
                    //trans.rotation = rotation
                case Keyframes_Scale:
                    prev_frame := o[channel.prev_frame]
                    next_frame := o[channel.next_frame]
                    scale := linalg.lerp(prev_frame, next_frame, t)
                    trans.scale += a.weight * (scale - node.original_trans.scale)
                }
            }
        } else {
            //make sure to not loop between frames when stopped
            for &channel, c in a.channels {
                channel.prev_frame = channel.next_frame
                if a.weight == 0 do continue
                source_channel := &source_channels[c]
                node := anim.scene.nodes[source_channel.target_node]
                trans := transform.write(anim.scene.tree, node)
                switch o in source_channel.output {
                case Keyframes_Translation:
                    translation := o[channel.next_frame]
                    trans.translation += a.weight * (translation - node.original_trans.translation)
                case Keyframes_Rotation:
                    rotation := o[channel.next_frame]
                    delta := rotation * linalg.quaternion_inverse(node.original_trans.rotation)
                    new_rot := quaternion(x=a.weight*delta.x, y=a.weight*delta.y, z=a.weight*delta.z, w=a.weight*delta.w)
                    if linalg.dot(rot_accum[source_channel.target_node], new_rot) < 0 {
                        new_rot = -new_rot
                    }
                    rot_accum[source_channel.target_node] += new_rot
                    //trans.rotation = rotation
                case Keyframes_Scale:
                    scale := o[channel.next_frame]
                    trans.scale += a.weight * (scale - node.original_trans.scale)
                }
            }
        }
    }
    //now apply accumulated rotations...
    for &node, i in anim.scene.nodes {
        accum := rot_accum[i]
        if accum == 0 do continue
        trans := transform.write(anim.scene.tree, node)
        trans.rotation = linalg.normalize(accum) * node.original_trans.rotation
    }
}
import "core:fmt"

play :: proc(anim: ^Animation_Player, id: int, looping: bool = false, speed: f32 = 1.0, weight: f32 = 1.0) {
    a := &anim.instances[id]
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
    a.weight = weight
}
stop :: proc(anim: ^Animation_Player, id: int, return_to_rest: bool = false) {
    a := &anim.instances[id]
    a.playing = false
    a.current_time = 0
    for &c, i in a.channels {
        c.next_frame = 0
        c.prev_frame = 0
        if return_to_rest {
            source_channel := &anim.scene.animations[id].channels[i]
            node := &anim.scene.nodes[source_channel.target_node]
            trans := transform.write(anim.scene.tree, node)
            trans^ = node.original_trans
        }
    }
}
pause :: proc(anim: ^Animation_Player, id: int) {
    anim.instances[id].playing = false
}
resume :: proc(anim: ^Animation_Player, id: int) {
    anim.instances[id].playing = true
}
