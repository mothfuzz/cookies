package spatial2

import "core:log"
import "core:math"

Grid_Entry :: struct {
    extents: [2][3]int, //AABB for all cells this id belongs to
    slots: [dynamic]int, //actual indices into cells over that AABB in fixed order
}

Grid :: struct(Cell_Size: int) {
    cells: map[[3]int][dynamic]int,
    entries: [dynamic]Grid_Entry, //flat entity index
}

@(private)
cell_extents :: proc(e: [2][3]f32, cell_size: int) -> (out: [2][3]int) {
    cs := f32(cell_size)
    out[0] = {int(math.floor(e[0].x/cs)), int(math.floor(e[0].y/cs)), int(math.floor(e[0].z/cs))}
    out[1] = {int(math.ceil(e[1].x/cs)), int(math.ceil(e[1].y/cs)), int(math.ceil(e[1].z/cs))}
    return
}

grid_insert :: proc(g: ^Grid($Cell_Size), id: int, extents: [2][3]f32) {
    entry := Grid_Entry{extents = cell_extents(extents, Cell_Size)}
    for x in entry.extents[0].x..=entry.extents[1].x {
        for y in entry.extents[0].y..=entry.extents[1].y {
            for z in entry.extents[0].z..=entry.extents[1].z {
                if _, cell, _, err := map_entry(&g.cells, [3]int{x, y, z}); err == nil {
                    append(&entry.slots, len(cell))
                    append(cell, id)
                } else {
                    log.panic("Could not grow spatial grid:", err)
                }
            }
        }
    }
    if id >= len(g.entries) {
        resize(&g.entries, id+1)
    }
    g.entries[id] = entry
}

@(private)
cell_slot :: proc(e: [2][3]int, cell: [3]int) -> int {
    dx := cell.x - e[0].x
    dy := cell.y - e[0].y
    dz := cell.z - e[0].z
    //x_len := e[1].x - e[0].x + 1
    y_len := e[1].y - e[0].y + 1
    z_len := e[1].z - e[0].z + 1
    return dz + z_len * (dy + y_len * dx)
}

grid_remove :: proc(g: ^Grid($Cell_Size), id: int) {
    if id < 0 || id >= len(g.entries) do return
    entry := g.entries[id]
    slots := entry.slots
    defer delete(slots)
    i := 0
    for x in entry.extents[0].x..=entry.extents[1].x {
        for y in entry.extents[0].y..=entry.extents[1].y {
            for z in entry.extents[0].z..=entry.extents[1].z {
                cell_index := [3]int{x, y, z}
                cell := &g.cells[cell_index]
                slot := slots[i] //i is index into slots, slot is index into cell
                i += 1
                //if this isn't already the last cell, make sure to update the entry that's being swapped
                //with its new slot (i.e. the current slot)
                if slot != len(cell)-1 {
                    replaced := cell[len(cell)-1]
                    replaced_entry := &g.entries[replaced]
                    replaced_slot := cell_slot(replaced_entry.extents, cell_index)
                    replaced_entry.slots[replaced_slot] = slot
                }
                unordered_remove(cell, slot) //swap-remove
                //don't leak cells, here is the natural place to delete them
                if len(cell) == 0 {
                    delete(cell^)
                    delete_key(&g.cells, cell_index)
                }
            }
        }
    }
}


grid_update :: proc(g: ^Grid($Cell_Size), id: int, extents: [2][3]f32) {
    entry := g.entries[id]
    new_extents := cell_extents(extents, Cell_Size)
    if entry.extents == new_extents do return
    //should probably optimize for if new extents contains/overlaps old extents...
    grid_remove(g, id)
    grid_insert(g, id, extents)
}

import "base:builtin"
grid_clear :: proc(g: ^Grid($Cell_Size)) {
    for entry in g.entries {
        delete(entry.slots)
    }
    builtin.clear(&g.entries)
    for cell, ids in g.cells {
        delete(ids)
    }
    builtin.clear(&g.cells)

}

@(private)
grid_get_ids :: proc(g: ^Grid($Cell_Size), extents: [2][3]int, output: ^[dynamic]int) {
    for x in extents[0].x..=extents[1].x {
        for y in extents[0].y..=extents[1].y {
            for z in extents[0].z..=extents[1].z {
                cell := [3]int{x, y, z}
                if cells, ok := g.cells[cell]; ok {
                    for id in cells {
                        entity_extents := g.entries[id].extents
                        min_overlap := [3]int{
                            max(entity_extents[0].x, extents[0].x),
                            max(entity_extents[0].y, extents[0].y),
                            max(entity_extents[0].z, extents[0].z),
                        }
                        if cell != min_overlap do continue
                        append(output, id)
                    }
                }
            }
        }
    }
}

grid_nearby :: proc(g: ^Grid($Cell_Size), extents: [2][3]f32) -> []int {
    output := make([dynamic]int, 0, context.temp_allocator)
    if g.cells == nil do return output[:]
    extents := cell_extents(extents, Cell_Size)
    grid_get_ids(g, extents, &output)
    return output[:]
}

grid_neighbors :: proc(g: ^Grid($Cell_Size), id: int) -> []int {
    output := make([dynamic]int, 0, context.temp_allocator)
    if id < 0 || id >= len(g.entries) do return output[:]
    if g.cells == nil do return output[:]
    extents := g.entries[id].extents
    grid_get_ids(g, extents, &output)
    //exclude self
    for self, i in output {
        if id == self {
            unordered_remove(&output, i)
            break
        }
    }
    return output[:]
}

grid_pairs :: proc(g: ^Grid($Cell_Size)) -> [][2]int {
    out := make([dynamic][2]int, context.temp_allocator)
    for cell, occupants in g.cells {
        for i in 0..<len(occupants) {
            for j in i+1..<len(occupants) {
                a := g.entries[occupants[i]]
                b := g.entries[occupants[j]]
                //get the canonical overlap, but, since we're emitting unique pairs only, we just need the min
                min_overlap := [3]int{
                    max(a.extents[0].x, b.extents[0].x),
                    max(a.extents[0].y, b.extents[0].y),
                    max(a.extents[0].z, b.extents[0].z),
                }
                if cell != min_overlap do continue //only report each candidate pair once, at the first sighting
                append(&out, [2]int{occupants[i], occupants[j]})
            }
        }
    }
    return out[:]
}
