package scene

import "core:fmt"
import "core:os"
import "core:thread"
import "core:sync"

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
    scene: ^Scene,
    name: string,
}

Scene :: struct #no_copy {
    actors: map[ActorId]Actor,
    baseid: ActorId,
    spawns: [dynamic]Actor,
    kills: [dynamic]ActorId,
    spawn_mutex: sync.Mutex,
    kill_mutex: sync.Mutex,
    pool: ^thread.Pool,
    ids: [dynamic]ActorId,
    name: string,

    using post_office: Post_Office,
}

destroy :: proc(s: ^Scene) {
    if s.pool != nil {
        thread.pool_finish(s.pool)
        thread.pool_destroy(s.pool)
        free(s.pool)
    }
    delete_post_office(s)
    delete(s.ids)
    for id, actor in s.actors {
        free(actor.data)
    }
    delete(s.actors)
    delete(s.spawns)
    delete(s.kills)
}

when ODIN_OS == .JS {
    spawn :: proc(s: ^Scene, t: $T, methods: ActorMethods, name: string="") -> ActorId {
        data := new(T)
        data^ = t
        s.baseid += 1
        append(&s.spawns, Actor{s.baseid, data, methods, s, name})
        return s.baseid
    }
} else {
    spawn :: proc(s: ^Scene, t: $T, methods: ActorMethods, name: string="") -> ActorId {
        if sync.mutex_guard(&s.spawn_mutex) {
            data := new(T)
            data^ = t
            s.baseid += 1
            append(&s.spawns, Actor{s.baseid, data, methods, s, name})
        }
        return s.baseid
    }
}

when ODIN_OS == .JS {
    kill :: proc(s: ^Scene, id: ActorId) {
        append(&s.kills, id)
    }
} else {
    kill :: proc(s: ^Scene, id: ActorId) {
        if sync.mutex_guard(&s.kill_mutex) {
            append(&s.kills, id)
        }
    }
}

num_workers :: proc() -> int {
    return os.processor_core_count() - 1
}

update_ids :: proc(s: ^Scene) {
    clear(&s.ids)
    for id in s.actors {
        append(&s.ids, id)
    }
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

tick :: proc(s: ^Scene) {

    if s.pool == nil && thread.IS_SUPPORTED {
        s.pool = new(thread.Pool)
        thread.pool_init(s.pool, context.allocator, num_workers())
        thread.pool_start(s.pool)
    }

    for actor in s.spawns {
        s.actors[actor.id] = actor
        if actor.init != nil {
            actor.init(&s.actors[actor.id])
        }
    }
    clear(&s.spawns)
    for id in s.kills {
        if a, ok := &s.actors[id]; ok {
            if a.kill != nil {
                a->kill()
            }
            unsubscribe_all(s, a.id)
            free(a.data)
            delete_key(&s.actors, id)
        }
    }
    clear(&s.kills)

    update_ids(s)

    process_subscriptions(s)

    if thread.IS_SUPPORTED {
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
    } else {
        for id, &actor in s.actors {
            process_events(s, &actor)
        }
        for id, &actor in s.actors {
            if actor.tick != nil {
                actor->tick()
            }
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
