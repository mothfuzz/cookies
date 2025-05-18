package window

//skyhooks!
init_hooks := make([dynamic]proc())
pre_tick_hooks := make([dynamic]proc())
post_tick_hooks := make([dynamic]proc())
resize_hooks := make([dynamic]proc())
draw_hooks := make([dynamic]proc(f64))
quit_hooks := make([dynamic]proc())

tick_rate : uint = 125
set_tick_rate :: proc(new_tick_rate: uint) {
    tick_rate = new_tick_rate
}
