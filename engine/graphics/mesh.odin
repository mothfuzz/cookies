package graphics

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "vendor:wgpu"

Vertex :: struct {
    position: [3]f32,
    normal: [3]f32,
    tangent: [3]f32,
    texcoord: [2]f32,
    color: [4]f32,
    bones: [4]f32,
    weights: [4]f32,
}

Extents :: struct {
    mini: [3]f32,
    maxi: [3]f32,
}

Mesh :: struct {
    size: u32,
    //buffers (currently at 8 - if we need more then we can interleave.)
    positions: wgpu.Buffer,
    normals: wgpu.Buffer,
    tangents: wgpu.Buffer,
    texcoords: wgpu.Buffer,
    colors: wgpu.Buffer,
    bones: wgpu.Buffer,
    weights: wgpu.Buffer,
    //index buffer
    indices: wgpu.Buffer,
    //optimizations
    bounding_box: Extents,
}

/*make_mesh_from_array :: proc(vertices: [$i]Vertex, indices: []u32 = nil) -> (mesh: Mesh) {
    new_vertices := #soa[i]Vertex
    for i in 0..<i {
        new_vertices[i] = vertices[i]
    }
    mesh = make_mesh_from_soa(new_vertices, indices)
    return
}*/
make_mesh_from_slice :: proc(vertices: []Vertex, indices: []u32 = nil) -> (mesh: Mesh) {
    size := len(vertices)
    new_vertices := make(#soa[]Vertex, size)
    for i in 0..<size {
        new_vertices[i] = vertices[i]
    }
    mesh = make_mesh_from_soa(new_vertices, indices)
    delete(new_vertices)
    return
}
make_mesh_from_soa :: proc(vertices: #soa[]Vertex, indices: []u32 = nil) -> (mesh: Mesh) {
    n := len(vertices)
    mesh.positions = wgpu.DeviceCreateBufferWithDataSlice(ren.device, &{usage={.Vertex, .CopyDst}}, vertices.position[0:n])
    mesh.normals = wgpu.DeviceCreateBufferWithDataSlice(ren.device, &{usage={.Vertex, .CopyDst}}, vertices.normal[0:n])
    mesh.tangents = wgpu.DeviceCreateBufferWithDataSlice(ren.device, &{usage={.Vertex, .CopyDst}}, vertices.tangent[0:n])
    mesh.texcoords = wgpu.DeviceCreateBufferWithDataSlice(ren.device, &{usage={.Vertex, .CopyDst}}, vertices.texcoord[0:n])
    mesh.colors = wgpu.DeviceCreateBufferWithDataSlice(ren.device, &{usage={.Vertex, .CopyDst}}, vertices.color[0:n])
    mesh.bones = wgpu.DeviceCreateBufferWithDataSlice(ren.device, &{usage={.Vertex, .CopyDst}}, vertices.bones[0:n])
    mesh.weights = wgpu.DeviceCreateBufferWithDataSlice(ren.device, &{usage={.Vertex, .CopyDst}}, vertices.weights[0:n])
    if indices != nil {
        mesh.indices = wgpu.DeviceCreateBufferWithDataSlice(ren.device, &{usage={.Index, .CopyDst}}, indices)
        mesh.size = u32(len(indices))
    } else {
        mesh.size = u32(len(vertices))
    }
    mesh.bounding_box.mini = math.INF_F32
    mesh.bounding_box.maxi = math.NEG_INF_F32
    for v in vertices {
        if v.position.x > mesh.bounding_box.maxi.x {
            mesh.bounding_box.maxi.x = v.position.x
        }
        if v.position.y > mesh.bounding_box.maxi.y {
            mesh.bounding_box.maxi.y = v.position.y
        }
        if v.position.z > mesh.bounding_box.maxi.z {
            mesh.bounding_box.maxi.z = v.position.z
        }
        if v.position.x < mesh.bounding_box.mini.x {
            mesh.bounding_box.mini.x = v.position.x
        }
        if v.position.y < mesh.bounding_box.mini.y {
            mesh.bounding_box.mini.y = v.position.y
        }
        if v.position.z < mesh.bounding_box.mini.z {
            mesh.bounding_box.mini.z = v.position.z
        }
    }
    return
}
delete_mesh :: proc(mesh: Mesh) {
    wgpu.BufferDestroy(mesh.positions)
    wgpu.BufferDestroy(mesh.normals)
    wgpu.BufferDestroy(mesh.tangents)
    wgpu.BufferDestroy(mesh.texcoords)
    wgpu.BufferDestroy(mesh.colors)
    wgpu.BufferDestroy(mesh.bones)
    wgpu.BufferDestroy(mesh.weights)
    if mesh.indices != nil {
        wgpu.BufferDestroy(mesh.indices)
    }
}

make_mesh :: proc{/*make_mesh_from_array,*/ make_mesh_from_slice, make_mesh_from_soa}

position_attribute := wgpu.VertexBufferLayout{
    stepMode = .Vertex,
    arrayStride = size_of([3]f32),
    attributeCount = 1,
    attributes = &wgpu.VertexAttribute{format = .Float32x3, shaderLocation = 0},
}
normal_attribute := wgpu.VertexBufferLayout{
    stepMode = .Vertex,
    arrayStride = size_of([3]f32),
    attributeCount = 1,
    attributes = &wgpu.VertexAttribute{format = .Float32x3, shaderLocation = 1},
}
tangent_attribute := wgpu.VertexBufferLayout{
    stepMode = .Vertex,
    arrayStride = size_of([3]f32),
    attributeCount = 1,
    attributes = &wgpu.VertexAttribute{format = .Float32x3, shaderLocation = 2},
}
texcoord_attribute := wgpu.VertexBufferLayout{
    stepMode = .Vertex,
    arrayStride = size_of([2]f32),
    attributeCount = 1,
    attributes = &wgpu.VertexAttribute{format = .Float32x2, shaderLocation = 3},
}
color_attribute := wgpu.VertexBufferLayout{
    stepMode = .Vertex,
    arrayStride = size_of([4]f32),
    attributeCount = 1,
    attributes = &wgpu.VertexAttribute{format = .Float32x4, shaderLocation = 4},
}
bones_attribute := wgpu.VertexBufferLayout{
    stepMode = .Vertex,
    arrayStride = size_of([4]f32),
    attributeCount = 1,
    attributes = &wgpu.VertexAttribute{format = .Float32x4, shaderLocation = 5},
}
weights_attribute := wgpu.VertexBufferLayout{
    stepMode = .Vertex,
    arrayStride = size_of([4]f32),
    attributeCount = 1,
    attributes = &wgpu.VertexAttribute{format = .Float32x4, shaderLocation = 6},
}

instance_data_location: u32 = 7
instance_data_attributes := []wgpu.VertexAttribute{
    {format = .Float32x4, offset = 0 * size_of([4]f32), shaderLocation = instance_data_location + 0}, //mvp1
    {format = .Float32x4, offset = 1 * size_of([4]f32), shaderLocation = instance_data_location + 1}, //mvp2
    {format = .Float32x4, offset = 2 * size_of([4]f32), shaderLocation = instance_data_location + 2}, //mvp3
    {format = .Float32x4, offset = 3 * size_of([4]f32), shaderLocation = instance_data_location + 3}, //mvp4
    {format = .Float32x4, offset = 4 * size_of([4]f32), shaderLocation = instance_data_location + 4}, //clip_rect
    {format = .Float32x4, offset = 5 * size_of([4]f32), shaderLocation = instance_data_location + 5}, //tint
}
instance_data_attribute := wgpu.VertexBufferLayout{
    stepMode = .Instance,
    arrayStride = size_of(InstanceData),
    attributeCount = len(instance_data_attributes),
    attributes = raw_data(instance_data_attributes),
}
vertex_buffer_layouts := []wgpu.VertexBufferLayout{
    position_attribute,
    normal_attribute,
    tangent_attribute,
    texcoord_attribute,
    color_attribute,
    bones_attribute,
    weights_attribute,
    instance_data_attribute,
}

//all data needed to render a single instance
MeshRenderItem :: struct {
    mesh: Mesh,
    material: Material,
    using draw: MeshDraw,
    //don't calculate these twice.
    bounding_box: [8][4]f32,
    //model: matrix[4,4]f32,
    local_calculated: bool,
    mvp: matrix[4,4]f32,
    mvp_calculated: bool,
}

//data that actually gets passed to the GPU
InstanceData :: struct {
    mvp: matrix[4,4]f32,
    dynamic_material: DynamicMaterial,
}

//this happens at an earlier stage than draw_instances i.e. multiple materials could be bound for one mesh
bind_mesh :: proc(render_pass: wgpu.RenderPassEncoder, mesh: Mesh) {
    wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 0, mesh.positions, 0, wgpu.BufferGetSize(mesh.positions))
    wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 1, mesh.normals, 0, wgpu.BufferGetSize(mesh.normals))
    wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 2, mesh.tangents, 0, wgpu.BufferGetSize(mesh.tangents))
    wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 3, mesh.texcoords, 0, wgpu.BufferGetSize(mesh.texcoords))
    wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 4, mesh.colors, 0, wgpu.BufferGetSize(mesh.colors))
    wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 5, mesh.bones, 0, wgpu.BufferGetSize(mesh.bones))
    wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 6, mesh.weights, 0, wgpu.BufferGetSize(mesh.weights))
}

//calculates local mesh data
precalcs :: proc(instance: ^MeshRenderItem) {
    if instance.local_calculated {
        return
    }
    //calculate clip_rect
    w := f32(wgpu.TextureGetWidth(instance.material.base_color.image))
    h := f32(wgpu.TextureGetHeight(instance.material.base_color.image))
    instance.clip_rect.x /= w
    instance.clip_rect.y /= h
    if instance.clip_rect[2] == 0 {
        instance.clip_rect[2] = 1.0
    } else {
        instance.clip_rect[2] /= w
    }
    if instance.draw.clip_rect[3] == 0 {
        instance.clip_rect[3] = 1.0
    } else {
        instance.clip_rect[3] /= h
    }
    //calculate model
    if instance.draw.is_sprite {
        temp_trans := instance.model[3]
        instance.model[3] = {0, 0, 0, 1}
        scale_w := w*instance.clip_rect[2]
        scale_h := h*instance.clip_rect[3]
        scale := linalg.matrix4_scale([3]f32{scale_w, scale_h, 1.0})
        instance.model *= scale
        instance.model[3] = temp_trans
    }
    //calculate bounding box
    bb := instance.mesh.bounding_box
    for i in 0..<8 {
        for j in 0..<3 {
            //convert extents to individual points (using 3-digit binary)
            instance.bounding_box[i][j] = bb.maxi[j] if i % (1 << uint(j+1)) > (1 << uint(j) - 1) else bb.mini[j]
        }
        instance.bounding_box[i][3] = 1
        instance.bounding_box[i] = instance.model * instance.bounding_box[i]
    }

    instance.local_calculated = true
}

//calculates world mesh data (aka the mvp)
//assumes local data already calculated
calculate_mvp :: proc(instance: ^MeshRenderItem, cam: ^Camera) {
    if instance.mvp_calculated {
        return
    }
    view_model: matrix[4,4]f32
    if instance.is_billboard {
        rotation_scale := cast(matrix[3,3]f32)(instance.model)
        view_model = cam.view * instance.model;
        trans := view_model[3] //save produced translation vector
        view_model = cast(matrix[4,4]f32)(rotation_scale) //and then revert to untransformed scaling/rotation
        view_model[3] = trans
    } else {
        view_model = cam.view * instance.model
    }
    instance.mvp = cam.projection * view_model
    instance.mvp_calculated = true
}

reset_mvps :: proc(instances: []MeshRenderItem) {
    for &instance in instances {
        instance.mvp_calculated = false
    }
}

//assumes material, mesh, and camera are all already bound & calculations are all done.
@(private)
draw_mesh_instances :: proc(render_pass: wgpu.RenderPassEncoder, mesh: Mesh, instances: []InstanceData) {
    instance_buffer := wgpu.DeviceCreateBufferWithDataSlice(ren.device, &{usage={.Vertex, .CopyDst}}, instances)
    wgpu.RenderPassEncoderSetVertexBuffer(render_pass, instance_data_location, instance_buffer, 0, wgpu.BufferGetSize(instance_buffer))
    wgpu.BufferRelease(instance_buffer)

    if mesh.indices != nil {
        wgpu.RenderPassEncoderSetIndexBuffer(render_pass, mesh.indices, .Uint32, 0, wgpu.BufferGetSize(mesh.indices))
        wgpu.RenderPassEncoderDrawIndexed(render_pass, mesh.size, u32(len(instances)), 0, 0, 0)
    } else {
        wgpu.RenderPassEncoderDraw(render_pass, mesh.size, u32(len(instances)), 0, 0)
    }
}
