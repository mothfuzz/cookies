#+build js

package actors

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

subscribe :: proc(po: ^Post_Office, handle: Handle, handler: proc(^$A, ^$E)) {
    append(&po.subscribes, construct_subscription(handle, handler))
}
unsubscribe :: proc(po: ^Post_Office, handle: Handle, $E: typeid) {
    typename := get_event_type(E)
    append(&po.subscribes, Subscribe{typename, handle})
}
