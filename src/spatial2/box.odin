package spatial2

import "core:math/linalg"

Box :: struct {
    center: [3]f32,
    half_extents: [3]f32,
}

box_extents :: proc(b: Box, t: matrix[4,4]f32) -> [2][3]f32 {
    center := (t * [4]f32{**b.center, 1}).xyz
    axes := [3][3]f32{t[0].xyz * b.half_extents.x, t[1].xyz * b.half_extents.y, t[2].xyz * b.half_extents.z}
    //Arvo's method
    e: [3]f32
    for a in axes {
        e += linalg.abs(a)
    }
    return {center - e, center + e}
}

aabb_aabb :: proc(a: [2][3]f32, b: [2][3]f32) -> bool {
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
        if abs(ta[i]) > a.half_extents[i] + b.half_extents[i] {
            return false
        }
    }

    //if absolute values of b_rot are near-1, then B is aligned with A's axes, and we can skip the other checks
    ALIGNED :: 1 - 1e-4
    if max(abs_r[0,0], abs_r[0,1], abs_r[0, 2]) > ALIGNED &&
        max(abs_r[1, 0], abs_r[1, 1], abs_r[1, 2]) > ALIGNED &&
        max(abs_r[2, 0], abs_r[2, 1], abs_r[2, 2]) > ALIGNED {
            return true
        }

    //if not, check B's 3 face axes...
    ra := linalg.transpose(abs_r) * a.half_extents
    tb := linalg.transpose(b_rot) * ta
    for i in 0..<3 {
        if abs(tb[i]) > a.half_extents[i] + b.half_extents[i] {
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

box_overlapping :: proc(a: Box, atrans: matrix[4,4]f32, b: Shape, btrans: matrix[4,4]f32) -> bool {
    #partial switch b in b {
        case Box:
        //A is axis-aligned in this frame
        a_local, a_frame := box_frame(a, atrans)
        b_local, b_frame := box_frame(b, btrans)
        //construct matrix of B's axes in A's frame
        b_rot: matrix[3,3]f32
        for i in 0..<3 {
            col := frame_vector(a_frame, b_frame.axes[i])
            b_rot[0, i] = col.x
            b_rot[1, i] = col.y
            b_rot[2, i] = col.z
        }
        b_world := b_frame.origin +
            b_frame.axes[0] * b_local.center.x +
            b_frame.axes[1] * b_local.center.y +
            b_frame.axes[2] * b_local.center.z
        //B's center is in A's frame, but B's extents are measured along its own axes, so b_rot can be used
        b_local = Box{frame_point(a_frame, b_world), b_local.half_extents}
        return box_box(a_local, b_local, b_rot)
        case Sphere:
        local, frame := box_frame(a, atrans)
        bt := transform_sphere(b, btrans)
        bt.center = frame_point(frame, bt.center)
        return sphere_aabb(bt, local)
    }
    return false
}

//for transforming other shapes into a box's local space
Box_Frame :: struct {
    origin: [3]f32,
    axes: [3][3]f32,
}

box_frame :: proc(b: Box, t: matrix[4,4]f32) -> (local: Box, frame: Box_Frame) {
    scale := [3]f32{linalg.length(t[0].xyz), linalg.length(t[1].xyz), linalg.length(t[2].xyz)}
    frame.origin = t[3].xyz
    frame.axes = {t[0].xyz / scale.x, t[1].xyz / scale.y, t[2].xyz / scale.z}
    local = {b.center * scale, b.half_extents * scale}
    return
}

frame_vector :: proc(frame: Box_Frame, v: [3]f32) -> [3]f32 {
    //project v onto the box's local axes
    return {linalg.dot(frame.axes[0], v), linalg.dot(frame.axes[1], v), linalg.dot(frame.axes[2], v)}
}

frame_point :: proc(frame: Box_Frame, p: [3]f32) -> [3]f32 {
    return frame_vector(frame, p - frame.origin)
}
