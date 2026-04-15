#+build js

package scene

Scene_Sync :: struct {}

@(private)
init_threads :: proc(s: ^Scene) {}

@(private)
delete_threads :: proc(s: ^Scene) {}

@(private)
process_threads :: proc(s: ^Scene) {
    for id, &actor in s.actors {
        process_events(s, &actor)
    }
    for id, &actor in s.actors {
        if actor.tick != nil {
            actor->tick()
        }
    }
}

spawn :: proc(s: ^Scene, t: $T, methods: ActorMethods, name: string="") -> ActorId {
    data := new(T)
    data^ = t
    s.baseid += 1
    append(&s.spawns, Actor{s.baseid, data, methods, s, name})
    return s.baseid
}

kill :: proc(s: ^Scene, id: ActorId) {
    append(&s.kills, id)
}
