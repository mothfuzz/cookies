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

Primitive_Key :: enum u8 {
    Triangles_CCW,
    Triangles_CW,
    Triangles_CCW_Double_Sided,
    Triangles_CW_Double_Sided,
    Lines,
    Points,
}
primitive_state := [Primitive_Key]struct{wgpu.PrimitiveTopology, wgpu.FrontFace, wgpu.CullMode} {
        .Triangles_CCW = {.TriangleList, .CCW, .Back},
        .Triangles_CW = {.TriangleList, .CW, .Back},
        .Triangles_CCW_Double_Sided = {.TriangleList, .CCW, .None},
        .Triangles_CW_Double_Sided = {.TriangleList, .CW, .None},
        .Lines = {.LineList, .Undefined, .None},
        .Points = {.PointList, .Undefined, .None},
}

topology_constant := #partial [wgpu.PrimitiveTopology]f64 {
        .TriangleList = 0,
        .LineList = 1,
        .PointList = 2,
}

pipelines: [Stage_Key][Blend_Key][Primitive_Key]wgpu.RenderPipeline

// TODO: actually uh. build the pipelines

create_pipeline_table :: proc() {
    for key in Primitive_Key {
        solid, trans := create_pipeline(**primitive_state[key])
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
