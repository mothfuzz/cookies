package spatial2

Entry :: struct(Entity: typeid) {
    shape: Shape,
    extents: [2][3]f32,
    trans: matrix[4,4]f32,
    //maybe cache inv_trans here too? For OBB == AABB in Box's local space trick
    entity: Entity,
}

Spatial :: struct(Entity, Accel: typeid) {
    accel: Accel,
    entities: map[Entity]int,
    entries: [dynamic]Entry(Entity),
    free_list: [dynamic]int,
}

//grid: Spatial(Grid(16))
//acceleration structures speak 'int' internally

@(private)
accel_insert :: proc{grid_insert}
accel_remove :: proc{grid_remove}
accel_update :: proc{grid_update}
accel_clear :: proc{grid_clear}
accel_nearby :: proc{grid_nearby}
accel_neighbors :: proc{grid_neighbors}
accel_pairs :: proc{grid_pairs}

insert :: proc(s: ^Spatial($Entity, $Accel), e: Entity, shape: Shape, trans: matrix[4,4]f32 = 1) {
    entry := Entry(Entity){shape, shape_extents(shape, trans), trans, e}
    id, ok := pop_safe(&s.free_list)
    if ok {
        s.entries[id] = entry
    } else {
        id = len(s.entries)
        append(&s.entries, entry)
    }
    s.entities[e] = id
    accel_insert(&s.accel, id, entry.extents)
}

update :: proc(s: ^Spatial($Entity, $Accel), e: Entity, trans: matrix[4,4]f32) {
    if id, ok := s.entities[e]; ok {
        entry := &s.entries[id]
        entry.trans = trans
        entry.extents = shape_extents(entry.shape, entry.trans)
        accel_update(&s.accel, id, entry.extents)
    }
}

remove :: proc(s: ^Spatial($Entity, $Accel), e: Entity) {
    if id, ok := s.entities[e]; ok {
        accel_remove(&s.accel, id)
        delete_key(&s.entities, e)
        append(&s.free_list, id)
    }
}

import "base:builtin"
clear :: proc(s: ^Spatial($Entity, $Accel)) {
    accel_clear(&s.accel)
    builtin.clear(&s.entities)
    builtin.clear(&s.entries)
    builtin.clear(&s.free_list)
}

world_extents :: proc(s: ^Spatial($Entity, $Accel), e: Entity) -> [2][3]f32 {
    if id, ok := s.entities[e]; ok {
        entry := s.entries[id]
        return shape_extents(entry.shape, entry.trans)
    }
    return {0, 0}
}

@(private)
nearby_internal :: proc(s: ^Spatial($Entity, $Accel), position: [3]f32, radius: f32, results: ^[dynamic]Entity) {
    extents := [2][3]f32{{position-radius}, {position+radius}}
    for id in accel_nearby(&s.accel, extents) {
        entry := s.entries[id]
        test_position := entry.trans[3]
        displacement := test_position - position
        if displacement*displacement <= radius*radius {
            append(&results, entry.entity)
        }
    }
}

nearby_entity :: proc(s: ^Spatial($Entity, $Accel), e: Entity, radius: f32) -> []Entity {
    results := make([dynamic]Entity, context.temp_allocator)
    if id, ok := s.entities[e]; ok {
        entry := s.entries[id]
        nearby_internal(s, entry.trans[3], radius, &results)
    }
    return results
}

nearby_position :: proc(s: ^Spatial($Entity, $Accel), position: [3]f32, radius: f32) -> []Entity {
    results := make([dynamic]Entity, context.temp_allocator)
    nearby_internal(s, position, radius, &results)
    return results
}

nearby :: proc{nearby_entity, nearby_position}

pairs :: proc(s: ^Spatial($Entity, $Accel)) -> [][2]Entity {
    results := make([dynamic][2]Entity, context.temp_allocator)
    for pair in accel_pairs(&s.accel) {
        a := s.entries[pair[0]]
        b := s.entries[pair[1]]
        if shape_overlapping(a.shape, a.trans, b.shape, b.trans) {
            append(&results, [2]Entity{a.entity, b.entity})
        } 
    }
    return results[:]
}

entity_overlapping :: proc(s: ^Spatial($Entity, $Accel), a: Entity, b: Entity) -> bool {
    a_id, a_ok := s.entities[a]
    if !a_ok do return false
    b_id, b_ok := s.entities[b]
    if !b_ok do return false
    a := s.entries[a_id]
    b := s.entries[b_id]
    if !aabb_aabb(a.extents, b.extents) do return false
    return shape_overlapping(a.shape, a.trans, b.shape, b.trans)
}

all_overlapping :: proc(s: ^Spatial($Entity, $Accel), e: Entity) -> []Entity {
    results := make([dynamic]Entity, context.temp_allocator)
    if id, ok := s.entities[e]; ok {
        a := s.entries[id]
        for candidate in accel_neighbors(&s.accel, id) {
            b := s.entries[candidate]
            if !aabb_aabb(a.extents, b.extents) do continue
            if shape_overlapping(a.shape, a.trans, b.shape, b.trans) {
                append(&results, b.entity)
            }
        }
    }
    return results[:]
}

overlapping :: proc{entity_overlapping, all_overlapping}
