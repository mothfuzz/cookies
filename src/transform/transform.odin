package transform

import "core:math/linalg"
import hm "core:container/handle_map"

Transform :: struct {
    idx: u32,
    gen: u32,
}

TRS :: struct {
    translation: [3]f32,
    rotation: quaternion128,
    scale: [3]f32,
}
ORIGIN :: TRS{0, 0, 1}

//helper procs
translate_trs :: proc(t: ^TRS, translation: [3]f32) {
    t.translation += translation
}
rotation_from_angles :: proc(rotation: [3]f32) -> quaternion128 {
    return linalg.quaternion_from_euler_angles(expand_values(rotation), .XYZ)
}
rotate_trs :: proc(t: ^TRS, rotation: [3]f32) {
    t.rotation = linalg.quaternion_from_euler_angles(expand_values(rotation), .XYZ) * t.rotation
}
rotatex_trs :: proc(t: ^TRS, rotation: f32) {
    t.rotation = linalg.quaternion_from_euler_angle_x(rotation) * t.rotation
}
rotatey_trs :: proc(t: ^TRS, rotation: f32) {
    t.rotation = linalg.quaternion_from_euler_angle_y(rotation) * t.rotation
}
rotatez_trs :: proc(t: ^TRS, rotation: f32) {
    t.rotation = linalg.quaternion_from_euler_angle_z(rotation) * t.rotation
}
scale_trs :: proc(t: ^TRS, scale: [3]f32) {
    t.scale *= scale
}

look_at_trs :: proc(viewer: ^TRS, target: [3]f32, up: [3]f32 = {0, 1, 0}) {
    forward := linalg.normalize(target - viewer.translation)
    right := linalg.normalize(linalg.cross(up, forward))
    up := linalg.cross(forward, right)
    viewer.rotation = linalg.quaternion_from_forward_and_up(forward, up)
}

compute :: proc(trs: TRS) -> matrix[4,4]f32 {
    return linalg.matrix4_from_trs(expand_values(trs))
}

lerp :: proc(a, b: TRS, alpha: f64) -> TRS {
    alpha := f32(alpha)
    return {
        translation = linalg.lerp(a.translation, b.translation, alpha),
        rotation = linalg.quaternion_slerp(a.rotation, b.rotation, alpha),
        scale = linalg.lerp(a.scale, b.scale, alpha),
    }
}

smooth :: proc(a, b: TRS, alpha: f64) -> matrix[4,4]f32 {
    return compute(lerp(a, b, alpha))
}

Transform_Data :: struct {
    handle: Transform,

    prev_trans: TRS,
    next_trans: TRS,
    world: matrix[4,4]f32,
    dirty: bool,
    alpha: f64,

    parent: Transform,
    first_child: Transform,
    last_child: Transform,
    prev_sibling: Transform,
    next_sibling: Transform,
}

Tree :: struct {
    transforms: hm.Dynamic_Handle_Map(Transform_Data, Transform),
    //roots: map[Transform]struct{},
}

tree_allocator: ^Tree //allocator-style default for when not using an explicit Tree

make_tree :: proc() -> (tt: Tree) {
    hm.dynamic_init(&tt.transforms, context.allocator)
    return
}

delete_tree :: proc(tt: ^Tree) {
    hm.dynamic_destroy(&tt.transforms)
}

make :: proc(trs: TRS = ORIGIN, parent: Transform = {0, 0}, tt: ^Tree = tree_allocator) -> (trans: Transform) {
    trs := trs
    if trs.scale == 0 {
        trs.scale = 1
    }
    if trs.rotation == 0 {
        trs.rotation = 1
    }
    trans = hm.add(&tt.transforms, Transform_Data{prev_trans = trs, next_trans = trs, dirty = true})
    if parent == {0, 0} {
        //tt.roots[trans] = {}
    } else {
        link(parent, trans, tt)
    }
    return
}

delete :: proc(trans: Transform, delete_children: bool = false, tt: ^Tree = tree_allocator) {
    //delete_key(&tt.roots, trans)
    if t, ok := hm.get(&tt.transforms, trans); ok {
        unlink(trans, tt) //removes from parent, adjusts siblings
        if delete_children && t.first_child != {0,0} {
            delete(t.first_child, true, tt)
        }
        hm.remove(&tt.transforms, trans)
    }
}

init :: proc(trans: Transform, trs: TRS, tt: ^Tree = tree_allocator) {
    trs := trs
    if trs.rotation == 0 {
        trs.rotation = 1
    }
    if trs.scale == 0 {
        trs.scale = 1
    }
    trans := write(trans, tt)
    trans^ = trs
}

link :: proc(parent: Transform, child: Transform, tt: ^Tree = tree_allocator) {
    //delete_key(&s.roots, child)
    unlink(child, tt)
    parent_trans := hm.get(&tt.transforms, parent)
    child_trans := hm.get(&tt.transforms, child)
    child_trans.parent = parent
    if parent_trans.first_child == {0,0} {
        parent_trans.first_child = child
    } else {
        last_child_trans := hm.get(&tt.transforms, parent_trans.last_child)
        last_child_trans.next_sibling = child
        child_trans.prev_sibling = parent_trans.last_child
    }
    parent_trans.last_child = child
}

unlink :: proc(trans: Transform, tt: ^Tree = tree_allocator) {
    t := hm.get(&tt.transforms, trans)
    if t.parent != {0,0} {
        if parent, ok := hm.get(&tt.transforms, t.parent); ok {
            if parent.first_child == trans {
                parent.first_child = {0,0}
            }
            if parent.last_child == trans {
                parent.last_child = {0,0}
            }
        }
        t.parent = {0,0}
    }
    if t.prev_sibling != {0,0} {
        if prev_sibling, ok := hm.get(&tt.transforms, t.prev_sibling); ok {
            prev_sibling.next_sibling = {0,0}
        }
        t.prev_sibling = {0,0}
    }
    if t.next_sibling != {0,0} {
        if next_sibling, ok := hm.get(&tt.transforms, t.next_sibling); ok {
            next_sibling.prev_sibling = {0,0}
        }
        t.next_sibling = {0,0}
    }
    //tt.roots[trans] = {}
}

read :: proc(n: Transform, tt: ^Tree = tree_allocator) -> TRS {
    if t, ok := hm.get(&tt.transforms, n); ok {
        return t.next_trans
    }
    return ORIGIN
}

write :: proc(n: Transform, tt: ^Tree = tree_allocator) -> ^TRS {
    if t, ok := hm.get(&tt.transforms, n); ok {
        if !t.dirty {
            t.dirty = true
            t.prev_trans = t.next_trans
        }
        t.alpha = 0
        return &t.next_trans
    }
    return nil
}

find_root :: proc(n: Transform, tt: ^Tree = tree_allocator) -> Transform {
    if t, ok := hm.get(&tt.transforms, n); ok {
        if t.parent != {0,0} {
            return find_root(t.parent, tt)
        }
        return n
    }
    return {0, 0}
}

@(private)
update_root :: proc(n: Transform, tt: ^Tree = tree_allocator, dirty: bool = false, parent_world: matrix[4,4]f32 = 1) {
    if t, ok := hm.get(&tt.transforms, n); ok {
        dirty := t.dirty || dirty
        t.world = parent_world * compute(t.next_trans)
        t.dirty = false
        update_root(t.next_sibling, tt, dirty, parent_world)
        update_root(t.first_child, tt, dirty, t.world)
    }
}

get_world :: proc(n: Transform, tt: ^Tree = tree_allocator) -> matrix[4,4]f32 {
    if t, ok := hm.get(&tt.transforms, n); ok {
        if t.dirty {
            root := find_root(n, tt)
            update_root(root, tt)
        }
        return t.world
    }
    return 1
}

@(private)
update_root_smooth :: proc(n: Transform, alpha: f64, tt: ^Tree = tree_allocator, dirty: bool = false, parent_world: matrix[4,4]f32 = 1) {
    if t, ok := hm.get(&tt.transforms, n); ok {
        dirty := t.dirty || dirty
        if alpha < t.alpha {
            //avoid looping/jittering
            t.prev_trans = t.next_trans
        }
        t.world = parent_world * smooth(t.prev_trans, t.next_trans, alpha)
        t.dirty = false
        t.alpha = alpha
        update_root_smooth(t.next_sibling, alpha, tt, dirty, parent_world)
        update_root_smooth(t.first_child, alpha, tt, dirty, t.world)
    }
}

get_world_smooth :: proc(n: Transform, alpha: f64, tt: ^Tree = tree_allocator) -> matrix[4,4]f32 {
    if t, ok := hm.get(&tt.transforms, n); ok {
        if t.dirty || t.alpha != alpha {
            root := find_root(n, tt)
            update_root_smooth(root, alpha, tt)
        }
        return t.world
    }
    return 1
}

world :: proc{get_world, get_world_smooth}

get_world_translation :: proc(world: matrix[4,4]f32) -> [3]f32 {
    return world[3].xyz
}

get_world_scale :: proc(world: matrix[4,4]f32) -> [3]f32 {
    basis := cast(matrix[3,3]f32)(world)
    return {linalg.length(basis[0]), linalg.length(basis[1]), linalg.length(basis[2])}
}

get_world_rotation :: proc(world: matrix[4,4]f32) -> quaternion128 {
    basis := cast(matrix[3,3]f32)(world)
    basis[0] = linalg.normalize(basis[0])
    basis[1] = linalg.normalize(basis[1])
    basis[2] = linalg.normalize(basis[2])
    return linalg.to_quaternion(basis)
}

get_world_trs :: proc(world: matrix[4,4]f32) -> (translation: [3]f32, rotation: quaternion128, scale: [3]f32) {
    translation = world[3].xyz
    basis := cast(matrix[3,3]f32)(world)
    scale.x = linalg.length(basis[0])
    scale.y = linalg.length(basis[1])
    scale.z = linalg.length(basis[2])
    basis[0] /= scale.x
    basis[1] /= scale.y
    basis[2] /= scale.z
    rotation = linalg.to_quaternion(basis)
    return
}

get_parent :: proc(tree: ^Tree, trans: Transform) -> Transform {
    if t, ok := hm.get(&tree.transforms, trans); ok {
        return t.parent
    }
    return {0, 0}
}
get_first_child :: proc(tree: ^Tree, trans: Transform) -> Transform {
    if t, ok := hm.get(&tree.transforms, trans); ok {
        return t.first_child
    }
    return {0, 0}
}
get_last_child :: proc(tree: ^Tree, trans: Transform) -> Transform {
    if t, ok := hm.get(&tree.transforms, trans); ok {
        return t.last_child
    }
    return {0, 0}
}
get_next_sibling :: proc(tree: ^Tree, trans: Transform) -> Transform {
    if t, ok := hm.get(&tree.transforms, trans); ok {
        return t.next_sibling
    }
    return {0, 0}
}
get_prev_sibling :: proc(tree: ^Tree, trans: Transform) -> Transform {
    if t, ok := hm.get(&tree.transforms, trans); ok {
        return t.prev_sibling
    }
    return {0, 0}
}

//helper procs for Transform itself
translate_t :: proc(t: Transform, translation: [3]f32) {
    translate_trs(write(t), translation)
}
rotate_t :: proc(t: Transform, rotation: [3]f32) {
    rotate_trs(write(t), rotation)
}
rotatex_t :: proc(t: Transform, rotation: f32) {
    rotatex_trs(write(t), rotation)
}
rotatey_t :: proc(t: Transform, rotation: f32) {
    rotatey_trs(write(t), rotation)
}
rotatez_t :: proc(t: Transform, rotation: f32) {
    rotatez_trs(write(t), rotation)
}
scale_t :: proc(t: Transform, scale: [3]f32) {
    scale_trs(write(t), scale)
}

look_at_t :: proc(viewer: Transform, target: [3]f32, up: [3]f32 = {0, 1, 0}) {
    look_at_trs(write(viewer), target, up)
}

translate :: proc{translate_trs, translate_t}
rotate :: proc{rotate_trs, rotate_t}
rotatex :: proc{rotatex_trs, rotatex_t}
rotatey :: proc{rotatey_trs, rotatey_t}
rotatez :: proc{rotatez_trs, rotatez_t}
scale :: proc{scale_trs, scale_t}
look_at :: proc{look_at_trs, look_at_t}
