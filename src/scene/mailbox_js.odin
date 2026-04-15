#+build js

package scene

import "core:fmt"

Mailbox_Sync :: struct {}

@(private)
append_event :: proc(m: ^Mailbox, event: Event) {
    append(&m.queue, event)
}

@(private)
buffer_events :: proc(m: ^Mailbox) {
    reserve(&m.inbox, len(m.queue))
    for event in m.queue {
        append(&m.inbox, event)
    }
    clear(&m.queue)
}

Post_Office_Sync :: struct {}

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
