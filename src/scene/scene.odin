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
    scene: ^Scene,
    name: string,
}

Scene :: struct {
    actors: map[ActorId]Actor,
    baseid: ActorId,
    spawns: [dynamic]Actor,
    kills: [dynamic]ActorId,
    using scene_sync: Scene_Sync,
    ids: [dynamic]ActorId,
    name: string,

    using post_office: Post_Office,
}

destroy :: proc(s: ^Scene) {
    delete_threads(s)
    delete_post_office(s)
    delete(s.ids)
    for id, actor in s.actors {
        free(actor.data)
    }
    delete(s.actors)
    delete(s.spawns)
    delete(s.kills)
}

update_ids :: proc(s: ^Scene) {
    clear(&s.ids)
    for id in s.actors {
        append(&s.ids, id)
    }
}

tick :: proc(s: ^Scene) {

    init_threads(s)

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

    process_threads(s)
}

draw :: proc(s: ^Scene, t: f64) {
    for id, &actor in s.actors {
        if actor.draw != nil {
            actor->draw(t)
        }
    }
}
