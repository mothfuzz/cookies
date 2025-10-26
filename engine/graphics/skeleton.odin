package graphics

import "core:math/linalg"

Bone :: struct {
    translation: [3]f32,
    rotation: quaternion128,
    scaling: [3]f32,

    id: int,
    children: []int,
}
Keyframe :: struct {
    translation: [3]f32,
    rotation: quaternion128,
    scaling: [3]f32,
    //weight animation not supported.

    start_time: f64,
    next_frame: ^Keyframe,
    prev_frame: ^Keyframe,
}
Animation :: struct {
    framerate: f64,
    duration: f64,
    keyframes: []Keyframe, //per bone
}

Skeleton :: struct {
    bones: []Bone,
    root_bone: int,
    bone_labels: map[string]int,
    animations: []Animation,
    animation_labels: map[string]int,
}

CurrentFrame :: struct {
    prev_frame: ^Keyframe,
    next_frame: ^Keyframe,
    dirty: bool,

    prev_translation: [3]f32,
    next_translation: [3]f32,
    prev_rotation: quaternion128,
    next_rotation: quaternion128,
    prev_scaling: [3]f32,
    next_scaling: [3]f32,
}

Animator :: struct {
    sk: ^Skeleton,
    speed_factor: f64, //multiplier of seconds
    current_time: f64,
    now_playing: int,
    looping: bool,
    current_frames: []CurrentFrame, //per bone so we don't have to do a search
    //SHOULD also be able to smoothly transition between different animations,
    //by setting next_frame to the first keyframe of the other animation
}

make_animator :: proc(sk: ^Skeleton) -> (a: Animator) {
    a.sk = sk
    a.current_frames = make([]CurrentFrame, len(sk.bones))
    return
}
delete_animator :: proc(a: ^Animator) {
    delete(a.current_frames)
}

animate :: proc(a: ^Animator, animation: string, speed: f64 = 1.0, looping: bool = false) {
    a.now_playing = a.sk.animation_labels[animation]
    a.current_time = 0
    a.looping = looping
}

animate_bone :: proc(a: ^Animator, bone_index: int, parent_world_trans: matrix[4,4]f32, output: ^[]matrix[4,4]f32) {
    bone := &a.sk.bones[bone_index]
    frame := &a.current_frames[bone_index]

    //>>
    if a.speed_factor > 0 {
        if frame.next_frame != nil && a.current_time > frame.next_frame.start_time {
            frame.next_frame = frame.next_frame.next_frame
            frame.prev_frame = frame.next_frame.prev_frame
            frame.dirty = true
        }
    }
    //<<
    if a.speed_factor < 0 {
        if frame.prev_frame != nil && a.current_time < frame.prev_frame.start_time {
            frame.prev_frame = frame.prev_frame.prev_frame
            frame.next_frame = frame.prev_frame.next_frame
            frame.dirty = true
        }
    }

    if frame.dirty {
        frame.prev_translation = bone.translation + frame.prev_frame.translation
        frame.prev_rotation = frame.prev_frame.rotation * bone.rotation
        frame.prev_scaling = frame.prev_frame.scaling * bone.scaling

        frame.next_translation = bone.translation + frame.next_frame.translation
        frame.next_rotation = frame.next_frame.rotation * bone.rotation
        frame.next_scaling = frame.next_frame.scaling * bone.scaling
        frame.dirty = false
    }

    t0 := frame.prev_frame.start_time
    t1 := frame.next_frame.start_time
    tc := a.current_time
    interp := f32((t1 - t0)/(tc - t0))

    i3:= [3]f32{interp, interp, interp}
    t := linalg.lerp(frame.prev_translation, frame.next_translation, i3)
    r := linalg.quaternion_slerp(frame.prev_rotation, frame.next_rotation, interp)
    s := linalg.lerp(frame.prev_scaling, frame.next_scaling, i3)
    world_transform := linalg.matrix4_from_trs(t, r, s)
    output[bone_index] = world_transform

    for child in bone.children {
        animate_bone(a, child, world_transform, output)
    }
}

animate_bones :: proc(a: ^Animator, seconds_since_last_frame: f64, global_trans: matrix[4,4]f32 = 1) -> (bones: []matrix[4,4]f32) {
    b := make([]matrix[4,4]f32, len(a.sk.bones), context.temp_allocator)

    animate_bone(a, a.sk.root_bone, global_trans, &b)

    duration := a.sk.animations[a.now_playing].duration
    if a.current_time >= duration {
        if a.looping {
            a.current_time = 0
        } else {
            a.current_time = duration
        }
    }
    a.current_time += seconds_since_last_frame * a.speed_factor

    return b
}
