package main

import "core:fmt"

import "cookies:actors"
import "core:time"

s: actors.Stage

Ping :: struct {
    using actor: actors.Actor,
    init: proc(^Ping),
    kill: proc(^Ping),
    partner: actors.Handle,
}

Pong :: struct {
    using actor: actors.Actor,
    init: proc(^Pong),
}

Ping_Ball :: struct {}
Pong_Ball :: struct {}

ping_init :: proc(self: ^Ping) {
    actors.subscribe(&s, self, ping_handler)
    self.partner = actors.spawn(&s, Pong{init=pong_init})
}

ping_kill :: proc(self: ^Ping) {
    //like romeo and juliet...
    actors.kill(&s, self.partner)
}

ping_handler :: proc(self: ^Ping, e: ^Ping_Ball) {
    fmt.println("ping:", self.handle)
    actors.send(&s, self.partner, Pong_Ball{})
}


pong_init :: proc(self: ^Pong) {
    actors.subscribe(&s, self, pong_handler)
}

pong_handler :: proc(self: ^Pong, e: ^Pong_Ball) {
    fmt.println("pong:", self.handle)
    //send back to ping if you want an infinite loop.
}


main :: proc() {
    s = actors.make_stage()

    for i in 0..<100 {
        ping := actors.spawn(&s, Ping{init=ping_init, kill=ping_kill})
        //spice it up a little, kill half
        if i % 2 == 0 {
            actors.kill(&s, ping)
        }
    }

    actors.tick(&s) //run 1 tick for spawns/kills
    fmt.println("should be 100:", actors.count(&s))

    actors.publish(&s, Ping_Ball{}) //should trigger ping_handler, then send to pong_handler next tick

    t0 := time.now()
    //run 2 ticks so that any messages that get queued next tick will get processed
    actors.tick(&s)
    actors.tick(&s)
    elapsed := time.diff(t0, time.now())
    fmt.println("elapsed time:", elapsed) //ironically most of this time is spent calling print

    actors.delete_stage(&s)

}
