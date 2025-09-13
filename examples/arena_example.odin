package main

import "../engine"
import "../engine/arena"
import "core:fmt"

Thing :: struct {
    name: string,
}
a: arena.Arena(Thing)

init :: proc() {
    //using arena
    //a = make(Arena(Thing))
    arena.init(&a)
    h1 := arena.insert(&a, Thing{"Hello"})
    h2 := arena.insert(&a, Thing{", "})
    h3 := arena.insert(&a, Thing{"Nobody"})
    arena.remove(&a, h3)
    h3 = arena.insert(&a, Thing{"World!"})

    fmt.println("len:", arena.len(&a))

    it: arena.Iterator
    for handle, thing in arena.iter(&a, &it) {
        fmt.println(handle)
    }
    it = {}
    for handle, thing in arena.iter(&a, &it) {
        fmt.print(thing.name)
    }
    fmt.println()

}

kill :: proc() {
    arena.delete(&a)
}

main :: proc() {
    engine.boot(init, nil, nil, kill)
}
