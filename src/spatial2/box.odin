package spatial2

import "core:math/linalg"

Box :: struct {
    center: [3]f32,
    half_extents: [3]f32,
}

AABB :: [2][3]f32

box_support :: proc(b: Box, dir: [3]f32) -> [3]f32 {
    return b.center + {
        dir.x >= 0 ? b.half_extents.x : -b.half_extents.x,
        dir.y >= 0 ? b.half_extents.y : -b.half_extents.y,
        dir.z >= 0 ? b.half_extents.z : -b.half_extents.z,
    }
}

//only for untransformed box
box_aabb :: proc(b: Box) -> AABB {
    return {b.center - b.half_extents, b.center + b.half_extents}
}

aabb_aabb :: proc(a: AABB, b: AABB) -> bool {
    return a[1].x >= b[0].x &&
            a[1].y >= b[0].y &&
            a[1].z >= b[0].z &&
            a[0].x <= b[1].x &&
            a[0].y <= b[1].y &&
            a[0].z <= b[1].z
}

box_box :: proc(a: Box, b: Box, b_rot: matrix[3,3]f32) -> bool {
    EPSILON :: 1e-6 //keep degeneration in near-parallel cross products
    abs_r: matrix[3,3]f32
    for i in 0..<3 {
        for j in 0..<3 {
            abs_r[i, j] = abs(b_rot[i, j]) + EPSILON
        }
    }

    //A's 3 face axes
    rb := abs_r * b.half_extents
    ta := b.center - a.center
    for i in 0..<3 {
        if abs(ta[i]) > a.half_extents[i] + rb[i] {
            return false
        }
    }

    //check B's 3 face axes
    ra := linalg.transpose(abs_r) * a.half_extents
    tb := linalg.transpose(b_rot) * ta
    for i in 0..<3 {
        if abs(tb[i]) > ra[i] + b.half_extents[i] {
            return false
        }
    }

    //lastly the 9 cross-axes AxB
    for i in 0..<3 {
        //rotate i...
        i0, i1, i2 := (i+0)%3, (i+1)%3, (i+2)%3
        for j in 0..<3 {
            //rotate j...
            j0, j1, j2 := (j+0)%3, (j+1)%3, (j+2)%3
            ra := a.half_extents[i1]*abs_r[i2, j0] + a.half_extents[i2]*abs_r[i1, j0]
            rb := b.half_extents[j1]*abs_r[i0, j2] + b.half_extents[j2]*abs_r[i0, j1]
            if abs(ta[i2]*b_rot[i1, j0] - ta[i1]*b_rot[i2, j0]) > ra + rb {
                return false
            }
        }
    }
    
    return true
}

