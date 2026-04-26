package graphics

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "vendor:wgpu"
import "base:runtime" //for hashing

Vertex :: struct {
    position: [3]f32,
    normal: [3]f32,
    tangent: [4]f32,
    texcoord: [2]f32,
    color: [4]f32,
    bones: [4]f32,
    weights: [4]f32,
}

Extents :: struct {
    mini: [3]f32,
    maxi: [3]f32,
}

Mesh_Hash :: distinct uintptr

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
    is_trans: bool, //at least one vertex alpha 0 < a < 1
    is_solid: bool, //at least one vertex alpha a = 1
    //
    hash: Mesh_Hash,
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
    if vertices.normal[0] == 0 {
        fmt.println("No normals, calculating...")
        calculate_normals(vertices.position[0:n], indices, vertices.normal[0:n])
    }
    if vertices.tangent[0] == 0 {
        fmt.println("No tangents, calculating...")
        n := len(vertices)
        calculate_tangents(vertices.position[0:n], vertices.normal[0:n], vertices.texcoord[0:n], indices, vertices.tangent[0:n])
    }
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
        if v.color.a > 0.0 && v.color.a < 1.0 {
            mesh.is_trans = true
        }
        if v.color.a == 1.0 {
            mesh.is_solid = true
        }
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

    mesh.hash = Mesh_Hash(runtime.default_hasher(&mesh, 0, size_of(Mesh)))
    return
}

calculate_normals :: proc(vertices: [][3]f32, indices: []u32, out_normals: [][3]f32) {
    indices := indices
    if indices == nil || len(indices) == 0 {
        indices = make([]u32, len(vertices))
        for i in 0..<len(vertices) {
            indices[i] = u32(i)
        }
    }
    for i := 0; i+2 < len(indices); i += 3  {
        ai := indices[i+0]
        bi := indices[i+1]
        ci := indices[i+2]
        a := vertices[ai]
        b := vertices[bi]
        c := vertices[ci]
        ba := b - a
        ca := c - a
        //keep track of accumulated direction for each influencing vertex
        //assumes counter-clockwise face winding
        out_normals[ai] += linalg.cross(ba, ca)
        out_normals[bi] += linalg.cross(ba, ca)
        out_normals[ci] += linalg.cross(ba, ca)
    }
    for &normal in out_normals {
        normal = linalg.normalize(normal) //normalize to average all the vertex influences
    }
}

calculate_tangents :: proc(vertices: [][3]f32, normals: [][3]f32, texcoords: [][2]f32, indices: []u32, out_tangents: [][4]f32) {
    indices := indices
    if indices == nil || len(indices) == 0 {
        indices = make([]u32, len(vertices))
        for i in 0..<len(vertices) {
            indices[i] = u32(i)
        }
    }
    for i := 0; i+2 < len(indices); i += 3 {
        ai := indices[i+0]
        bi := indices[i+1]
        ci := indices[i+2]
        pos_ba := vertices[bi] - vertices[ai]
        pos_ca := vertices[ci] - vertices[ai]
        tex_ba := texcoords[bi] - texcoords[ai]
        tex_ca := texcoords[ci] - texcoords[ai]

        tangent := [4]f32{}
        f := 1.0 / (tex_ba.x * tex_ca.y - tex_ca.x * tex_ba.y)
        tangent.x = f * (tex_ca.y * pos_ba.x - tex_ba.y * pos_ca.x)
        tangent.y = f * (tex_ca.y * pos_ba.y - tex_ba.y * pos_ca.y)
        tangent.z = f * (tex_ca.y * pos_ba.z - tex_ba.y * pos_ca.z)
        tangent.w = 1.0

        out_tangents[ai] = tangent
        out_tangents[bi] = tangent
        out_tangents[ci] = tangent
    }
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
    arrayStride = size_of([4]f32),
    attributeCount = 1,
    attributes = &wgpu.VertexAttribute{format = .Float32x4, shaderLocation = 2},
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
    {format = .Float32x4, offset = 0 * size_of([4]f32), shaderLocation = instance_data_location + 0}, //modelview
    {format = .Float32x4, offset = 1 * size_of([4]f32), shaderLocation = instance_data_location + 1}, //modelview
    {format = .Float32x4, offset = 2 * size_of([4]f32), shaderLocation = instance_data_location + 2}, //modelview
    {format = .Float32x4, offset = 3 * size_of([4]f32), shaderLocation = instance_data_location + 3}, //modelview
    {format = .Float32x4, offset = 4 * size_of([4]f32), shaderLocation = instance_data_location + 4}, //clip_rect
    {format = .Float32x4, offset = 5 * size_of([4]f32), shaderLocation = instance_data_location + 5}, //base_color_tint
    {format = .Float32x4, offset = 6 * size_of([4]f32), shaderLocation = instance_data_location + 6}, //pbr_tint
    {format = .Float32x4, offset = 7 * size_of([4]f32), shaderLocation = instance_data_location + 7}, //emissive_tint
}
instance_data_attribute := wgpu.VertexBufferLayout{
    stepMode = .Instance,
    arrayStride = size_of(Instance),
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

Mesh_Draw :: struct {
    using instance: Instance,
    is_sprite: bool,
    is_billboard: bool,
    bones: []matrix[4,4]f32,
    bounding_box: [8][4]f32,
}
Instance :: struct {
    transform: matrix[4,4]f32,
    using dynamic_material: Dynamic_Material,
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

//calculates local mesh data (i.e. not relative to camera)
calculate_mesh_local :: proc(instance: ^Mesh_Draw, mesh: Mesh, material: Material) {
    //calculate clip_rect
    w := f32(wgpu.TextureGetWidth(material.base_color.image))
    h := f32(wgpu.TextureGetHeight(material.base_color.image))
    instance.clip_rect.x /= w
    instance.clip_rect.y /= h
    if instance.clip_rect[2] == 0 {
        instance.clip_rect[2] = 1.0
    } else {
        instance.clip_rect[2] /= w
    }
    if instance.clip_rect[3] == 0 {
        instance.clip_rect[3] = 1.0
    } else {
        instance.clip_rect[3] /= h
    }
    //calculate model
    if instance.is_sprite {
        temp_trans := instance.transform[3]
        instance.transform[3] = {0, 0, 0, 1}
        scale_w := w*instance.clip_rect[2]
        scale_h := h*instance.clip_rect[3]
        scale_z := f32(1.0)
        if instance.is_billboard {
            //since billboards face the camera, we want them to be thick from all angles
            scale_z = max(scale_w, scale_h)
        }
        scale := linalg.matrix4_scale([3]f32{scale_w, scale_h, scale_z})
        instance.transform *= scale
        instance.transform[3] = temp_trans
    }
    //calculate bounding box
    bb := mesh.bounding_box
    if instance.is_billboard && bb.mini.z == 0 && bb.maxi.z == 0 { //give it some thickness
        bb.mini.z = min(bb.mini.x, bb.mini.y)
        bb.maxi.z = max(bb.maxi.x, bb.maxi.y)
    }
    for i in 0..<8 {
        for j in 0..<3 {
            //convert extents to individual points (using 3-digit binary)
            instance.bounding_box[i][j] = bb.maxi[j] if i % (1 << uint(j+1)) > (1 << uint(j) - 1) else bb.mini[j]
        }
        instance.bounding_box[i][3] = 1
        instance.bounding_box[i] = instance.transform * instance.bounding_box[i]
    }
}

//calculates world mesh data (aka the modelview)
//assumes local data already calculated
calculate_mesh_world :: proc(instance: ^Mesh_Draw, cam: Camera) {
    if instance.is_billboard {
        rotation_scale := cast(matrix[3,3]f32)(instance.transform) //isolate untransformed rotation/scale
        instance.transform = cam.view * instance.transform; //transform to camera...
        trans := instance.transform[3] //save produced translation vector
        instance.transform = cast(matrix[4,4]f32)(rotation_scale) //and then revert to untransformed scaling/rotation
        instance.transform[3] = trans //while keeping translation transformed to camera.
    } else {
        instance.transform = cam.view * instance.transform
    }
}

//assumes material, mesh, and camera are all already bound & calculations are all done.
@(private)
draw_mesh_instances :: proc(render_pass: wgpu.RenderPassEncoder, mesh: Mesh, instances: []Instance) {
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
