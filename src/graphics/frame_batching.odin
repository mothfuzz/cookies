package graphics

import "core:slice"

Instance_Data :: struct {
    //sorted data
    instances: [dynamic]Instance_Uniforms, //canonical buffer, in BATCH ORDER
    culls: [dynamic]Mesh_Cull, //same order as instances
    skeletons: [dynamic]matrix[4,4]f32,

    batches: [dynamic]Batch, //rendering a view iterates this.
    solid_end: int, //solid pass = batches[:solid_end]
    trans_begin: int, //trans pass = batches[trans_begin:]
}

Alpha_Set :: struct {
    zero, one: bool, //at least one value is 0/1
    lo, hi: f32, //low and high for inbetweens
}

@(private)
alpha_product :: proc(a, b: Alpha_Set) -> (r: Alpha_Set) {
    r.zero = a.zero || b.zero
    r.one = a.one && b.one
    r.lo, r.hi = 1, 0 //empty
    a_partial := a.lo <= a.hi
    b_partial := b.lo <= b.hi
    if a_partial && b.one {
        r.lo = min(r.lo, a.lo)
        r.hi = max(r.hi, a.hi)
    }
    if b_partial && a.one {
        r.lo = min(r.lo, b.lo)
        r.hi = max(r.hi, b.hi)
    }
    if a_partial && b_partial {
        r.lo = min(r.lo, a.lo * b.lo)
        r.hi = max(r.hi, a.hi * b.hi)
    }
    return
}

Alpha_Class :: enum u8 {
    Solid,
    Mixed, //needs to be in the center for contiguous ranges in a pass.
    Trans,
}

@(private)
alpha_class :: proc(a: Alpha_Set, mul, add: f32) -> (alpha: Alpha_Class, ok: bool) {
    solid, trans: bool
    test :: proc(lo, hi: f32) -> (solid, trans: bool) {
        return hi >= 1, lo < 1 && hi > 0
    }
    if a.zero {
        a, b := test(add, add) //mul * 0 == 0
        solid |= a
        trans |= b
    }
    if a.one {
        a, b := test(mul + add, mul + add)
        solid |= a
        trans |= b
    }
    if a.lo <= a.hi {
        x := a.lo * mul + add
        y := a.hi * mul + add
        a, b := test(min(x, y), max(x, y))
        solid |= a
        trans |= b
    }
    switch {
    case solid && trans: return .Mixed, true
    case solid: return .Solid, true
    case trans: return .Trans, true
    }
    return
}

//provides map index + sort order
Batch_Key :: struct {
    alpha: Alpha_Class,
    primitive: Primitive_Key,
    mesh: Mesh_Hash,
    material: Material_Hash,
}

Batch :: struct {
    id: u32,
    key: Batch_Key, //so we can get pass/pipeline state
    mesh: Mesh,
    material: Material,
    //for counting sort later
    first_instance: u32,
    instance_count: u32,
}

@(private)
batch_key_less :: proc(a, b: Batch_Key) -> bool {
    if a.alpha != b.alpha do return a.alpha < b.alpha //preserve continuity between Solid, Mixed, Trans
    if a.primitive != b.primitive do return a.primitive < b.primitive //fewest pipeline switches
    if a.mesh != b.mesh do return a.mesh < b.mesh //mesh-outer since mesh is more bindings
    return a.material < b.material
}

@(private)
batch_instances :: proc(f: ^Render_Frame, draws: []Mesh_Draw, batches: []Batch) {

    //order unique batches
    append(&f.batches, ..batches)
    slice.sort_by(f.batches[:], proc(a, b: Batch) -> bool {
        return batch_key_less(a.key, b.key)
    })

    //prefix sum
    next := make([]u32, len(batches)) //indexed by id
    running_total: u32
    for &b in f.batches {
        b.first_instance = running_total
        next[b.id] = running_total
        running_total += b.instance_count
    }
    //scatter
    resize(&f.instances, len(draws))
    resize(&f.culls, len(draws))
    for d in draws {
        dst := next[d.batch]
        next[d.batch] += 1
        inst := d.instance
        if d.bones != nil {
            inst.skeleton_offset = i32(len(f.skeletons))
            append(&f.skeletons, ..d.bones)
        }
        f.instances[dst] = inst
        f.culls[dst] = d.cull
    }
    
    //find solid/trans split
    f.solid_end = len(f.batches)
    f.trans_begin = len(f.batches)
    for batch, i in f.batches {
        if batch.key.alpha != .Solid && f.trans_begin == len(f.batches) {
            f.trans_begin = i
        }
        if batch.key.alpha == .Trans {
            f.solid_end = i
            //trans strictly follows solid/mixed, so can end here
            break
        }
    }
}
