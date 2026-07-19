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

skeletons_layout_entries := []wgpu.BindGroupLayoutEntry{
    //just bones
    wgpu.BindGroupLayoutEntry{
        binding = 0,
        visibility = {.Vertex},
        buffer = {type=.ReadOnlyStorage}
    },
}
skeletons_layout: wgpu.BindGroupLayout
skeletons_bind_group: wgpu.BindGroup
skeletons_buffer: wgpu.Buffer
skeletons_buffer_len: int
skeletons_buffer_cap: int

realloc_skeletons_buffer :: proc(new_size: int) {
    new_size_bytes := max(new_size * size_of(matrix[4,4]f32), size_of(matrix[4,4]f32)) //always alloc at least 1
    rebind := skeletons_bind_group == nil
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
    if rebind {
        if skeletons_bind_group != nil {
            wgpu.BindGroupRelease(skeletons_bind_group)
        }
        bindings := []wgpu.BindGroupEntry{
            {binding = 0, buffer = skeletons_buffer, size = u64(skeletons_buffer_len)},
        }
        skeletons_bind_group = wgpu.DeviceCreateBindGroup(ren.device, &{
            label = "skeletons",
            layout = skeletons_layout,
            entryCount = len(bindings),
            entries = raw_data(bindings),
        })
    }
}

delete_skeletons_buffer :: proc() {
    if skeletons_bind_group != nil {
        wgpu.BindGroupRelease(skeletons_bind_group)
    }
    if skeletons_buffer_cap > 0 {
        wgpu.BufferRelease(skeletons_buffer)
    }
}


bind_skeletons :: proc(render_pass: wgpu.RenderPassEncoder, slot: u32) {
    wgpu.RenderPassEncoderSetBindGroup(render_pass, slot, skeletons_bind_group)
}
