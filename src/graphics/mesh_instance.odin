package graphics
//batching, sorting, buffering, huzzah

import "vendor:wgpu"

Cull_Mode :: enum {
    Back_CCW, //normal
    Front_CCW, //inverted
    None, //double-sided
}

Instance_Flags :: enum u32 {
    Unlit,
    Billboard
}

//exact same as the struct in wgsl
Instance_Uniforms :: struct {
    model: matrix[4,4]f32,
    clip_rect: [4]f32,
    base_color_mul: [4]f32,
    base_color_add: [4]f32,
    pbr_mul: [3]f32,      skeleton_offset: i32,
    pbr_add: [3]f32,      probe_a: i32,
    emissive_mul: [3]f32, probe_b: i32,
    emissive_add: [3]f32, flags: bit_set[Instance_Flags; u32],
}

//everything needed to determine belonging to a view
Instance_Bin_Uniforms :: struct {
    using bounds: Bounds,
    layer_mask: Layer_Mask,
    batch: u32,
}

Mesh_Draw :: struct {
    batch: u32, //dense id
    instance: Instance_Uniforms,
    cull: Mesh_Cull,
    bones: []matrix[4,4]f32,
}

@(private)
scale_sprite :: proc(model: matrix[4,4]f32, uv: [4]f32, tex_size: [2]f32, billboard: bool) -> matrix[4,4]f32 {
    size := tex_size * uv.zw
    model := model
    model[0] *= size.x
    model[1] *= size.y
    model[2] *= billboard ? max(size.x, size.y) : 1 //since billboards face the camera, we want them to be thick from all angles
    return model
}

// TODO: move this to vertex shader.
//calculates world mesh data (aka the modelview)
//assumes local data already calculated
calculate_mesh_world :: proc(instance: ^Mesh_Draw, cam: Camera_View) {
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

instance_buffer: wgpu.Buffer
instance_buffer_len: int
instance_buffer_cap: int

@(private)
realloc_instance_buffer :: proc(new_size: int) -> (rebind: bool) {
    /*if new_size == 0 || new_size <= instance_buffer_cap do return
    if instance_buffer_cap > 0 {
        wgpu.BufferRelease(instance_buffer)
    }
    instance_buffer = wgpu.DeviceCreateBuffer(ren.device, &{usage = {.Vertex, .CopyDst}, size = new_size})
    instance_buffer_cap = new_size*/
    return
}

delete_instance_buffer :: proc() {
    if instance_buffer_cap > 0 {
        wgpu.BufferRelease(instance_buffer)
    }
}

instance_id_buffer: wgpu.Buffer
instance_id_buffer_cap: u64

@(private)
realloc_instance_id_buffer :: proc(new_size: u64) {
    if new_size == 0 || new_size <= instance_id_buffer_cap do return
    if instance_id_buffer_cap > 0 {
        wgpu.BufferRelease(instance_id_buffer)
    }
    instance_id_buffer = wgpu.DeviceCreateBuffer(ren.device, &{usage = {.Vertex, .CopyDst}, size = new_size})
    instance_id_buffer_cap = new_size
    return
}

delete_instance_id_buffer :: proc() {
    if instance_id_buffer_cap > 0 {
        wgpu.BufferRelease(instance_id_buffer)
    }
}

//single index into the *real* instance data
instance_attribute := wgpu.VertexBufferLayout{
    stepMode = .Instance,
    arrayStride = size_of(u32),
    attributeCount = 1,
    attributes = &wgpu.VertexAttribute{format = .Uint32, shaderLocation = 7},
}


bind_instance_ids :: proc(render_pass: wgpu.RenderPassEncoder) {
    //should take a range, not the whole buffer
    wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 7, instance_id_buffer, 0, instance_id_buffer_cap)
}


//assumes material, mesh, and camera are all already bound & calculations are all done.
@(private)
draw_mesh_instances :: proc(render_pass: wgpu.RenderPassEncoder, mesh: Mesh, count: u32, buffer_offset: u64) {
    if count == 0 do return
    first_instance := u32(buffer_offset / size_of(Instance_Uniforms))
    if mesh.indices != nil {
        wgpu.RenderPassEncoderDrawIndexed(render_pass, mesh.size, count, 0, 0, first_instance)
    } else {
        wgpu.RenderPassEncoderDraw(render_pass, mesh.size, count, 0, first_instance)
    }
}
