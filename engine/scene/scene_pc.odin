#+build !js

package scene

import "core:os"
import "core:sync"

num_workers :: proc() -> int {
    return os.get_processor_core_count() - 1
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
