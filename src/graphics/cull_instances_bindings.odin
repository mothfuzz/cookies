package graphics

import "vendor:wgpu"

cull_bind_group: wgpu.BindGroup
cull_layout: wgpu.BindGroupLayout
cull_layout_entries :: []wgpu.BindGroupLayoutEntry{
    //draws
    {binding = 0, visibility = {.Compute}, buffer = {type=.Storage}},
    //instance ids
    {binding = 1, visibility = {.Compute}, buffer = {type=.Storage}},
    //cameras
    {binding = 2, visibility = {.Compute}, buffer = {type=.ReadOnlyStorage}},
    //cull counts
    {binding = 3, visibility = {.Compute}, buffer = {type=.Uniform}},
    //bins
    {binding = 4, visibility = {.Compute}, buffer = {type=.ReadOnlyStorage}},
    //batch offsets
    {binding = 5, visibility = {.Compute}, buffer = {type=.ReadOnlyStorage}},
}
batch_offsets_buffer := Growable_Buffer{usage={.Storage, .CopyDst}}
instance_bins_buffer := Growable_Buffer{usage={.Storage, .CopyDst}}
cull_counts_buffer: wgpu.Buffer

write_cull_buffers :: proc(batch_offsets: []u32) {
    rebind := cull_bind_group == nil
    cull_counts := Cull_Counts_Uniforms{
        num_batches = u32(len(f.batches)),
        num_bins = u32(len(f.instance_bins))
    }
    if cull_counts_buffer == nil {
        cull_counts_buffer = wgpu.DeviceCreateBufferWithData(ren.device, &{usage={.Uniform, .CopyDst}}, cull_counts)
        rebind = true
    } else {
        wgpu.QueueWriteBuffer(ren.queue, cull_counts_buffer, 0, &cull_counts, size_of(Cull_Counts_Uniforms))
    }

    rebind |= write_buffer(&batch_offsets_buffer, batch_offsets)
    rebind |= write_buffer(&instance_bins_buffer, f.instance_bins[:])

    rebind |= write_buffer(&draws_buffer, f.draws[:])
    rebind |= grow_instance_ids()

    if rebind {
        if cull_bind_group != nil {
            wgpu.BindGroupRelease(cull_bind_group)
        }
        bindings := []wgpu.BindGroupEntry{
            {binding = 0, buffer = draws_buffer.buffer, size = u64(draws_buffer.capacity)},
            {binding = 1, buffer = instance_id_buffer.buffer, size = u64(instance_id_buffer.capacity)},
            {binding = 2, buffer = camera_buffer.buffer, size = u64(camera_buffer.capacity)},
            {binding = 3, buffer = cull_counts_buffer, size = size_of(Cull_Counts_Uniforms)},
            {binding = 4, buffer = instance_bins_buffer.buffer, size = u64(instance_bins_buffer.capacity)},
            {binding = 5, buffer = batch_offsets_buffer.buffer, size = u64(batch_offsets_buffer.capacity)},
        }
        cull_bind_group = wgpu.DeviceCreateBindGroup(ren.device, &{
            label = "instance culling",
            layout = cull_layout,
            entryCount = len(bindings),
            entries = raw_data(bindings),
        })
    }
}

delete_cull_bindings :: proc() {
    if cull_bind_group != nil {
        wgpu.BindGroupRelease(cull_bind_group)
    }
    if cull_layout != nil {
        wgpu.BindGroupLayoutRelease(cull_layout)
    }
    delete_buffer(batch_offsets_buffer)
    delete_buffer(instance_bins_buffer)
    if cull_counts_buffer != nil {
        wgpu.BufferRelease(cull_counts_buffer)
    }
}
