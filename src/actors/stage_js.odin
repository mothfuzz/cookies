#+build js

package actors
import hm "core:container/handle_map"

Stage_Sync :: struct {}

@(private)
init_threads :: proc(s: ^Stage) {}

@(private)
delete_threads :: proc(s: ^Stage) {}

@(private)
process_threads :: proc(s: ^Stage) {
    it := hm.iterator_make(&s.actors)
    for actor, _ in hm.iterate(&it) {
        actor := actor.ptr
        process_events(s, actor)
    }
    it = hm.iterator_make(&s.actors)
    for actor, _ in hm.iterate(&it) {
        actor := actor.ptr
        if actor.user_tick != nil {
            actor->user_tick()
        }
    }
}

spawn :: proc(s: ^Stage, t: $T, name: string="") -> Actor_Handle {
    actor := construct_actor(t, name)
    handle := hm.add(&s.actors, actor)
    append(&s.spawns, handle)
    actor.ptr.handle = handle
    return handle
}

kill :: proc(s: ^Stage, handle: Actor_Handle) {
    if actor, ok := hm.get(&s.actors, handle); ok {
        actor.ptr.state = .Killed
        append(&s.kills, handle)
    }
}
