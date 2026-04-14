package graphics

import "cookies:transform"

Bone :: struct {
    node: uint, //contains name, parent, etc
    inv_bind: matrix[4,4]f32,
}

Skeleton :: struct {
    name: string,
    bones: []Bone,
    root: uint,
}

delete_skeleton :: proc(sk: Skeleton) {
    delete(sk.bones)
}


//This is also where GPU buffer management will go, once that's implemented.
// TODO: in order to support procedural bone animation we should have a bone 'overlay' struct
// similar to how Animations will overwrite the bone transform,
// we should do this with whatever matrix the user wants to pass.
