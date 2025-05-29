package graphics

import "core:fmt"
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

model_location: u32 = 3
model_attributes := []wgpu.VertexAttribute{
    {format = .Float32x4, offset = 0 * size_of([4]f32), shaderLocation = model_location + 0},
    {format = .Float32x4, offset = 1 * size_of([4]f32), shaderLocation = model_location + 1},
    {format = .Float32x4, offset = 2 * size_of([4]f32), shaderLocation = model_location + 2},
    {format = .Float32x4, offset = 3 * size_of([4]f32), shaderLocation = model_location + 3},
}
model_attribute := wgpu.VertexBufferLayout{
    stepMode = .Instance,
    arrayStride = size_of(matrix[4, 4]f32),
    attributeCount = len(model_attributes),
    attributes = raw_data(model_attributes),
}

Batch :: struct {
    models: [dynamic]matrix[4,4]f32,
    buffer: wgpu.Buffer,
    cap: u32,
}
//more often do we have the same mesh with different textures
//than we have the same texture on different meshes
batches: map[Mesh]map[Material]Batch

bind_mesh :: proc(render_pass: wgpu.RenderPassEncoder, mesh: Mesh) {
    wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 0, mesh.positions, 0, wgpu.BufferGetSize(mesh.positions))
    wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 1, mesh.texcoords, 0, wgpu.BufferGetSize(mesh.texcoords))
    wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 2, mesh.colors, 0, wgpu.BufferGetSize(mesh.colors))
}

//assumes material & mesh are already bound.
@(private)
draw_batch :: proc(render_pass: wgpu.RenderPassEncoder, mesh: Mesh, material: Material) {
    batches := &batches[mesh]
    instances := &batches[material]

    len := len(instances.models)
    size := u64(instances.cap * size_of(matrix[4,4]f32))
    if wgpu.BufferGetSize(instances.buffer) != size {
        wgpu.BufferDestroy(instances.buffer)
        instances.buffer = wgpu.DeviceCreateBuffer(ren.device, &{usage={.Vertex, .CopyDst}, size=size})
    }
    wgpu.QueueWriteBuffer(ren.queue, instances.buffer, 0, raw_data(instances.models), uint(len)*size_of(matrix[4,4]f32))

    wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 3, instances.buffer, 0, wgpu.BufferGetSize(instances.buffer))

    if mesh.indices != nil {
        wgpu.RenderPassEncoderSetIndexBuffer(render_pass, mesh.indices, .Uint32, 0, wgpu.BufferGetSize(mesh.indices))
        wgpu.RenderPassEncoderDrawIndexed(render_pass, mesh.size, u32(len), 0, 0, 0)
    } else {
        wgpu.RenderPassEncoderDraw(render_pass, mesh.size, u32(len), 0, 0)
    }
}

@(private)
clear_batches :: proc() {
    for mesh, &batch in batches {
        for material, &instances in batch {
            clear(&instances.models)
        }
    }
}

draw_mesh :: proc(mesh: Mesh, material: Material, model: matrix[4, 4]f32) {
    model := model
    if !(mesh in batches) {
        batches[mesh] = {}
    }
    batch := &batches[mesh]
    if !(material in batch) {
        //create instance buffer
        batch[material] = Batch{
            models = {},
            buffer = wgpu.DeviceCreateBuffer(ren.device, &{usage={.Vertex, .CopyDst}}),
        }
    }
    instances := &batch[material]
    append(&instances.models, model)
    if u32(len(instances.models)) + 1 > instances.cap {
        instances.cap = (instances.cap + 1) * 2
    }
}
