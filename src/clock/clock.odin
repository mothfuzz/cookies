package clock

//tick... tock...

Clock :: struct {
    tick_rate: uint,
    accumulator: f64,
    current_tick: u64,
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
    delta := 1.0/f64(clk.tick_rate)
    if clk.accumulator < delta {
        clk.alpha = clk.accumulator / delta
        return false
    }
    clk.accumulator -= delta
    clk.current_tick += 1
    return true
}
