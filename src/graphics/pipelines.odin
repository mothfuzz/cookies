package graphics

import "vendor:wgpu"

//THE! pipeline table

//needs a way to key a table of pipelines by 'feature'
//i.e. shadow targets skip lines/point
//any feature we add that doesn't support trans passes skips trans
//etc etc

//skipping doesn't require a manual check on a bit_set, it should check for nil entries in the pipelines table
//and not emit any draw ranges for that pipeline

Stage_Key :: enum u8 {
    Shadow,
    Main,
}

Blend_Key :: enum u8 {
    Opaque,
    Blended,
}

alpha_blends :: [Alpha_Class]bit_set[Blend_Key]{
        .Solid = {.Opaque},
        .Mixed = {.Opaque, .Blended},
        .Trans = {.Blended},
}

//will replace the Cull_Mode split in a lot of places.
Primitive_Key :: enum u8 {
    Triangles_Back,
    Triangles_Front,
    Triangles_None,
    Lines,
    Points,
}
topology_cull := [Primitive_Key]struct{Cull_Mode, Mesh_Topology} {
        .Triangles_Back = {.Back_CCW, .Triangles},
        .Triangles_Front = {.Front_CCW, .Triangles},
        .Triangles_None = {.None, .Triangles},
        .Lines = {.None, .Lines},
        .Points = {.None, .Points},
}

wgpu_cull_mode := [Cull_Mode]wgpu.CullMode {
        .Back_CCW = .Back,
        .Front_CCW = .Front,
        .None = .None,
}

wgpu_topology := [Mesh_Topology]wgpu.PrimitiveTopology {
        .Triangles = .TriangleList,
        .Lines = .LineList,
        .Points = .PointList,
}

topology_constant := [Mesh_Topology]f64 {
        .Triangles = 0,
        .Lines = 1,
        .Points = 2,
}

pipelines: [Stage_Key][Blend_Key][Primitive_Key]wgpu.RenderPipeline

// TODO: actually uh. build the pipelines

create_pipeline_table :: proc() {
    for key in Primitive_Key {
        solid, trans := create_pipeline(**topology_cull[key])
        pipelines[.Main][.Opaque][key] = solid
        pipelines[.Main][.Blended][key] = trans
    }
}

destroy_pipeline_table :: proc() {
    for bp, stage in pipelines {
        for pp, blend in bp {
            for pipeline, primitive in pp {
                if pipeline == nil do continue
                wgpu.RenderPipelineRelease(pipeline)
            }
        }
    }
}
