package transform

import "core:math/linalg"
import hm "core:container/handle_map"
import "cookies:clock"

TRS :: struct {
    translation: [3]f32,
    rotation: quaternion128,
    scale: [3]f32,
}
ORIGIN_TRS :: TRS{0, 1, 1}

TRS_Smoothed :: clock.Smoothed(TRS)
ORIGIN :: TRS_Smoothed{ORIGIN_TRS, ORIGIN_TRS, 0}

TRS_Angles :: struct {
    translation: [3]f32,
    rotation: [3]f32,
    scale: [3]f32,
}

Handle :: struct {
    idx: u32,
    gen: u32,
}

Node_Local :: union #no_nil {
    TRS_Smoothed,
    matrix[4,4]f32,
}

Node :: struct {
    handle: Handle,
    tree: ^Tree,
}

@(private)
Transform_Data :: struct {
    handle: Handle,

    local: Node_Local,
    world: matrix[4,4]f32,
    world_serial: u64, //replacement for dirty-flag

    parent: Handle,
    first_child: Handle,
    next_sibling: Handle,
}

Tree :: struct {
    transforms: hm.Dynamic_Handle_Map(Transform_Data, Handle),
    clk: ^clock.Clock,
    serial: u64,
    last_alpha: f64,
    last_tick: u64,
}

default_tree: ^Tree //allocator-style default for when not using an explicit Tree

make_tree :: proc(clk: ^clock.Clock = clock.default) -> (tt: Tree) {
    hm.dynamic_init(&tt.transforms, context.allocator)
    tt.clk = clk
    return
}

delete_tree :: proc(tt: ^Tree) {
    hm.dynamic_destroy(&tt.transforms)
}

sync_tree :: proc(tt: ^Tree) {
    if tt.clk.alpha != tt.last_alpha || tt.clk.current_tick != tt.last_tick {
        tt.last_alpha = tt.clk.alpha
        tt.last_tick = tt.clk.current_tick
        tt.serial += 1
    }
}

insert_node :: proc(trs: TRS = ORIGIN_TRS, parent: Node = {}, tt: ^Tree = default_tree) -> (trans: Node) {
    trs := trs
    if trs.scale == 0 {
        trs.scale = 1
    }
    if trs.rotation == 0 {
        trs.rotation = 1
    }
    return insert_node_smoothed({trs, trs, tt.clk.current_tick}, parent, tt)
}

insert_node_smoothed :: proc(trs: TRS_Smoothed, parent: Node = {}, tt: ^Tree = default_tree) -> (trans: Node) {
    trans.handle = hm.add(&tt.transforms, Transform_Data{local = trs})
    trans.tree = tt
    if parent != {} {
        link_node(parent, trans)
    }
    return
}

insert_node_matrix :: proc(m: matrix[4,4]f32, parent: Node = {}, tt: ^Tree = default_tree) -> (trans: Node) {
    trans.handle = hm.add(&tt.transforms, Transform_Data{local = m})
    trans.tree = tt
    if parent != {} {
        link_node(parent, trans)
    }
    return
}

remove_node :: proc(trans: Node, delete_children: bool = false) {
    if t, ok := hm.get(&trans.tree.transforms, trans.handle); ok {
        unlink_node(trans) //removes from parent, adjusts siblings
        if delete_children && t.first_child != {} {
            remove_node({t.first_child, trans.tree}, true)
        }
        hm.remove(&trans.tree.transforms, trans.handle)
    }
}

init_node :: proc(trans: Node, trs: TRS) {
    trs := trs
    if trs.rotation == 0 {
        trs.rotation = 1
    }
    if trs.scale == 0 {
        trs.scale = 1
    }
    trans := local_node(trans)
    trans^ = trs
}

copy_node :: proc(dst, src: Node) {
    dst.tree.serial += 1
    dst, dst_ok := hm.get(&dst.tree.transforms, dst.handle)
    src, src_ok := hm.get(&src.tree.transforms, src.handle)
    if !(dst_ok && src_ok) {
        return
    }
    dst.local = src.local
}

link_node :: proc(parent: Node, child: Node) {
    assert(parent.tree == child.tree, "Parent and child must belong to the same tree.")
    tree := &parent.tree.transforms
    unlink_node(child)
    parent_trans := hm.get(tree, parent.handle)
    child_trans := hm.get(tree, child.handle)
    child_trans.parent = parent.handle
    if parent_trans.first_child != {} {
        child_trans.next_sibling = parent_trans.first_child
    }
    parent_trans.first_child = child.handle
}

unlink_node :: proc(trans: Node) {
    tree := &trans.tree.transforms
    t := hm.get(&trans.tree.transforms, trans.handle)
    if t.parent != {} {
        if parent, ok := hm.get(tree, t.parent); ok {
            if parent.first_child == trans.handle {
                parent.first_child = t.next_sibling
            } else {
                //not the first child, so there must be a predecessor
                prev_sibling := hm.get(tree, parent.first_child)
                for ; prev_sibling.next_sibling != t.handle; prev_sibling = hm.get(tree, prev_sibling.next_sibling) {}
                prev_sibling.next_sibling = t.next_sibling
            }
        }
        t.parent = {}
        t.next_sibling = {}
    }
}

//live, interpolated, user-transforms
Transform :: union {
    //TRS_Angles, //need to think about JSON/promotion semantics
    //TRS?? //maybe not supported in the public API
    TRS_Smoothed,
    Node,
    matrix[4,4]f32, //terminal type, largely for passthrough
}

tree_of :: proc(t: ^Transform) -> ^Tree {
    if t, ok := t.(Node); ok {
        return t.tree
    }
    return nil
}

promote :: proc(t: ^Transform, tt: ^Tree) -> Node {
    switch t in t {
    case Node:
        return t
    case TRS_Smoothed:
        return insert_node_smoothed(t, tt=tt)
    case matrix[4,4]f32:
        tx, rx, sx := get_world_trs(t)
        return insert_node({tx, rx, sx}, tt=tt)
    case nil: //promote nil to ORIGIN
        return insert_node(tt=tt)
    }
    return {}
}

link :: proc(parent, child: ^Transform, tree: ^Tree = nil) {
    parent_tree := tree_of(parent)
    child_tree := tree_of(child)
    tt := parent_tree
    if child_tree != nil {
        assert(parent_tree == nil || parent_tree == child_tree, "parent and child belong to different trees")
        tt = child_tree
    }
    if tt == nil {
        tt = default_tree if tree == nil else tree
    }
    assert(tree == nil || tt == tree, "explicitly passed tree conflicts with parent/child's own tree")
    p := promote(parent, tt)
    c := promote(child, tt)
    link_node(p, c)
    parent^ = p
    child^ = c
}

unlink :: proc(t: ^Transform) {
    if t, ok := t.(Node); ok {
        unlink_node(t)
    }
}

make :: proc(trs: TRS = ORIGIN_TRS, parent: ^Transform = nil, tree: ^Tree = nil) -> (t: Transform) {
    trs := trs
    if trs.rotation == 0 {
        trs.rotation = 1
    }
    if trs.scale == 0 {
        trs.scale = 1
    }
    t = TRS_Smoothed{prev = trs, next = trs} 
    if parent != nil {
        link(parent, &t)
    }
    return t
}

delete :: proc(t: Transform) {
    #partial switch t in t {
        case Node:
        remove_node(t)
    }
}

local_node :: proc(n: Node) -> ^TRS {
    if t, ok := hm.get(&n.tree.transforms, n.handle); ok {
        n.tree.serial += 1
        switch &val in t.local {
        case TRS_Smoothed:
            return clock.write(&val, n.tree.clk)
        case matrix[4,4]f32:
            trs := TRS{get_world_trs(val)}
            t.local = TRS_Smoothed{trs, trs, n.tree.clk.current_tick}
            return clock.write(&t.local.(TRS_Smoothed), n.tree.clk)
        }
    }
    return nil
}

local_trs :: proc(trs: ^TRS) -> ^TRS {
    return trs
}

local_trs_smoothed :: proc(trs: ^TRS_Smoothed, c: ^clock.Clock = clock.default) -> ^TRS {
    return clock.write(trs, c) 
}

local_transform :: proc(t: ^Transform) -> ^TRS {
    switch &val in t {
    case Node:
        return local_node(val)
    case TRS_Smoothed:
        return local_trs_smoothed(&val)
    case matrix[4,4]f32:
        //if you're trying to get a local TRS out of a computed matrix, you probably want extraction...
        //shear would be lost, though.
        trs := TRS{get_world_trs(val)}
        t^ = TRS_Smoothed{trs, trs, clock.default.current_tick}
        return local_trs_smoothed(&t.(TRS_Smoothed), clock.default)
    }
    return nil
}

local :: proc{local_node, local_trs, local_trs_smoothed, local_transform}

compute_trs :: proc(trs: TRS) -> matrix[4,4]f32 {
    return linalg.matrix4_from_trs_f32(**trs)
}

lerp_trs :: proc(a, b: TRS, alpha: f64) -> TRS {
    alpha := f32(alpha)
    return {
        translation = linalg.lerp(a.translation, b.translation, alpha),
        rotation = linalg.quaternion_slerp(a.rotation, b.rotation, alpha),
        scale = linalg.lerp(a.scale, b.scale, alpha),
    }
}

compute_trs_smoothed :: proc(trs: TRS_Smoothed) -> matrix[4,4]f32 {
    return compute_trs(lerp_trs(clock.sample(trs)))
}

compute_node :: proc(n: Node) -> matrix[4,4]f32 {
    sync_tree(n.tree)
    if t, ok := hm.get(&n.tree.transforms, n.handle); ok {
        if t.world_serial != n.tree.serial {
            local: matrix[4,4]f32
            switch val in t.local {
            case TRS_Smoothed:
                local = compute_trs(lerp_trs(clock.sample(val, n.tree.clk)))
            case matrix[4,4]f32:
                local = val
            }
            if t.parent != {} {
                parent_world := compute_node(Node{t.parent, n.tree})
                t.world = parent_world * local
            } else {
                t.world = local
            }
            t.world_serial = n.tree.serial
        }
        return t.world
    }
    return 1
}

compute_transform :: proc(t: Transform) -> matrix[4,4]f32 {
    switch t in t {
    case nil:
        return 1
    case TRS_Smoothed:
        return compute_trs_smoothed(t)
    case Node:
        return compute_node(t)
    case matrix[4,4]f32:
        return t
    }
    return 1
}

world :: proc{compute_trs, compute_trs_smoothed, compute_node, compute_transform}

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

get_parent :: proc(trans: Node) -> Node {
    if t, ok := hm.get(&trans.tree.transforms, trans.handle); ok {
        return {t.parent, trans.tree}
    }
    return {}
}
get_first_child :: proc(trans: Node) -> Node {
    if t, ok := hm.get(&trans.tree.transforms, trans.handle); ok {
        return {t.first_child, trans.tree}
    }
    return {}
}
get_next_sibling :: proc(trans: Node) -> Node {
    if t, ok := hm.get(&trans.tree.transforms, trans.handle); ok {
        return {t.next_sibling, trans.tree}
    }
    return {}
}

//helper procs for Transform itself
translate_t :: proc(t: Node, translation: [3]f32) {
    translate_trs(local(t), translation)
}
rotate_t :: proc(t: Node, rotation: [3]f32) {
    rotate_trs(local(t), rotation)
}
rotatex_t :: proc(t: Node, rotation: f32) {
    rotatex_trs(local(t), rotation)
}
rotatey_t :: proc(t: Node, rotation: f32) {
    rotatey_trs(local(t), rotation)
}
rotatez_t :: proc(t: Node, rotation: f32) {
    rotatez_trs(local(t), rotation)
}
scale_t :: proc(t: Node, scale: [3]f32) {
    scale_trs(local(t), scale)
}

look_at_t :: proc(viewer: Node, target: [3]f32, up: [3]f32 = {0, 1, 0}) {
    look_at_trs(local(viewer), target, up)
}

translate :: proc{translate_trs, translate_t}
rotate :: proc{rotate_trs, rotate_t}
rotatex :: proc{rotatex_trs, rotatex_t}
rotatey :: proc{rotatey_trs, rotatey_t}
rotatez :: proc{rotatez_trs, rotatez_t}
scale :: proc{scale_trs, scale_t}
look_at :: proc{look_at_trs, look_at_t}
