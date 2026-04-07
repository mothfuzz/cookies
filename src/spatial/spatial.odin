package spatial

insert :: proc{grid_insert, spatial_insert}
remove :: proc{grid_remove}
update :: proc{grid_update, spatial_update_shape, spatial_update_transform, spatial_update_both}
clear :: proc{grid_clear, spatial_clear}
nearby :: proc{grid_nearby, spatial_nearby_entity, spatial_nearby_position_radius}
neighbors :: proc{grid_neighbors}

//just to make sure parapoly works
Octree :: struct(Entity: typeid) {}
R_Tree :: struct(Entity: typeid) {}

init_grid :: proc "contextless" ($T: typeid/Grid($Entity, $Cell_Size)) -> (output: Spatial(Entity, T)) {
    return
}
init_octree :: proc "contextless" ($T: typeid/Octree($Entity)) -> (output: Spatial(Entity, T)) {
    return
}
init_rtree :: proc "contextless" ($T: typeid/R_Tree($Entity)) -> (output: Spatial(Entity, T)) {
    return
}

init :: proc{init_grid, init_octree, init_rtree}

Spatial :: struct(Entity, Structure: typeid) {
    st: Structure,
    colliders: map[Entity]Collider,
}

collider_init :: proc(shape: Shape, trans: matrix[4,4]f32) -> (c: Collider) {
    c.shape = shape
    c.trans = trans
    c.extents = extents(shape)
    c.transformed_shape = transform(shape, trans)
    c.transformed_extents = extents(c.transformed_shape)
    return
}

spatial_insert :: proc(s: ^Spatial($Entity, $S), e: Entity, shape: Shape = Point{}, trans: matrix[4,4]f32 = 1) {
    if s.colliders == nil {
        s.colliders = make(map[Entity]Collider)
    }
    c := collider_init(shape, trans)
    s.colliders[e] = c
    insert(&s.st, e, c.transformed_extents)
}
spatial_clear :: proc(s: ^Spatial($Entity, $S)) {
    delete(s.colliders)
    clear(&s.st)
}

spatial_update_shape :: proc(s: ^Spatial($Entity, $S), e: Entity, shape: Shape) {
    c := &s.colliders[e]
    c^ = collider_init(shape, c.trans)
    update(&s.st, e, c.transformed_extents)
}
spatial_update_transform :: proc(s: ^Spatial($Entity, $S), e: Entity, trans: matrix[4,4]f32) {
    c := &s.colliders[e]
    if trans != c.trans {
        c^ = collider_init(c.shape, trans)
    }
    update(&s.st, e, c.transformed_extents)
}
spatial_update_both :: proc(s: ^Spatial($Entity, $S), e: Entity, shape: Shape, trans: matrix[4,4]f32) {
    c := &s.colliders[e]
    c^ = collider_init(shape, trans)
    update(&s.st, e, c.transformed_extents)
}

overlapping :: proc(s: ^Spatial($Entity, $S), ea: Entity) -> []Entity {
    results := make([dynamic]Entity, context.temp_allocator)
    a := s.colliders[ea]
    for eb in neighbors(&s.st, ea) {
        b := s.colliders[eb]
        if overlaps(a.transformed_shape, b.transformed_shape) {
            append(&results, eb)
        }
    }
    return results[:]
}

spatial_nearby_entity :: proc(s: ^Spatial($Entity, $S), e: Entity, radius: f32) -> []Entity {
    pos := s.colliders[e].trans[3]
    return spatial_nearby_position_radius(pos, radius)
}

spatial_nearby_position_radius :: proc(s: ^Spatial($Entity, $S), position: [3]f32, radius: f32) -> []Entity {
    results := make([dynamic]Entity)
    extents := [2][3]f32{{position-radius}, {position+radius}}
    for e in nearby(&s.st, extents) {
        pos := s.colliders[e].trans[3]
        vec := pos - position
        if vec*vec <= radius*radius {
            append(&results, e)
        }
    }
    return results
}
