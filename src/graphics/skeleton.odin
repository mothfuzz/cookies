package graphics

import "cookies:transform"
import "vendor:wgpu"
import "core:math/linalg"

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


//This is also where GPU buffer management will go, once that's implemented.
// TODO: in order to support procedural bone animation we should have a bone 'overlay' struct
// similar to how Animations will overwrite the bone transform,
// we should do this with whatever matrix the user wants to pass.

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

calculate_skeleton :: proc(scene: ^Scene, node: ^Node, t: f64) -> []matrix[4,4]f32 {
    bones: [dynamic]matrix[4,4]f32
    if node.animated {
        //look up the actual skeleton, and multiply with inv_bind
        //animation *should* be fully calculated at this point
        skeleton := &scene.skeletons[node.skin]
        bones = make([dynamic]matrix[4,4]f32, context.temp_allocator)
        for &bone in skeleton.bones {
            inv_trans := linalg.inverse(transform.smooth(&node.transform, t))
            bone_trans := transform.smooth(&scene.nodes[bone.node].transform, t)
            append(&bones, inv_trans * bone_trans * bone.inv_bind)
        }
    } else {
        //just use identity
        bones = make([dynamic]matrix[4,4]f32, context.temp_allocator)
        append(&bones, 1)
    }
    return bones[:]
}

import "core:fmt"
skeletons_bound: bool = false
current_skeletons_buffer: wgpu.Buffer
current_skeletons_uniform_buffer: wgpu.Buffer
current_skeletons_bind_group: wgpu.BindGroup
bind_skeletons :: proc(render_pass: wgpu.RenderPassEncoder, slot: u32, skeletons: []matrix[4,4]f32, num_instances: u32) {
    //if len(skeletons) > 1 {
        //fmt.println("BINDING SKELETONS:", skeletons)
    //}
    if skeletons_bound {
        wgpu.BindGroupRelease(current_skeletons_bind_group)
        wgpu.BufferRelease(current_skeletons_buffer)
        wgpu.BufferRelease(current_skeletons_uniform_buffer)
    }

    current_skeletons_buffer = wgpu.DeviceCreateBufferWithDataSlice(ren.device, &{usage={.Storage}}, skeletons)
    current_skeletons_uniform_buffer = wgpu.DeviceCreateBufferWithData(ren.device, &{usage={.Uniform, .CopyDst}}, u32(len(skeletons))/num_instances)

    bindings := []wgpu.BindGroupEntry{
        {binding = 0, buffer=current_skeletons_buffer, size=size_of(matrix[4,4]f32)*u64(len(skeletons))},
        {binding = 1, buffer=current_skeletons_uniform_buffer, size=size_of(u32)},
    }
    current_skeletons_bind_group = wgpu.DeviceCreateBindGroup(ren.device, &{
        layout = skeletons_layout,
        entryCount = len(bindings),
        entries = raw_data(bindings),
    })

    wgpu.RenderPassEncoderSetBindGroup(render_pass, slot, current_skeletons_bind_group)
}
