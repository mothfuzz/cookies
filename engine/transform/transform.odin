package transform

//interpolated transform hierarchy

import "core:math/linalg"

Transform :: struct {
    local_translation: [3]f32,
    local_rotation: quaternion128,
    local_scale: [3]f32,
    parent: ^Transform,
    children: map[^Transform]struct{},
    dirty: bool,
    //relative to tick
    world_model: matrix[4,4]f32,
    world_translation: [3]f32,
    world_rotation: quaternion128,
    world_scale: [3]f32,
    //relative to draw
    current_world_model: matrix[4,4]f32,
    current_world_translation: [3]f32,
    current_world_rotation: quaternion128,
    current_world_scale: [3]f32,
}

origin :: proc() -> (trans: Transform) {
    trans.local_translation = 0
    trans.local_rotation = 1
    trans.local_scale = 1
    //set all the others to default values so no first-frame artifacts
    trans.world_model = 1
    trans.world_translation = 0
    trans.world_rotation = 1
    trans.world_scale = 1
    trans.current_world_model = 1
    trans.current_world_translation = 0
    trans.current_world_rotation = 1
    trans.current_world_scale = 1
    return
}

unlink :: proc(trans: ^Transform) {
    if trans == nil {
        return
    }
    if trans.parent == nil {
        return
    }
    delete_key(&trans.parent.children, trans)
    trans.parent = nil
}

parent :: proc(parent: ^Transform, child: ^Transform) {
    unlink(child.parent)
    child.parent = parent
    child.parent.children[child] = {}
}

translate :: proc(trans: ^Transform, translation: [3]f32) {
    trans.local_translation += translation
    dirt(trans)
}
set_translation :: proc(trans: ^Transform, translation: [3]f32) {
    trans.local_translation = translation
    dirt(trans)
}
rotate :: proc(trans: ^Transform, rotation: [3]f32) {
    trans.local_rotation = linalg.quaternion_from_euler_angles(expand_values(rotation), linalg.Euler_Angle_Order.XYZ) * trans.local_rotation
    dirt(trans)
}
rotatex :: proc(trans: ^Transform, rotation: f32) {
    trans.local_rotation = linalg.quaternion_from_euler_angle_x(rotation) * trans.local_rotation
    dirt(trans)
}
rotatey :: proc(trans: ^Transform, rotation: f32) {
    trans.local_rotation = linalg.quaternion_from_euler_angle_y(rotation) * trans.local_rotation
    dirt(trans)
}
rotatez :: proc(trans: ^Transform, rotation: f32) {
    trans.local_rotation = linalg.quaternion_from_euler_angle_z(rotation) * trans.local_rotation
    dirt(trans)
}
set_rotation :: proc(trans: ^Transform, rotation: [3]f32) {
    trans.local_rotation = linalg.quaternion_from_euler_angles(expand_values(rotation), linalg.Euler_Angle_Order.XYZ)
    dirt(trans)
}
scale :: proc(trans: ^Transform, scale: [3]f32) {
    trans.local_scale *= scale
    dirt(trans)
}
set_scale :: proc(trans: ^Transform, scale: [3]f32) {
    trans.local_scale = scale
    dirt(trans)
}

/*
world_model, world_translation, world_rotation, and world_scale are ALWAYS CACHED.
that means any other entities are reading the back-tick and not the forward-tick
this is good for multithreading.

transforms will only be updated once per tick, but may or may not be used in each draw.
*/

dirt :: proc(trans: ^Transform) {
    trans.dirty = true
    for c in trans.children {
        dirt(c)
    }
}

//computed ONCE globally at the end of a tick, after all is said and done.
compute :: proc(trans: ^Transform) -> matrix[4, 4]f32 {
    if trans == nil {
        return 1
    }

    if trans.dirty {
        //cache the values
        trans.world_model = trans.current_world_model
        trans.world_translation = trans.current_world_translation
        trans.world_rotation = trans.current_world_rotation
        trans.world_scale = trans.current_world_scale

        //recalculate
        parent_world_model := compute(trans.parent)
        local_model := linalg.matrix4_from_trs(trans.local_translation, trans.local_rotation, trans.local_scale)
        world_model := parent_world_model * local_model
        trans.current_world_model = world_model

        //extract components
        trans.current_world_translation = world_model[3].xyz
        world_model[3].xyz = 0
        trans.current_world_scale.x = linalg.length(world_model[0])
        trans.current_world_scale.y = linalg.length(world_model[1])
        trans.current_world_scale.z = linalg.length(world_model[2])
        world_model[0] /= trans.current_world_scale.x
        world_model[1] /= trans.current_world_scale.y
        world_model[2] /= trans.current_world_scale.z
        trans.current_world_rotation = linalg.quaternion_from_matrix4(world_model)

        //clean :3
        trans.dirty = false
    }
    return trans.current_world_model
}

/*
since transforms are optimized to only be computed once when necessary, that means we can also smoothly interpolate between the last time a transform was computed and now.
this will provide smooth frame-by-frame visuals even when your tick rate is lower than your draw rate.
to use this functionality, simply call transform.smooth() with a delta time instead of transform.compute() in your draw procedure.
*/
smooth :: proc(trans: ^Transform, t: f64) -> matrix[4, 4]f32 {
    t := f32(t)
    compute(trans)
    translation := linalg.lerp(trans.world_translation, trans.current_world_translation, [3]f32{t, t, t})
    rotation := linalg.quaternion_slerp(trans.world_rotation, trans.current_world_rotation, t)
    scale := linalg.lerp(trans.world_scale, trans.current_world_scale, [3]f32{t, t, t})
    return linalg.matrix4_from_trs(translation, rotation, scale)
}

/*
TODO, for collision:

colliders should have userdata. Don't tie it to the actor system, but have the option to attach an ActorID.

tick:
collision.transform(collider, transform) <- would need to be staged until post-tick (double-buffered!) to get correct world transforms.

kill:
collision.destroy(collider)
*/
