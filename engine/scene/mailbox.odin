package scene

import "core:fmt"
import "base:runtime"
import "core:sync"

Handler :: distinct proc(self: ^Actor, message: ^Event)

Event :: struct {
    data: rawptr,
}

Mailbox :: struct {
    handler: Handler,
    //double-buffered
    queue_mutex: sync.Mutex,
    queue: [dynamic]Event,
    inbox: [dynamic]Event,
}

@(private)
Subscribe :: struct {
    event_type: string,
    id: ActorId,
    handler: Handler,
}

@(private)
Unsubscribe :: struct {
    event_type: string,
    id: ActorId,
}

Post_Office :: struct {
    routes: map[string]map[ActorId]^Mailbox, //must be pointer because queue_mutex must not change location
    subscriptions: map[ActorId]map[string]struct{},
    subscribes_mutex: sync.Mutex,
    subscribes: [dynamic]Subscribe,
    unsubscribes_mutex: sync.Mutex,
    unsubscribes: [dynamic]Unsubscribe,
}

//supports both direct sending of messages AND pubsub

get_event_type :: proc($E: typeid) -> (typename: string, ok: bool) {
    named_type := type_info_of(E).variant.(runtime.Type_Info_Named) or_return
    return fmt.tprintf("%s.%s", named_type.pkg, named_type.name), true
}

when ODIN_OS == .JS {
    subscribe :: proc(po: ^Post_Office, id: ActorId, $E: typeid, handler: Handler) {
        if typename, ok := get_event_type(E); ok {
            append(&po.subscribes, Subscribe{typename, id, handler})
        } else {
            fmt.eprintln("Event must be a named type.")
        }
    }
    unsubscribe :: proc(po: ^Post_Office, id: ActorId, $E: typeid) {
        if typename, ok := get_event_type(E); ok {
            append(&po.subscribes, Subscribe{typename, id})
        }
    }
} else {
    subscribe :: proc(po: ^Post_Office, id: ActorId, $E: typeid, handler: Handler) {
        if typename, ok := get_event_type(E); ok {
            if sync.mutex_guard(&po.subscribes_mutex) {
                append(&po.subscribes, Subscribe{typename, id, handler})
            }
        } else {
            fmt.eprintln("Event must be a named type.")
        }
    }
    unsubscribe :: proc(po: ^Post_Office, id: ActorId, $E: typeid) {
        if typename, ok := get_event_type(E); ok {
            if sync.mutex_guard(&po.unsubscribes_mutex) {
                append(&po.unsubscribes, Unsubscribe{typename, id})
            }
        }
    }
}

@(private)
unsubscribe_all :: proc(po: ^Post_Office, id: ActorId) {
    for event_type, &route in po.routes {
        if mailbox, ok := route[id]; ok {
            //no need for mutex because this happens upon actor death
            append(&po.unsubscribes, Unsubscribe{event_type, id})
        }
    }
}


@(private)
process_subscriptions :: proc(po: ^Post_Office) {
    for subscribe in po.subscribes {
        route := po.routes[subscribe.event_type] or_else map[ActorId]^Mailbox{}
        if mailbox, ok := route[subscribe.id]; ok {
            free(mailbox)
        }
        m := new(Mailbox)
        m.queue = make([dynamic]Event)
        m.inbox = make([dynamic]Event)
        m.handler = subscribe.handler
        route[subscribe.id] = m
        po.routes[subscribe.event_type] = route
        subs := po.subscriptions[subscribe.id] or_else make(map[string]struct{})
        subs[subscribe.event_type] = {}
        po.subscriptions[subscribe.id] = subs
    }
    clear(&po.subscribes)

    for unsubscribe in po.unsubscribes {
        if route, ok := &po.routes[unsubscribe.event_type]; ok {
            if mailbox, ok := route[unsubscribe.id]; ok {
                delete(mailbox.queue)
                delete(mailbox.inbox)
                free(mailbox)
            }
            delete_key(route, unsubscribe.id)
        }
        if subscription, ok := &po.subscriptions[unsubscribe.id]; ok {
            delete_key(subscription, unsubscribe.event_type)
        }
    }
    clear(&po.unsubscribes)
}

when ODIN_OS == .JS {
    @(private)
    append_event :: proc(m: ^Mailbox, event: Event) {
        append(&m.queue, event)
    }
} else {
    @(private)
    append_event :: proc(m: ^Mailbox, event: Event) {
        if sync.mutex_guard(&m.queue_mutex) {
            append(&m.queue, event)
        }
    }
}

publish :: proc(scene: ^Scene, event: $E) {
    if typename, ok := get_event_type(E); ok {
        if route, ok := &scene.routes[typename]; ok {
            for id, mailbox in route {
                data := new(E)
                data^ = event
                event := Event{data}
                append_event(mailbox, event)
            }
        }
    }
}

send :: proc(scene: ^Scene, id: ActorId, event: $E) {
    if typename, ok := get_event_type(E); ok {
        if route, ok := &scene.routes[typename]; ok {
            if mailbox, ok := route[id]; ok {
                data := new(E)
                data^ = event
                event := Event{data}
                append_event(mailbox, event)
            }
        }
    }
}

when ODIN_OS == .JS {
    @(private)
    buffer_events :: proc(m: ^Mailbox) {
        reserve(&m.inbox, len(m.queue))
        for event in m.queue {
            append(&m.inbox, event)
        }
        clear(&m.queue)
    }

} else {
    @(private)
    buffer_events :: proc(m: ^Mailbox) {
        if sync.mutex_guard(&m.queue_mutex) {
            reserve(&m.inbox, len(m.queue))
            for event in m.queue {
                append(&m.inbox, event)
            }
            clear(&m.queue)
        }
    }
}

//called pre-tick
@(private)
process_events :: proc(po: ^Post_Office, actor: ^Actor) {
    if subs, ok := po.subscriptions[actor.id]; ok {
        for event_type in subs {
            mailbox := po.routes[event_type][actor.id]
            buffer_events(mailbox)
            for &event in mailbox.inbox {
                mailbox.handler(actor, &event)
                free(event.data)
            }
            clear(&mailbox.inbox)
        }
    }
}
