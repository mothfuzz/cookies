package graphics

import "vendor:wgpu"

//0 - view data
//1 - material data
//2 - instance data
//3 - lighting data

//just moving instance data here for now since the bind group covers skeletons & instances
//and I didn't want to put them in either file

/*
storage buffers - 
8 max per stage
vertex - 
1. instances
2. skeletons
fragment - 
1. local lights
2. global lights
3. light indices
4. local light shadow transforms
5. global light shadow transforms
others...?
*/

Bind_Groups :: enum u8 {
    View,
    Material,
    Instance,
    Lighting,
}
Bind_Group_Rebind :: bit_set[Bind_Groups]

Growable_Buffer :: struct {
    buffer: wgpu.Buffer,
    capacity: int,
}

view_layout_entries := []wgpu.BindGroupLayoutEntry{
    //camera buffer
    {
        binding = 0,
        visibility = {.Vertex, .Fragment}, //does camera need .Fragment?
        buffer = {type = .Uniform, hasDynamicOffset = true},
    },
}
view_layout: wgpu.BindGroupLayout
view_bind_group: wgpu.BindGroup

bind_view_data :: proc(render_pass: wgpu.RenderPassEncoder, buffer_index: u32) {
    offset := buffer_index * u32(cam_buffer.stride)
    wgpu.RenderPassEncoderSetBindGroup(render_pass, u32(Bind_Groups.View), view_bind_group, {offset})
}

material_layout_entries := []wgpu.BindGroupLayoutEntry{
    wgpu.BindGroupLayoutEntry{
        binding = 0,
        visibility = {.Fragment},
        sampler = {type = .Filtering},
    },
    //base_color
    wgpu.BindGroupLayoutEntry{
        binding = 1,
        visibility = {.Fragment},
        texture = {sampleType = .Float, viewDimension = ._2D},
    },
    //normal
    wgpu.BindGroupLayoutEntry{
        binding = 2,
        visibility = {.Fragment},
        texture = {sampleType = .Float, viewDimension = ._2D},
    },
    //pbr
    wgpu.BindGroupLayoutEntry{
        binding = 3,
        visibility = {.Fragment},
        texture = {sampleType = .Float, viewDimension = ._2D},
    },
    //emissive
    wgpu.BindGroupLayoutEntry{
        binding = 4,
        visibility = {.Fragment},
        texture = {sampleType = .Float, viewDimension = ._2D},
    },
}
material_layout: wgpu.BindGroupLayout
//bind group owned per-material

make_material_bind_group :: proc(base_color, normal, pbr, emissive: wgpu.TextureView, sampler: wgpu.Sampler) -> (bind_group: wgpu.BindGroup){
    bindings := []wgpu.BindGroupEntry{
        {binding = 0, sampler = sampler},
        {binding = 1, textureView = base_color},
        {binding = 2, textureView = normal},
        {binding = 3, textureView = pbr},
        {binding = 4, textureView = emissive},
    }
    bind_group = wgpu.DeviceCreateBindGroup(ren.device, &{
        layout = material_layout,
        entryCount = len(bindings),
        entries = raw_data(bindings),
    })
    return
}
delete_material_bind_group :: proc(bind_group: wgpu.BindGroup) {
    wgpu.BindGroupRelease(bind_group)
}
bind_material :: proc(render_pass: wgpu.RenderPassEncoder, bind_group: wgpu.BindGroup) {
    wgpu.RenderPassEncoderSetBindGroup(render_pass, u32(Bind_Groups.Material), bind_group)
}

instances_layout_entries := []wgpu.BindGroupLayoutEntry{
    //instance data
    {
        binding = 0,
        visibility = {.Vertex, .Fragment},
        buffer = {type=.ReadOnlyStorage},
    },
    //just bones
    {
        binding = 1,
        visibility = {.Vertex},
        buffer = {type=.ReadOnlyStorage},
    },
}
instances_layout: wgpu.BindGroupLayout
instances_bind_group: wgpu.BindGroup

write_instance_buffers :: proc(instances: []Instance_Uniforms, skeletons: []matrix[4,4]f32) {
    rebind := instances_bind_group == nil
    rebind |= realloc_skeletons_buffer(len(skeletons))
    rebind |= realloc_instance_buffer(len(instances))
    wgpu.QueueWriteBuffer(ren.queue, instance_buffer, 0, raw_data(instances), len(instances) * size_of(Instance_Uniforms))
    wgpu.QueueWriteBuffer(ren.queue, skeletons_buffer, 0, raw_data(skeletons), len(skeletons) * size_of(matrix[4,4]f32))
    if rebind {
        if instances_bind_group != nil {
            wgpu.BindGroupRelease(instances_bind_group)
        }
        bindings := []wgpu.BindGroupEntry{
            {binding = 0, buffer = instance_buffer, size = u64(instance_buffer_cap)},
            {binding = 1, buffer = skeletons_buffer, size = u64(skeletons_buffer_cap)},
        }
        instances_bind_group = wgpu.DeviceCreateBindGroup(ren.device, &{
            label = "instances",
            layout = instances_layout,
            entryCount = len(bindings),
            entries = raw_data(bindings),
        })
    }
}

bind_instance_data :: proc(render_pass: wgpu.RenderPassEncoder) {
    wgpu.RenderPassEncoderSetBindGroup(render_pass, u32(Bind_Groups.Instance), instances_bind_group)
}
