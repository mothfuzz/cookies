package actors

import "core:fmt"
import "base:runtime"
import "base:intrinsics"

Handler :: distinct proc(mailbox: ^Mailbox, self: ^Actor, message: ^Event)

Event :: struct {
    data: rawptr,
}

Mailbox :: struct {
    handler: Handler,
    user_handler: rawptr,
    //double-buffered
    queue: [dynamic]Event,
    inbox: [dynamic]Event,
    using mailbox_sync: Mailbox_Sync,
}

@(private)
Subscribe :: struct {
    event_type: string,
    handle: Actor_Handle,
    handler: Handler,
    user_handler: rawptr,
}

@(private)
Unsubscribe :: struct {
    event_type: string,
    handle: Actor_Handle,
}

Post_Office :: struct {
    routes: map[string]map[Actor_Handle]^Mailbox, //must be pointer because queue_mutex must not change location
    subscriptions: map[Actor_Handle]map[string]struct{},
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

get_event_type :: proc($E: typeid) -> string {
    return intrinsics.type_canonical_name(E)
}

@(private)
unsubscribe_all :: proc(po: ^Post_Office, handle: Actor_Handle) {
    for event_type, &route in po.routes {
        if mailbox, ok := route[handle]; ok {
            //no need for mutex because this happens upon actor death
            append(&po.unsubscribes, Unsubscribe{event_type, handle})
        }
    }
}

@(private)
construct_subscription :: proc(handle: Actor_Handle, handler: proc(^$A, ^$E)) -> Subscribe {
    typename := get_event_type(E)
    user_handler := rawptr(handler)
    handler := proc(mailbox: ^Mailbox, a: ^Actor, e: ^Event) {
        actor := cast(^A)(uintptr(a) + actor_offset(A))
        event := cast(^E)(e.data)
        handler := cast(proc(^A, ^E))(mailbox.user_handler)
        handler(actor, event)
    }
    return Subscribe{typename, handle, handler, user_handler}
}

@(private)
process_subscriptions :: proc(po: ^Post_Office) {
    for subscribe in po.subscribes {
        route := po.routes[subscribe.event_type] or_else map[Actor_Handle]^Mailbox{}
        if mailbox, ok := route[subscribe.handle]; ok {
            delete(mailbox.queue)
            delete(mailbox.inbox)
            free(mailbox)
        }
        m := new(Mailbox)
        m.queue = make([dynamic]Event)
        m.inbox = make([dynamic]Event)
        m.handler = subscribe.handler
        m.user_handler = subscribe.user_handler
        route[subscribe.handle] = m
        po.routes[subscribe.event_type] = route

        subs := po.subscriptions[subscribe.handle] or_else make(map[string]struct{})
        subs[subscribe.event_type] = {}
        po.subscriptions[subscribe.handle] = subs
    }
    clear(&po.subscribes)

    for unsubscribe in po.unsubscribes {
        if route, ok := &po.routes[unsubscribe.event_type]; ok {
            if mailbox, ok := route[unsubscribe.handle]; ok {
                delete(mailbox.queue)
                delete(mailbox.inbox)
                free(mailbox)
            }
            delete_key(route, unsubscribe.handle)
        }
        if subscription, ok := &po.subscriptions[unsubscribe.handle]; ok {
            delete_key(subscription, unsubscribe.event_type)
        }
    }
    clear(&po.unsubscribes)
}

publish :: proc(stage: ^Stage, event: $E) {
    typename := get_event_type(E)
    if route, ok := &stage.routes[typename]; ok {
        for _, mailbox in route {
            data := new(E)
            data^ = event
            event := Event{data}
            append_event(mailbox, event)
        }
    }
}

send :: proc(stage: ^Stage, handle: Actor_Handle, event: $E) {
    typename := get_event_type(E)
    if route, ok := &stage.routes[typename]; ok {
        if mailbox, ok := route[handle]; ok {
            data := new(E)
            data^ = event
            event := Event{data}
            append_event(mailbox, event)
        }
    }
}

//called pre-tick
@(private)
process_events :: proc(po: ^Post_Office, actor: ^Actor) {
    if subs, ok := po.subscriptions[actor.handle]; ok {
        for event_type in subs {
            mailbox := po.routes[event_type][actor.handle]
            buffer_events(mailbox)
            for &event in mailbox.inbox {
                mailbox->handler(actor, &event)
                free(event.data)
            }
            clear(&mailbox.inbox)
        }
    }
}
