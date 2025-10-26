package transform

//interpolated transform hierarchy

import "core:math/linalg"

Transform :: struct {
    position: [3]f32,
    orientation: quaternion128,
    scale: [3]f32,
    prev_local_trans: matrix[4, 4]f32,
    prev_world_trans: matrix[4, 4]f32,
    next_local_trans: matrix[4, 4]f32,
    next_world_trans: matrix[4, 4]f32,
    parent: ^Transform,
    first_child: ^Transform,
    last_child: ^Transform,
    prev_sibling: ^Transform,
    next_sibling: ^Transform,
    dirty: bool,
}

ORIGIN :: Transform{position=0, orientation=1, scale=1,
                    prev_local_trans=1, prev_world_trans=1,
                    next_local_trans=1, next_world_trans=1}

link :: proc "contextless" (parent: ^Transform, child: ^Transform) {
    unlink(child)
    child.parent = parent
    if parent.first_child == nil {
        parent.first_child = child
    } else {
        parent.last_child.next_sibling = child
        child.prev_sibling =  parent.last_child
    }
    parent.last_child = child
    child.dirty = true
}

unlink :: proc "contextless" (node: ^Transform) {
    if node.parent != nil {
        if node.parent.first_child == node {
            node.parent.first_child = nil
        }
        if node.parent.last_child == node {
            node.parent.last_child = nil
        }
        node.parent = nil
    }
    if node.prev_sibling != nil {
        node.prev_sibling.next_sibling = nil
        node.prev_sibling = nil
    }
    if node.next_sibling != nil {
        node.next_sibling.prev_sibling = nil
        node.next_sibling = nil
    }
}

//to compute a transform immediately and 'cancel' interpolation
reset :: proc "contextless" (node: ^Transform) {
    node.dirty = true
    update_root(node, reset=true)
    //node.prev_local_trans = node.next_local_trans
    //node.prev_world_trans = node.next_world_trans
}

update_root :: proc "contextless" (node: ^Transform, reset: bool = false) {
    if node == nil {
        return
    }
    if node.parent != nil {
        update_root(node.parent, reset)
    } else {
        update(node, reset=reset)
    }
}

update :: proc "contextless" (node: ^Transform, dirty: bool = false, reset: bool = false) {
    if node == nil {
        return
    }
    dirty := dirty || node.dirty
    if dirty {
        //fmt.println("recalculating trans:", node,"\n")
        node.prev_local_trans = node.next_local_trans
        node.prev_world_trans = node.next_world_trans
        node.next_local_trans = linalg.matrix4_from_trs(node.position, node.orientation, node.scale)
        if node.parent != nil {
            node.next_world_trans = node.parent.next_world_trans * node.next_local_trans
        } else {
            node.next_world_trans = node.next_local_trans
        }
        node.dirty = false
    }
    if reset {
        node.prev_local_trans = node.next_local_trans
        node.prev_world_trans = node.next_world_trans
    }
    update(node.next_sibling, dirty, reset)
    update(node.first_child, dirty, reset)
}
extract :: proc "contextless" (m: matrix[4, 4]f32) -> (position: [3]f32, orientation: quaternion128, scale: [3]f32) {
    position = m[3].xyz
    basis := cast(matrix[3, 3]f32)(m)
    scale.x = linalg.length(basis[0])
    scale.y = linalg.length(basis[1])
    scale.z = linalg.length(basis[2])
    basis[0] /= scale.x
    basis[1] /= scale.y
    basis[2] /= scale.z
    orientation = linalg.to_quaternion(basis)
    return
}

interp :: proc "contextless" (trans: ^Transform, t: f32) -> (position: [3]f32, orientation: quaternion128, scale: [3]f32) {
    prev_position, prev_orientation, prev_scale := extract(trans.prev_world_trans)
    next_position, next_orientation, next_scale := extract(trans.next_world_trans)
    position = linalg.lerp(prev_position, next_position, t)
    orientation = linalg.quaternion_slerp(prev_orientation, next_orientation, t)
    scale = linalg.lerp(prev_scale, next_scale, t)
    return
}

compute :: proc "contextless" (trans: ^Transform) -> matrix[4, 4]f32 {
    update_root(trans)
    return trans.next_world_trans
}

smooth :: proc "contextless" (trans: ^Transform, t: f64) -> matrix[4, 4]f32 {
    update_root(trans)
    return linalg.matrix4_from_trs(interp(trans, f32(t)))
}


translate :: proc "contextless" (trans: ^Transform, translation: [3]f32) {
    trans.position += translation
    trans.dirty = true
}
set_position :: proc "contextless" (trans: ^Transform, position: [3]f32, interpolate: bool = false) {
    trans.position = position
    trans.dirty = true
    if !interpolate {
        reset(trans)
    }
}
get_position :: proc "contextless" (trans: ^Transform) -> [3]f32 {
    t, r, s := extract(trans.prev_world_trans)
    return t
}

rotate :: proc "contextless" (trans: ^Transform, rotation: [3]f32) {
    trans.orientation = linalg.quaternion_from_euler_angles(expand_values(rotation), linalg.Euler_Angle_Order.XYZ) * trans.orientation
    trans.dirty = true
}
rotatex :: proc "contextless" (trans: ^Transform, rotation: f32) {
    trans.orientation = linalg.quaternion_from_euler_angle_x(rotation) * trans.orientation
    trans.dirty = true
}
rotatey :: proc "contextless" (trans: ^Transform, rotation: f32) {
    trans.orientation = linalg.quaternion_from_euler_angle_y(rotation) * trans.orientation
    trans.dirty = true
}
rotatez :: proc "contextless" (trans: ^Transform, rotation: f32) {
    trans.orientation = linalg.quaternion_from_euler_angle_z(rotation) * trans.orientation
    trans.dirty = true
}
set_orientation :: proc "contextless" (trans: ^Transform, orientation: [3]f32, interpolate: bool = false) {
    trans.orientation = linalg.quaternion_from_euler_angles(expand_values(orientation), .XYZ)
    trans.dirty = true
    if !interpolate {
        reset(trans)
    }
}
set_orientation_quaternion :: proc "contextless" (trans: ^Transform, orientation: quaternion128, interpolate: bool = false) {
    trans.orientation = orientation
    trans.dirty = true
    if !interpolate {
        reset(trans)
    }
}
get_orientation :: proc "contextless" (trans: ^Transform) -> [3]f32 {
    t, r, s := extract(trans.prev_world_trans)
    x, y, z := linalg.euler_angles_from_quaternion(r, .XYZ)
    return {x, y, z}
}
get_orientation_quaternion :: proc "contextless" (trans: ^Transform) -> quaternion128 {
    t, r, s := extract(trans.prev_world_trans)
    return r
}

scale :: proc "contextless" (trans: ^Transform, scale: [3]f32) {
    trans.scale *= scale
    trans.dirty = true
}
set_scale :: proc "contextless" (trans: ^Transform, scale: [3]f32, interpolate: bool = false) {
    trans.scale = scale
    trans.dirty = true
    if !interpolate {
        reset(trans)
    }
}
get_scale :: proc "contextless" (trans: ^Transform) -> [3]f32 {
    t, r, s := extract(trans.prev_world_trans)
    return s
}

init :: proc "contextless" (trans: ^Transform,
                            position: [3]f32 = 0,
                            orientation: quaternion128 = 1,
                            scale: [3]f32 = 1) {
    trans.position = position
    trans.orientation = orientation
    trans.scale = scale
    reset(trans)
}


/*
world_model, world_translation, world_rotation, and world_scale are ALWAYS CACHED.
that means any other entities are reading the back-tick and not the forward-tick
this is good for multithreading.

transforms will only be updated once per tick, but may or may not be used in each draw.
*/

//computed ONCE globally at the end of a tick, after all is said and done.

/*since transforms are optimized to only be computed once when necessary, that means we can also smoothly interpolate between the last time a transform was computed and now.
this will provide smooth frame-by-frame visuals even when your tick rate is lower than your draw rate.
to use this functionality, simply call transform.smooth() with a delta time instead of transform.compute() in your draw procedure.
*/
