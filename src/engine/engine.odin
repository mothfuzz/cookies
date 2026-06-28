package engine

//bit of glue code so that these packages can work somewhat independently

//import "cookies:window"
//import "cookies:input"
//import "cookies:audio"

//skyhooks!
/*init_hooks := make([dynamic]proc())
pre_tick_hooks := make([dynamic]proc())
post_tick_hooks := make([dynamic]proc())
resize_hooks := make([dynamic]proc())
draw_hooks := make([dynamic]proc(f64))
quit_hooks := make([dynamic]proc())*/

tick_rate : uint = 125
@(export)
set_tick_rate :: proc(new_tick_rate: uint) {
    tick_rate = new_tick_rate
}

Boot_State :: struct(T: typeid) {
    using state: T,
    init: proc(^T),
    tick: proc(^T),
    draw: proc(^T, f64, f64),
    quit: proc(^T),
}
@(private)
boot_state: rawptr

//typed boot helpers so we don't have to use statics everywhere
boot_with :: proc($T: typeid, init: proc(^T), tick: proc(^T), draw: proc(^T, f64, f64), quit: proc(^T)) {
    boot_state = new(Boot_State(T))
    boot_state := cast(^Boot_State(T))(boot_state)
    boot_state.init = init
    boot_state.tick = tick
    boot_state.draw = draw
    boot_state.quit = quit
    boot(
        proc() {
            boot_state := cast(^Boot_State(T))(boot_state)
            if boot_state.init != nil do boot_state->init()
        },
        proc() {
            boot_state := cast(^Boot_State(T))(boot_state)
            if boot_state.tick != nil do boot_state->tick()
        },
        proc(alpha, delta: f64) {
            boot_state := cast(^Boot_State(T))(boot_state)
            if boot_state.draw != nil do boot_state->draw(alpha, delta)
        },
        proc() {
            boot_state := cast(^Boot_State(T))(boot_state)
            if boot_state.quit != nil do boot_state->quit()
        },
    )
}
