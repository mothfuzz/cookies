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

Animation_Instance :: struct {
    anim: Animation,
    current_time: f64,
    current_frame: int,
    playing: bool,
    looping: bool,
    speed: f64,
}

Animation_State :: struct {
    animations: []Animation_Instance,
}

animate :: proc(scene: ^Scene) -> (anim: Animation_State) {
    //anim.animations = make([]Animation_Instance, len(scene.animations))
    for &a, i in anim.animations {
        //a.anim = scene.animations[i]
        a.speed = 1.0
    }
    return
}

play :: proc(a: ^Animation_State, id: int, looping: bool = false, speed: f64 = 1.0) {
    anim := &a.animations[id]
    anim.current_time = 0
    anim.current_frame = 0
    anim.playing = true
    anim.looping = looping
    anim.speed = speed
}
stop :: proc(a: ^Animation_State, id: int) {
    anim := &a.animations[id]
    anim.playing = false
    anim.current_time = 0
    anim.current_frame = 0
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
