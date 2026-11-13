package graphics

import "core:log"
import "core:math"
import "core:math/linalg"
import "vendor:wgpu"
//for hashing
import "core:slice"
import "core:hash"

Vertex :: struct {
    position: [3]f32,
    normal: [3]f32,
    tangent: [4]f32,
    texcoord: [2]f32,
    color: [4]f32,
    bones: [4]u16,
    weights: [4]u16,
}

Extents :: struct {
    mini: [3]f32,
    maxi: [3]f32,
}

Bounds :: struct {
    center: [3]f32,
    radius: f32,
    axes: [3][3]f32,
}


Mesh_Hash :: distinct u32

Mesh_Key :: struct {
    path: cstring,
}

Mesh_Topology :: enum {
    Triangles,
    Lines,
    Points,
}

Mesh :: struct {
    using key: Mesh_Key,
    size: u32,
    topology: Mesh_Topology,
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
    bounds: Bounds,
    alpha: Alpha_Set,
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
make_mesh_from_slice :: proc(vertices: []Vertex, indices: []u32 = nil, topology: Mesh_Topology = .Triangles, wireframe: bool = false) -> (mesh: Mesh) {
    size := len(vertices)
    new_vertices := make(#soa[]Vertex, size)
    for i in 0..<size {
        new_vertices[i] = vertices[i]
    }
    mesh = make_mesh_from_soa(new_vertices, indices, topology, wireframe)
    delete(new_vertices)
    return
}
make_mesh_from_soa :: proc(vertices: #soa[]Vertex, indices: []u32 = nil, topology: Mesh_Topology = .Triangles, wireframe: bool = false) -> (mesh: Mesh) {
    n := len(vertices)
    indices := indices
    if topology == .Triangles {
        if vertices.normal[0] == 0 {
            log.debug("No normals, calculating...")
            calculate_normals(vertices.position[0:n], indices, vertices.normal[0:n])
        }
        if vertices.tangent[0] == 0 {
            log.debug("No tangents, calculating...")
            calculate_tangents(vertices.position[0:n], vertices.normal[0:n], vertices.texcoord[0:n], indices, vertices.tangent[0:n])
        }
    } else if topology == .Lines {
        if vertices.tangent[0] == 0 {
            log.debug("creating artificial tangents for lines...")
            calculate_lines_tangents(vertices.position[0:n], indices, vertices.tangent[0:n])
        }
    } else {
        //1px points don't really have anything sensible...
    }
    if wireframe {
        //implies topology=.Lines but whatever
        indices = triangles_to_lines(indices)
    }
    mesh.topology = topology
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
    mesh.alpha.lo = 1
    mesh.alpha.hi = 0
    for v in vertices {
        if v.color.a > 0.0 && v.color.a < 1.0 {
            mesh.alpha.lo = min(v.color.a, mesh.alpha.lo)
            mesh.alpha.hi = max(v.color.a, mesh.alpha.hi)
        }
        if v.color.a == 1.0 {
            mesh.alpha.one = true
        }
        if v.color.a == 0.0 {
            mesh.alpha.zero = true
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
    mesh.bounding_center = (mesh.bounding_box.mini + mesh.bounding_box.maxi)/2
    x, y, z := **(mesh.bounding_box.maxi - mesh.bounding_box.mini)
    mesh.bounding_radius = max(x, y, z)/2

    mesh.hash = Mesh_Hash(hash.fnv32a(slice.bytes_from_ptr(&mesh, size_of(Mesh))))
    return
}

import "core:strings"
import "core:strconv"
make_mesh_from_file :: proc(filedata: []byte) -> (mesh: Mesh) {
    //load .obj format
    positions: [dynamic][3]f32
    defer delete(positions)
    texcoords: [dynamic][2]f32
    defer delete(texcoords)
    normals: [dynamic][3]f32
    defer delete(normals)

    vertices: [dynamic]Vertex
    defer delete(vertices)
    Face_Vertex :: struct {
        position: [3]f32,
        texcoord: [2]f32,
        normal: [3]f32,
    }

    current_index: u32 = 0
    indices_dict: map[Face_Vertex]u32
    defer delete(indices_dict)
    indices: [dynamic]u32
    defer delete(indices)

    add_index :: proc(vertices: ^[dynamic]Vertex, indices_dict: ^map[Face_Vertex]u32, indices: ^[dynamic]u32, current_index: ^u32, f: Face_Vertex) {
        f := f
        if key, val, just_inserted, err := map_entry(indices_dict, f); err == nil {
            if just_inserted {
                val^ = current_index^
                current_index^ = current_index^ + 1
                f.texcoord.y = 1-f.texcoord.y
                append(vertices, Vertex{position=f.position, texcoord=f.texcoord, normal=f.normal, color={1, 1, 1, 1}})
            }
            append(indices, val^)
        }
    }

    it := string(filedata)
    for line in strings.split_lines_iterator(&it) {
        if strings.starts_with(line, "#") do continue
        if strings.starts_with(line, "v ") {
            v := strings.split(line[2:], " ", context.temp_allocator)
            x := strconv.parse_f32(v[0]) or_break
            y := strconv.parse_f32(v[1]) or_break
            z := strconv.parse_f32(v[2]) or_break
            append(&positions, [3]f32{x, y, z})
        }
        if strings.starts_with(line, "vt ") {
            vt := strings.split(line[3:], " ", context.temp_allocator)
            u := strconv.parse_f32(vt[0]) or_break
            v: f32 = 0
            if len(vt) > 1 {
                v = strconv.parse_f32(vt[1]) or_break
            }
            append(&texcoords, [2]f32{u, v})
        }
        if strings.starts_with(line, "vn ") {
            vn := strings.split(line[3:], " ", context.temp_allocator)
            x := strconv.parse_f32(vn[0]) or_break
            y := strconv.parse_f32(vn[1]) or_break
            z := strconv.parse_f32(vn[2]) or_break
            append(&normals, [3]f32{x, y, z})
        }
        if strings.starts_with(line, "f ") {
            f := strings.split(line[2:], " ", context.temp_allocator)
            f_v: [3]Face_Vertex
            switch strings.count(line[2:], "/") {
            case 0:
                //f v v v
                v0 := strconv.parse_uint(f[0]) or_break
                v1 := strconv.parse_uint(f[1]) or_break
                v2 := strconv.parse_uint(f[2]) or_break
                fv: [3][3]f32 = {positions[v0 - 1], positions[v1 - 1], positions[v2 - 1]}
                fvt: [3][2]f32 = 0
                fvn: [3][3]f32
                calculate_normals(fv[:], nil, fvn[:])
                f_v[0] = {fv[0], fvt[0], fvn[0]}
                f_v[1] = {fv[1], fvt[1], fvn[1]}
                f_v[2] = {fv[2], fvt[2], fvn[2]}
            case 3:
                //f v/vt v/vt v/vt
                v_vt0 := strings.split(f[0], "/", context.temp_allocator)
                v_vt1 := strings.split(f[1], "/", context.temp_allocator)
                v_vt2 := strings.split(f[2], "/", context.temp_allocator)
                v0 := strconv.parse_uint(v_vt0[0]) or_break
                v1 := strconv.parse_uint(v_vt1[0]) or_break
                v2 := strconv.parse_uint(v_vt2[0]) or_break
                fv: [3][3]f32 = {positions[v0 - 1], positions[v1 - 1], positions[v2 - 1]}
                vt0 := strconv.parse_uint(v_vt0[1]) or_break
                vt1 := strconv.parse_uint(v_vt1[1]) or_break
                vt2 := strconv.parse_uint(v_vt2[1]) or_break
                fvt: [3][2]f32 = {texcoords[vt0 - 1], texcoords[vt1 - 1], texcoords[vt2 - 1]}
                fvn: [3][3]f32
                calculate_normals(fv[:], nil, fvn[:])
                f_v[0] = {fv[0], fvt[0], fvn[0]}
                f_v[1] = {fv[1], fvt[1], fvn[1]}
                f_v[2] = {fv[2], fvt[2], fvn[2]}
            case 6:
                //f v/vt/vn v/vt/vn v/vt/vn
                v_vt_vn0 := strings.split(f[0], "/", context.temp_allocator)
                v_vt_vn1 := strings.split(f[1], "/", context.temp_allocator)
                v_vt_vn2 := strings.split(f[2], "/", context.temp_allocator)
                v0 := strconv.parse_uint(v_vt_vn0[0]) or_break
                v1 := strconv.parse_uint(v_vt_vn1[0]) or_break
                v2 := strconv.parse_uint(v_vt_vn2[0]) or_break
                fv: [3][3]f32 = {positions[v0 - 1], positions[v1 - 1], positions[v2 - 1]}
                vt0 := strconv.parse_uint(v_vt_vn0[1]) or_else 0
                vt1 := strconv.parse_uint(v_vt_vn1[1]) or_else 0
                vt2 := strconv.parse_uint(v_vt_vn2[1]) or_else 0
                fvt: [3][2]f32 = {vt0==0?0:texcoords[vt0 - 1], vt1==0?0:texcoords[vt1 - 1], vt2==0?0:texcoords[vt2 - 1]}
                vn0 := strconv.parse_uint(v_vt_vn0[2]) or_break
                vn1 := strconv.parse_uint(v_vt_vn1[2]) or_break
                vn2 := strconv.parse_uint(v_vt_vn2[2]) or_break
                fvn: [3][3]f32 = {normals[vn0 - 1], normals[vn1 - 1], normals[vn2 - 1]}
                f_v[0] = {fv[0], fvt[0], fvn[0]}
                f_v[1] = {fv[1], fvt[1], fvn[1]}
                f_v[2] = {fv[2], fvt[2], fvn[2]}
            }
            add_index(&vertices, &indices_dict, &indices, &current_index, f_v[0])
            add_index(&vertices, &indices_dict, &indices, &current_index, f_v[1])
            add_index(&vertices, &indices_dict, &indices, &current_index, f_v[2])
        }
	}
    mesh = make_mesh_from_slice(vertices[:], indices[:])
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

calculate_lines_tangents :: proc(vertices: [][3]f32, indices: []u32, out_tangents: [][4]f32) {
    indices := indices
    if indices == nil || len(indices) == 0 {
        indices = make([]u32, len(vertices))
        for i in 0..<len(vertices) {
            indices[i] = u32(i)
        }
    }
    for i := 0; i+1 < len(indices); i += 2 {
        ai := indices[i+0]
        bi := indices[i+1]
        ab := vertices[bi] - vertices[ai]
        out_tangents[ai].xyz += ab
        out_tangents[bi].xyz += ab
    }
    for &tangent in out_tangents {
        tangent.xyz = linalg.normalize(tangent.xyz)
        tangent.w = 1.0
    }
}

//for if you have a triangle mesh with triangle-based indices and want to render it wireframe
triangles_to_lines :: proc(indices: []u32) -> []u32 {
    seen := make(map[[2]u32]struct{}, len(indices), context.temp_allocator)
    //max same size if there are no shared edges
    lines := make([dynamic]u32, 0, len(indices))
    for i := 0; i < len(indices)-2; i += 3 {
        tri := [3]u32{indices[i], indices[i+1], indices[i+2]}
        //iterate through triangle edges
        for j in 0..<3 {
            a, b := tri[j], tri[(j+1)%3]
            edge := [2]u32{min(a, b), max(a, b)} //make sure they're sorted for dedup
            if edge in seen do continue
            seen[edge] = {}
            append(&lines, a, b)
        }
    }
    return lines[:]
}

@(private)
mesh_bounds :: proc(model: matrix[4,4]f32, bounding_box: Extents, billboard: bool) -> (b: Bounds) {
    box := bounding_box
    if billboard && box.mini.z == 0 && box.maxi.z == 0 { //give it some thickness
        box.mini.z = min(box.mini.x, box.mini.y)
        box.maxi.z = max(box.maxi.x, box.maxi.y)
    }
    center := (box.mini + box.maxi)/2
    radi := (box.maxi - box.mini)/2
    b.center = (model * [4]f32{center.x, center.y, center.z, 1}).xyz
    b.axes = {model[0].xyz * radi.x, model[1].xyz * radi.y, model[2].xyz * radi.z}
    a := b.axes
    b.radius = linalg.sqrt(max(
        linalg.length2(a[0] + a[1] + a[2]),
        linalg.length2(a[0] + a[1] - a[2]),
        linalg.length2(a[0] - a[1] + a[2]),
        linalg.length2(a[0] - a[1] - a[2]),
    ))
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
    arrayStride = size_of([4]u16),
    attributeCount = 1,
    attributes = &wgpu.VertexAttribute{format = .Uint16x4, shaderLocation = 5},
}
weights_attribute := wgpu.VertexBufferLayout{
    stepMode = .Vertex,
    arrayStride = size_of([4]u16),
    attributeCount = 1,
    attributes = &wgpu.VertexAttribute{format = .Unorm16x4, shaderLocation = 6},
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
    if mesh.indices != nil {
        wgpu.RenderPassEncoderSetIndexBuffer(render_pass, mesh.indices, .Uint32, 0, wgpu.BufferGetSize(mesh.indices))
    }
}
