#+build !js

package scene

import "core:os"
import "core:thread"
import "core:sync"

Scene_Sync :: struct {
    pool: ^thread.Pool,
    spawn_mutex: sync.Mutex,
    kill_mutex: sync.Mutex,
}

num_workers :: proc() -> int {
    return os.get_processor_core_count() - 1
}

work :: proc(t: thread.Task) {
    s := (^Scene)(t.data)
    starting_index := t.user_index
    ending_index := min(len(s.ids), starting_index + max(1, len(s.ids)/num_workers()))
    //fmt.println("updating actors numbered", starting_index, "-", ending_index, "in this thread")
    for i := starting_index; i < ending_index; i += 1 {
        actor := &s.actors[s.ids[i]]
        //fmt.println("processing actor", actor.id)
        if actor.tick != nil {
            actor->tick()
        }
    }
}

work_events :: proc(t: thread.Task) {
    s := (^Scene)(t.data)
    starting_index := t.user_index
    ending_index := min(len(s.ids), starting_index + max(1, len(s.ids)/num_workers()))
    for i := starting_index; i < ending_index; i += 1 {
        actor := &s.actors[s.ids[i]]
        //fmt.println("processing actor", actor.id)
        process_events(s, actor)
    }
}

@(private)
init_threads :: proc(s: ^Scene) {
    if s.pool == nil {
        s.pool = new(thread.Pool)
        thread.pool_init(s.pool, context.allocator, num_workers())
        thread.pool_start(s.pool)
    }
}

@(private)
delete_threads :: proc(s: ^Scene) {
    if s.pool != nil {
        thread.pool_finish(s.pool)
        thread.pool_destroy(s.pool)
        free(s.pool)
    }
}

@(private)
process_threads :: proc(s: ^Scene) {
    //yay parallel!

    chunk_size := max(1, len(s.ids)/num_workers())
    for i := 0; i < len(s.ids); i += chunk_size {
        thread.pool_add_task(s.pool, context.allocator, work_events, s, i)
    }
    thread.pool_finish(s.pool)

    for i := 0; i < len(s.ids); i += chunk_size {
        thread.pool_add_task(s.pool, context.allocator, work, s, i)
    }
    thread.pool_finish(s.pool)
}

spawn :: proc(s: ^Scene, t: $T, methods: ActorMethods, name: string="") -> ActorId {
    if sync.mutex_guard(&s.spawn_mutex) {
        data := new(T)
        data^ = t
        s.baseid += 1
        append(&s.spawns, Actor{s.baseid, data, methods, s, name})
    }
    return s.baseid
}

kill :: proc(s: ^Scene, id: ActorId) {
    if sync.mutex_guard(&s.kill_mutex) {
        append(&s.kills, id)
    }
}
