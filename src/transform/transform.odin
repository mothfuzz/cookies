package transform

import "core:math/linalg"
import hm "core:container/handle_map"

Node :: struct {
    idx: u32,
    gen: u32,
}

Transform :: struct {
    translation: [3]f32,
    rotation: quaternion128,
    scale: [3]f32,
}
ORIGIN :: Transform{0, 0, 1}

//helper procs
translate :: proc(t: ^Transform, translation: [3]f32) {
    t.translation += translation
}
rotation_from_angles :: proc(rotation: [3]f32) -> quaternion128 {
    return linalg.quaternion_from_euler_angles(expand_values(rotation), .XYZ)
}
rotate :: proc(t: ^Transform, rotation: [3]f32) {
    t.rotation = linalg.quaternion_from_euler_angles(expand_values(rotation), .XYZ) * t.rotation
}
rotatex :: proc(t: ^Transform, rotation: f32) {
    t.rotation = linalg.quaternion_from_euler_angle_x(rotation) * t.rotation
}
rotatey :: proc(t: ^Transform, rotation: f32) {
    t.rotation = linalg.quaternion_from_euler_angle_y(rotation) * t.rotation
}
rotatez :: proc(t: ^Transform, rotation: f32) {
    t.rotation = linalg.quaternion_from_euler_angle_z(rotation) * t.rotation
}
scale :: proc(t: ^Transform, scale: [3]f32) {
    t.scale *= scale
}

look_at :: proc(viewer: ^Transform, target: [3]f32, up: [3]f32 = {0, 1, 0}) {
    forward := linalg.normalize(target - viewer.translation)
    right := linalg.normalize(linalg.cross(up, forward))
    up := linalg.cross(forward, right)
    viewer.rotation = linalg.quaternion_from_forward_and_up(forward, up)
}

compute :: proc(t: Transform) -> matrix[4,4]f32 {
    return linalg.matrix4_from_trs(expand_values(t))
}

lerp :: proc(a, b: Transform, alpha: f64) -> Transform {
    alpha := f32(alpha)
    return {
        translation = linalg.lerp(a.translation, b.translation, alpha),
        rotation = linalg.quaternion_slerp(a.rotation, b.rotation, alpha),
        scale = linalg.lerp(a.scale, b.scale, alpha),
    }
}

smooth :: proc(a, b: Transform, alpha: f64) -> matrix[4,4]f32 {
    return compute(lerp(a, b, alpha))
}

Node_Transform :: struct {
    handle: Node,

    prev_trans: Transform,
    next_trans: Transform,
    world: matrix[4,4]f32,
    dirty: bool,
    alpha: f64,

    parent: Node,
    first_child: Node,
    last_child: Node,
    prev_sibling: Node,
    next_sibling: Node,
}

Tree :: struct {
    transforms: hm.Dynamic_Handle_Map(Node_Transform, Node),
    //roots: map[Node]struct{},
}

make_tree :: proc() -> (tt: Tree) {
    hm.dynamic_init(&tt.transforms, context.allocator)
    return
}

delete_tree :: proc(tt: ^Tree) {
    hm.dynamic_destroy(&tt.transforms)
}

create_node :: proc(tt:  ^Tree, t: Transform = ORIGIN, parent: Node = {0, 0}) -> (node: Node) {
    t := t
    if t.scale == 0 {
        t.scale = 1
    }
    if t.rotation == 0 {
        t.rotation = 1
    }
    node = hm.add(&tt.transforms, Node_Transform{prev_trans = t, next_trans = t, dirty = true})
    if parent == {0, 0} {
        //tt.roots[node] = {}
    } else {
        link(tt, parent, node)
    }
    return
}

delete_node :: proc(tt: ^Tree, node: Node, delete_children: bool = false) {
    //delete_key(&tt.roots, node)
    if t, ok := hm.get(&tt.transforms, node); ok {
        unlink(tt, node) //removes from parent, adjusts siblings
        if delete_children && t.first_child != {0,0} {
            delete_node(tt, t.first_child, true)
        }
        hm.remove(&tt.transforms, node)
    }
}

link :: proc(tt: ^Tree, parent: Node, child: Node) {
    //delete_key(&s.roots, child)
    unlink(tt, child)
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

unlink :: proc(tt: ^Tree, node: Node) {
    t := hm.get(&tt.transforms, node)
    if t.parent != {0,0} {
        if parent, ok := hm.get(&tt.transforms, t.parent); ok {
            if parent.first_child == node {
                parent.first_child = {0,0}
            }
            if parent.last_child == node {
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
    //tt.roots[node] = {}
}

read :: proc(tt: ^Tree, n: Node) -> Transform {
    if t, ok := hm.get(&tt.transforms, n); ok {
        return t.next_trans
    }
    return ORIGIN
}

write :: proc(tt: ^Tree, n: Node) -> ^Transform {
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

find_root :: proc(tt: ^Tree, n: Node) -> Node {
    if t, ok := hm.get(&tt.transforms, n); ok {
        if t.parent != {0,0} {
            return find_root(tt, t.parent)
        }
        return n
    }
    return {0, 0}
}

@(private)
update_root :: proc(tt: ^Tree, n: Node, dirty: bool = false, parent_world: matrix[4,4]f32 = 1) {
    if t, ok := hm.get(&tt.transforms, n); ok {
        dirty := t.dirty || dirty
        t.world = parent_world * compute(t.next_trans)
        t.dirty = false
        update_root(tt, t.next_sibling, dirty, parent_world)
        update_root(tt, t.first_child, dirty, t.world)
    }
}

get_world :: proc(tt: ^Tree, n: Node) -> matrix[4,4]f32 {
    if t, ok := hm.get(&tt.transforms, n); ok {
        if t.dirty {
            root := find_root(tt, n)
            update_root(tt, root)
        }
        return t.world
    }
    return 1
}

@(private)
update_root_smooth :: proc(tt: ^Tree, n: Node, alpha: f64, dirty: bool = false, parent_world: matrix[4,4]f32 = 1) {
    if t, ok := hm.get(&tt.transforms, n); ok {
        dirty := t.dirty || dirty
        if alpha < t.alpha {
            //avoid looping/jittering
            t.prev_trans = t.next_trans
        }
        t.world = parent_world * smooth(t.prev_trans, t.next_trans, alpha)
        t.dirty = false
        t.alpha = alpha
        update_root_smooth(tt, t.next_sibling, alpha, dirty, parent_world)
        update_root_smooth(tt, t.first_child, alpha, dirty, t.world)
    }
}

get_world_smooth :: proc(tt: ^Tree, n: Node, alpha: f64) -> matrix[4,4]f32 {
    if t, ok := hm.get(&tt.transforms, n); ok {
        if t.dirty || t.alpha != alpha {
            root := find_root(tt, n)
            update_root_smooth(tt, root, alpha)
        }
        return t.world
    }
    return 1
}

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

get_parent :: proc(tree: ^Tree, node: Node) -> Node {
    if t, ok := hm.get(&tree.transforms, node); ok {
        return t.parent
    }
    return {0, 0}
}
get_first_child :: proc(tree: ^Tree, node: Node) -> Node {
    if t, ok := hm.get(&tree.transforms, node); ok {
        return t.first_child
    }
    return {0, 0}
}
get_last_child :: proc(tree: ^Tree, node: Node) -> Node {
    if t, ok := hm.get(&tree.transforms, node); ok {
        return t.last_child
    }
    return {0, 0}
}
get_next_sibling :: proc(tree: ^Tree, node: Node) -> Node {
    if t, ok := hm.get(&tree.transforms, node); ok {
        return t.next_sibling
    }
    return {0, 0}
}
get_prev_sibling :: proc(tree: ^Tree, node: Node) -> Node {
    if t, ok := hm.get(&tree.transforms, node); ok {
        return t.prev_sibling
    }
    return {0, 0}
}
