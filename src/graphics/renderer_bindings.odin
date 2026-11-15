package graphics

import "vendor:wgpu"

//0 - view data
//1 - material data
//2 - instance data
//3 - lighting data

/*
storage buffers - 
8 max per stage
vertex - 
1. instances
2. skeletons
fragment - 
1. also instances
2. point lights
3. directional lights
4. spot lights
5. light indices (later clusters)
6. shadow transforms (spot + cascade in one binding)
others...?
*/

Bind_Groups :: enum u8 {
    Camera,   //view
    Material, //pass
    Instance, //draw
    Lighting, //frame
}
Bind_Group_Rebind :: bit_set[Bind_Groups]

camera_layout_entries := []wgpu.BindGroupLayoutEntry{
    //camera buffer
    {
        binding = 0,
        visibility = {.Vertex, .Fragment},
        buffer = {type = .Uniform, hasDynamicOffset = true},
    },
}
camera_layout: wgpu.BindGroupLayout
camera_bind_group: wgpu.BindGroup

camera_buffer := Growable_Buffer{usage={.Uniform, .CopyDst}}

write_camera_buffer :: proc() {
    rebind := camera_bind_group == nil
    rebind |= write_buffer(&camera_buffer, f.cameras[:])
    if rebind {
        if camera_bind_group != nil {
            wgpu.BindGroupRelease(camera_bind_group)
        }
        bindings := []wgpu.BindGroupEntry{
            {binding = 0, buffer = camera_buffer.buffer, size = size_of(Camera_Uniforms)}
        }
        camera_bind_group = wgpu.DeviceCreateBindGroup(ren.device, &{
            label = "camera",
            layout = camera_layout,
            entryCount = len(bindings),
            entries = raw_data(bindings)
        })
    }
}

bind_camera_data :: proc(render_pass: wgpu.RenderPassEncoder, camera_index: u32) {
    offset := camera_index * size_of(Camera_Uniforms)
    wgpu.RenderPassEncoderSetBindGroup(render_pass, u32(Bind_Groups.Camera), camera_bind_group, {offset})
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
    //ids is a vertex array
}
instances_layout: wgpu.BindGroupLayout
instances_bind_group: wgpu.BindGroup

instance_buffer := Growable_Buffer{usage={.Storage, .CopyDst}}
skeletons_buffer := Growable_Buffer{usage={.Storage, .CopyDst}}

write_instance_buffers :: proc() {
    rebind := instances_bind_group == nil
    rebind |= write_buffer(&instance_buffer, f.instances[:])
    rebind |= write_buffer(&skeletons_buffer, f.skeletons[:])
    if rebind {
        if instances_bind_group != nil {
            wgpu.BindGroupRelease(instances_bind_group)
        }
        bindings := []wgpu.BindGroupEntry{
            {binding = 0, buffer = instance_buffer.buffer, size = u64(instance_buffer.capacity)},
            {binding = 1, buffer = skeletons_buffer.buffer, size = u64(skeletons_buffer.capacity)},
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

// TODO: lighting

write_light_buffers :: proc() {
    
}
