package graphics

import "core:fmt"
import "core:math/linalg"
import "vendor:wgpu"

Vertex :: struct {
    position: [3]f32,
    texcoord: [2]f32,
    color: [4]f32,
}

Mesh :: struct {
    size: u32,
    //buffers
    positions: wgpu.Buffer,
    texcoords: wgpu.Buffer,
    colors: wgpu.Buffer,
    indices: wgpu.Buffer,
}

make_mesh_array :: proc(vertices: [$i]Vertex, indices: []u32 = nil) -> (mesh: Mesh) {
    new_vertices := #soa[i]Vertex
    for i in 0..<i {
        new_vertices[i] = vertices[i]
    }
    mesh = make_mesh_soa(new_vertices, indices)
    return
}
make_mesh_slice :: proc(vertices: []Vertex, indices: []u32 = nil) -> (mesh: Mesh) {
    size := len(vertices)
    new_vertices := make(#soa[]Vertex, size)
    for i in 0..<size {
        new_vertices[i] = vertices[i]
    }
    mesh = make_mesh_soa(new_vertices, indices)
    delete(new_vertices)
    return
}
make_mesh_soa :: proc(vertices: #soa[]Vertex, indices: []u32 = nil) -> (mesh: Mesh) {
    n := len(vertices)
    mesh.positions = wgpu.DeviceCreateBufferWithDataSlice(ren.device, &{usage={.Vertex, .CopyDst}}, vertices.position[0:n])
    mesh.texcoords = wgpu.DeviceCreateBufferWithDataSlice(ren.device, &{usage={.Vertex, .CopyDst}}, vertices.texcoord[0:n])
    mesh.colors = wgpu.DeviceCreateBufferWithDataSlice(ren.device, &{usage={.Vertex, .CopyDst}}, vertices.color[0:n])
    if indices != nil {
        mesh.indices = wgpu.DeviceCreateBufferWithDataSlice(ren.device, &{usage={.Index, .CopyDst}}, indices)
        mesh.size = u32(len(indices))
    } else {
        mesh.size = u32(len(vertices))
    }
    return
}
delete_mesh :: proc(mesh: Mesh) {
    wgpu.BufferDestroy(mesh.positions)
    wgpu.BufferDestroy(mesh.texcoords)
    wgpu.BufferDestroy(mesh.colors)
    if mesh.indices != nil {
        wgpu.BufferDestroy(mesh.indices)
    }
}

make_mesh :: proc{make_mesh_array, make_mesh_slice, make_mesh_soa}

position_attribute := wgpu.VertexBufferLayout{
    stepMode = .Vertex,
    arrayStride = size_of([3]f32),
    attributeCount = 1,
    attributes = &wgpu.VertexAttribute{format = .Float32x3, shaderLocation = 0},
}
texcoord_attribute := wgpu.VertexBufferLayout{
    stepMode = .Vertex,
    arrayStride = size_of([2]f32),
    attributeCount = 1,
    attributes = &wgpu.VertexAttribute{format = .Float32x2, shaderLocation = 1},
}
color_attribute := wgpu.VertexBufferLayout{
    stepMode = .Vertex,
    arrayStride = size_of([4]f32),
    attributeCount = 1,
    attributes = &wgpu.VertexAttribute{format = .Float32x4, shaderLocation = 2},
}

instance_data_location: u32 = 3
instance_data_attributes := []wgpu.VertexAttribute{
    {format = .Float32x4, offset = 0 * size_of([4]f32), shaderLocation = instance_data_location + 0},
    {format = .Float32x4, offset = 1 * size_of([4]f32), shaderLocation = instance_data_location + 1},
    {format = .Float32x4, offset = 2 * size_of([4]f32), shaderLocation = instance_data_location + 2},
    {format = .Float32x4, offset = 3 * size_of([4]f32), shaderLocation = instance_data_location + 3},
    {format = .Float32x4, offset = 4 * size_of([4]f32), shaderLocation = instance_data_location + 4},
}
instance_data_attribute := wgpu.VertexBufferLayout{
    stepMode = .Instance,
    arrayStride = size_of(InstanceData),
    attributeCount = len(instance_data_attributes),
    attributes = raw_data(instance_data_attributes),
}

InstanceData :: struct {
    using buffer_data: InstanceBufferData,
    is_sprite: bool,
    is_billboard: bool,
}
InstanceBufferData :: struct {
    model: matrix[4,4]f32,
    clip_rect: [4]f32,
}

//more often do we have the same mesh with different textures
//than we have the same texture on different meshes
batches: map[Mesh]map[Material][dynamic]InstanceData

bind_mesh :: proc(render_pass: wgpu.RenderPassEncoder, mesh: Mesh) {
    wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 0, mesh.positions, 0, wgpu.BufferGetSize(mesh.positions))
    wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 1, mesh.texcoords, 0, wgpu.BufferGetSize(mesh.texcoords))
    wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 2, mesh.colors, 0, wgpu.BufferGetSize(mesh.colors))
}

//assumes material & mesh are already bound.
@(private)
draw_batch :: proc(render_pass: wgpu.RenderPassEncoder, mesh: Mesh, material: Material, cam: ^Camera) {
    batches := &batches[mesh]
    instances := &batches[material]

    instances_actual := make([]InstanceBufferData, len(instances))
    defer delete(instances_actual)
    for instance, i in instances {
        w := f32(wgpu.TextureGetWidth(material.albedo.image))
        h := f32(wgpu.TextureGetHeight(material.albedo.image))
        instances_actual[i].clip_rect.x = instance.clip_rect.x / w
        instances_actual[i].clip_rect.y = instance.clip_rect.y / h
        if instance.clip_rect[2] == 0 {
            instances_actual[i].clip_rect[2] = 1.0
        } else {
            instances_actual[i].clip_rect[2] = instance.clip_rect[2] / w
        }
        if instance.clip_rect[3] == 0 {
            instances_actual[i].clip_rect[3] = 1.0
        } else {
            instances_actual[i].clip_rect[3] = instance.clip_rect[3] / h
        }

        if instance.is_sprite {
            instances_actual[i].model = instance.model
            instances_actual[i].model[3] = {0, 0, 0, 1}
            scale := linalg.matrix4_scale([3]f32{instance.clip_rect[2], instance.clip_rect[3], 1.0})
            instances_actual[i].model *= scale
            instances_actual[i].model[3] = instance.model[3]
        } else {
            instances_actual[i].model = instance.model
        }
        view_model: matrix[4,4]f32
        if instance.is_billboard {
            rotation_scale := cast(matrix[3,3]f32)(instances_actual[i].model)
            view_model = cam.view * instances_actual[i].model;
            trans := view_model[3] //save produced translation vector
            view_model = cast(matrix[4,4]f32)(rotation_scale) //and then revert to untransformed scaling/rotation
            view_model[3] = trans
        } else {
            view_model = cam.view * instances_actual[i].model
        }
        instances_actual[i].model = cam.projection * view_model

    }
    instance_buffer := wgpu.DeviceCreateBufferWithDataSlice(ren.device, &{usage={.Vertex, .CopyDst}}, instances_actual)
    wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 3, instance_buffer, 0, wgpu.BufferGetSize(instance_buffer))
    wgpu.BufferRelease(instance_buffer)

    if mesh.indices != nil {
        wgpu.RenderPassEncoderSetIndexBuffer(render_pass, mesh.indices, .Uint32, 0, wgpu.BufferGetSize(mesh.indices))
        wgpu.RenderPassEncoderDrawIndexed(render_pass, mesh.size, u32(len(instances_actual)), 0, 0, 0)
    } else {
        wgpu.RenderPassEncoderDraw(render_pass, mesh.size, u32(len(instances_actual)), 0, 0)
    }
}

@(private)
clear_batches :: proc() {
    for mesh, &batch in batches {
        for material, &instances in batch {
            clear(&instances)
        }
    }
}

draw_mesh :: proc(mesh: Mesh, material: Material, model: matrix[4, 4]f32 = 0, clip_rect: [4]f32 = 0, sprite: bool = false, billboard: bool = false) {
    model := model
    if !(mesh in batches) {
        batches[mesh] = {}
    }
    batch := &batches[mesh]
    if !(material in batch) {
        //create instance buffer
        batch[material] = make([dynamic]InstanceData, 0)
    }
    instances := &batch[material]
    append(instances, InstanceData{{model, clip_rect}, sprite, billboard})
}

sprite_mesh: Mesh

draw_sprite :: proc(material: Material, model: matrix[4, 4]f32 = 0, clip_rect: [4]f32 = 0, billboard: bool = true) {
    if sprite_mesh.size == 0 {
        sprite_mesh = make_mesh([]Vertex{
            {position={-0.5, +0.5, 0.0}, texcoord={0.0, 0.0}, color={1, 1, 1, 1}},
            {position={+0.5, +0.5, 0.0}, texcoord={1.0, 0.0}, color={1, 1, 1, 1}},
            {position={+0.5, -0.5, 0.0}, texcoord={1.0, 1.0}, color={1, 1, 1, 1}},
            {position={-0.5, -0.5, 0.0}, texcoord={0.0, 1.0}, color={1, 1, 1, 1}},
        }, {0, 1, 2, 0, 2, 3})
    }
    draw_mesh(sprite_mesh, material, model, clip_rect, true, billboard)
}
