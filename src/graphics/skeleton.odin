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
//so calculating the starting bone would simpyly be N * instance_index.
//waha

skeletons_layout_entries := []wgpu.BindGroupLayoutEntry{
    //just bones
    wgpu.BindGroupLayoutEntry{
        binding = 0,
        visibility = {.Vertex},
        buffer = {type=.ReadOnlyStorage}
    },
    //length of bones per-batch
    wgpu.BindGroupLayoutEntry{
        binding = 1,
        visibility = {.Vertex},
        buffer = {type=.Uniform}
    }
}
skeletons_layout: wgpu.BindGroupLayout
skeletons_bind_group: wgpu.BindGroup
skeletons_buffer: wgpu.Buffer

//skeletons is flat array of num_bones_in_pose * num_instances
bind_skeletons :: proc(render_pass: wgpu.RenderPassEncoder, slot: u32, skeletons: []matrix[4,4]f32, num_instances: u32) {
    //if len(skeletons) > 1 {
        //fmt.println("BINDING SKELETONS:", skeletons)
    //}

    skeletons_buffer := wgpu.DeviceCreateBufferWithDataSlice(ren.device, &{usage={.Storage}}, skeletons)
    defer wgpu.BufferRelease(skeletons_buffer)
    skeletons_uniform_buffer := wgpu.DeviceCreateBufferWithData(ren.device, &{usage={.Uniform, .CopyDst}}, u32(len(skeletons))/num_instances)
    defer wgpu.BufferRelease(skeletons_uniform_buffer)

    bindings := []wgpu.BindGroupEntry{
        {binding = 0, buffer=skeletons_buffer, size=size_of(matrix[4,4]f32)*u64(len(skeletons))},
        {binding = 1, buffer=skeletons_uniform_buffer, size=size_of(u32)},
    }
    skeletons_bind_group := wgpu.DeviceCreateBindGroup(ren.device, &{
        layout = skeletons_layout,
        entryCount = len(bindings),
        entries = raw_data(bindings),
    })
    defer wgpu.BindGroupRelease(skeletons_bind_group)

    wgpu.RenderPassEncoderSetBindGroup(render_pass, slot, skeletons_bind_group)
}
