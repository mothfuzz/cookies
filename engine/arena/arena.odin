package arena

import "base:builtin"

Handle :: struct {
    id: uint,
    generation: uint,
}
Entity :: struct($T: typeid) {
    generation: uint,
    data: T,
    dead: bool,
}
Arena :: struct($T: typeid) {
    entities: [dynamic]Entity(T),
    free_list: [dynamic]uint,
}

init :: proc(a: ^Arena($T)) {
    a.entities = builtin.make([dynamic]Entity(T))
    a.free_list = builtin.make([dynamic]uint)
}
make :: proc($T: typeid/Arena($E)) -> (a: Arena(E)) {
    init(&a)
    return
}
delete :: proc(a: ^Arena($T)) {
    builtin.delete(a.entities)
    builtin.delete(a.free_list)
}
insert :: proc(a: ^Arena($T), t: T) -> (h: Handle) {
    if id, ok := pop_safe(&a.free_list); ok {
        h.id = id
    } else {
        h.id = builtin.len(&a.entities)
        append(&a.entities, Entity(T){})
    }
    entity := &a.entities[h.id]
    entity.dead = false
    entity.data = t
    h.generation = entity.generation
    return
}
get :: proc(a: ^Arena($T), h: Handle) -> ^T {
    entity := &a.entities[h.id]
    if  entity.generation == h.generation {
        return &entity.data
    }
    return nil
}

remove :: proc(a: ^Arena($T), h: Handle) {
    entity := &a.entities[h.id]
    if entity.generation == h.generation {
        entity.dead = true
        entity.generation += 1
        append(&a.free_list, h.id)
    }
}

Iterator :: struct {
    index: uint,
}
iter :: proc(a: ^Arena($T), iterator: ^Iterator) -> (handle: Handle, data: ^T, ok: bool) {
    if iterator.index >= builtin.len(a.entities) {
        ok = false
        return
    }
    if a.entities[iterator.index].dead {
        iterator.index += 1
        return iter(a, iterator)
    }
    entity := &a.entities[iterator.index]
    data = &entity.data
    handle = Handle{id=iterator.index, generation=entity.generation}
    ok = true
    iterator.index += 1
    return
}
len :: proc(a: ^Arena($T)) -> (count: uint) {
    i: Iterator
    for handle, entity in iter(a, &i) {
        count += 1
    }
    return
}
