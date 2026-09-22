package clock

//tick... tock...

Clock :: struct {
    tick_rate: uint,
    accumulator: f64,
    current_tick: u64,
    current_frame: u64,
    alpha: f64,
}

@(private)
default_clock := Clock{
    tick_rate=125,
}
default: ^Clock = &default_clock

wind :: proc(clk: ^Clock, delta: f64) {
    clk.accumulator += delta
}

tick :: proc(clk: ^Clock) -> bool {
    clk.current_frame += 1
    delta := 1.0/f64(clk.tick_rate)
    if clk.accumulator < delta {
        clk.alpha = clk.accumulator / delta
        return false
    }
    clk.accumulator -= delta
    clk.current_tick += 1
    return true
}

Smoothed :: struct(T: typeid) {
    prev, next: T,
    tick_wrote: u64,
}

write :: proc(s: ^Smoothed($T), c: ^Clock = default) -> ^T {
    if s.tick_wrote != c.current_tick { s.prev = s.next; s.tick_wrote = c.current_tick }
    return &s.next
}

sample :: proc(s: Smoothed($T), c: ^Clock = default) -> (prev, next: T, alpha: f64) {
    if s.tick_wrote != c.current_tick do return s.next, s.next, 1
    return s.prev, s.next, c.alpha
}

import "core:math"
//convenience proc for trivially-lerpable values
read :: proc(s: Smoothed($T), c: ^Clock = default) -> T {
    return math.lerp(sample(s, c))
}
