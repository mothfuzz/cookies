package spatial

Grid :: struct(Entity: typeid, Cell_Size: int) {
    //bidirectional
    cells: map[[3]int]map[Entity]struct{},
    entities: map[Entity]map[[3]int]struct{},
    extents: map[Entity][2][3]int,
}

grid_remove :: proc(g: ^Grid($Entity, $Cell_Size), e: Entity) {
    if e in g.entities {
        for cell in g.entities[e] {
            delete_key(&g.cells[cell], e)
        }
        delete(g.entities[e])
        delete_key(&g.entities, e)
        delete_key(&g.extents, e)
    }
}

grid_cell_extents :: proc(g: ^Grid($Entity, $Cell_Size), extents: [2][3]f32) -> [2][3]int {
    minf := extents[0]/f32(Cell_Size)
    maxf := extents[1]/f32(Cell_Size)
    min := [3]int{int(minf.x), int(minf.y), int(minf.z)}
    max := [3]int{int(maxf.x), int(maxf.y), int(maxf.z)}
    return {min, max}
}

grid_insert :: proc(g: ^Grid($Entity, $Cell_Size), e: Entity, extents: [2][3]f32) {
    if g.cells == nil {
        g.cells = make(map[[3]int]map[Entity]struct{})
    }
    if g.entities == nil {
        g.entities = make(map[Entity]map[[3]int]struct{})
    }

    extents := grid_cell_extents(g, extents)

    if g.extents == nil {
        g.extents = make(map[Entity][2][3]int)
    } else if e in g.extents && g.extents[e] == extents {
        return
    }

    grid_remove(g, e)

    g.extents[e] = extents
    g.entities[e] = make(map[[3]int]struct{})

    for x in extents[0].x..=extents[1].x {
        for y in extents[0].y..=extents[1].y {
            for z in extents[0].z..=extents[1].z {
                cell := [3]int{x, y, z}
                if g.cells[cell] == nil {
                    g.cells[cell] = make(map[Entity]struct{})
                }
                (&g.cells[cell])[e] = {}
                (&g.entities[e])[cell] = {}
            }
        }
    }
}

grid_update :: proc(g: ^Grid($Entity, $Cell_Size), e: Entity, extents: [2][3]f32) {
    if g.extents[e] != grid_cell_extents(g, extents) {
        grid_remove(g, e)
        grid_insert(g, e, extents)
    }
}

grid_clear :: proc(g: ^Grid($Entity, $Cell_Size)) {
    for cell, &entities in g.cells {
        delete(entities)
    }
    delete(g.cells)
    g.cells = nil

    for entity, &cells in g.entities {
        delete(cells)
    }
    delete(g.entities)
    g.entities = nil
}

grid_get_entities :: proc(g: ^Grid($Entity, $Cell_Size), cell_extents: [2][3]int, output: ^[dynamic]Entity) {
    set := make(map[Entity]struct{})
    defer delete(set)
    for x in cell_extents[0].x..=cell_extents[1].x {
        for y in cell_extents[0].y..=cell_extents[1].y {
            for z in cell_extents[0].z..=cell_extents[1].z {
                if g.cells == nil {
                    return
                }
                if g.cells[{x, y, z}] == nil {
                    continue
                }
                for entity in g.cells[{x, y, z}] {
                    set[entity] = {}
                }
            }
        }
    }
    for entity in set {
        append(output, entity)
    }
}

grid_nearby :: proc(g: ^Grid($Entity, $Cell_Size), extents: [2][3]f32) -> []Entity {
    output := make([dynamic]Entity, 0, context.temp_allocator)
    extents := grid_cell_extents(g, extents)
    grid_get_entities(g, extents, &output)
    return output[:]
}

grid_neighbors :: proc(g: ^Grid($Entity, $Cell_Size), e: Entity) -> []Entity {
    output := make([dynamic]Entity, 0, context.temp_allocator)
    if e in g.extents {
        grid_get_entities(g, g.extents[e], &output)
        //remove self
        for entity, i in output {
            if entity == e {
                unordered_remove(&output, i)
                break
            }
        }
    }
    return output[:]
}
