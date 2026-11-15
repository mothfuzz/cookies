package graphics

import "vendor:wgpu"

//growable buffers & texture arrays

Growable_Buffer :: struct {
    buffer: wgpu.Buffer,
    usage: wgpu.BufferUsageFlags,
    capacity: u64,
}

//new_size in bytes
grow_buffer :: proc(g: ^Growable_Buffer, new_len: int, $T: typeid) -> bool {
    new_cap := size_of(T) * max(1, new_len) //wgpu buffers can't be zero-sized
    if u64(new_cap) > g.capacity || g.buffer == nil {
        g.capacity = u64(new_cap) //g.capacity * 2
        if g.buffer != nil do wgpu.BufferRelease(g.buffer)
        g.buffer = wgpu.DeviceCreateBuffer(ren.device, &{usage = g.usage, size = g.capacity})
        return true
    }
    return false
}

write_buffer :: proc(g: ^Growable_Buffer, data: []$T) -> (rebind: bool) {
    rebind = grow_buffer(g, len(data), T)
    if len(data) > 0 {
        wgpu.QueueWriteBuffer(ren.queue, g.buffer, 0, raw_data(data), len(data)*size_of(T))
    }
    return
}
