package scene

import "core:fmt"

ActorId :: distinct u64

ActorMethods :: struct {
    init: proc(^Actor),
    tick: proc(^Actor),
    draw: proc(^Actor, f64),
    kill: proc(^Actor),
}

Actor :: struct {
    id: ActorId,
    data: rawptr,
    using methods: ActorMethods,
}

Scene :: struct {
    actors: map[ActorId]Actor,
    baseid: ActorId,
}

spawn :: proc(s: ^Scene, t: $T, methods: ActorMethods) -> ActorId {
    data := new(T)
    data^ = t
    s.baseid += 1
    s.actors[s.baseid] = Actor{s.baseid, data, methods}
    return s.baseid
}

tick :: proc(s: ^Scene) {
    for id, &actor in s.actors {
        if actor.tick != nil {
            actor->tick()
        }
    }
}

draw :: proc(s: ^Scene, t: f64) {
    for id, &actor in s.actors {
        if actor.draw != nil {
            actor->draw(t)
        }
    }
}
