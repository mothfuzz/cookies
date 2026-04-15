package scene

import "core:fmt"
import "base:runtime"

Handler :: distinct proc(self: ^Actor, message: ^Event)

Event :: struct {
    data: rawptr,
}

Mailbox :: struct {
    handler: Handler,
    //double-buffered
    queue: [dynamic]Event,
    inbox: [dynamic]Event,
    using mailbox_sync: Mailbox_Sync,
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
    subscribes: [dynamic]Subscribe,
    unsubscribes: [dynamic]Unsubscribe,
    using post_office_sync: Post_Office_Sync,
}

delete_post_office :: proc(po: ^Post_Office) {
    for event_type, &route in po.routes {
        for a, &mailbox in route {
            delete(mailbox.queue)
            delete(mailbox.inbox)
            free(mailbox)
        }
        delete(route)
    }
    delete(po.routes)
    for a, &subscriptions in po.subscriptions {
        delete(subscriptions)
    }
    delete(po.subscriptions)
    delete(po.subscribes)
    delete(po.unsubscribes)
}

//supports both direct sending of messages AND pubsub

get_event_type :: proc($E: typeid) -> (typename: string, ok: bool) {
    named_type := type_info_of(E).variant.(runtime.Type_Info_Named) or_return
    return fmt.tprintf("%s.%s", named_type.pkg, named_type.name), true
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
            delete(mailbox.queue)
            delete(mailbox.inbox)
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
