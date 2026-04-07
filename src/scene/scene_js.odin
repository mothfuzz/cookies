#+build js

package scene

num_workers :: proc() -> int {
    return 1
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
