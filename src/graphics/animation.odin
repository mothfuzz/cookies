package graphics

import "core:fmt"
import "vendor:cgltf"

Interpolation :: enum {
    Linear,
    Step,
    //Cubic_Spline, //not supported yet
}
Animation_Sampler :: struct {
    input: []f32, //timestamps
    output: []f32, //values at said timestamps
    interp: Interpolation,
}
Animation_Type :: enum {
    Translation,
    Rotation,
    Scale,
    //Weights, //not supported yet
}
Animation_Channel :: struct {
    sampler: int,
    target_node: int,
    type: Animation_Type,
}
Animation :: struct {
    name: string,
    samplers: []Animation_Sampler,
    channels: []Animation_Channel,
}

Animation_Instance :: struct {
    anim: Animation,
    current_time: f64,
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
    anim.playing = true
    anim.looping = looping
    anim.speed = speed
}
stop :: proc(a: ^Animation_State, id: int) {
    anim := &a.animations[id]
    anim.playing = false
    anim.current_time = 0
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
