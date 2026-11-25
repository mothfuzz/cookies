package graphics

import "vendor:wgpu"
import "core:slice"

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
1. also instances (soon just material params)
2. point lights
3. directional lights
4. spot lights
5. probes
6. cluster headers + cluster items (V * Cluster_Size(v) x vec4 + N x u32)
7. shadow transforms (spot + cascade in one binding)
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

camera_buffer := Growable_Buffer{usage={.Uniform, .Storage, .CopyDst}}

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
delete_camera_bindings :: proc() {
    wgpu.BindGroupLayoutRelease(camera_layout)
    wgpu.BindGroupRelease(camera_bind_group)
    delete_buffer(camera_buffer)
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
delete_material_bindings :: proc() {
    wgpu.BindGroupLayoutRelease(material_layout)
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
delete_instance_bindings :: proc() {
    wgpu.BindGroupLayoutRelease(instances_layout)
    wgpu.BindGroupRelease(instances_bind_group)
    delete_buffer(instance_buffer)
    delete_buffer(skeletons_buffer)
}

lights_layout_entries := []wgpu.BindGroupLayoutEntry{
    //point lights
    wgpu.BindGroupLayoutEntry{
        binding = 0,
        visibility = {.Fragment},
        buffer = {type=.ReadOnlyStorage},
    },
    //directional lights
    wgpu.BindGroupLayoutEntry{
        binding = 1,
        visibility = {.Fragment},
        buffer = {type=.ReadOnlyStorage},
    },
    //spot lights
    wgpu.BindGroupLayoutEntry{
        binding = 2,
        visibility = {.Fragment},
        buffer = {type=.ReadOnlyStorage},
    },
    //light count
    wgpu.BindGroupLayoutEntry{
        binding = 3,
        visibility = {.Fragment},
        buffer = {type=.Uniform},
    },
    //shadow depth sampler (must be Comparison for textureSampleCompare in WGSL)
    wgpu.BindGroupLayoutEntry{
        binding = 4,
        visibility = {.Fragment},
        sampler = {type = .Comparison}
    },
    //shadow color sampler
    wgpu.BindGroupLayoutEntry{
        binding = 5,
        visibility = {.Fragment},
        sampler = {type = .Filtering}
    },
    //point light depth shadows
    wgpu.BindGroupLayoutEntry{
        binding = 6,
        visibility = {.Fragment},
        texture = {sampleType = .Depth, viewDimension = .CubeArray, multisampled=false},
    },
    //point light color shadows
    wgpu.BindGroupLayoutEntry{
        binding = 7,
        visibility = {.Fragment},
        texture = {sampleType = .Float, viewDimension = .CubeArray, multisampled=false},
    },
    //directional light depth shadows
    wgpu.BindGroupLayoutEntry{
        binding = 8,
        visibility = {.Fragment},
        texture = {sampleType = .Depth, viewDimension = ._2DArray, multisampled=false},
    },
    //directional light color shadows
    wgpu.BindGroupLayoutEntry{
        binding = 9,
        visibility = {.Fragment},
        texture = {sampleType = .Float, viewDimension = ._2DArray, multisampled=false},
    },
    //spot light depth shadows
    wgpu.BindGroupLayoutEntry{
        binding = 10,
        visibility = {.Fragment},
        texture = {sampleType = .Depth, viewDimension = ._2DArray, multisampled=false},
    },
    //spot light color shadows
    wgpu.BindGroupLayoutEntry{
        binding = 11,
        visibility = {.Fragment},
        texture = {sampleType = .Float, viewDimension = ._2DArray, multisampled=false},
    },
    //cubemaps texture
    wgpu.BindGroupLayoutEntry{
        binding = 12,
        visibility = {.Fragment},
        texture = {sampleType = .Float, viewDimension = .CubeArray, multisampled=false},
    },
    //cubemaps sampler
    wgpu.BindGroupLayoutEntry{
        binding = 13,
        visibility = {.Fragment},
        sampler = {type = .Filtering}
    },
    //probes buffer
    wgpu.BindGroupLayoutEntry{
        binding = 14,
        visibility = {.Fragment},
        buffer = {type = .ReadOnlyStorage},
    },
    //clusters
    wgpu.BindGroupLayoutEntry{
        binding = 15,
        visibility = {.Fragment},
        buffer = {type = .ReadOnlyStorage},
    },
    //shadow transforms
    wgpu.BindGroupLayoutEntry{
        binding = 16,
        visibility = {.Fragment},
        buffer = {type = .ReadOnlyStorage},
    }
}
lights_layout: wgpu.BindGroupLayout
lights_bind_group: wgpu.BindGroup

point_lights_buffer := Growable_Buffer{usage = {.Storage, .CopyDst}}
directional_lights_buffer := Growable_Buffer{usage = {.Storage, .CopyDst}}
spot_lights_buffer := Growable_Buffer{usage = {.Storage, .CopyDst}}
light_counts_buffer: wgpu.Buffer
shadow_depth_sampler: wgpu.Sampler
shadow_color_sampler: wgpu.Sampler
point_light_depth_shadows := Growable_Texture_Array{size = POINT_SHADOW_RES, format=.Depth32Float, usage={.RenderAttachment}, cubemap=true}
point_light_color_shadows := Growable_Texture_Array{size = POINT_SHADOW_RES, format=.RGBA8Unorm, usage={.RenderAttachment}, cubemap=true}
directional_light_depth_shadows := Growable_Texture_Array{size = DIRECTIONAL_SHADOW_RES, format=.Depth32Float, usage={.RenderAttachment}}
directional_light_color_shadows := Growable_Texture_Array{size = DIRECTIONAL_SHADOW_RES, format=.RGBA8Unorm, usage={.RenderAttachment}}
spot_light_depth_shadows := Growable_Texture_Array{size = SPOT_SHADOW_RES, format=.Depth32Float, usage={.RenderAttachment}}
spot_light_color_shadows := Growable_Texture_Array{size = SPOT_SHADOW_RES, format=.RGBA8Unorm, usage={.RenderAttachment}}
probes_buffer := Growable_Buffer{usage = {.Storage, .CopyDst}}
clusters_buffer := Growable_Buffer{usage = {.Storage, .CopyDst}}
shadow_transforms_buffer := Growable_Buffer{usage = {.Storage, .CopyDst}}

visualize_clusters: bool = false
write_light_buffers :: proc(command_encoder: wgpu.CommandEncoder) {
    //realloc, rebind...
    rebind := lights_bind_group == nil
    rebind |= write_buffer(&point_lights_buffer, f.point_lights.entries[:])
    rebind |= write_buffer(&directional_lights_buffer, f.directional_lights.entries[:])
    rebind |= write_buffer(&spot_lights_buffer, f.spot_lights.entries[:])
    light_counts := Light_Counts_Uniforms{
        total_lights = u32(
            len(f.point_lights.entries) +
            len(f.directional_lights.entries) +
            len(f.spot_lights.entries)
        ),
        directional_lights = u32(len(f.directional_lights.entries)),
        point_shadows = 0,//u32(f.point_lights.num_shadowed),
        directional_shadows = 0,//u32(f.directional_lights.num_shadowed)),
        spot_shadows = 0,//u32(f.spot_lights.num_shadowed),
        visualize_clusters = 1 if visualize_clusters else 0,
    }
    if light_counts_buffer == nil {
        light_counts_buffer = wgpu.DeviceCreateBufferWithDataTyped(ren.device, &{usage={.Uniform, .CopyDst}}, light_counts)
        rebind = true
    } else {
        wgpu.QueueWriteBuffer(ren.queue, light_counts_buffer, 0, &light_counts, size_of(Light_Counts_Uniforms))
    }
    if shadow_depth_sampler == nil {
        shadow_depth_sampler = wgpu.DeviceCreateSampler(ren.device, &{
            minFilter = .Linear,
            magFilter = .Linear,
            mipmapFilter = .Nearest,
            addressModeU = .ClampToEdge,
            addressModeV = .ClampToEdge,
            addressModeW = .ClampToEdge,
            compare = .GreaterEqual,
            maxAnisotropy = 1,
        })
        rebind = true
    }
    if shadow_color_sampler == nil {
        shadow_color_sampler = wgpu.DeviceCreateSampler(ren.device, &{
            minFilter = .Linear,
            magFilter = .Linear,
            mipmapFilter = .Nearest,
            addressModeU = .ClampToEdge,
            addressModeV = .ClampToEdge,
            addressModeW = .ClampToEdge,
            maxAnisotropy = 1,
        })
        rebind = true
    }
    rebind |= grow_texture_array(&point_light_depth_shadows, f.point_lights.num_shadowed)
    rebind |= grow_texture_array(&point_light_color_shadows, f.point_lights.num_shadowed)
    rebind |= grow_texture_array(&directional_light_depth_shadows, len(f.cascade_shadow_transforms))
    rebind |= grow_texture_array(&directional_light_color_shadows, len(f.cascade_shadow_transforms))
    rebind |= grow_texture_array(&spot_light_depth_shadows, f.spot_lights.num_shadowed)
    rebind |= grow_texture_array(&spot_light_color_shadows, f.spot_lights.num_shadowed)
    rebind |= realloc_cubemaps(command_encoder)
    rebind |= write_buffer(&probes_buffer, f.reflection_probes[:])
    rebind |= write_buffer2(&clusters_buffer, f.cluster_headers[:], f.cluster_items[:])
    rebind |= write_buffer(&shadow_transforms_buffer, []matrix[4,4]f32{})
    
    if rebind {
        if lights_bind_group != nil {
            wgpu.BindGroupRelease(lights_bind_group)
        }
        //holy shit
        bindings := []wgpu.BindGroupEntry{
            {binding = 0, buffer = point_lights_buffer.buffer, size = u64(point_lights_buffer.capacity)},
            {binding = 1, buffer = directional_lights_buffer.buffer, size = u64(directional_lights_buffer.capacity)},
            {binding = 2, buffer = spot_lights_buffer.buffer, size = u64(spot_lights_buffer.capacity)},
            {binding = 3, buffer = light_counts_buffer, size = size_of(Light_Counts_Uniforms)},
            {binding = 4, sampler = shadow_depth_sampler},
            {binding = 5, sampler = shadow_color_sampler},
            {binding = 6, textureView = point_light_depth_shadows.texture_view},
            {binding = 7, textureView = point_light_color_shadows.texture_view},
            {binding = 8, textureView = directional_light_depth_shadows.texture_view},
            {binding = 9, textureView = directional_light_color_shadows.texture_view},
            {binding = 10, textureView = spot_light_depth_shadows.texture_view},
            {binding = 11, textureView = spot_light_color_shadows.texture_view},
            {binding = 12, textureView = cubemaps.texture_view},
            {binding = 13, sampler = cubemaps_sampler},
            {binding = 14, buffer = probes_buffer.buffer, size = u64(probes_buffer.capacity)},
            {binding = 15, buffer = clusters_buffer.buffer, size = u64(clusters_buffer.capacity)},
            {binding = 16, buffer = shadow_transforms_buffer.buffer, size = u64(shadow_transforms_buffer.capacity)},
        }
        lights_bind_group = wgpu.DeviceCreateBindGroup(ren.device, &{
            label = "lights",
            layout = lights_layout,
            entryCount = len(bindings),
            entries = raw_data(bindings),
        })
    }
}
bind_light_data :: proc(render_pass: wgpu.RenderPassEncoder) {
    wgpu.RenderPassEncoderSetBindGroup(render_pass, u32(Bind_Groups.Lighting), lights_bind_group)
}
delete_light_bindings :: proc() {
    wgpu.BindGroupLayoutRelease(lights_layout)
    wgpu.BindGroupRelease(lights_bind_group)
    delete_buffer(point_lights_buffer)
    delete_buffer(directional_lights_buffer)
    delete_buffer(spot_lights_buffer)
    wgpu.BufferRelease(light_counts_buffer)
    wgpu.SamplerRelease(shadow_depth_sampler)
    wgpu.SamplerRelease(shadow_color_sampler)
    delete_texture_array(point_light_depth_shadows)
    delete_texture_array(point_light_color_shadows)
    delete_texture_array(directional_light_depth_shadows)
    delete_texture_array(directional_light_color_shadows)
    delete_texture_array(spot_light_depth_shadows)
    delete_texture_array(spot_light_color_shadows)
    delete_buffer(probes_buffer)
    delete_buffer(clusters_buffer)
    delete_buffer(shadow_transforms_buffer)
}

delete_renderer_bindings :: proc() {
    delete_camera_bindings()
    delete_material_bindings()
    delete_instance_bindings()
    delete_light_bindings()
}
