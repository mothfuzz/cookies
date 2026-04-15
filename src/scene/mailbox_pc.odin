#+build !js

package scene

import "core:sync"
import "core:fmt"

Mailbox_Sync :: struct {
    queue_mutex: sync.Mutex,
}

@(private)
append_event :: proc(m: ^Mailbox, event: Event) {
    if sync.mutex_guard(&m.queue_mutex) {
        append(&m.queue, event)
    }
}

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

Post_Office_Sync :: struct {
    subscribes_mutex: sync.Mutex,
    unsubscribes_mutex: sync.Mutex,
}

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
