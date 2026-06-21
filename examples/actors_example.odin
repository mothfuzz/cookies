package main

import "core:fmt"

import "cookies:actors"
import "core:time"

s: actors.Stage

My_Actor :: struct {
    using actor: actors.Actor,
    init: proc(^My_Actor),
    tick: proc(^My_Actor),
    num: int,
}

My_Event :: struct {
    i: int,
}

my_event_handler :: proc(a: ^My_Actor, e: ^My_Event) {
    fmt.println("received event:", e.i)
}

my_init :: proc(self: ^My_Actor) {
    fmt.println("init!")
    actors.subscribe(&s, self, my_event_handler)
}

my_tick :: proc(self: ^My_Actor) {
    self.num = int(self.handle.idx + self.handle.gen)
    fmt.println("tick:", self.num)
}

main :: proc() {
    s = actors.make_stage()

    for i in 0..<200 {
        handle := actors.spawn(&s, My_Actor{init=my_init, tick=my_tick})
        if (i+1) % 2 == 0 {
            actors.kill(&s, handle)
        }
    }


    actors.tick(&s)
    fmt.println(actors.count(&s))

    actors.publish(&s, My_Event{i=4})

    t0 := time.now()
    actors.tick(&s)
    elapsed := time.diff(t0, time.now())
    fmt.println("elapsed time:", elapsed)

    actors.delete_stage(&s)

}
