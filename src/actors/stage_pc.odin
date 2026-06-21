#+build !js

package actors

import "core:os"
import "core:thread"
import "core:sync"
import hm "core:container/handle_map"
import "core:fmt"

Stage_Sync :: struct {
    pool: ^thread.Pool,
    spawn_mutex: sync.Mutex,
    kill_mutex: sync.Mutex,
}

num_workers :: proc() -> int {
    return os.get_processor_core_count() - 1
}

work :: proc(t: thread.Task) {
    s := (^Stage)(t.data)
    starting_index := t.user_index
    ending_index := min(len(s.handles), starting_index + max(1, len(s.handles)/num_workers()))
    fmt.println("updating actors numbered", starting_index, "-", ending_index, "in this thread")
    for i := starting_index; i < ending_index; i += 1 {
        actor := hm.get(&s.actors, s.handles[i]).ptr
        if actor.state == .Active && actor.user_tick != nil {
            //fmt.println("processing actor", actor.id)
            actor->user_tick()
        }
    }
}

work_events :: proc(t: thread.Task) {
    s := (^Stage)(t.data)
    starting_index := t.user_index
    ending_index := min(len(s.handles), starting_index + max(1, len(s.handles)/num_workers()))
    for i := starting_index; i < ending_index; i += 1 {
        actor := hm.get(&s.actors, s.handles[i]).ptr
        if actor.state == .Active {
            //fmt.println("processing actor", actor.id)
            process_events(s, actor)
        }
    }
}

@(private)
init_threads :: proc(s: ^Stage) {
    if s.pool == nil {
        s.pool = new(thread.Pool)
        thread.pool_init(s.pool, context.allocator, num_workers())
        thread.pool_start(s.pool)
    }
}

@(private)
delete_threads :: proc(s: ^Stage) {
    if s.pool != nil {
        thread.pool_finish(s.pool)
        thread.pool_destroy(s.pool)
        free(s.pool)
    }
}

@(private)
pool_wait :: proc(pool: ^thread.Pool) {
    for !thread.pool_is_empty(pool) {
        if task, ok := thread.pool_pop_done(pool); ok {
            //cleanup task if I allocate any per-thread resources here...
        } else if task, ok := thread.pool_pop_waiting(pool); ok {
            thread.pool_do_work(pool, task)
        } else {
            thread.yield()
        }
    }
}

@(private)
process_threads :: proc(s: ^Stage) {
    //yay parallel!

    chunk_size := max(1, len(s.handles)/num_workers())
    for i := 0; i < len(s.handles); i += chunk_size {
        thread.pool_add_task(s.pool, context.allocator, work_events, s, i)
    }
    pool_wait(s.pool)

    for i := 0; i < len(s.handles); i += chunk_size {
        thread.pool_add_task(s.pool, context.allocator, work, s, i)
    }
    pool_wait(s.pool)
}

spawn :: proc(s: ^Stage, t: $T, name: string="") -> Actor_Handle {
    actor := construct_actor(t, name)
    handle: Actor_Handle
    if sync.mutex_guard(&s.spawn_mutex) {
        handle = hm.add(&s.actors, actor)
        append(&s.spawns, handle)
    }
    actor.ptr.handle = handle
    return handle
}

kill :: proc(s: ^Stage, handle: Actor_Handle) {
    if sync.mutex_guard(&s.kill_mutex) {
        if actor, ok := hm.get(&s.actors, handle); ok {
            actor.ptr.state = .Killed
            append(&s.kills, handle)
        }
    }
}
