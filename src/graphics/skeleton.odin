package graphics

import "cookies:transform"

Bone :: struct {
    name: string,
    node: ^transform.Transform,
    inv_bind: matrix[4,4]f32,
}

Skeleton :: struct {
    name: string,
    bones: []Bone,
    root: int,
}

delete_skeleton :: proc(sk: Skeleton) {
    delete(sk.bones)
}


//This is also where GPU buffer management will go, once that's implemented.
