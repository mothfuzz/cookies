package graphics

import "vendor:wgpu"

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

//all instances in a batch will have the same number of bones.
//waha

skeletons_buffer: wgpu.Buffer
skeletons_buffer_len: int
skeletons_buffer_cap: int

realloc_skeletons_buffer :: proc(new_size: int) -> (rebind: bool) {
    new_size_bytes := max(new_size * size_of(matrix[4,4]f32), size_of(matrix[4,4]f32)) //always alloc at least 1
    if new_size_bytes > skeletons_buffer_cap {
        if skeletons_buffer_cap > 0 {
            wgpu.BufferRelease(skeletons_buffer)
        }
        skeletons_buffer = wgpu.DeviceCreateBuffer(ren.device, &{usage={.Storage, .CopyDst}, size = u64(new_size_bytes)})
        skeletons_buffer_cap = new_size_bytes
        rebind = true
    }
    if new_size_bytes != skeletons_buffer_len {
        skeletons_buffer_len = new_size_bytes
        rebind = true
    }
    return
}

delete_skeletons_buffer :: proc() {
    if skeletons_buffer_cap > 0 {
        wgpu.BufferRelease(skeletons_buffer)
    }
}
